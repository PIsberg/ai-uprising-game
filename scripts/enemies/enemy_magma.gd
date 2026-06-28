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
	drops_loot = true # a foundry mini-elite leaves supplies (landed on the catwalk)
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

## The chassis is the winged QuadShell model, tinted molten-hot by RobotModel; this
## adds the live FX on top: a rising ember plume so
## it trails fire as it flies.
func _build_magma_look() -> void:
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
