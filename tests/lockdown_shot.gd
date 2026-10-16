extends Node3D
## Windowed visual check for a level's lockdown house (Maple Grove's by
## default): the doorway from the street with the locked safe inside, then the
## sealed door from inside as wave 1 warps in, then the safe open after the
## clear. Headless gives black frames.
##   godot --path . res://tests/lockdown_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "suburb"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://lockdown_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

## The level's own trigger spawners wake as the player walks in; keep every
## robot out of the frame so the door and safe can be judged.
func _hide_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node3D).visible = false

func _shot(name: String) -> void:
	_hide_enemies()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/lockdown_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false
	GameState.current_state = GameState.State.PLAYING
	var z := lvl.find_children("*", "LockdownZone", true, false)[0] as LockdownZone
	var door: FirewallBarrier = z.doors[0]
	var out := (door.global_position - z.global_position)
	out.y = 0.0
	out = out.normalized()
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.get_node("Damageable").set("invulnerable", true)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	# Parked far off: a robot marker aimed at the player stood in the doorway view.
	player.global_position = Vector3(0, 30, -200)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	cam.global_position = door.global_position + out * 6.0 + Vector3.UP * 1.7
	cam.look_at(z.global_position + Vector3.UP * 0.8)
	for i in 10:
		await get_tree().physics_frame
	await _shot("street")
	player.global_position = z.global_position + Vector3.UP * 0.1
	while z.phase != LockdownZone.Phase.FIGHTING or z.spawned_this_wave < 1:
		await get_tree().physics_frame
	for i in 30:
		await get_tree().physics_frame
	var side := out.cross(Vector3.UP).normalized()
	cam.global_position = z.global_position + side * 2.4 - out * 0.5 + Vector3.UP * 1.7
	cam.look_at(door.global_position + Vector3.UP * 1.3)
	await _shot("sealed")
	z.waves = [z.waves[0]]
	for r in z.live:
		if is_instance_valid(r) and r.hp:
			r.hp.apply_damage(1.0e6, null)
	while z.phase != LockdownZone.Phase.CLEARED:
		await get_tree().physics_frame
		for r in z.live:
			if is_instance_valid(r) and r.hp and r.hp.is_alive():
				r.hp.apply_damage(1.0e6, null)
	for i in 20:
		await get_tree().physics_frame
	var safe := z.to_global(z.reward + Vector3(0, 0.5, 0.9))
	cam.global_position = safe + out * 3.0 + Vector3.UP * 1.2
	cam.look_at(safe)
	await _shot("safe_open")
	print("RESULT PASS")
	get_tree().quit()
