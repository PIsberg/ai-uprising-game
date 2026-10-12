extends Node3D
## Windowed visual check for a level's fire vents (the Crucible's north gap by
## default): the row from the approach, caught while one vent warns and while
## one erupts. Headless gives black frames.
##   godot --path . res://tests/fire_vent_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "crucible"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://fire_vent_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/vent_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

## Keep every robot (late spawns too) out of the frame and out of the fight.
func _still() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false

## Step physics until `vent` is in `state` at least `into` seconds.
func _wait_for(vent: FireVent, state: FireVent.Phase, into: float) -> void:
	var t := 0.0
	while true:
		await get_tree().physics_frame
		_still()
		if vent.state == state:
			t += get_physics_process_delta_time()
			if t >= into:
				return

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	_still()
	var vents := lvl.find_children("*", "FireVent", true, false)
	var a := vents[0] as FireVent
	var b := vents[1] as FireVent
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.global_position = a.global_position + Vector3(0, 0, 40)
	player.get_node("Damageable").set("invulnerable", true)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	var mid := (a.global_position + b.global_position) * 0.5
	var across := (b.global_position - a.global_position).normalized()
	var toward := across.cross(Vector3.UP)
	cam.global_position = mid + toward * 7.0 + Vector3.UP * 1.7
	cam.look_at(mid + Vector3.UP * 1.0)
	await _wait_for(a, FireVent.Phase.WARN, 0.8)
	await _shot("warn")
	await _wait_for(a, FireVent.Phase.ERUPT, 0.4)
	await _shot("erupt")
	cam.global_position = mid - toward * 7.0 + Vector3.UP * 1.7
	cam.look_at(mid + Vector3.UP * 1.0)
	await _wait_for(b, FireVent.Phase.ERUPT, 0.4)
	await _shot("erupt_back")
	print("RESULT PASS")
	get_tree().quit()
