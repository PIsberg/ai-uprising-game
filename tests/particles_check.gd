extends SceneTree
## Headless sanity check for GraphicsSettings.create_particles on both paths.

func _init() -> void:
	var gs := root.get_node_or_null("/root/GraphicsSettings")
	if gs == null:
		# Autoloads aren't present in --script mode; load the singleton manually.
		gs = load("res://scripts/autoload/graphics_settings.gd").new()
		root.add_child(gs)
	var mesh := BoxMesh.new()

	gs.set("gpu_particles_enabled", true)
	var g = gs.create_particles(12, 0.6, 0.0, Vector3.UP, 30.0, Vector3(0,-9,0),
		2.0, 5.0, 0.2, 0.6, mesh)
	print("GPU result: ", g, " class=", g.get_class() if g else "NULL",
		" draw_pass_1=", (g.draw_pass_1 if g else null))

	gs.set("gpu_particles_enabled", false)
	var c = gs.create_particles(12, 0.6, 0.0, Vector3.UP, 30.0, Vector3(0,-9,0),
		2.0, 5.0, 0.2, 0.6, mesh)
	print("CPU result: ", c, " class=", c.get_class() if c else "NULL",
		" mesh=", (c.mesh if c else null))
	quit()
