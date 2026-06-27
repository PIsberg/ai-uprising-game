class_name EnemyFishbot
extends EnemyDrone
## ANGLER UNIT — a robotic deep-sea fish that prowls the flooded basins. Built on
## the drone's flight AI but faster and more darting, with an undulating swim, a
## finned silhouette (tail, dorsal, pectorals), a needle harpoon-nose and a trail
## of bubbles. It spits pressurised water bolts. Native to the water world.

func _ready() -> void:
	super._ready()
	# Fast, darting and fragile — a hit-and-run swimmer.
	max_health = 70.0
	move_speed = 7.4
	sight_range = 40.0
	attack_range = 20.0
	preferred_range = 10.0
	attack_cooldown = 0.55
	projectile_speed = 34.0
	projectile_damage = 12.0
	score_value = 110
	hover_amplitude = 0.5   # a deeper, fish-like undulation
	hover_freq = 2.6
	hp.max_health = max_health
	hp.current_health = max_health
	_build_fish_look()

func _emissive_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

## A thin finned blade (box) at `pos`, rotated `rot_deg`, sized `size`.
func _fin(size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material) -> void:
	var fin := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	fin.mesh = bm
	fin.material_override = mat
	fin.position = pos
	fin.rotation = Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	add_child(fin)

## Bolt-on fish anatomy. Forward is −Z (the body's front), so the tail rides +Z.
func _build_fish_look() -> void:
	var finmat := _emissive_mat(Color(0.25, 0.7, 1.0), 2.2)
	# Caudal (tail) fin: a swept V at the back.
	_fin(Vector3(0.03, 0.5, 0.4), Vector3(0, 0.12, 0.5), Vector3(28, 0, 0), finmat)
	_fin(Vector3(0.03, 0.5, 0.4), Vector3(0, -0.12, 0.5), Vector3(-28, 0, 0), finmat)
	# Dorsal fin on top, swept back.
	_fin(Vector3(0.03, 0.34, 0.5), Vector3(0, 0.4, 0.1), Vector3(-22, 0, 0), finmat)
	# Pectoral fins flaring from the flanks.
	_fin(Vector3(0.4, 0.03, 0.3), Vector3(0.42, -0.02, 0.05), Vector3(0, 0, -24), finmat)
	_fin(Vector3(0.4, 0.03, 0.3), Vector3(-0.42, -0.02, 0.05), Vector3(0, 0, 24), finmat)
	# Needle harpoon nose at the front — the weaponised tip.
	var nose := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.08
	cm.height = 0.55
	cm.radial_segments = 8
	nose.mesh = cm
	nose.material_override = _emissive_mat(Color(0.5, 0.9, 1.0), 2.6)
	nose.rotation.x = deg_to_rad(-90.0) # point forward (-Z)
	nose.position = Vector3(0, -0.02, -0.5)
	add_child(nose)

## Override the drone's orange thruster trail with a slow rising bubble stream.
func _make_exhaust() -> void:
	var p := CPUParticles3D.new()
	p.amount = 16
	p.lifetime = 1.2
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 18.0
	p.gravity = Vector3(0, 0.8, 0) # bubbles drift up
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4)); curve.add_point(Vector2(0.5, 1.0)); curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.scale_amount_min = 0.4; p.scale_amount_max = 0.9
	var mesh := SphereMesh.new()
	mesh.radius = 0.05; mesh.height = 0.1; mesh.radial_segments = 6; mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.85, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.8, 1.0)
	mat.emission_energy_multiplier = 1.2
	mesh.material = mat
	p.mesh = mesh
	p.position = Vector3(0, 0.0, 0.25) # trail from behind
	add_child(p)
