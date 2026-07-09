extends Node3D
## Reproduces the reported "I shoot / get shot and lose my weapons" bug.
## Spawns the real player + rack, then alternates firing and taking damage while
## watching the rack EVERY frame for: current going null/freed, current going
## invisible while drawn, the weapons array shrinking, or current_index drifting.
##   godot --headless --path . res://tests/weapon_vanish_probe.tscn

const FRAMES := 3000

var _player: Node3D
var _wm: Node
var _bad := 0

func _ready() -> void:
	_run.call_deferred()

func _report(msg: String) -> void:
	_bad += 1
	print("BAD  f=%d  %s" % [_f, msg])

var _f := 0
var _hip0: Vector3

func _run() -> void:
	# A REAL level: default rack (no unlock_all), real robots shooting back, real
	# pickups on the floor. The bug is reported during ordinary play.
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	for i in 60:
		await get_tree().physics_frame
	GameState.set_state(GameState.State.PLAYING)
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_wm = _player.get_node_or_null("Head/Camera3D/WeaponHolder")
	var hp: Node = _player.get_node_or_null("Damageable")
	hp.max_health = 1000000.0
	hp.current_health = 1000000.0
	print("rack size = ", _wm.weapons.size(), "  index = ", _wm.current_index)
	var n0: int = _wm.weapons.size()
	_hip0 = _wm.position

	# Weapons the player can find on the floor mid-fight.
	var PICKUPS := ["shotgun", "magnum", "tesla", "arccoil", "sniper", "plasma",
		"gauss", "swarm", "tempest", "devastator", "omega"]
	var pick := 0
	var prev_name := ""
	for i in FRAMES:
		_f = i
		# Fire continuously; every 40 frames take a hit; every 90 frames swap;
		# every 120 frames pick a new gun up off the floor, mid-trigger-pull.
		Input.action_press("fire")
		if i % 40 == 0:
			hp.apply_damage(7.0, null)
		if i % 120 == 0 and pick < PICKUPS.size():
			var ps: PackedScene = load("res://scenes/weapons/%s.tscn" % PICKUPS[pick])
			pick += 1
			_wm.add_weapon(ps, true)
			n0 = _wm.weapons.size()
		if i % 90 == 0:
			Input.action_press("weapon_next")
		await get_tree().physics_frame
		Input.action_release("weapon_next")
		hp.current_health = 1000000.0

		var cur = _wm.current
		if cur == null or not is_instance_valid(cur):
			_report("current is null/freed (index=%d size=%d)" % [_wm.current_index, _wm.weapons.size()])
			break
		if _wm.weapons.size() != n0:
			_report("rack shrank %d -> %d" % [n0, _wm.weapons.size()])
			break
		if not cur.visible and _wm._equip_timer <= 0.0:
			_report("'%s' INVISIBLE while drawn (equip_timer=%.2f)" % [cur.name, _wm._equip_timer])
			break
		# The weapon can also "vanish" without leaving the rack: hidden by a parent,
		# or shoved out of the camera frustum by drifting recoil/sway/ADS maths.
		if not cur.is_visible_in_tree() and _wm._equip_timer <= 0.0:
			_report("'%s' not visible IN TREE (holder.visible=%s)" % [cur.name, _wm.visible])
			break
		var holder_off: float = (_wm.position - _hip0).length()
		if holder_off > 1.5:
			_report("holder drifted %.2f m from hip (pos=%v)" % [holder_off, _wm.position])
			break
		if cur.get("viewmodel") != null:
			var vm: Node3D = cur.get("viewmodel")
			if not is_instance_valid(vm):
				_report("'%s' viewmodel FREED" % cur.name)
				break
			var vm_off: float = (vm.position - cur.get("_viewmodel_home")).length()
			if vm_off > 1.5:
				_report("'%s' viewmodel drifted %.2f m from home (pos=%v)" % [cur.name, vm_off, vm.position])
				break
		prev_name = cur.name
	Input.action_release("fire")
	print("rack size at end = ", _wm.weapons.size(), " index = ", _wm.current_index)
	print("RESULT ", "PASS (no vanish)" if _bad == 0 else "FAIL")
	get_tree().quit()
