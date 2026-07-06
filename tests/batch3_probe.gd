extends Node3D
## Dev probe: inspect the 4 batch-3 models — screenshots + structure dump.
##   godot --path . res://tests/batch3_probe.tscn
const OUT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/4f2aa26d-c9cb-4e2f-aeea-a17e19a4e75b/scratchpad/"
const MODELS := [
	"robot_arm_wip_2", "robot_ball", "robot-killer_model", "walking_robot_gun",
]

var _cam: Camera3D
var _holder: Node3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.1)
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_energy = 1.8
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.7
	add_child(fill)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	_holder = Node3D.new()
	add_child(_holder)
	_run.call_deferred()

func _run() -> void:
	for mname in MODELS:
		for c in _holder.get_children():
			c.queue_free()
		await get_tree().process_frame
		var path := "res://assets/models/robots/%s.glb" % mname
		if not ResourceLoader.exists(path):
			print(mname, " MISSING")
			continue
		var m: Node3D = load(path).instantiate()
		_holder.add_child(m)
		await get_tree().process_frame
		await get_tree().process_frame
		print("=== ", mname, " ===")
		_dump(m, 0)
		for ap in m.find_children("*", "AnimationPlayer", true, false):
			print("  ANIMS: ", (ap as AnimationPlayer).get_animation_list())
		var tri := 0
		var aabb := AABB()
		var first := true
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			if inst.mesh == null:
				continue
			for s in inst.mesh.get_surface_count():
				var arr := inst.mesh.surface_get_arrays(s)
				if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
					tri += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				elif arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
					tri += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var wb: AABB = inst.global_transform * inst.mesh.get_aabb()
			if first:
				aabb = wb; first = false
			else:
				aabb = aabb.merge(wb)
		var c := aabb.get_center()
		var r := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5
		print("%s  center=%v size=%v tris=%d" % [mname, c, aabb.size, tri])
		var dist := r / tan(deg_to_rad(35.0)) + r
		# Front three-quarter shot.
		_cam.position = c + Vector3(dist * 0.55, aabb.size.y * 0.15, dist)
		_cam.look_at_from_position(_cam.position, c, Vector3.UP)
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT_DIR + "b3_" + mname + ".png")
		# Back shot too (facing check).
		_cam.position = c + Vector3(-dist * 0.55, aabb.size.y * 0.15, -dist)
		_cam.look_at_from_position(_cam.position, c, Vector3.UP)
		await get_tree().create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT_DIR + "b3_" + mname + "_back.png")
		print("SAVED ", mname)
	print("BATCH3 PROBE DONE")
	get_tree().quit()

func _dump(n: Node, depth: int) -> void:
	if depth > 4:
		return
	var extra := ""
	if n is Skeleton3D:
		extra = " bones=%d" % (n as Skeleton3D).get_bone_count()
	print("  ".repeat(depth + 1), n.name, " [", n.get_class(), "]", extra)
	for ch in n.get_children():
		_dump(ch, depth + 1)
