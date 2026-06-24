extends Node3D
## Live weapon-FX showcase: fire the new player weapons into a real crowd of robots
## and capture the effects — TEMPEST chain lightning arcing through the pack, and
## the VORTEX grenade imploding it. Run windowed:
##   godot --path . res://tests/weaponfx_probe.tscn

const TEMPEST_PROJ := preload("res://scenes/weapons/projectile_tempest.tscn")
const VORTEX := preload("res://scenes/weapons/grenade_vortex.tscn")
const SKITTER := preload("res://scenes/enemies/skitter.tscn")

var _cam: Camera3D

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44, 35, 0); sun.light_energy = 1.2
	add_child(sun)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.4, 0.45, 0.55)
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.06, 0.07, 0.1)
	we.environment.glow_enabled = true
	add_child(we)
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(60, 1, 60)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0); sb.add_child(cs); add_child(sb)
	var fmi := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(60, 60)
	fmi.mesh = pm; var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.14, 0.15, 0.18)
	fmi.material_override = fm; add_child(fmi)
	_cam = Camera3D.new(); add_child(_cam)

	# ---- TEMPEST: a packed line of tanky robots, chain-zapped from one round.
	# (High HP so they survive the impact splash and the chain visibly arcs to
	# each — against one-shot fodder the splash clears them before the chain.) ----
	var pack: Array = []
	for i in 8:
		var ang := TAU * float(i) / 8.0
		pack.append(_dummy(Vector3(cos(ang) * 4.0, 0.8, -9 + sin(ang) * 3.5)))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_cam.global_position = Vector3(7, 4.5, 4)
	_cam.look_at(Vector3(0, 0.8, -10), Vector3.UP)
	var proj := TEMPEST_PROJ.instantiate()
	add_child(proj)
	proj.global_position = Vector3(0, 0.8, -7)
	proj.launch(Vector3(0, 0, -1), self, 60.0, 2.8, 55.0)
	proj._explode(Vector3(0, 0.8, -9))   # detonate inside the pack → chain arcs
	# Arcs live a fraction of a second — grab several rapid frames to catch them.
	for fi in 4:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/wf_chain_%d.png" % fi)
	print("  shot wf_chain (4 frames)")

	# ---- VORTEX: a fresh pack, imploded then detonated. ----
	for s in pack:
		if is_instance_valid(s): s.queue_free()
	var pack2: Array = []
	for i in 7:
		var a := TAU * float(i) / 7.0
		pack2.append(_skitter(Vector3(20 + cos(a) * 5.0, 0, sin(a) * 5.0)))
	await get_tree().physics_frame
	_cam.global_position = Vector3(20, 7, 12)
	_cam.look_at(Vector3(20, 0.8, 0), Vector3.UP)
	var g := VORTEX.instantiate()
	add_child(g)
	g.global_position = Vector3(20, 0.4, 0)
	g._begin_implosion()
	for _i in 10:
		g._pull_enemies(0.05, 1.0)
		await get_tree().physics_frame
	await _grab("wf_vortex_pull")          # ring + motes + bunched pack
	g._detonate()
	await get_tree().physics_frame
	await _grab("wf_vortex_boom")
	print("WEAPONFX done")
	get_tree().quit()

## A tanky visible robot stand-in (survives splash so chain lightning arcs to it).
func _dummy(pos: Vector3) -> Node:
	var b := StaticBody3D.new()
	b.collision_layer = 0b0000100; b.collision_mask = 0
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(0.9, 1.6, 0.9)
	cs.shape = sh; b.add_child(cs)
	var mi := MeshInstance3D.new(); var cap := CapsuleMesh.new(); cap.radius = 0.4; cap.height = 1.6
	mi.mesh = cap; mi.position = Vector3(0, 0.0, 0)
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.5, 0.32, 0.34); m.metallic = 0.6
	mi.material_override = m; b.add_child(mi)
	var d := Damageable.new(); d.name = "Damageable"; d.max_health = 1000.0
	b.add_child(d)
	add_child(b); b.global_position = pos
	return b

func _skitter(pos: Vector3) -> Node:
	var s: Node3D = SKITTER.instantiate()
	add_child(s)
	s.global_position = pos
	s.set_physics_process(false); s.set_process(false)  # pose as a static target crowd
	return s

func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/" + name + ".png")
	print("  shot ", name)
