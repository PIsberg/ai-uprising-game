extends Node3D
## Probe: a heavy round's blast scorch (ScorchDecal) lies on the face it struck.
## The decal used to project straight down wherever the blast was, so a rocket
## into a wall smeared its burn and ember ring down the wall as two vertical
## stripes (seen in tests/palm_fx_shot). Through the Devastator's real rocket:
##   - into a wall: one scorch, its projection axis (local Y) along the wall's
##     normal, centred on the wall's face;
##   - down at the floor: one scorch, axis up, as before;
##   - burst in the open air: one scorch, axis up, as before (it marks whatever
##     is below within the decal's depth);
##   - ScorchDecal.spawn with no normal still projects down (grenades, the
##     seeker and the convoy call it that way).
##   godot --headless --path . --audio-driver Dummy res://tests/scorch_wall_probe.tscn

var ok := true
var marks: Array = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _on_node(n: Node) -> void:
	if n is ScorchDecal:
		marks.append(n)

func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	_box(Vector3(0, -0.5, -10), Vector3(80, 1, 80)) # floor, top at y = 0
	_box(Vector3(0, 3.0, -8), Vector3(8, 6, 0.5)) # wall, face at z = -7.75, normal +Z
	var w: Weapon = (load("res://scenes/weapons/devastator.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().physics_frame
	w._active_shooter = null
	get_tree().node_added.connect(_on_node)

	# Into the wall, 3 m up (the floor is out of the old downward decal's reach).
	await _fire(w, Vector3(0, 3.0, 4), Vector3(0, 0, -1))
	_check("a rocket into a wall leaves one scorch", marks.size() == 1, str(marks.size()))
	if marks.size() == 1:
		var d: Decal = marks[0]
		_check("its projection axis lies along the wall's normal", absf(d.global_basis.y.normalized().dot(Vector3(0, 0, 1))) > 0.97,
				"axis %s" % d.global_basis.y.normalized())
		_check("it is centred on the wall's face", absf(d.global_position.z - (-7.75)) < 0.5 and absf(d.global_position.y - 3.0) < 0.5,
				str(d.global_position))

	# Down at the floor.
	marks.clear()
	await _fire(w, Vector3(20, 4, 0), Vector3(0, -1, -0.4).normalized())
	_check("a rocket into the floor leaves one scorch", marks.size() == 1, str(marks.size()))
	if marks.size() == 1:
		_check("its axis is up", (marks[0] as Decal).global_basis.y.normalized().dot(Vector3.UP) > 0.97,
				"axis %s" % (marks[0] as Decal).global_basis.y.normalized())

	# In the open air.
	marks.clear()
	var before := get_children()
	w._spawn_projectile(Vector3(-20, 10, 0), Vector3(0, 0, -1))
	for n in get_children():
		if not n in before and n.has_method("launch"):
			n._explode(n.global_position)
	await get_tree().process_frame
	_check("an air burst leaves one scorch, axis up", marks.size() == 1
			and (marks[0] as Decal).global_basis.y.normalized().dot(Vector3.UP) > 0.97, str(marks.size()))

	# The plain call.
	marks.clear()
	ScorchDecal.spawn(self, Vector3(-30, 0, 0), 2.0)
	_check("spawn with no normal projects down", marks.size() == 1
			and (marks[0] as Decal).global_basis.y.normalized().dot(Vector3.UP) > 0.999, str(marks.size()))
	get_tree().node_added.disconnect(_on_node)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## Fire one rocket and wait for it to go off.
func _fire(w: Weapon, origin: Vector3, dir: Vector3) -> void:
	var before := get_children()
	w._spawn_projectile(origin, dir)
	var proj: Node = null
	for n in get_children():
		if not n in before and n.has_method("launch"):
			proj = n
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(proj) and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().physics_frame
	await get_tree().process_frame

func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = at
	return sb
