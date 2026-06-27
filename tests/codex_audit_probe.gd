extends Node3D
## Reproduces the Encyclopedia stage to AUDIT codex visuals: renders the bosses
## (orange-ring / entrance-FX suspects) and runs a SWITCH test (boss -> drone) to
## catch FX that stick to the next entry. Saves user://cxa_*.png + counts stray
## nodes left under the scene root after an entry is freed.
## Run windowed: godot --path . --quit-after 1500 res://tests/codex_audit_probe.tscn

const SHOTS := ["terminator", "overseer", "colossus", "smasher", "titan", "ravager", "drone"]

var _camera: Camera3D
var _turntable: Node3D
var _bot: Node3D

func _ready() -> void:
	_build_stage()
	for t in SHOTS:
		await _show(t)
		await get_tree().create_timer(2.4).timeout
		await _grab("cxa_" + t)
		_report_strays(t)
	# Switch test: stage a boss that emits entrance FX, free it, stage a drone,
	# and see whether a "tornado"/ring lingers on the drone.
	await _show("overseer")
	await get_tree().create_timer(2.2).timeout
	await _show("drone")
	await get_tree().create_timer(1.6).timeout
	await _grab("cxa_switch_drone")
	_report_strays("switch->drone")
	print("CODEX_AUDIT_DONE")
	get_tree().quit()

func _show(t: String) -> void:
	if _bot and is_instance_valid(_bot):
		_bot.queue_free()
		_bot = null
	_turntable.rotation = Vector3.ZERO
	var e := EnemyCodex.get_entry(t)
	var bot: Node3D = (load(e["scene"]) as PackedScene).instantiate()
	if "preview" in bot:
		bot.preview = true
	_turntable.add_child(bot)
	bot.rotation.y = PI
	bot.scale = Vector3.ONE * float(e.get("scale", 1.0))
	bot.position = Vector3(0, float(e.get("y", 0.0)), 0)
	if bot.has_method("set_physics_process"):
		bot.set_physics_process(false)
	_bot = bot
	await get_tree().process_frame

## Count nodes parented to the scene root that AREN'T the stage/turntable/bot —
## i.e. FX an enemy spawned into current_scene that will outlive the entry.
func _report_strays(label: String) -> void:
	var strays: Array = []
	for c in get_children():
		if c == _camera or c == _turntable or c.name in ["WE", "Key", "Fill", "Rim", "Disc", "Ring"]:
			continue
		strays.append(c.name)
	print("STRAYS [%s]: %d  %s" % [label, strays.size(), strays])

func _grab(name: String) -> void:
	# Frame the bot using bone-AABB (same as the codex).
	if _bot and is_instance_valid(_bot):
		var ab := _world_aabb(_bot)
		var cy: float = maxf(ab.position.y, 0.0) + maxf(ab.size.y, 0.8) * 0.5
		var d: float = maxf(maxf(ab.size.y, ab.size.x) * 1.7, 4.0)
		_camera.global_position = Vector3(0, cy, d)
		_camera.look_at(Vector3(0, cy, 0), Vector3.UP)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/" + name + ".png")

func _world_aabb(bot: Node3D) -> AABB:
	var skels := bot.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var skel := skels[0] as Skeleton3D
		if skel.get_bone_count() > 0:
			var b := AABB(); var first := true
			for i in skel.get_bone_count():
				var p: Vector3 = (skel.global_transform * skel.get_bone_global_pose(i)).origin
				if first: b = AABB(p, Vector3.ZERO); first = false
				else: b = b.expand(p)
			return b.grow(0.5)
	var merged := AABB(); var first := true
	for mi in bot.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh:
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			merged = a if first else merged.merge(a); first = false
	return merged if not first else AABB(Vector3(-1, 0, -1), Vector3(2, 3, 2))

func _build_stage() -> void:
	var we := WorldEnvironment.new(); we.name = "WE"; we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.03, 0.035, 0.05)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.35, 0.4, 0.55)
	we.environment.ambient_light_energy = 0.6
	we.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	we.environment.glow_enabled = true
	add_child(we)
	_camera = Camera3D.new(); _camera.current = true; _camera.fov = 40.0; add_child(_camera)
	var key := SpotLight3D.new(); key.name = "Key"; key.position = Vector3(2.6, 5, 4.5)
	add_child(key); key.look_at(Vector3(0, 1, 0), Vector3.UP); key.light_energy = 5.0; key.spot_angle = 48.0
	var fill := OmniLight3D.new(); fill.name = "Fill"; fill.position = Vector3(-3.5, 3, 3); fill.light_energy = 2.0; fill.omni_range = 16.0
	add_child(fill)
	var disc := MeshInstance3D.new(); disc.name = "Disc"
	var cm := CylinderMesh.new(); cm.top_radius = 2.4; cm.bottom_radius = 2.6; cm.height = 0.12
	disc.mesh = cm
	var dmat := StandardMaterial3D.new(); dmat.albedo_color = Color(0.07, 0.08, 0.1); dmat.metallic = 0.2; dmat.roughness = 0.85
	disc.material_override = dmat; disc.position = Vector3(0, -0.06, 0); add_child(disc)
	_turntable = Node3D.new(); add_child(_turntable)
