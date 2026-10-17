extends Node3D
## Windowed visual check for honeypots in a level (MISTRAL's first by default):
## the bait at eye height from 4 m with a real pickup of its kind 1.6 m to its
## left, first between tears (they must look the same), then mid-tear (red,
## squashed, knocked sideways). Headless gives black frames.
##   godot --path . res://tests/honeypot_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "mistral"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://honeypot_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/honeypot_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.get_node("Damageable").set("invulnerable", true)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(90, 10, 90)
	var bait := lvl.find_children("*", "HoneypotCache", true, false)[0] as HoneypotCache
	bait.set_physics_process(false)
	var at := bait.global_position
	var to_centre := (Vector3.ZERO - at)
	to_centre.y = 0.0
	to_centre = to_centre.normalized()
	var left := Vector3(to_centre.z, 0.0, -to_centre.x)
	var real := (LevelBuilder.pickup_scene(bait.kind).instantiate()) as Node3D
	lvl.add_child(real)
	real.global_position = at + left * 1.6
	real.set_deferred("monitoring", false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 60.0
	cam.global_position = at + left * 0.8 + to_centre * 4.0 + Vector3.UP * 1.5
	cam.look_at(at + left * 0.8 + Vector3.UP * 0.6)
	while bait.glitching:
		await get_tree().process_frame
	for i in 6:
		await get_tree().process_frame
	await _shot("calm")
	while not bait.glitching:
		await get_tree().process_frame
	await _shot("tear")
	print("RESULT PASS")
	get_tree().quit()
