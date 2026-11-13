extends Node3D
## What does a model's shadow mesh buy on the GPU? (#56)
##
## The importer stores, beside every mesh, a second position-only copy with the
## seams welded, which the shadow and depth passes draw instead. It is a fifth of
## the mesh bytes the game ships (tools/scene_weight.gd: 19.9 of 81.6 MB in
## memory over 80 models). This renders COPIES of one model under a shadowed sun
## and a shadowed lamp with the shadow meshes on (A), off (B), on again (A2) and
## off again (B2), in ONE process and from one camera, and prints the median GPU
## and CPU render time of each. A against A2 is the noise; A against B the cost
## of shipping without them. It also compares the last frame of each run pixel by
## pixel, so a shadow that changes shape shows. Both comparisons need an import
## that still HAS shadow meshes (set meshes/create_shadow_meshes=true on the
## model and re-import; the game's imports have none). Windowed: render timings
## need a real GPU.
##
##   godot --path . res://tools/shadow_mesh_ab.tscn -- model=res://assets/models/robots/rusty_claws_robot.glb copies=8 frames=240
##   shadows=0   both lights cast none: the gap to a normal run is what the shadow
##               passes cost at all, so a flat A/B is not the tool being blind

const SETTLE_FRAMES := 40

func _ready() -> void:
	var model_path := "res://assets/models/robots/rusty_claws_robot.glb"
	var copies := 8
	var frames := 240
	var shadows := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("model="):
			model_path = a.trim_prefix("model=")
		elif a.begins_with("copies="):
			copies = maxi(int(a.trim_prefix("copies=")), 1)
		elif a.begins_with("frames="):
			frames = maxi(int(a.trim_prefix("frames=")), 10)
		elif a == "shadows=0":
			shadows = false
	var scene := load(model_path) as PackedScene
	if scene == null:
		print("RESULT FAIL cannot load %s" % model_path)
		get_tree().quit(1)
		return
	var side := int(ceil(sqrt(float(copies))))
	var meshes: Dictionary = {} # ArrayMesh -> its shadow mesh
	for i in copies:
		var inst := scene.instantiate() as Node3D
		add_child(inst)
		var box := _bounds(inst)
		var s := 3.0 / maxf(box.size.y, 0.001)
		inst.scale = Vector3.ONE * s
		inst.position = Vector3((i % side - (side - 1) * 0.5) * 3.5, -box.position.y * s, (i / side - (side - 1) * 0.5) * 3.5)
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var am := (mi as MeshInstance3D).mesh as ArrayMesh
			if am and am.shadow_mesh:
				meshes[am] = am.shadow_mesh
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mi.mesh = plane
	add_child(floor_mi)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = shadows
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.shadow_enabled = shadows
	lamp.omni_range = 30.0
	lamp.position = Vector3(0, 6, 0)
	add_child(lamp)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 4.5, side * 3.5 + 5.0)
	cam.look_at(Vector3(0, 1.5, 0))
	cam.current = true
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var verts := 0
	var shadow_verts := 0
	for am: ArrayMesh in meshes:
		for si in am.get_surface_count():
			verts += am.surface_get_array_len(si)
		var sm := meshes[am] as ArrayMesh
		for si in sm.get_surface_count():
			shadow_verts += sm.surface_get_array_len(si)
	print("MODEL %s  copies=%d  shadows=%s  meshes with a shadow mesh=%d  vertices=%d  shadow-mesh vertices=%d" % [
		model_path.get_file(), copies, shadows, meshes.size(), verts, shadow_verts])
	var out: Dictionary = {}
	var shots: Dictionary = {} # run -> the last frame it drew
	for run: String in ["A", "B", "A2", "B2"]:
		for am: ArrayMesh in meshes:
			am.shadow_mesh = meshes[am] if run.begins_with("A") else null
		for i in SETTLE_FRAMES:
			await get_tree().process_frame
		var gpu: Array[float] = []
		var cpu: Array[float] = []
		for i in frames:
			await get_tree().process_frame
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		gpu.sort()
		cpu.sort()
		out[run] = gpu[gpu.size() / 2]
		shots[run] = get_viewport().get_texture().get_image()
		print("RUN %-2s shadow meshes %-3s  gpu median %.3f ms (p10 %.3f, p90 %.3f)  cpu median %.3f ms  prims %d" % [
			run, "on" if run.begins_with("A") else "off", gpu[gpu.size() / 2], gpu[gpu.size() / 10], gpu[gpu.size() * 9 / 10],
			cpu[cpu.size() / 2], RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	var on := (float(out["A"]) + float(out["A2"])) * 0.5
	var off := (float(out["B"]) + float(out["B2"])) * 0.5
	print("SUMMARY %s: on %.3f ms, off %.3f ms, off costs %+.3f ms for %d copies (%+.4f ms each); noise A vs A2 %.3f ms" % [
		model_path.get_file(), on, off, off - on, copies, (off - on) / copies, absf(float(out["A"]) - float(out["A2"]))])
	# Does the picture change? A against A2 is what two identical runs differ by.
	print("PICTURE on vs on: %s" % _diff(shots["A"], shots["A2"]))
	print("PICTURE on vs off: %s" % _diff(shots["A"], shots["B"]))
	get_tree().quit()

## Pixels of `a` and `b` that differ by more than 2/255 on a channel, and the largest difference.
func _diff(a: Image, b: Image) -> String:
	var da := a.get_data()
	var db := b.get_data()
	if da.size() != db.size():
		return "sizes differ"
	var bpp := da.size() / (a.get_width() * a.get_height())
	var changed := 0
	var worst := 0
	for px in a.get_width() * a.get_height():
		var d := 0
		for c in mini(bpp, 3):
			d = maxi(d, absi(da[px * bpp + c] - db[px * bpp + c]))
		worst = maxi(worst, d)
		if d > 2:
			changed += 1
	return "%d of %d pixels (%dx%d) differ by more than 2/255 (largest difference %d/255)" % [changed, a.get_width() * a.get_height(), a.get_width(), a.get_height(), worst]

func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
