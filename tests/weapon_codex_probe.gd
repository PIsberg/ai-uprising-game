extends Node
## Dev probe: screenshots the Weapon Codex so its layout/stats can be eyeballed.
##   godot --path . res://tests/weapon_codex_probe.tscn
const OUT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/weapon_codex.png"

func _ready() -> void:
	var c: Control = load("res://scenes/ui/weapon_codex.tscn").instantiate()
	add_child(c)
	_shoot.call_deferred()

func _shoot() -> void:
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("SAVED ", OUT)
	get_tree().quit()
