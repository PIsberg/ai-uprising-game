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
## (6) bosses keep the classic death;
## (7) the robots with their own _on_died (#194): a gauss kill dissolves a
##     drone, raptor, mender and skitter in place with no death blast; an arc
##     kill holds a drone in the air through the spasms, then it falls; a
##     seeker keeps its shot-down blast (that blast is a mechanic);
## (8) a shotgun or magnum kill SHREDS: the robot is hurled away from the shooter
##     in a tumbling arc with no blast in the air, scrap sprays out of its back,
##     and the classic blast goes off where it lands; a wall behind it stops the
##     flight short; a drone shot down by the magnum is kicked away and falls,
##     never electrocuted.
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
			"shotgun": 3, "magnum": 3, "devastator": 0, "swarm": 0}
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

	# 7. Robots with their own _on_died.
	var x := 90.0
	for scene in ["drone", "raptor", "mender", "skitter"]:
		var r := _robot(Vector3(x, 0, 0), "res://scenes/enemies/%s.tscn" % scene)
		if scene != "skitter":
			r.global_position.y = 3.0
		await _frames(3)
		blasts0 = _blasts
		_wake(r)
		r.hp.current_health = 1.0
		var at := _body_centre(r)
		gauss._do_hitscan(at + Vector3(0, 0, 10), Vector3(0, 0, -1))
		_check("%s: gauss killed it" % scene, not is_instance_valid(r) or not r.hp.is_alive())
		_check("%s: disintegrates" % scene, is_instance_valid(r) and _dissolving(r) > 0)
		await _frames(int(KillFx.DISSOLVE_TIME * 60.0) + 20)
		_check("%s: no death blast, gone after the dissolve" % scene,
				_blasts == blasts0 and not is_instance_valid(r), "%d -> %d" % [blasts0, _blasts])
		x += 12.0
	var dz := _robot(Vector3(x, 3.0, 0), "res://scenes/enemies/drone.tscn")
	await _frames(3)
	_wake(dz)
	dz.hp.current_health = 1.0
	var y0 := dz.global_position.y
	arc._do_hitscan(_body_centre(dz) + Vector3(0, 0, 10), Vector3(0, 0, -1))
	await _frames(20)
	_check("drone: electrocuted in the air", is_instance_valid(dz) and _shocked(dz) > 0
			and absf(dz.global_position.y - y0) < 0.3 and not dz._dying)
	await _frames(int(KillFx.SHOCK_TIME * 60.0) + 10)
	_check("drone: then loses lift", is_instance_valid(dz) and dz._dying)
	x += 12.0
	var sk := _robot(Vector3(x, 2.0, 0), "res://scenes/enemies/seeker.tscn")
	await _frames(3)
	_wake(sk)
	sk.hp.current_health = 1.0
	gauss._do_hitscan(_body_centre(sk) + Vector3(0, 0, 10), Vector3(0, 0, -1))
	await _frames(3)
	_check("seeker: keeps its blast", not is_instance_valid(sk) or _dissolving(sk) == 0)
	_check("seeker: detonated", not is_instance_valid(sk) or sk._detonated)

	# 8. SHRED: ballistic kills hurl the robot off its feet.
	var ballistic := Node3D.new()
	ballistic.add_to_group("player")
	add_child(ballistic)
	ballistic.global_position = Vector3(-120, 1.5, 30)
	var shotgun := _gun("shotgun", ballistic)
	var s := _robot(Vector3(-120, 0, 0))
	await _frames(3)
	blasts0 = _blasts
	_wake(s)
	s.hp.current_health = 1.0
	var s0 := s.global_position
	shotgun._do_hitscan(Vector3(-120, 1.2, 10), Vector3(0, 0, -1))
	_check("shotgun killed it", not s.hp.is_alive())
	_check("shred: tag cleared", s.hp.kill_fx == KillFx.NONE)
	_check("shred: scrap sprays out", _scrap() > 0, "%d emitters" % _scrap())
	await _frames(int(KillFx.SHRED_TIME * 60.0 * 0.5))
	_check("shred: airborne mid-flight", s.global_position.y > s0.y + 0.2, "y %.2f" % s.global_position.y)
	_check("shred: thrown away from the shooter", s.global_position.z < s0.z - 0.5, "z %.2f" % s.global_position.z)
	_check("shred: no blast in the air", _blasts == blasts0, "%d -> %d" % [blasts0, _blasts])
	await _frames(int(KillFx.SHRED_TIME * 60.0 * 0.5) + 6)
	_check("shred: classic blast where it lands", _blasts == blasts0 + 1, "%d -> %d" % [blasts0, _blasts])
	_check("shred: landed metres back", is_instance_valid(s) and s0.z - s.global_position.z > KillFx.SHRED_FLING * 0.8,
			"%.2f m" % (s0.z - s.global_position.z if is_instance_valid(s) else -1.0))
	_check("shred: no dissolve, no shock skin", is_instance_valid(s) and _dissolving(s) == 0 and _shocked(s) == 0)

	# A wall a metre and a half behind the robot stops the flight short.
	ballistic.global_position = Vector3(-150, 1.5, 30)
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbs := BoxShape3D.new()
	wbs.size = Vector3(6, 4, 0.5)
	wcs.shape = wbs
	wall.add_child(wcs)
	add_child(wall)
	wall.global_position = Vector3(-150, 2, -1.5)
	var mag := _gun("magnum", ballistic)
	var w := _robot(Vector3(-150, 0, 0))
	await _frames(3)
	_wake(w)
	w.hp.current_health = 1.0
	mag._do_hitscan(Vector3(-150, 1.2, 10), Vector3(0, 0, -1))
	_check("magnum killed it", not w.hp.is_alive())
	await _frames(int(KillFx.SHRED_TIME * 60.0) + 6)
	_check("shred: stops short of a wall", is_instance_valid(w) and w.global_position.z > -1.3,
			"z %.2f" % (w.global_position.z if is_instance_valid(w) else 99.0))

	# A drone shot down by the magnum is kicked away and falls; never shocked.
	ballistic.global_position = Vector3(-180, 3.0, 30)
	var dm := _robot(Vector3(-180, 3.0, 0), "res://scenes/enemies/drone.tscn")
	await _frames(3)
	_wake(dm)
	dm.hp.current_health = 1.0
	mag._do_hitscan(_body_centre(dm) + Vector3(0, 0, 10), Vector3(0, 0, -1))
	await _frames(4)
	_check("drone: shred is not electrocute", is_instance_valid(dm) and _shocked(dm) == 0)
	_check("drone: kicked away and falling", is_instance_valid(dm) and dm._dying and dm.velocity.z < -3.0,
			"vz %.2f" % (dm.velocity.z if is_instance_valid(dm) else 0.0))

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## Scrap-spray emitters a SHRED kill left in the scene.
func _scrap() -> int:
	var n := 0
	for c in get_children():
		if c.name.begins_with("ShredScrap"):
			n += 1
	return n

## Where a shot lands on `e`: its first collision shape's centre.
func _body_centre(e: Node3D) -> Vector3:
	for c in e.find_children("*", "CollisionShape3D", true, false):
		return (c as Node3D).global_position
	return e.global_position + Vector3.UP * 0.5

func _gun(id: String, shooter: Node) -> Weapon:
	var w: Weapon = (load("res://scenes/weapons/%s.tscn" % id) as PackedScene).instantiate()
	add_child(w)
	w._active_shooter = shooter
	return w

func _robot(pos: Vector3, scene: String = ANDROID) -> EnemyBase:
	var e: EnemyBase = (load(scene) as PackedScene).instantiate()
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
