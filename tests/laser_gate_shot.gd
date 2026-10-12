extends Node3D
## Windowed visual check for a level's laser gate (Skybridge Uplink's first
## blast door by default): the doorway from 6 m with the knee beam live, with
## the chest beam flickering its warning, and with the chest beam live.
## Headless gives black frames.
##   godot --path . res://tests/laser_gate_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "uplink"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://laser_gate_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/gate_%s_%s.png" % [_out_dir, _level, name])
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
	var gate := lvl.find_children("*", "LaserGate", true, false)[0] as LaserGate
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.global_position = gate.global_position + Vector3(0, 0, -40)
	player.get_node("Damageable").set("invulnerable", true)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	var at := gate.global_position
	cam.global_position = at + Vector3(1.2, 1.6, 6.0)
	cam.look_at(at + Vector3(0, 0.9, 0))
	await _until(func() -> bool: return gate.live_beam() == 0 and gate.flickering() == -1)
	await _shot("knee_live")
	await _until(func() -> bool: return gate.flickering() == 1 and gate.beam_shown(1))
	await _shot("chest_warns")
	await _until(func() -> bool: return gate.live_beam() == 1 and gate.flickering() == -1)
	await _shot("chest_live")
	print("RESULT PASS")
	get_tree().quit()
