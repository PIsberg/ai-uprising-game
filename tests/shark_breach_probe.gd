extends Node3D
## Live test: drop the RAZORFIN shark near a player proxy over water and let it
## run. Confirms it acquires the target, BREACHES above the surface, and bites.
##   godot --headless --path . res://tests/shark_breach_probe.tscn

var _shark: Node3D
var _player: Node3D
var _max_y: float = -100.0
var _t: float = 0.0
var _start_hp: float = 0.0

func _ready() -> void:
	# Player proxy on a "gantry": a static body the shark's LOS ray can hit.
	_player = StaticBody3D.new()
	_player.add_to_group("player")
	_player.collision_layer = 1
	_player.position = Vector3(3, 2.0, 0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	cs.shape = box
	_player.add_child(cs)
	var dmg := Node.new()
	dmg.set_script(load("res://scripts/systems/damageable.gd"))
	dmg.name = "Damageable"
	dmg.set("max_health", 200.0)
	_player.add_child(dmg)
	add_child(_player)

	_shark = load("res://scenes/enemies/shark.tscn").instantiate()
	add_child(_shark)
	_shark.global_position = Vector3(0, 0, 0)
	await get_tree().process_frame
	var hp = _shark.get("hp")
	_start_hp = 200.0
	var pd = _player.get_node("Damageable")
	if pd:
		_start_hp = pd.get("current_health")

func _physics_process(delta: float) -> void:
	_t += delta
	if is_instance_valid(_shark):
		_max_y = maxf(_max_y, _shark.global_position.y)
	if _t > 5.0:
		var pd = _player.get_node_or_null("Damageable")
		var hp_now: float = pd.get("current_health") if pd else _start_hp
		var bit := hp_now < _start_hp
		var breached := _max_y > 0.6   # rose above the surface (y=0)
		print("max_y=%.2f  bit=%s  state_ok=%s" % [_max_y, bit, str(is_instance_valid(_shark))])
		print("RESULT ", "PASS" if (breached and bit) else "FAIL")
		get_tree().quit()
