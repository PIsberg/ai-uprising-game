extends Node3D
## Same proven arena/approach as tools/mantle_probe.gd (floor + waist-high
## ledge, pulsed jump while walking in) but also tracks weapon_holder so we
## can confirm the mantle's new viewmodel kick actually fires on a real,
## successful mantle (not just that the mantle itself still works).
var _player: CharacterBody3D
var _weapon_holder: Node3D
var _home: Vector3
var _t := 0.0
var _max_y := -99.0
var _max_kick := 0.0
var _jt := 0.0

func _make_box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new(); sh.size = size
	cs.shape = sh
	b.add_child(cs)
	add_child(b)
	b.global_position = pos
	return b

func _ready() -> void:
	_make_box(Vector3(0, -0.5, 0), Vector3(20, 1, 20))      # floor, top at y=0
	_make_box(Vector3(0, 0.65, -10), Vector3(8, 1.3, 18))   # deep ledge platform, top y=1.3
	var ps: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	_player = ps
	add_child(ps)
	await get_tree().process_frame
	_weapon_holder = _player.get_node("Head/Camera3D/WeaponHolder")
	_home = _weapon_holder.position
	_player.global_position = Vector3(0, 0.2, 1.0)          # on the floor, facing -Z toward the ledge
	Input.action_press("move_forward")

func _physics_process(delta: float) -> void:
	if _player == null or _weapon_holder == null: return
	_t += delta
	_max_y = maxf(_max_y, _player.global_position.y)
	_max_kick = maxf(_max_kick, (_weapon_holder.position - _home).length())
	_jt += delta
	if _t < 2.5:
		if _jt > 0.7:
			_jt = 0.0
			Input.action_press("jump")
		elif _jt > 0.08 and Input.is_action_pressed("jump"):
			Input.action_release("jump")
	else:
		Input.action_release("move_forward")
		if Input.is_action_pressed("jump"): Input.action_release("jump")
	if _t > 4.0:
		var on_ledge := _player.global_position.y > 1.1 and _player.global_position.z < -2.2
		print("MANTLE result: final_pos=(%.2f,%.2f,%.2f) max_y=%.2f on_ledge=%s max_weapon_kick=%.4f" % [
			_player.global_position.x, _player.global_position.y, _player.global_position.z,
			_max_y, on_ledge, _max_kick])
		Input.action_release("move_forward")
		get_tree().quit()
