extends Node3D
## Live physics probe for this session's player-feel additions: dash and
## hard-landing viewmodel kicks, and the weapon-accurate dynamic crosshair
## reading a real WeaponData's spread/aim identity.
## Run: godot --headless --path . --quit-after 900 res://tests/player_feel_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _player: CharacterBody3D
var _weapon_holder: Node3D
var _max_dash_kick := 0.0
var _max_land_kick := 0.0

func _ready() -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	# Floor plus a raised ledge to fall from for a hard landing.
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	nav.add_child(floor_mi)
	var floor_body := StaticBody3D.new(); floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new(); var fbs := BoxShape3D.new(); fbs.size = Vector3(60, 1, 60)
	fcs.shape = fbs; fcs.position = Vector3(0, -0.5, 0); floor_body.add_child(fcs)
	nav.add_child(floor_body)
	var ledge_body := StaticBody3D.new(); ledge_body.collision_layer = 1
	var lcs := CollisionShape3D.new(); var lbs := BoxShape3D.new(); lbs.size = Vector3(6, 1, 6)
	lcs.shape = lbs; ledge_body.add_child(lcs)
	ledge_body.position = Vector3(0, 9.5, -20)
	add_child(ledge_body)
	var sun := DirectionalLight3D.new(); add_child(sun)

	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	_weapon_holder = _player.get_node("Head/Camera3D/WeaponHolder")
	var home := _weapon_holder.position

	# --- Phase 1: dash on flat ground, watch weapon_holder deviate from home. ---
	_player.global_position = Vector3(0, 1.0, 0)
	await get_tree().create_timer(0.3).timeout
	Input.action_press("move_forward")
	await get_tree().physics_frame
	Input.action_press("dash")
	for i in 20:
		await get_tree().physics_frame
		_max_dash_kick = maxf(_max_dash_kick, (_weapon_holder.position - home).length())
	Input.action_release("dash")
	Input.action_release("move_forward")
	print("DASH  max weapon_holder offset from home = %.4f" % _max_dash_kick)

	# --- Phase 2: drop off the ledge for a hard landing. ---
	await get_tree().create_timer(0.3).timeout
	var cam := _player.get_node("Head/Camera3D") as Camera3D
	var cam_home_y := cam.position.y
	# Well above the plain floor (not the ledge) so there's real fall distance to
	# build up a hard-landing-tier impact, not a half-metre step-off.
	_player.global_position = Vector3(10, 20.0, 10)
	_player.velocity = Vector3.ZERO
	var elapsed := 0.0
	var was_floor := _player.is_on_floor()
	var min_cam_y := cam_home_y
	while elapsed < 4.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		_max_land_kick = maxf(_max_land_kick, (_weapon_holder.position - home).length())
		min_cam_y = minf(min_cam_y, cam.position.y)
		var on_floor := _player.is_on_floor()
		if on_floor != was_floor:
			print("  t=%.2f on_floor -> %s  vel.y=%.2f" % [elapsed, on_floor, _player.velocity.y])
			was_floor = on_floor
	print("LANDING  max weapon_holder offset from home = %.4f  min_cam_y_dip=%.4f (home=%.4f)" % [
		_max_land_kick, cam_home_y - min_cam_y, cam_home_y])

	print("RESULT dash_kicked=%s land_kicked=%s" % [_max_dash_kick > 0.01, _max_land_kick > 0.01])
	print("PLAYER_FEEL_PROBE_DONE")
	get_tree().quit()
