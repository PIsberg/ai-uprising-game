extends Node3D
## Windowed visual check for a level's shock floor (the Neon Arcade's, inside
## its north gap, by default): the floor from inside the hall while one group
## glows its warning and while it arcs. Headless gives black frames.
##   godot --path . res://tests/shock_floor_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "neon"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://shock_floor_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/shock_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

## Keep every robot (late spawns too) out of the frame and out of the fight.
func _still() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false

## Step physics until `cond` holds.
func _until(cond: Callable) -> void:
	while not cond.call():
		await get_tree().physics_frame
		_still()

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	_still()
	var sf := lvl.find_children("*", "ShockFloor", true, false)[0] as ShockFloor
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.global_position = sf.global_position + Vector3(0, 0, 30)
	player.get_node("Damageable").set("invulnerable", true)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	var depth := sf.cells.y * sf.cell
	cam.global_position = sf.global_position + Vector3(0, 2.6, depth * 0.5 + 4.0)
	cam.look_at(sf.global_position + Vector3(0, 0.2, -depth * 0.25))
	var warn_late := func() -> bool:
		return sf.tile_state(0, 0) == ShockFloor.Tile.WARN \
			and fposmod(sf.get("_t"), ShockFloor.WARN_TIME + ShockFloor.ZAP_TIME) > ShockFloor.WARN_TIME * 0.7
	await _until(warn_late)
	await _shot("warn")
	await _until(func() -> bool: return sf.tile_state(0, 0) == ShockFloor.Tile.ZAP)
	await _until(func() -> bool: return fposmod(sf.get("_t"), ShockFloor.WARN_TIME + ShockFloor.ZAP_TIME) > ShockFloor.WARN_TIME + 0.2)
	await _shot("arc")
	print("RESULT PASS")
	get_tree().quit()
