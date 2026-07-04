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
	var pdmg := lvl.find_child("Damageable", true, false)
	if pdmg:
		pdmg.set("invulnerable", true)
	# Let the ride reach the first demo platform with the swarm + a pursuit
	# gun-truck in play, then frame truck, platform and chase together.
	await get_tree().create_timer(17.5).timeout
	var ride := lvl.get_node("ConvoyRide")
	var truck: Node3D = ride.get("_truck")
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.global_position = truck.global_position + Vector3(-10.0, 7.5, 5.0)
	cam.look_at(Vector3(9.0, 5.5, 66.0), Vector3.UP)
	cam.current = true
	for i in 24:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(SHOT)
	print("SAVED ", SHOT)
	get_tree().quit()
