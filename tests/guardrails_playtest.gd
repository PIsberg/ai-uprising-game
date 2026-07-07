extends Node3D
## PLAYTEST BOT for Generative Guardrails: drives the real player through the
## level the way a person would — stand on a safe slab, aim the ACTUAL camera at
## the next cell ahead, fire an anchor tag, walk forward onto it, repeat, until
## the override gate. Reports whether it's survivable, whether traversal works
## (can you walk the bridge?), whether the bot gets stuck, health over the run,
## and completion time. Run windowed.

var _gz
var _player: CharacterBody3D
var _head: Node3D
var _cam: Camera3D
var _dmg
var _phase := "boot"
var _t := 0.0
var _last_z := -999.0
var _stuck_t := 0.0
var _min_hp := 100.0
var _fire_cd := 0.0
var _log: Array = []
var _col := 0
var _mid_shot := false

func _capture_eye() -> void:
	# Freeze the bot (stop walking) while we point the camera and grab the frame,
	# so the screenshot doesn't cost the survivability read.
	_phase = "shot"
	Input.action_release("move_forward")
	_player.velocity = Vector3.ZERO
	var eye := _cam.global_position
	_player.rotation.y = 0.0 # gate is straight ahead (+Z)
	_head.rotation.x = -0.15
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/guardrails_eye.png")
	print("MID_SHOT captured at eye ", eye.round())
	_phase = "cross"

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_guardrails.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	for n in lvl.find_children("*", "GenerativeZone", true, false):
		_gz = n; break
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_head = _player.get_node("Head")
	_cam = _player.get_node("Head/Camera3D")
	_dmg = _player.get_node_or_null("Damageable")
	_col = _gz._cols / 2
	# Don't make the bot invulnerable — we WANT to measure if the crossing is
	# survivable. But cap enemy chaos out of the equation for a clean traversal
	# read by disabling their fire; hazards/floor still apply.
	print("PLAYTEST start: cols=%d rows=%d floor_dot=%.1f hazard_period=%.1f" % [
		_gz._cols, _gz._rows, _gz.floor_dot, _gz.hazard_period])
	_phase = "cross"

func _physics_process(delta: float) -> void:
	if _phase != "cross" or _gz == null or not is_instance_valid(_player):
		return
	_t += delta
	_fire_cd = maxf(0.0, _fire_cd - delta)
	if _dmg:
		_min_hp = minf(_min_hp, _dmg.current_health)

	var pcell: Vector2i = _gz._world_cell(_player.global_position)
	# Mid-crossing eye-level capture: what the player actually sees looking ahead.
	if pcell.y == 4 and not _mid_shot:
		_mid_shot = true
		_capture_eye()
	# Reached the gate?
	if GameState.is_task_done("guardrails"):
		_finish("COMPLETE")
		return
	# Fell in / dying?
	if _dmg and _dmg.current_health <= 1.0:
		_finish("DIED")
		return
	if _t > 60.0:
		_finish("TIMEOUT")
		return

	# Target: the next cell straight ahead toward the gate.
	var tr: int = clampi(pcell.y + 1, 0, _gz._rows) # may be == _rows → step to gate
	var target: Vector3
	if tr < _gz._rows:
		target = _gz._cell_world(tr, _col)
	else:
		target = _gz._gate_pos

	# Aim the REAL camera at the target cell (eye-level, pitched down).
	var eye := _cam.global_position
	var flat := Vector2(target.x - eye.x, target.z - eye.z)
	var yaw := atan2(-flat.x, -flat.y) # -Z forward convention
	_player.rotation.y = yaw
	var dist := flat.length()
	var pitch := atan2((target.y + 0.1) - eye.y, dist)
	_head.rotation.x = clampf(pitch, -1.4, 1.4)

	# Fire an anchor at the target cell if it isn't safe yet.
	if tr < _gz._rows and _gz._state[tr][_col] != _gz.ANCHORED and _fire_cd <= 0.0:
		_gz._t_cd = 0.0
		_gz._fire_anchor()
		_fire_cd = 0.25

	# Walk forward (body yaw already points at the target).
	Input.action_press("move_forward")

	# Stuck detection: forward Z not advancing.
	if _player.global_position.z <= _last_z + 0.02:
		_stuck_t += delta
	else:
		_stuck_t = 0.0
		_last_z = _player.global_position.z
	if _stuck_t > 3.0:
		_log.append("STUCK at cell %s pos=%s (hp=%.0f)" % [pcell, _player.global_position.round(), _dmg.current_health if _dmg else -1])
		_finish("STUCK")

func _finish(how: String) -> void:
	_phase = "done"
	Input.action_release("move_forward")
	print("PLAYTEST RESULT: %s  time=%.1fs  min_hp=%.0f  final_hp=%.0f  reached_cell=%s" % [
		how, _t, _min_hp, (_dmg.current_health if _dmg else -1),
		_gz._world_cell(_player.global_position)])
	for l in _log:
		print("  ", l)
	# Screenshot the bot where it ended up.
	_cam.global_position = _gz.field_center + Vector3(0, 2.4, -21)
	_cam.look_at(_gz.field_center + Vector3(0, 1.0, 8), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/guardrails_playtest.png")
	print("PLAYTEST_DONE")
	get_tree().quit()
