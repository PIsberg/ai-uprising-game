extends Node3D
## Windowed screenshot of the Highway Breakout ride mid-roll: frames the truck
## deck plus the roadside streetlights/barriers/gantries to judge the dressing.
##   godot --path . res://tests/convoy_shot.tscn --quit-after 900

const SHOT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/95a1d0e0-6d29-460c-8157-97f2f1fe8e7d/scratchpad/convoy_shot.png"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var lvl := (load("res://scenes/levels/level_convoy.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lvl)
	await get_tree().create_timer(6.5).timeout
	var pdmg := lvl.find_child("Damageable", true, false)
	if pdmg:
		pdmg.set("invulnerable", true)
	var ride := lvl.get_node("ConvoyRide")
	var truck: Node3D = ride.get("_truck")
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	cam.global_position = truck.global_position + Vector3(7.0, 6.0, 11.0)
	cam.look_at(truck.global_position + Vector3(0, 1.5, -14.0), Vector3.UP)
	cam.current = true
	for i in 24:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(SHOT)
	print("SAVED ", SHOT)
	get_tree().quit()
