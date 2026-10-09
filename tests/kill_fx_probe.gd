extends Node
## Probe: weapon-specific deaths (KillFx) through the real weapon hit paths.
## (1) the energy guns carry their kill style in their WeaponData;
## (2) a gauss hitscan kill DISINTEGRATES: dissolve materials, no wreck debris,
##     the robot is gone within the dissolve time and leaves an ash scorch;
## (3) a plasma projectile kill disintegrates too (projectile + splash path);
## (4) an arc-coil kill ELECTROCUTES: convulsing under the shock skin with no
##     debris yet, then the classic blast and topple once the spasms end;
## (5) a non-tagged kill (a grenade or hazard) after an energy hit stays classic,
##     and the tag never outlives the hit that set it;
## (6) bosses keep the classic death.
##   godot --headless --path . --audio-driver Dummy res://tests/kill_fx_probe.tscn

const ANDROID := "res://scenes/enemies/android.tscn"
var ok := true
var _blasts := 0 ## classic death blasts (enemy_explosion.tscn) spawned so far

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	child_entered_tree.connect(func(n: Node) -> void:
			if n.scene_file_path == "res://scenes/fx/enemy_explosion.tscn":
				_blasts += 1)
	# 1. Data.
	var want := {"gauss": 1, "sniper": 1, "plasma": 1, "omega": 1,
			"tesla": 2, "arccoil": 2, "tempest": 2, "pistol": 0, "rifle": 0,
			"shotgun": 0, "magnum": 0, "devastator": 0, "swarm": 0}
	for k in want:
		var d: WeaponData = load("res://assets/weapons/%s_data.tres" % k)
		_check("%s kill_fx" % k, d.kill_fx == want[k], "got %d want %d" % [d.kill_fx, want[k]])

	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(200, 1, 200)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var shooter := Node3D.new()
	shooter.add_to_group("player")
	add_child(shooter)
	shooter.global_position = Vector3(0, 1.5, 60)

	# 2. Gauss hitscan kill.
	var gauss := _gun("gauss", shooter)
	var e := _robot(Vector3(0, 0, 0))
	await _frames(3)
	var blasts0 := _blasts
	_wake(e)
	e.hp.current_health = 1.0
	gauss._do_hitscan(Vector3(0, 1.2, 10), Vector3(0, 0, -1))
	_check("gauss killed the android", not e.hp.is_alive())
	_check("tag cleared after the hit", e.hp.kill_fx == KillFx.NONE)
	_check("disintegrate: dissolve materials", _dissolving(e) > 0, "%d meshes" % _dissolving(e))
	await _frames(30)
	var mid := _progress(e)
	_check("disintegrate: half way through at 0.5 s", mid > 0.1 and mid < 0.95, "%.2f" % mid)
	_check("disintegrate: no death blast", _blasts == blasts0, "%d -> %d" % [blasts0, _blasts])
	await _frames(int(KillFx.DISSOLVE_TIME * 60.0))
	_check("disintegrate: robot gone after the dissolve", not is_instance_valid(e))
	_check("disintegrate: ash scorch left", _has_scorch())

	# 3. Plasma projectile kill.
	var plasma := _gun("plasma", shooter)
	var p := _robot(Vector3(30, 0, 0))
	await _frames(3)
	blasts0 = _blasts
	_wake(p)
	p.hp.current_health = 1.0
	plasma._spawn_projectile(Vector3(30, 1.2, 8), Vector3(0, 0, -1))
	for i in 90:
		await get_tree().physics_frame
		if not is_instance_valid(p) or not p.hp.is_alive():
			break
	_check("plasma round killed it", not is_instance_valid(p) or not p.hp.is_alive())
	_check("plasma kill disintegrates", is_instance_valid(p) and _dissolving(p) > 0)
	await _frames(10)
	_check("plasma kill: no death blast", _blasts == blasts0, "%d -> %d" % [blasts0, _blasts])

	# 4. Arc-coil hitscan kill electrocutes, then blows.
	var arc := _gun("arccoil", shooter)
	var z := _robot(Vector3(-30, 0, 0))
	await _frames(3)
	blasts0 = _blasts
	_wake(z)
	z.hp.current_health = 1.0
	arc._do_hitscan(Vector3(-30, 1.2, 10), Vector3(0, 0, -1))
	_check("arc coil killed it", not z.hp.is_alive())
	await _frames(15)
	_check("electrocute: shock skin on the chassis", _shocked(z) > 0, "%d meshes" % _shocked(z))
	_check("electrocute: no blast during the spasms", _blasts == blasts0)
	_check("electrocute: no dissolve", _dissolving(z) == 0)
	await _frames(int(KillFx.SHOCK_TIME * 60.0) + 10)
	_check("electrocute: classic blast after the spasms", _blasts == blasts0 + 1, "%d -> %d" % [blasts0, _blasts])
	_check("electrocute: shock skin removed", is_instance_valid(z) and _shocked(z) == 0)

	# 5. Energy hit, then an untagged kill.
	var g := _robot(Vector3(60, 0, 0))
	g.hp.max_health = 100000.0
	g.hp.current_health = 100000.0
	await _frames(3)
	blasts0 = _blasts
	_wake(g)
	gauss._do_hitscan(Vector3(60, 1.2, 10), Vector3(0, 0, -1))
	_check("gauss hit landed", g.hp.current_health < 100000.0)
	_check("tag does not outlive the hit", g.hp.kill_fx == KillFx.NONE)
	g.hp.apply_damage(999999.0, shooter, false, g.global_position) # grenade splash
	await _frames(6)
	_check("untagged kill stays classic", _dissolving(g) == 0 and _blasts == blasts0 + 1)

	# 6. Boss-sized kill keeps the classic death.
	var b := _robot(Vector3(-60, 0, 0))
	b.score_value = 1000
	await _frames(3)
	blasts0 = _blasts
	_wake(b)
	b.hp.current_health = 1.0
	gauss._do_hitscan(Vector3(-60, 1.2, 10), Vector3(0, 0, -1))
	await _frames(6)
	_check("boss kill: no disintegrate", is_instance_valid(b) and _dissolving(b) == 0 and _blasts == blasts0 + 1)

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _gun(id: String, shooter: Node) -> Weapon:
	var w: Weapon = (load("res://scenes/weapons/%s.tscn" % id) as PackedScene).instantiate()
	add_child(w)
	w._active_shooter = shooter
	return w

func _robot(pos: Vector3) -> EnemyBase:
	var e: EnemyBase = (load(ANDROID) as PackedScene).instantiate()
	# AI off, collision on: a disabled body is otherwise REMOVED from physics.
	e.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	e.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(e)
	e.global_position = pos
	return e

## The death tweens are bound to the robot, so it must process when it dies.
func _wake(e: EnemyBase) -> void:
	e.process_mode = Node.PROCESS_MODE_INHERIT

func _has_scorch() -> bool:
	for c in get_children():
		if c is ScorchMark:
			return true
	return false

func _dissolving(e: Node) -> int:
	var n := 0
	for mi in e.find_children("*", "MeshInstance3D", true, false):
		for s in (mi as MeshInstance3D).get_surface_override_material_count():
			var m := (mi as MeshInstance3D).get_surface_override_material(s) as ShaderMaterial
			if m and m.shader == KillFx.DISSOLVE_SHADER:
				n += 1
				break
	return n

func _progress(e: Node) -> float:
	if not is_instance_valid(e):
		return -1.0
	for mi in e.find_children("*", "MeshInstance3D", true, false):
		var v = (mi as MeshInstance3D).get_instance_shader_parameter("dissolve")
		if v is float:
			return v
	return -1.0

func _shocked(e: Node) -> int:
	var n := 0
	for mi in e.find_children("*", "MeshInstance3D", true, false):
		var o := (mi as MeshInstance3D).material_overlay as StandardMaterial3D
		if o and Color(o.albedo_color, 1.0).is_equal_approx(Color(KillFx.SHOCK_COLOR, 1.0)):
			n += 1
	return n
