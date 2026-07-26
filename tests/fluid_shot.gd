extends Node3D
## WINDOWED shot probe for the fluid beds (needs a real window: shaders never
## compile under --headless, and save_png hangs there).
##
## Builds an ISOLATED rig — one flat grey floor, one fluid bed, a fixed
## top-down camera — so the ONLY edge in frame is the shoreline itself. A real
## level is useless for this: walls, props and lights put high-contrast edges
## everywhere and there is no way to tell the pool's rim from the scenery.
##
## Straight down means each rim is a vertical line in the image, so the middle
## scanline crosses both perpendicular and fluid_edge_verify can measure how
## many pixels the floor -> fluid transition takes. A slab laid on the floor
## steps over in ~1-2 px; a dissolved shoreline ramps over many.
##
##   godot --path . tests/fluid_shot.tscn            (after)
##   godot --path . tests/fluid_shot.tscn -- before  (writes *_before.png)

const BED := Vector2(10.0, 10.0)
const FLOOR_SPAN := 40.0

func _ready() -> void:
	var suffix := "_before" if "before" in OS.get_cmdline_user_args() else ""
	var out := OS.get_user_data_dir()
	GraphicsSettings.set_quality(GraphicsSettings.Quality.ULTRA)

	# Flat, evenly-lit floor so the shoreline is the only gradient in frame.
	var fl := MeshInstance3D.new()
	var fm := PlaneMesh.new()
	fm.size = Vector2(FLOOR_SPAN, FLOOR_SPAN)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.42, 0.42, 0.44)
	fmat.roughness = 0.95
	fm.material = fmat
	fl.mesh = fm
	add_child(fl)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-72.0, -30.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.62)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 14.0, 0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	for kind in ["water", "lava"]:
		var bed := LavaHazard.new()
		bed.size = BED
		bed.water = (kind == "water")
		add_child(bed)
		await get_tree().create_timer(1.2).timeout
		# The amber hazard frame is a deliberate — and deliberately hard-edged —
		# gameplay cue sitting exactly ON the rim, so it swamps any shoreline
		# measurement. Hidden by MATERIAL SIGNATURE rather than node name so
		# this behaves identically against the stashed old build during an A/B.
		_hide_warning_frame(bed)
		await get_tree().process_frame
		await _shoot("%s/fluid_%s%s.png" % [out, kind, suffix])
		bed.queue_free()
		await get_tree().process_frame

	print("FLUID_SHOT_DONE bed=%s suffix='%s' -> %s" % [BED, suffix, out])
	get_tree().quit()

## Hide the pulsing amber hazard bars: unshaded + emissive is unique to them on
## a fluid bed (the fluid surfaces are ShaderMaterials, the shore is not
## unshaded), so this finds them in both the old and new builds.
func _hide_warning_frame(n: Node) -> void:
	if n is MeshInstance3D:
		var m: Mesh = (n as MeshInstance3D).mesh
		var mat: Material = (m as PrimitiveMesh).material if m is PrimitiveMesh else null
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and sm.emission_enabled:
				(n as MeshInstance3D).visible = false
	for c in n.get_children():
		_hide_warning_frame(c)

func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("  wrote %s" % path)
