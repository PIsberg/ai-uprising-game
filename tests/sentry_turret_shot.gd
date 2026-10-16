extends Node3D
## Windowed visual check for a level's sentry turret (GROK's first by
## default): the turret painting the player with its lock-on laser, seen from
## beside the player; then the hack ring under the gun mid-hack; then the
## turret hacked green. Headless gives black frames.
##   godot --path . res://tests/sentry_turret_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "grok"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://turret_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node3D).visible = false
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/turret_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
	GameState.current_state = GameState.State.PLAYING
	var tur := lvl.find_children("*", "SentryTurret", true, false)[0] as SentryTurret
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.get_node("Damageable").set("invulnerable", true)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var fwd := -tur.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	player.global_position = tur.global_position + fwd * 10.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	var side := fwd.cross(Vector3.UP).normalized()
	cam.global_position = tur.global_position + fwd * 12.0 + side * 3.0 + Vector3.UP * 2.0
	cam.look_at(tur.global_position + Vector3.UP * 1.2)
	while tur._lock_t < SentryTurret.LOCK_TIME * 0.7:
		await get_tree().physics_frame
	await _shot("locking")
	player.global_position = tur.global_position + fwd * 1.5
	while tur.hack_t < SentryTurret.HACK_SECONDS * 0.6:
		await get_tree().physics_frame
	cam.global_position = tur.global_position + fwd * 5.0 + side * 2.5 + Vector3.UP * 3.0
	cam.look_at(tur.global_position)
	await _shot("hacking")
	while tur.phase != SentryTurret.Phase.ALLIED:
		await get_tree().physics_frame
	for i in 10:
		await get_tree().physics_frame
	await _shot("hacked")
	print("RESULT PASS")
	get_tree().quit()
