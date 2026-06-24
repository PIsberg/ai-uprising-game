extends Node3D
## Promo screenshots (3D): a fierce-enemy showcase, the Tempest chain lightning,
## and the Vortex grenade implosion — lit cinematically and saved straight into
## docs/screenshots/ for the README. Run windowed:
##   godot --path . res://tests/promo_3d.tscn

const SKITTER := preload("res://scenes/enemies/skitter.tscn")
const TEMPEST := preload("res://scenes/weapons/projectile_tempest.tscn")
const VORTEX := preload("res://scenes/weapons/grenade_vortex.tscn")

var _cam: Camera3D
var _env: Environment
var _spawned: Array = []

func _ready() -> void:
	# --- cinematic world ---
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.045, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.5, 0.66)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
	env.fog_enabled = true
	env.fog_light_color = Color(0.18, 0.23, 0.34)
	env.fog_density = 0.012
	_env = env
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 38, 0); key.light_energy = 2.0
	key.light_color = Color(1.0, 0.93, 0.85); key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0); fill.light_energy = 0.5
	fill.light_color = Color(0.5, 0.65, 1.0)
	add_child(fill)
	# Dark reflective floor.
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(80, 80); floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.08, 0.09, 0.11); fmat.metallic = 0.5; fmat.roughness = 0.45
	floor_mi.material_override = fmat
	add_child(floor_mi)
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(80, 1, 80)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0); sb.add_child(cs); add_child(sb)
	_cam = Camera3D.new(); _cam.fov = 60.0; add_child(_cam)

	await get_tree().create_timer(0.3).timeout
	await _shot_enemies()
	await _shot_combat()
	await _shot_vortex()
	print("PROMO3D done")
	get_tree().quit()

func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await get_tree().process_frame

func _spawn(path: String, pos: Vector3, yaw: float = PI) -> Node:
	var e: Node3D = (load(path) as PackedScene).instantiate()
	add_child(e)
	e.global_position = pos
	e.rotation.y = yaw            # face +Z toward the camera by default
	e.set_physics_process(false)  # pose, don't fight
	if e.has_method("set_process"):
		e.set_process(false)
	_spawned.append(e)
	return e

func _play_idle(e: Node) -> void:
	var ap := e.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return
	for clip in ["RobotArmature|Idle", "CharacterArmature|Idle", "Idle"]:
		if ap.has_animation(clip):
			ap.play(clip); return

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var tw := 1600
	var th := int(round(1600.0 * img.get_height() / float(img.get_width())))
	img.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	img.save_png("res://docs/screenshots/%s.png" % name)
	print("SAVED ", name, " ", tw, "x", th)

## A fierce-enemy lineup: the looming Warmech flanked by a Ravager and a skitter pack.
func _shot_enemies() -> void:
	await _clear()
	var wm := _spawn("res://scenes/enemies/warmech.tscn", Vector3(0.5, 0, -9), PI)
	var rav := _spawn("res://scenes/enemies/ravager.tscn", Vector3(-4.5, 0, -3.5), PI - 0.4)
	for p in [Vector3(3.4, 0, -1.0), Vector3(1.8, 0, 0.8), Vector3(4.6, 0, -3.2), Vector3(-2.2, 0, 0.4)]:
		_spawn("res://scenes/enemies/skitter.tscn", p, PI + randf_range(-0.6, 0.6))
	for n in _spawned:
		_play_idle(n)
	_cam.global_position = Vector3(2.6, 1.9, 6.2)
	_cam.look_at(Vector3(-0.4, 1.7, -5), Vector3.UP)
	await get_tree().create_timer(0.7).timeout
	await _save("enemies")

## Live combat: the Warmech siege mech charging + lobbing a salvo while a Ravager
## and skitters close on the player — real AI, captured mid-fight.
func _shot_combat() -> void:
	await _clear()
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2; player.collision_mask = 1
	var pcs := CollisionShape3D.new(); var pcap := CapsuleShape3D.new()
	pcap.radius = 0.4; pcap.height = 1.7; pcs.shape = pcap; pcs.position = Vector3(0, 0.9, 0)
	player.add_child(pcs)
	var pdmg := Damageable.new(); pdmg.name = "Damageable"; pdmg.max_health = 9999.0
	player.add_child(pdmg)
	add_child(player); player.global_position = Vector3(0, 1.0, 12)
	_spawned.append(player)
	# Hostiles with REAL AI running (no freeze) so the Warmech charges + fires.
	var wm := (load("res://scenes/enemies/warmech.tscn") as PackedScene).instantiate()
	add_child(wm); wm.global_position = Vector3(-2, 0.5, -14); _spawned.append(wm)
	var rav := (load("res://scenes/enemies/ravager.tscn") as PackedScene).instantiate()
	add_child(rav); rav.global_position = Vector3(6, 0.5, 0); _spawned.append(rav)
	for i in 5:
		var a := TAU * float(i) / 5.0
		var s := SKITTER.instantiate()
		add_child(s); s.global_position = Vector3(cos(a) * 4.0, 0.5, 4 + sin(a) * 2.5); _spawned.append(s)
	_cam.global_position = Vector3(13, 8, 13)
	_cam.look_at(Vector3(-1, 1.6, -2), Vector3.UP)
	await get_tree().create_timer(2.1).timeout   # let the fight develop, then grab mid-salvo
	await _save("combat")

## Vortex grenade: a violet gravity well sucking a pack into one knot.
func _shot_vortex() -> void:
	await _clear()
	_env.glow_intensity = 0.9       # restore the bloom for the violet well
	_env.glow_bloom = 0.25
	_env.glow_hdr_threshold = 1.0
	_env.ambient_light_energy = 0.5
	var ring: Array = []
	for i in 8:
		var a := TAU * float(i) / 8.0
		ring.append(_spawn("res://scenes/enemies/skitter.tscn", Vector3(cos(a) * 5.0, 0, -8 + sin(a) * 5.0), PI))
	for n in ring:
		_play_idle(n)
	_cam.global_position = Vector3(0, 6.5, 3.0)
	_cam.look_at(Vector3(0, 0.6, -8), Vector3.UP)
	var g := VORTEX.instantiate(); add_child(g)
	g.global_position = Vector3(0, 0.4, -8)
	g._begin_implosion()
	for _i in 9:
		g._pull_enemies(0.05, 1.0)
		await get_tree().process_frame
	await _save("vortex_grenade")
