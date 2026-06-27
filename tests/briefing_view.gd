extends Node
## Renders the new per-level comic briefing for a couple levels to confirm the
## comic art + glow FX + weather + title/tagline/objective all show.
## Run windowed: godot --path . --quit-after 600 res://tests/briefing_view.tscn

const SCENE := preload("res://scenes/cutscene/level_comic_briefing.tscn")
const LEVELS := ["gpt", "mistral", "suburb_boss"]

func _ready() -> void:
	for id in LEVELS:
		GameState.current_level_path = "res://scenes/levels/level_%s.tscn" % id
		var b := SCENE.instantiate()
		add_child(b)
		await get_tree().create_timer(2.6).timeout  # past fade-in (1.1s), before finish (5.2s)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/brief_%s.png" % id)
		print("SHOT ", id)
		b.queue_free()
		await get_tree().process_frame
	print("BRIEFING_VIEW_DONE")
	get_tree().quit()
