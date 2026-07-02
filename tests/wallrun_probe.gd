extends Node3D
## Live physics probe for the player's wall-run: builds a small arena with a
## wall, spawns the REAL player scene, simulates sprinting into the wall via
## the Input singleton, and confirms _wall_running engages, holds velocity
## along the wall's tangent, and a wall-jump launches away from the wall with
## the expected up/forward carry.
## Run: godot --headless --path . --quit-after 2000 res://tests/wallrun_probe.tscn
## Note: a couple of physics frames of latency are expected after any
## Input.action_press() call before is_action_just_pressed() reads true — an
## artifact of simulating input this way, not present with real input events.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _player: CharacterBody3D
var _saw_wall_run := false
var _peak_wall_speed := 0.0
var _max_weapon_lean := 0.0
var _wall_jump_launch_vel := Vector3.ZERO

func _ready() -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	nav.add_child(floor_mi)
	var floor_body := StaticBody3D.new(); floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new(); var fbs := BoxShape3D.new(); fbs.size = Vector3(60, 1, 60)
	fcs.shape = fbs; fcs.position = Vector3(0, -0.5, 0); floor_body.add_child(fcs)
	nav.add_child(floor_body)

	# A long wall running along Z at x=3.5, for the player to sprint into.
	var wall_body := StaticBody3D.new(); wall_body.collision_layer = 1
	var wcs := CollisionShape3D.new(); var wbs := BoxShape3D.new(); wbs.size = Vector3(1, 6, 40)
	wcs.shape = wbs; wall_body.add_child(wcs)
	wall_body.position = Vector3(3.5, 3, 0)
	add_child(wall_body)

	var sun := DirectionalLight3D.new(); add_child(sun)

	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 1.0, -10)
	_player.rotation.y = 0.0 # facing -Z (forward); wall is to the +X side

	await get_tree().create_timer(0.3).timeout

	# Sprint forward with a rightward drift into the wall, hop to get airborne,
	# then keep holding into the wall so the wall-run engages mid-air.
	Input.action_press("sprint")
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await get_tree().create_timer(0.5).timeout
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")

	var elapsed := 0.0
	var jumped_for_wall_run := false
	while elapsed < 4.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if "_wall_running" in _player and _player._wall_running:
			# Let the idle-process pass run too (WeaponManager._process folds
			# external_roll into weapon_holder.rotation.z there, after this
			# physics tick) before reading the viewmodel's actual rendered lean.
			await get_tree().process_frame
			var wh: Node3D = _player.get_node("Head/Camera3D/WeaponHolder")
			if not _saw_wall_run:
				print("WALL_RUN ENGAGED at t=%.2f  normal=%s  run_dir=%s  weapon_holder.rotation.z=%.4f" % [
					elapsed, _player._wall_normal, _player._wall_run_dir, wh.rotation.z])
			_saw_wall_run = true
			_max_weapon_lean = maxf(_max_weapon_lean, absf(wh.rotation.z))
			_peak_wall_speed = maxf(_peak_wall_speed, Vector2(_player.velocity.x, _player.velocity.z).length())
			if not jumped_for_wall_run and elapsed > 0.6:
				jumped_for_wall_run = true
				# Release movement so the post-jump reading isn't immediately
				# blended back toward held-input direction by _handle_movement.
				Input.action_release("move_forward")
				Input.action_release("move_right")
				Input.action_release("sprint")
				Input.action_press("jump")
				for i in 3: # settle past the simulated-input just-pressed latency
					await get_tree().physics_frame
				_wall_jump_launch_vel = _player.velocity
				Input.action_release("jump")
				print("WALL_JUMP  launch_vel=%s  (expect away-from-wall x, positive y, some z carry)" % _wall_jump_launch_vel)

	print("RESULT saw_wall_run=%s peak_wall_speed=%.2f max_weapon_lean_deg=%.2f wall_jump_launched_away=%s" % [
		_saw_wall_run, _peak_wall_speed, rad_to_deg(_max_weapon_lean),
		_wall_jump_launch_vel.x < -0.5 and _wall_jump_launch_vel.y > 0.5 if _saw_wall_run else "n/a"])
	print("WALLRUN_PROBE_DONE")
	get_tree().quit()
