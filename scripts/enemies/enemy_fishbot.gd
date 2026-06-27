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

## The fins (tail/dorsal/pectoral) and harpoon nose are baked into the model
## (EyeDrone_fishbot.glb, forked in Blender — see tools/blender/cfg_fishbot.json)
## and tinted blue by RobotModel. Override the drone's orange thruster trail with
## a slow rising stream of bubbles so it reads as swimming.
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
