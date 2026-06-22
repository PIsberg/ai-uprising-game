class_name SimpleProp
extends Node3D
## A family of lightweight, fully-procedural props (no external model assets) so
## the level editor has a big obstacle/nature/water vocabulary. One scene per
## `kind` (scenes/props/<kind>.tscn) sets the kind; LevelBuilder.PROP_SCENES maps
## the editor type -> that scene. Solid kinds add a StaticBody collider on the
## world layer so they block fire and the navmesh routes around them; decorative
## kinds (grass, water, flowers...) are visual only.

@export var kind: String = "rock"

func _ready() -> void:
	_build()

func _build() -> void:
	match kind:
		"pine": _pine()
		"dead_tree": _dead_tree()
		"bush": _bush()
		"grass": _grass()
		"flowers": _flowers()
		"reeds": _reeds()
		"fern": _fern()
		"mushroom": _mushroom()
		"log": _log()
		"stump": _stump()
		"rock": _rock(1.0)
		"boulder": _rock(1.9)
		"rubble": _rubble()
		"river": _water(Vector3(4, 0.08, 16), Color(0.18, 0.4, 0.55, 0.7))
		"pond": _pond()
		"barrier": _barrier()
		"sandbags": _sandbags()
		"planter": _planter()
		"hydrant": _hydrant()
		"dumpster": _dumpster()
		"cone": _cone_prop()
		"bench": _bench()
		"pillar": _pillar()
		"statue": _statue()
		"crate_stack": _crate_stack()
		_: _rock(1.0)

# ---------- mesh helpers ----------

func _mat(c: Color, rough := 0.9, metal := 0.0, emis := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emis:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.0
	return m

func _box(size: Vector3, c: Color, pos: Vector3, rot := Vector3.ZERO, mat: StandardMaterial3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm
	mi.material_override = mat if mat else _mat(c)
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi

func _cyl(rt: float, rb: float, h: float, c: Color, pos: Vector3, mat: StandardMaterial3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = rt; cm.bottom_radius = rb; cm.height = h; cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = mat if mat else _mat(c)
	mi.position = pos
	add_child(mi)
	return mi

func _sphere(r: float, c: Color, pos: Vector3, mat: StandardMaterial3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 8; sm.rings = 5
	mi.mesh = sm
	mi.material_override = mat if mat else _mat(c)
	mi.position = pos
	add_child(mi)
	return mi

func _collide_box(size: Vector3, ypos: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("surf_metal")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new(); sh.size = size
	cs.shape = sh
	cs.position = Vector3(0, ypos, 0)
	body.add_child(cs)
	add_child(body)

func _collide_cyl(r: float, h: float, ypos: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new(); sh.radius = r; sh.height = h
	cs.shape = sh
	cs.position = Vector3(0, ypos, 0)
	body.add_child(cs)
	add_child(body)

# ---------- nature ----------

func _pine() -> void:
	var bark := _mat(Color(0.32, 0.22, 0.13))
	var needle := _mat(Color(0.13, 0.33, 0.16))
	var h := randf_range(3.0, 4.5)
	_cyl(0.12, 0.2, h * 0.5, Color.BLACK, Vector3(0, h * 0.25, 0), bark)
	var tiers := 3
	for i in tiers:
		var t := float(i) / tiers
		var r := lerpf(1.3, 0.4, t)
		_cyl(0.0, r, 1.2, Color.BLACK, Vector3(0, h * 0.4 + t * h * 0.55, 0), needle)
	_collide_cyl(0.22, h * 0.5, h * 0.25)

func _dead_tree() -> void:
	var bark := _mat(Color(0.3, 0.27, 0.24))
	var h := randf_range(2.6, 3.6)
	_cyl(0.1, 0.22, h, Color.BLACK, Vector3(0, h * 0.5, 0), bark)
	for i in 4:
		var a := randf() * TAU
		var br := _cyl(0.03, 0.07, randf_range(0.8, 1.4), Color.BLACK, Vector3(sin(a) * 0.3, h * randf_range(0.6, 0.95), cos(a) * 0.3), bark)
		br.rotation = Vector3(randf_range(-0.8, -0.3), a, randf_range(-0.4, 0.4))
	_collide_cyl(0.22, h, h * 0.5)

func _bush() -> void:
	var g := _mat(Color(0.16, 0.34, 0.18))
	for i in 4:
		_sphere(randf_range(0.4, 0.6), Color.BLACK, Vector3(randf_range(-0.4, 0.4), randf_range(0.3, 0.6), randf_range(-0.4, 0.4)), g)

func _grass() -> void:
	var g := _mat(Color(0.25, 0.45, 0.2))
	for i in 14:
		var blade := _box(Vector3(0.04, randf_range(0.3, 0.6), 0.04), Color.BLACK, Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5)), Vector3.ZERO, g)
		blade.position.y = blade.mesh.size.y * 0.5
		blade.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))

func _flowers() -> void:
	_grass()
	for i in 5:
		var col: Color = [Color(1, 0.8, 0.2), Color(0.9, 0.3, 0.5), Color(0.7, 0.4, 1.0)][randi() % 3]
		_sphere(0.07, Color.BLACK, Vector3(randf_range(-0.4, 0.4), randf_range(0.4, 0.6), randf_range(-0.4, 0.4)), _mat(col, 0.6, 0.0, true))

func _reeds() -> void:
	var g := _mat(Color(0.4, 0.5, 0.25))
	for i in 10:
		var b := _box(Vector3(0.03, randf_range(0.8, 1.4), 0.03), Color.BLACK, Vector3.ZERO, Vector3.ZERO, g)
		b.position = Vector3(randf_range(-0.4, 0.4), b.mesh.size.y * 0.5, randf_range(-0.4, 0.4))
		b.rotation = Vector3(randf_range(-0.15, 0.15), randf() * TAU, randf_range(-0.15, 0.15))

func _fern() -> void:
	var g := _mat(Color(0.18, 0.4, 0.2))
	for i in 6:
		var a := TAU * i / 6.0
		var frond := _box(Vector3(0.06, 0.04, 0.8), Color.BLACK, Vector3(sin(a) * 0.2, 0.25, cos(a) * 0.2), Vector3(-0.5, a, 0), g)

func _mushroom() -> void:
	_cyl(0.06, 0.08, 0.22, Color.BLACK, Vector3(0, 0.11, 0), _mat(Color(0.85, 0.82, 0.7)))
	_sphere(0.16, Color.BLACK, Vector3(0, 0.26, 0), _mat(Color(0.7, 0.2, 0.15)))

func _log() -> void:
	var l := _cyl(0.3, 0.3, 2.2, Color.BLACK, Vector3(0, 0.3, 0), _mat(Color(0.34, 0.24, 0.15)))
	l.rotation = Vector3(0, 0, PI * 0.5)
	_collide_box(Vector3(2.2, 0.6, 0.6), 0.3)

func _stump() -> void:
	_cyl(0.4, 0.45, 0.6, Color.BLACK, Vector3(0, 0.3, 0), _mat(Color(0.36, 0.26, 0.16)))
	_cyl(0.34, 0.34, 0.05, Color.BLACK, Vector3(0, 0.6, 0), _mat(Color(0.5, 0.4, 0.28)))
	_collide_cyl(0.45, 0.6, 0.3)

func _rock(scale: float) -> void:
	var grey := _mat(Color(0.4, 0.41, 0.43))
	for i in 3:
		var s := randf_range(0.5, 0.9) * scale
		var mi := _sphere(s, Color.BLACK, Vector3(randf_range(-0.3, 0.3) * scale, s * 0.5, randf_range(-0.3, 0.3) * scale), grey)
		mi.scale = Vector3(1.0, randf_range(0.6, 0.9), 1.0)
	_collide_box(Vector3(1.4 * scale, 1.0 * scale, 1.4 * scale), 0.5 * scale)

func _rubble() -> void:
	var grey := _mat(Color(0.33, 0.32, 0.31))
	for i in 8:
		var s := randf_range(0.15, 0.4)
		_box(Vector3(s, s * 0.7, s * 1.2), Color.BLACK, Vector3(randf_range(-0.7, 0.7), s * 0.35, randf_range(-0.7, 0.7)), Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3)), grey)

# ---------- water ----------

func _water(size: Vector3, c: Color) -> void:
	var m := _mat(c, 0.1, 0.3)
	m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 0.15
	_box(size, Color.BLACK, Vector3(0, size.y * 0.5, 0), Vector3.ZERO, m)

func _pond() -> void:
	var c := Color(0.16, 0.38, 0.5, 0.7)
	var m := _mat(c, 0.1, 0.3)
	_cyl(3.0, 3.0, 0.1, Color.BLACK, Vector3(0, 0.05, 0), m)

# ---------- urban obstacles ----------

func _barrier() -> void:
	var grey := _mat(Color(0.6, 0.6, 0.62))
	# Jersey barrier: wide base tapering up.
	_box(Vector3(2.0, 0.4, 0.7), Color.BLACK, Vector3(0, 0.2, 0), Vector3.ZERO, grey)
	_box(Vector3(2.0, 0.6, 0.35), Color.BLACK, Vector3(0, 0.7, 0), Vector3.ZERO, grey)
	_collide_box(Vector3(2.0, 1.0, 0.7), 0.5)

func _sandbags() -> void:
	var tan := _mat(Color(0.55, 0.48, 0.32))
	for row in 3:
		var n := 3 - row
		for i in n:
			var mi := _sphere(0.28, Color.BLACK, Vector3((i - (n - 1) * 0.5) * 0.55, 0.2 + row * 0.32, 0), tan)
			mi.scale = Vector3(1.3, 0.7, 0.9)
	_collide_box(Vector3(1.8, 1.0, 0.7), 0.5)

func _planter() -> void:
	_box(Vector3(1.2, 0.6, 1.2), Color.BLACK, Vector3(0, 0.3, 0), Vector3.ZERO, _mat(Color(0.5, 0.5, 0.52)))
	_box(Vector3(1.0, 0.1, 1.0), Color.BLACK, Vector3(0, 0.62, 0), Vector3.ZERO, _mat(Color(0.25, 0.18, 0.1)))
	_sphere(0.5, Color.BLACK, Vector3(0, 1.0, 0), _mat(Color(0.18, 0.36, 0.2)))
	_collide_box(Vector3(1.2, 0.7, 1.2), 0.35)

func _hydrant() -> void:
	var red := _mat(Color(0.75, 0.15, 0.12))
	_cyl(0.13, 0.16, 0.6, Color.BLACK, Vector3(0, 0.3, 0), red)
	_sphere(0.16, Color.BLACK, Vector3(0, 0.62, 0), red)
	_box(Vector3(0.5, 0.1, 0.12), Color.BLACK, Vector3(0, 0.4, 0), Vector3.ZERO, red)
	_collide_cyl(0.2, 0.7, 0.35)

func _dumpster() -> void:
	var green := _mat(Color(0.2, 0.4, 0.25))
	_box(Vector3(2.0, 1.2, 1.1), Color.BLACK, Vector3(0, 0.6, 0), Vector3.ZERO, green)
	_box(Vector3(2.1, 0.1, 1.2), Color.BLACK, Vector3(0, 1.2, 0), Vector3.ZERO, _mat(Color(0.15, 0.15, 0.16)))
	_collide_box(Vector3(2.0, 1.2, 1.1), 0.6)

func _cone_prop() -> void:
	_cyl(0.0, 0.22, 0.6, Color.BLACK, Vector3(0, 0.3, 0), _mat(Color(0.95, 0.45, 0.1, 1.0), 0.6))
	_box(Vector3(0.5, 0.05, 0.5), Color.BLACK, Vector3(0, 0.03, 0), Vector3.ZERO, _mat(Color(0.9, 0.4, 0.1)))

func _bench() -> void:
	var wood := _mat(Color(0.42, 0.3, 0.18))
	var metal := _mat(Color(0.3, 0.3, 0.33), 0.5, 0.6)
	_box(Vector3(1.8, 0.1, 0.5), Color.BLACK, Vector3(0, 0.5, 0), Vector3.ZERO, wood)
	_box(Vector3(1.8, 0.5, 0.1), Color.BLACK, Vector3(0, 0.75, -0.2), Vector3.ZERO, wood)
	for x in [-0.8, 0.8]:
		_box(Vector3(0.1, 0.5, 0.5), Color.BLACK, Vector3(x, 0.25, 0), Vector3.ZERO, metal)
	_collide_box(Vector3(1.8, 1.0, 0.5), 0.5)

func _pillar() -> void:
	var stone := _mat(Color(0.62, 0.6, 0.55))
	_box(Vector3(0.9, 0.3, 0.9), Color.BLACK, Vector3(0, 0.15, 0), Vector3.ZERO, stone)
	_cyl(0.32, 0.36, 3.0, Color.BLACK, Vector3(0, 1.8, 0), stone)
	_box(Vector3(0.9, 0.3, 0.9), Color.BLACK, Vector3(0, 3.45, 0), Vector3.ZERO, stone)
	_collide_cyl(0.4, 3.6, 1.8)

func _statue() -> void:
	var stone := _mat(Color(0.55, 0.54, 0.5))
	_box(Vector3(1.2, 0.6, 1.2), Color.BLACK, Vector3(0, 0.3, 0), Vector3.ZERO, stone)
	_cyl(0.25, 0.3, 1.4, Color.BLACK, Vector3(0, 1.3, 0), stone)
	_sphere(0.28, Color.BLACK, Vector3(0, 2.2, 0), stone)
	for x in [-0.4, 0.4]:
		_box(Vector3(0.15, 1.0, 0.15), Color.BLACK, Vector3(x, 1.5, 0), Vector3(0, 0, x * 0.4), stone)
	_collide_box(Vector3(1.2, 2.4, 1.2), 1.2)

func _crate_stack() -> void:
	var w := _mat(Color(0.5, 0.38, 0.22))
	_box(Vector3(1.0, 1.0, 1.0), Color.BLACK, Vector3(0, 0.5, 0), Vector3.ZERO, w)
	_box(Vector3(0.9, 0.9, 0.9), Color.BLACK, Vector3(0.5, 1.45, 0.3), Vector3(0, 0.3, 0), w)
	_box(Vector3(0.8, 0.8, 0.8), Color.BLACK, Vector3(-0.4, 0.4, 0.6), Vector3(0, 0.6, 0), w)
	_collide_box(Vector3(1.8, 1.0, 1.6), 0.5)
