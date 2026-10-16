extends Node3D
## Windowed visual check for a level's intercept courier (Maple Grove's by
## default): the courier mid-run from a chasing player's eye height, with its
## amber data core and DATA COURIER tag; the uplink pad and beam from across
## the map; the courier uploading on the pad with the beam at full strength.
## Headless gives black frames.
##   godot --path . res://tests/intercept_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "suburb"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://intercept_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/intercept_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

## Keep the level's own robots out of the frame and out of the fight.
func _still(keep: Node) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == keep:
			continue
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 60:
		await get_tree().physics_frame
	_still(null)
	var task: Dictionary = {}
	for t in LevelDefs.get_def(_level).get("tasks", []):
		if t.get("type", "") == "intercept":
			task = t
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.get_node("Damageable").set("invulnerable", true)
	player.global_position = Vector3(-50, 0.1, -50)
	GameState.register_task("shot_run", "shot run", 0.0)
	var ic := InterceptCourier.new()
	ic.task_id = "shot_run"
	ic.unit_scene = LevelBuilder.enemy_scene(String(task.get("enemy", "android")))
	ic.route = task.get("route", [])
	ic.uplink = task.get("to", Vector3.ZERO)
	ic.upload_seconds = 1000.0
	ic.position = task.get("pos", Vector3.ZERO) + Vector3.UP * 0.3
	lvl.add_child(ic)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 75.0
	# Chase view: 9 m behind the courier at eye height, on its first bridge leg.
	while ic.leg < 2:
		await get_tree().physics_frame
		_still(ic.unit)
	var u := ic.unit
	var back := -Vector3(u.velocity.x, 0.0, u.velocity.z).normalized()
	cam.global_position = u.global_position + back * 9.0 + Vector3.UP * 1.7
	cam.look_at(u.global_position + Vector3.UP * 1.2)
	await _shot("chase")
	# The uplink from the bridge: the beam marks where it is going.
	cam.global_position = Vector3(0, 3.6, 11.2)
	cam.look_at(ic.uplink + Vector3.UP * 6.0)
	await _shot("uplink_far")
	while not ic.uploading:
		await get_tree().physics_frame
		_still(u)
	ic.upload_t = 800.0 # most of the way: the beam near full strength
	for i in 6:
		await get_tree().physics_frame
	cam.global_position = ic.uplink + Vector3(7.0, 2.2, 7.0)
	cam.look_at(ic.uplink + Vector3.UP * 1.5)
	await _shot("uploading")
	print("RESULT PASS")
	get_tree().quit()
