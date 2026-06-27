extends Node3D
## Verifies Blender-edited / re-exported models still FRAME correctly in the codex
## viewer (they used to shrink to a speck). Replicates the Encyclopedia's exact
## bone-AABB framing for a set of models and screenshots each.
## Run windowed: godot --path . --quit-after 400 res://tests/codex_frame_probe.tscn

# (codex type, scene, codex scale)
const CASES := [
	["smasher", "res://scenes/enemies/smasher.tscn", 0.3],
	["reaper",  "res://scenes/enemies/reaper.tscn", 1.0],
	["gunner",  "res://scenes/enemies/gunner.tscn", 1.0],
]

var _cam: Camera3D
var _turntable: Node3D

func _ready() -> void:
	var we := WorldEnvironment.new(); we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.03, 0.035, 0.05)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.4, 0.45, 0.6)
	we.environment.ambient_light_energy = 0.8
	add_child(we)
	var key := SpotLight3D.new(); key.position = Vector3(2.6, 5, 4.5)
	add_child(key); key.look_at(Vector3(0, 1, 0), Vector3.UP); key.light_energy = 5.0; key.spot_angle = 50.0
	_cam = Camera3D.new(); _cam.fov = 40.0; _cam.current = true; add_child(_cam)
	_turntable = Node3D.new(); add_child(_turntable)
	for c in CASES:
		await _show(c[0], c[1], float(c[2]))
	print("CODEX_FRAME_DONE")
	get_tree().quit()

func _show(id: String, path: String, scl: float) -> void:
	for ch in _turntable.get_children():
		ch.queue_free()
	await get_tree().process_frame
	var bot: Node3D = (load(path) as PackedScene).instantiate()
	if "preview" in bot:
		bot.preview = true
	_turntable.add_child(bot)
	bot.rotation.y = PI
	bot.scale = Vector3.ONE * scl
	if bot.has_method("set_physics_process"):
		bot.set_physics_process(false)
	# settle a few frames (RobotModel sizes over a frame or two), reframe each.
	for i in 8:
		await get_tree().process_frame
		_frame(bot)
	await RenderingServer.frame_post_draw
	var ab := _world_aabb(bot)
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/codexframe_%s.png" % id)
	print("CODEXFRAME %s  aabb_h=%.2f w=%.2f  (a speck would be <0.3)" % [id, ab.size.y, maxf(ab.size.x, ab.size.z)])

func _frame(bot: Node3D) -> void:
	var ab := _world_aabb(bot)
	var bottom: float = maxf(ab.position.y, 0.0)
	var top: float = ab.position.y + ab.size.y
	var h: float = maxf(top - bottom, 0.8)
	var w: float = maxf(maxf(ab.size.x, ab.size.z), 0.8)
	var cy := (bottom + top) * 0.5
	var vfov := deg_to_rad(_cam.fov)
	var hfov := 2.0 * atan(tan(vfov * 0.5) * 1.78)
	var d := maxf(maxf((h * 0.5 * 1.65) / tan(vfov * 0.5), (w * 0.5 * 1.5) / tan(hfov * 0.5)), 3.0)
	_cam.global_position = Vector3(0, cy, d)
	_cam.look_at(Vector3(d * 0.22, cy, 0), Vector3.UP)

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
			b = b.grow(0.4); b.position.y = maxf(b.position.y, 0.0)
			return b
	var merged := AABB(); var first := true
	for mi in bot.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			var a: AABB = m.global_transform * m.mesh.get_aabb()
			merged = a if first else merged.merge(a); first = false
	return merged if not first else AABB(Vector3(-0.6, 0, -0.6), Vector3(1.2, 2, 1.2))
