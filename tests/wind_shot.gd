extends Node3D
## Windowed visual check for a level's crosswind (Water World's first SCRAM
## gantry by default): looking down the gantry at eye height from its start,
## first calm (windsocks hanging), then mid-gust (socks straight out,
## streaks running across). Headless gives black frames.
##   godot --path . res://tests/wind_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "water_world"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://wind_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/wind_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 40:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.get_node("Damageable").set("invulnerable", true)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(0, 30, 0)
	var z := lvl.find_children("*", "WindZone", true, false)[0] as WindZone
	var across := Vector3(-z.dir.z, 0, z.dir.x)
	var half := 0.5 * (absf(across.x) * z.size.x + absf(across.z) * z.size.y)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	cam.global_position = z.global_position + across * (half + 2.0) + Vector3.UP * 1.7 - z.dir * 1.5
	cam.look_at(z.global_position - across * half + Vector3.UP * 1.2)
	# A fresh calm (just after a gust), so the capture cannot drift into the
	# warning: the first version did, and showed warn streaks as "calm".
	while z.phase != WindZone.Phase.GUST:
		await get_tree().physics_frame
	while z.phase != WindZone.Phase.CALM:
		await get_tree().physics_frame
	for i in 20:
		await get_tree().process_frame
	await _shot("calm")
	while z.phase != WindZone.Phase.GUST:
		await get_tree().physics_frame
	for i in 12:
		await get_tree().process_frame
	await _shot("gust")
	print("RESULT PASS")
	get_tree().quit()
