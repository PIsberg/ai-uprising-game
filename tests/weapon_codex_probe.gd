extends Node
## Dev probe: screenshots the Weapon Codex so its layout/stats can be eyeballed.
##   godot --path . res://tests/weapon_codex_probe.tscn
const OUT := "user://weapon_codex.png"

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
