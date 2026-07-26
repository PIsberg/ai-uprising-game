extends Node
## WINDOWED unit test for the blast screen-warp (needs a real window: shaders do
## not compile under --headless, and save_png hangs there).
##
## Renders a static high-frequency checker through shaders/post_process.gdshader
## and captures it with the shockwave uniform off vs. held mid-expansion. With
## grain/speed_warp/low_health/glitch all zeroed the shader is time-invariant, so
## the two captures are identical EXCEPT for the refraction ring — which is what
## makes screen_shock_verify's radial diff profile meaningful.
##
## (Capturing a real level instead does not work: GPU particles and the animated
## lava/flame/CRT shaders keep advancing on TIME even with the tree paused, and
## bury the ring under whole-screen motion.)
##
##   godot --path . tests/screen_shock_shot.tscn
##   -> user://shock_off.png / shock_mid.png / shock_glitch.png

## Held progress for the measured capture. Crest radius = PROGRESS * 0.78 in
## aspect-corrected UV; screen_shock_verify asserts the ring lands there.
const PROGRESS := 0.35

func _ready() -> void:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var layer := CanvasLayer.new()
	add_child(layer)

	var back := TextureRect.new()
	back.texture = ImageTexture.create_from_image(_pattern(int(size.x), int(size.y)))
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(back)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/post_process.gdshader")
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	layer.add_child(rect)

	# Silence every time-varying term so the only variable is the shockwave.
	mat.set_shader_parameter("advanced_post_process_enabled", true)
	mat.set_shader_parameter("grain_amount", 0.0)
	mat.set_shader_parameter("speed_warp", 0.0)
	mat.set_shader_parameter("low_health", 0.0)
	mat.set_shader_parameter("glitch", 0.0)

	var zero := PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
	var out := OS.get_user_data_dir()

	mat.set_shader_parameter("shockwaves", zero)
	await _shoot(out + "/shock_off.png")

	mat.set_shader_parameter("shockwaves", PackedVector4Array([
		Vector4(0.5, 0.5, PROGRESS, 1.0), Vector4.ZERO, Vector4.ZERO]))
	await _shoot(out + "/shock_mid.png")

	mat.set_shader_parameter("shockwaves", zero)
	mat.set_shader_parameter("glitch", 1.0)
	await _shoot(out + "/shock_glitch.png")

	print("SHOCK_SHOT_DONE progress=%.2f size=%dx%d -> %s"
		% [PROGRESS, int(size.x), int(size.y), out])
	get_tree().quit()

## Fine checker + diagonals: high spatial frequency in every direction, so even a
## sub-pixel UV displacement shows up as a large per-pixel difference.
func _pattern(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var checker := ((x / 8) + (y / 8)) % 2 == 0
			var diag := ((x + y) / 6) % 2 == 0
			var v := 0.85 if checker else 0.15
			if diag:
				v = clampf(v + 0.12, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v * 0.9, v * 0.8))
	return img

func _shoot(path: String) -> void:
	# Two frames: one to apply the uniform, one to be certain it is drawn.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("  wrote %s" % path)
