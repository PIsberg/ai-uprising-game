extends Node3D
## Loads a real campaign level, makes the player invulnerable and walks it into
## the arena to draw a horde, then films the firefight with a cinematic chase cam
## and saves a PNG frame sequence to docs/screenshots/action/frame_###.png.
##
## Run (needs a window/GPU): godot --path . tools/capture_action.tscn
## Pick the level with LEVEL_ID.

const LEVEL_ID := "suburb"
const OUT_DIR := "res://docs/screenshots/action"
const WARMUP := 1.6        # seconds for the level to build + enemies to close in
const FRAMES := 48         # captured frames
const WALK_SPEED := 3.0
const FILL := false        # daylit levels don't need a fill light

var _cam: Camera3D
var _key: OmniLight3D
var _player: Node3D
var _center := Vector3.ZERO
var _dir := Vector3.FORWARD
var _t := 0.0
var _frame := 0
var _ready_done := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	Engine.time_scale = 0.5  # slow-mo for a smooth, readable sequence

	var lvl: Node = load("res://scenes/levels/level_%s.tscn" % LEVEL_ID).instantiate()
	add_child(lvl)

	# Hide the FPS HUD overlay so the chase-cam framing stays clean.
	var hud := lvl.get_node_or_null("HUD")
	if hud:
		hud.queue_free()

	# Wait for the builder (_ready spawns enemies + bakes navmesh).
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout

	_player = get_tree().get_first_node_in_group("player")
	if _player:
		# Survive the firefight, and stop the player's own input/physics so we can
		# dolly it forward by hand into the swarm.
		if "hp" in _player and _player.hp:
			_player.hp.invulnerable = true
		_player.set_physics_process(false)
		if "camera" in _player and _player.camera:
			_player.camera.current = false
		_center = Vector3(0, _player.global_position.y, 0)
		_dir = (_center - _player.global_position)
		_dir.y = 0
		_dir = _dir.normalized() if _dir.length() > 0.1 else Vector3.FORWARD

	_cam = Camera3D.new()
	_cam.fov = 68.0
	add_child(_cam)
	_cam.make_current()

	# Optional travelling key light (dark levels only).
	if FILL:
		var key := OmniLight3D.new()
		key.light_energy = 2.4
		key.omni_range = 22.0
		key.light_color = Color(1.0, 0.95, 0.85)
		add_child(key)
		_key = key
	_ready_done = true


func _process(delta: float) -> void:
	if not _ready_done:
		return
	if _player == null or not is_instance_valid(_player):
		get_tree().quit()
		return

	# Dolly the player slowly into the arena to trip proximity spawns and gather a crowd.
	_player.global_position += _dir * WALK_SPEED * delta
	if _player.has_method("look_at"):
		pass
	# Face the player's body toward the action.
	var look_yaw := atan2(_dir.x, _dir.z)
	_player.rotation.y = look_yaw

	# High diving chase cam: above + behind, looking down past the hero into the
	# fight. The height keeps it clear of floor-level wall geometry (no clipping).
	var p := _player.global_position
	_cam.global_position = p - _dir * 5.5 + Vector3(0, 6.5, 0)
	_cam.look_at(p + _dir * 4.0 + Vector3(0, 0.4, 0), Vector3.UP)
	if _key:
		_key.global_position = p + Vector3(0, 5.0, 0)

	_t += delta
	if _t < WARMUP:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/frame_%03d.png" % [OUT_DIR, _frame])
	_frame += 1
	if _frame >= FRAMES:
		print("ACTION CAPTURED frames=", _frame, " level=", LEVEL_ID)
		get_tree().quit()
