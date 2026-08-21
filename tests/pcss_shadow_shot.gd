extends Node3D
## Deterministic PCSS shadow capture — no particles, no random decor, fixed
## camera. Exists so a Godot version bump can be checked for shadow changes:
## Godot PR GH-120774 (in 4.7.2) fixed PCSS reading shadow range begin in the
## wrong space, and warned that existing `light_angular_distance` values may
## render differently. Every level here sets `sun.light_angular_distance`
## (level_builder.gd), so that warning applies to this project.
##
## Windowed (shadows need a real GPU):
##   godot --path . tests/pcss_shadow_shot.tscn
## Saves user://pcss_shadow.png. Diff the file across engine versions; the
## scene is static, so any pixel delta is the engine, not scene noise.

func _ready() -> void:
	# Match the project's shipped shadow settings (project.godot sets both
	# soft_shadow_filter_quality to 4) so we measure what the game renders.
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.positional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.12, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.40, 0.50)
	env.ambient_light_energy = 0.30
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Sun with the same angular distance level_builder.gd uses (1.2) — this is
	# the parameter PCSS penumbra width is derived from.
	var sun := DirectionalLight3D.new()
	sun.light_angular_distance = 1.2
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.light_energy = 1.6
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	add_child(sun)

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.62, 0.62, 0.66)
	floor_mat.roughness = 0.9
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(60.0, 0.4, 60.0)
	var fl := MeshInstance3D.new()
	fl.mesh = floor_mesh
	fl.material_override = floor_mat
	fl.position = Vector3(0.0, -0.2, 0.0)
	add_child(fl)

	# A row of pillars at increasing distance from the floor: PCSS penumbra
	# widens with caster-to-receiver gap, so a contact-shadow-to-soft-shadow
	# gradient is exactly what GH-120774 changes.
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.80, 0.30, 0.22)
	for i in range(6):
		var box := BoxMesh.new()
		box.size = Vector3(1.2, 1.2, 1.2)
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = pillar_mat
		# Height above the floor grows left-to-right -> penumbra grows with it.
		mi.position = Vector3(-10.0 + float(i) * 4.0, 0.8 + float(i) * 1.6, 0.0)
		add_child(mi)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 65.0
	cam.position = Vector3(0.0, 7.0, 22.0)
	cam.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
	add_child(cam)

	# Two frames is enough for a static scene; no timers, so the capture is
	# not sensitive to frame pacing between engine versions.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://pcss_shadow.png")
	print("PCSS_SHADOW_SHOT saved user://pcss_shadow.png size=", img.get_size())
	get_tree().quit()
