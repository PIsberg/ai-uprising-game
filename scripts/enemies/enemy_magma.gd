class_name EnemyMagma
extends EnemyDrone
## MAGMA WRAITH — a molten foundry drone. Built on the recon drone's flight AI but
## up-armoured, slower and meaner: it lobs scorching bolts and is dressed in a
## glowing crown of molten horns, an ember plume and twin cannon barrels, so it
## reads as a fierce, weaponised fire-bot at a glance. Native to the lava world.

func _ready() -> void:
	super._ready()
	# Heavier and harder-hitting than a recon drone, and more deliberate.
	max_health = 95.0
	move_speed = 5.6
	sight_range = 40.0
	attack_range = 22.0
	preferred_range = 13.0
	attack_cooldown = 0.75
	projectile_speed = 30.0
	projectile_damage = 16.0
	score_value = 130
	hp.max_health = max_health
	hp.current_health = max_health
	_build_magma_look()

func _emissive_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

## Bolt-on geometry that gives the chassis a fierce molten identity. Parented to
## the body (not the leaning model) so the parts stay rigid as it banks.
func _build_magma_look() -> void:
	var molten := _emissive_mat(Color(1.0, 0.42, 0.1), 3.2)
	# A jagged crown of molten horns ringing the chassis.
	var horns := 6
	for i in horns:
		var a := TAU * float(i) / float(horns)
		var spike := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.07
		cm.height = 0.42
		cm.radial_segments = 5
		spike.mesh = cm
		spike.material_override = molten
		spike.position = Vector3(sin(a) * 0.42, 0.2, cos(a) * 0.42)
		spike.rotation = Vector3(cos(a) * 0.5, 0.0, -sin(a) * 0.5) # splay outward
		add_child(spike)
	# Twin cannon barrels flanking the optic — the "weaponised" read.
	for sx in [-1.0, 1.0]:
		var barrel := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.05
		bm.bottom_radius = 0.065
		bm.height = 0.5
		bm.radial_segments = 8
		barrel.mesh = bm
		barrel.material_override = _emissive_mat(Color(0.9, 0.28, 0.05), 1.6)
		barrel.rotation.x = deg_to_rad(90.0) # cylinder Y-axis -> point forward (-Z)
		barrel.position = Vector3(0.13 * sx, -0.05, -0.42)
		add_child(barrel)
	# A rising ember plume so it trails fire as it flies.
	var p := CPUParticles3D.new()
	p.amount = 20
	p.lifetime = 0.8
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 26.0
	p.gravity = Vector3(0, 1.4, 0) # embers rise
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0)); curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.scale_amount_min = 0.5; p.scale_amount_max = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.05; mesh.height = 0.1; mesh.radial_segments = 6; mesh.rings = 3
	mesh.material = _emissive_mat(Color(1.0, 0.5, 0.15), 3.5)
	p.mesh = mesh
	p.position = Vector3(0, 0.12, 0)
	add_child(p)
