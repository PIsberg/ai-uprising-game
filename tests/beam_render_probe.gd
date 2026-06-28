extends Node3D
## Render the ElectricBeam to a PNG to confirm the lightning actually draws.
##   godot --path . res://tests/beam_render_probe.tscn

const OUT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/beam_render.png"

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.05, 0.08)
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.2
	env.environment = e
	add_child(env)
	var beam := ElectricBeam.new()
	add_child(beam)
	beam.set_color(Color(0.45, 0.85, 1.0))
	var cam := Camera3D.new()
	cam.position = Vector3(1.5, 0.4, 2.6)
	cam.look_at_from_position(cam.position, Vector3(1.5, 0, 0), Vector3.UP)
	add_child(cam)
	_run.call_deferred(beam)

func _run(beam) -> void:
	for i in 3:
		beam.update_beam(Vector3(0, 0, 0), Vector3(3, 0, 0), true)
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("SAVED ", OUT)
	get_tree().quit()
