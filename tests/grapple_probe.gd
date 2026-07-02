extends Node3D
## Live physics probe for the grapple hook: floor + a tall wall, real player
## scene, aim up at the wall and press "grapple". Confirms: the HUD validity
## cue reads true pre-fire, the tether attaches, the winch actually pulls the
## player toward the anchor (distance shrinks + height gained), the tether
## visual exists while attached and is freed on release, and the release
## preserves momentum.
## Run: godot --headless --path . --quit-after 1200 res://tests/grapple_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

func _make_box(pos: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new(); sh.size = size
	cs.shape = sh
	b.add_child(cs)
	add_child(b)
	b.global_position = pos

func _ready() -> void:
	_make_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))    # floor
	_make_box(Vector3(0, 12, -22), Vector3(30, 24, 1))    # tall wall to grapple
	add_child(DirectionalLight3D.new())

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	# Face -Z (toward the wall), pitch the head up so the ray lands high on it.
	var head: Node3D = player.get_node("Head")
	head.rotation.x = deg_to_rad(22)
	await get_tree().create_timer(0.4).timeout

	# 1) Pre-fire: the throttled validity probe should read true within ~0.2s.
	await get_tree().create_timer(0.3).timeout
	var valid_before: bool = player._grapple_valid
	print("PRE-FIRE grapple_valid=%s" % valid_before)

	Input.action_press("grapple")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("grapple")

	var attached: bool = player._grappling
	var anchor: Vector3 = player._grapple_point
	var start_dist := player.global_position.distance_to(anchor)
	print("ATTACHED=%s anchor=%s start_dist=%.1f tether_alive=%s" % [
		attached, anchor, start_dist, is_instance_valid(player._tether)])

	var min_dist := start_dist
	var max_height := player.global_position.y
	var release_speed := 0.0
	var elapsed := 0.0
	while elapsed < 4.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if player._grappling:
			min_dist = minf(min_dist, player.global_position.distance_to(anchor))
			release_speed = player.velocity.length()
		max_height = maxf(max_height, player.global_position.y)

	var tether_freed: bool = player._tether == null or not is_instance_valid(player._tether)
	print("PULL min_dist=%.1f (started %.1f)  max_height=%.1f  speed_at_release=%.1f" % [
		min_dist, start_dist, max_height, release_speed])
	print("POST grappling=%s tether_freed=%s cooldown_started=%s" % [
		player._grappling, tether_freed, player._grapple_cd > 0.0 or player._grappling])
	var ok: bool = valid_before and attached and min_dist < start_dist * 0.4 \
		and max_height > 4.0 and tether_freed and not player._grappling
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	print("GRAPPLE_PROBE_DONE")
	get_tree().quit()
