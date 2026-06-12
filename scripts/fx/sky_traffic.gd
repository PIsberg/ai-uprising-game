class_name SkyTraffic
extends Node3D
## Sky life for open-air levels: distant occupation craft endlessly circling
## above the skyline (dark hulls, glowing engines, blinking nav lights) and
## the odd meteor streaking down — the war is bigger than this arena.
## Pure backdrop: everything lives far outside the play space, casts no
## shadows, and is built from a handful of boxes.

@export var arena_radius: float = 30.0 ## Half the floor diagonal, set by the builder.
@export var ship_count: int = 3
@export var accent: Color = Color(1.0, 0.25, 0.15) ## Engine/anti-collision color.

var _meteor_timer: Timer

func _ready() -> void:
	for i in ship_count:
		_build_ship(i)
	_meteor_timer = Timer.new()
	_meteor_timer.one_shot = true
	_meteor_timer.timeout.connect(_on_meteor_timer)
	add_child(_meteor_timer)
	_meteor_timer.start(randf_range(2.0, 6.0))

# ---------- patrol craft ----------

## A ship on a slow circular patrol: a pivot at the level centre spins, the
## hull hangs off it at radius. Each ship gets its own radius/altitude/speed
## and direction so the traffic never reads as a formation.
func _build_ship(i: int) -> void:
	var pivot := Node3D.new()
	pivot.rotation.y = randf() * TAU
	add_child(pivot)
	var ship := Node3D.new()
	var radius := arena_radius + 35.0 + i * 22.0 + randf_range(0.0, 10.0)
	var alt := 32.0 + i * 9.0 + randf_range(0.0, 6.0)
	ship.position = Vector3(radius, alt, 0)
	# Fly nose-first along the orbit (tangent direction).
	var dir := 1.0 if i % 2 == 0 else -1.0
	ship.rotation.y = PI * 0.5 * dir
	pivot.add_child(ship)
	_build_hull(ship)
	var tw := pivot.create_tween().set_loops()
	tw.tween_property(pivot, "rotation:y", TAU * dir, randf_range(70.0, 110.0)).as_relative()

func _build_hull(ship: Node3D) -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.085, 0.1)
	dark.metallic = 0.6
	dark.roughness = 0.5
	var hull := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(2.6, 1.1, 7.5)
	hm.material = dark
	hull.mesh = hm
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ship.add_child(hull)
	var wing := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(7.0, 0.3, 2.4)
	wm.material = dark
	wing.mesh = wm
	wing.position = Vector3(0, -0.1, 1.2)
	wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ship.add_child(wing)
	# Engine glow: two emissive blocks at the stern.
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.45, 0.8, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.45, 0.8, 1.0)
	glow.emission_energy_multiplier = 3.5
	for x in [-0.7, 0.7]:
		var eng := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.7, 0.5, 0.25)
		em.material = glow
		eng.mesh = em
		eng.position = Vector3(x, 0, 3.85)
		eng.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ship.add_child(eng)
	# Belly running-lights: players mostly see these ships from below, so a
	# dim strip along the underside is what makes them read as craft, not blobs.
	var belly := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.35, 0.1, 5.5)
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.5, 0.75, 0.95)
	bmat.emission_enabled = true
	bmat.emission = Color(0.5, 0.75, 0.95)
	bmat.emission_energy_multiplier = 1.6
	bm.material = bmat
	belly.mesh = bm
	belly.position = Vector3(0, -0.62, 0)
	belly.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ship.add_child(belly)
	# Blinking anti-collision light on the tail (reuses the prop Blinker).
	var nav := Blinker.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.3, 0.3, 0.3)
	var nmat := StandardMaterial3D.new()
	nmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nmat.albedo_color = accent
	nmat.emission_enabled = true
	nmat.emission = accent
	nmat.emission_energy_multiplier = 4.0
	nm.material = nmat
	nav.mesh = nm
	nav.min_on = 0.12
	nav.max_on = 0.18
	nav.min_off = 0.9
	nav.max_off = 1.4
	nav.on_energy = 5.0
	nav.position = Vector3(0, 0.75, 3.2)
	nav.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ship.add_child(nav)

# ---------- meteor falls ----------

func _on_meteor_timer() -> void:
	spawn_meteor()
	_meteor_timer.start(randf_range(4.0, 10.0))

## A bright head with a long additive tail, falling on a steep diagonal far
## beyond the walls, burning out before it would ever reach the skyline.
func spawn_meteor() -> void:
	var ang := randf() * TAU
	var dist := arena_radius + randf_range(50.0, 120.0)
	var start := Vector3(cos(ang) * dist, randf_range(55.0, 85.0), sin(ang) * dist)
	var fall := Vector3(randf_range(-0.5, 0.5), -1.0, randf_range(-0.5, 0.5)).normalized() * randf_range(45.0, 70.0)
	var life := randf_range(0.9, 1.4)
	var meteor := Node3D.new()
	add_child(meteor)
	meteor.global_position = start
	meteor.look_at(start + fall) # -Z down the fall line; the tail stretches back
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.85, 0.6, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.5)
	mat.emission_energy_multiplier = 3.0
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = mat
	head.mesh = sm
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	meteor.add_child(head)
	var tail := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.35, 0.35, 14.0)
	tm.material = mat
	tail.mesh = tm
	tail.position = Vector3(0, 0, 7.5) # trailing behind the head (+Z = backwards)
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	meteor.add_child(tail)
	var tw := meteor.create_tween().set_parallel(true)
	tw.tween_property(meteor, "global_position", start + fall * life, life)
	tw.tween_property(mat, "albedo_color:a", 0.0, life) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(meteor.queue_free)
