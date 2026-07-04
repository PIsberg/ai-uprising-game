extends Node
## Headless convoy PLAYTEST bot — rides Highway Breakout end to end the way a
## player would: stays aboard the hauler (repositioning with movement keys when
## drifting toward an edge), aim-assists onto the nearest live pursuer, fires in
## bursts, never manually reloads. After the truck parks it hops the rail and
## walks to the exit portal.
##
## Gates (the experience contract):
##   A) alive when the truck reaches the terminus
##   B) the "Survive the ride" task completes
##   C) the level itself completes at the exit portal (State.LEVEL_COMPLETE)
## Telemetry (reported, not gated): kills, min hp, off-deck excursions, peak
## simultaneous pursuit, time-to-complete.
##   godot --headless --path . --audio-driver Dummy res://tests/convoy_playtest.tscn

const TIME_LIMIT := 150.0
const TICK := 0.3

var _player: CharacterBody3D
var _cam: Camera3D
var _head: Node3D
var _truck: Node3D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.current_level_path = "res://scenes/levels/level_convoy.tscn"
	# Representative mid-campaign loadout: convoy is level 7 of 22 — a real run
	# arrives with the early-game pickups, not the bare starter pistol.
	GameState.unlocked_weapons.assign([
		"res://scenes/weapons/pistol.tscn",
		"res://scenes/weapons/rifle.tscn",
		"res://scenes/weapons/shotgun.tscn",
	])
	GameState.equipped_weapon = "res://scenes/weapons/rifle.tscn"
	var lvl: Node = load(GameState.current_level_path).instantiate()
	add_child(lvl)
	var hud := lvl.get_node_or_null("HUD")
	if hud:
		hud.queue_free()
	await get_tree().create_timer(2.5).timeout
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		print("NO PLAYER"); print("RESULT FAIL"); get_tree().quit(); return
	_cam = _player.get("camera")
	_head = _player.get_node_or_null("Head")
	_truck = lvl.get_node("ConvoyRide").get("_truck")
	var ride: Node = lvl.get_node("ConvoyRide")
	GameState.set_state(GameState.State.PLAYING)

	var t := 0.0
	var min_hp := 1e9
	var falls := 0
	var off_deck := false
	var peak_enemies := 0
	var arrived_alive := false
	var arrived_t := -1.0
	var task_done_t := -1.0
	var complete_t := -1.0
	var died_t := -1.0
	var end_z: float = ride.get("end_z")
	var exit_pos := Vector3(7.5, 1.5, -174)

	var deaths := 0
	while t < TIME_LIMIT:
		if not is_instance_valid(_player):
			died_t = t
			break
		if not _player.hp.is_alive():
			# What a player does: hit the respawn button, come back at the
			# checkpoint (pinned to the deck), keep fighting.
			deaths += 1
			print("[%5.1fs] DIED (killer=%s, death #%d)" % [t, GameState.last_killer, deaths])
			if deaths > 3 or not GameState.has_checkpoint():
				died_t = t
				break
			GameState.respawn_at_checkpoint()
			await get_tree().create_timer(0.5).timeout
			t += 0.5
			continue
		min_hp = minf(min_hp, _player.hp.current_health)
		var live := 0
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is EnemyBase and (e as EnemyBase).hp and (e as EnemyBase).hp.is_alive():
				live += 1
		peak_enemies = maxi(peak_enemies, live)

		var truck_z: float = _truck.global_position.z
		var parked: bool = truck_z <= end_z + 0.1
		if parked and arrived_t < 0.0:
			arrived_t = t
			arrived_alive = _player.hp.is_alive()
			print("[%5.1fs] truck parked at terminus, player alive=%s hp=%.0f" % [t, arrived_alive, _player.hp.current_health])
		# Off-deck tracking while the ride is rolling (a fall mid-ride is the
		# experience failure this level's soft separation was built to prevent).
		var rel := _player.global_position - _truck.global_position
		var aboard: bool = absf(rel.x) <= 3.4 and rel.z >= -8.0 and rel.z <= 7.0 \
			and _player.global_position.y > 0.9
		if not parked:
			if not aboard and not off_deck:
				off_deck = true
				falls += 1
				print("[%5.1fs] OFF DECK at %s (truck z=%.1f)" % [t, _player.global_position, truck_z])
			elif aboard and off_deck:
				off_deck = false
				print("[%5.1fs] back aboard" % t)
		if task_done_t < 0.0 and GameState.all_tasks_done():
			task_done_t = t
			print("[%5.1fs] survive task complete — exit unsealed" % t)
		if GameState.current_state == GameState.State.LEVEL_COMPLETE:
			complete_t = t
			print("[%5.1fs] LEVEL COMPLETE" % t)
			break

		if not parked:
			_fight_tick(rel)
		else:
			# Ride over: hop the rail and walk to the exit portal, still shooting
			# anything that followed us in.
			var e := _nearest_enemy()
			if e and _player.global_position.distance_to(e.global_position) < 12.0:
				_aim_at(e.global_position + Vector3(0, 0.6, 0))
				Input.action_press("fire")
			else:
				Input.action_release("fire")
				# Still on the deck? Hop the RIGHT rail first — the cab blocks
				# the straight line to the portal — then walk the roadside.
				var target := exit_pos
				if absf(_player.global_position.x) < 3.4 and _player.global_position.y > 1.0:
					target = _truck.global_position + Vector3(6.0, 1.2, 0.0)
				_aim_at(target + Vector3(0, 0.6, 0))
				Input.action_press("move_forward")
				if fmod(t, 1.2) < TICK: # rail hop / ledge assist
					Input.action_press("jump")
					await get_tree().create_timer(0.15).timeout
					Input.action_release("jump")
				if fmod(t, 4.0) < TICK:
					var portal: Node3D = null
					for o in get_tree().get_nodes_in_group("objective"):
						if o is Portal:
							portal = o
							break
					if portal:
						print("[%5.1fs] walking out: player=%s portal=%s locked=%s completed=%s monitoring=%s" % [t,
							_player.global_position, portal.global_position, portal.get("_locked"), portal.get("_completed"), (portal as Area3D).monitoring])
					else:
						print("[%5.1fs] walking out: player=%s NO PORTAL FOUND state=%s" % [t, _player.global_position, GameState.current_state])
		await get_tree().create_timer(TICK).timeout
		Input.action_release("fire")
		t += TICK + 0.02

	for a in ["move_forward", "move_left", "move_right", "move_back", "fire", "jump"]:
		Input.action_release(a)

	var gate_a := arrived_alive
	var gate_b := task_done_t >= 0.0
	var gate_c := complete_t >= 0.0
	print("")
	print("CONVOY PLAYTEST t=%.0fs kills=%d min_hp=%.0f falls=%d peak_pursuit=%d deaths=%d" % [t, GameState.kills, min_hp, falls, peak_enemies, deaths])
	if died_t >= 0.0:
		print("     run ended dead at %.1fs killer=%s" % [died_t, GameState.last_killer])
	print(("ok   ride survived (parked %.1fs)" % arrived_t) if gate_a else "BAD  did not survive the ride")
	print(("ok   survive task done at %.1fs" % task_done_t) if gate_b else "BAD  survive task never completed")
	print(("ok   level complete at %.1fs" % complete_t) if gate_c else "BAD  exit never completed the level")
	print("RESULT ", "PASS" if gate_a and gate_b and gate_c else "FAIL")
	get_tree().quit()

## One combat beat while riding: grab the deck medkit when hurt, keep near the
## deck centre, burst-fire at the highest-priority pursuer. Movement is a
## repositioning nudge, not a sprint — a bot holding move_forward on a flatbed
## walks off the nose.
func _fight_tick(rel: Vector3) -> void:
	for a in ["move_forward", "move_left", "move_right", "move_back"]:
		Input.action_release(a)
	# Hurt and a medkit is riding the deck? Walk over it (supply magnetism
	# closes the last metre) — what any player does between volleys.
	if _player.hp.current_health < 60.0:
		var med := _deck_health()
		if med:
			_aim_at(med.global_position)
			Input.action_press("move_forward")
			var e0 := _pick_target()
			if e0:
				_aim_at(e0.global_position + Vector3(0, 0.6, 0))
				Input.action_press("fire")
			return
	# Peek-and-shelter: hurt → duck under the canopy to break the flyers'
	# sightlines and recover; healthy enough → fight from the nook's MOUTH,
	# stepping toward open deck whenever the roof blocks the shot. This is the
	# baseline cover rhythm a human falls into on this ride.
	var sheltering: bool = _player.hp.current_health < 45.0
	var anchor := Vector3(-0.4, 1.8, -1.0) # nook mouth: covered flank, open sky ahead
	if sheltering:
		anchor = Vector3(-1.7, 1.8, -2.6)  # deep under the canopy
	var drift := Vector2(rel.x - anchor.x, rel.z - anchor.z)
	if drift.length() > 1.6 and _player.global_position.y > 0.9:
		# Face the anchor point and take a step toward it.
		_aim_at(_truck.global_position + anchor)
		Input.action_press("move_forward")
		return
	var e := _pick_target()
	if e:
		_aim_at(e.global_position + Vector3(0, 0.6, 0))
		if _clear_shot(e):
			Input.action_press("fire")
		elif not sheltering:
			# Roof (or cab) is eating the shot — step out to the open deck.
			_aim_at(_truck.global_position + Vector3(0.8, 1.8, 0.8))
			Input.action_press("move_forward")

func _clear_shot(target: Node3D) -> bool:
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(_cam.global_position,
		target.global_position + Vector3(0, 0.6, 0))
	q.collision_mask = 1
	q.exclude = [_player.get_rid()]
	return space.intersect_ray(q).is_empty()

## Kamikaze seekers closing in get shot FIRST — every playtest death so far
## was a seeker detonation on a low-hp player busy with the nearest drone.
func _pick_target() -> Node3D:
	var seeker: Node3D = null
	var sd := 25.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as EnemyBase).hp and (e as EnemyBase).hp.is_alive():
			if "SEEKER" in str((e as Node).name).to_upper():
				var d: float = _player.global_position.distance_to((e as Node3D).global_position)
				if d < sd:
					sd = d
					seeker = e
	return seeker if seeker else _nearest_enemy()

func _deck_health() -> Node3D:
	for p in get_tree().get_nodes_in_group("pickup"):
		if p is Node3D and p.get("kind") == 0 and not p.get("_taken") \
			and _player.global_position.distance_to((p as Node3D).global_position) < 9.0:
			return p
	return null

func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as EnemyBase).hp and (e as EnemyBase).hp.is_alive():
			var d: float = _player.global_position.distance_to((e as Node3D).global_position)
			if d < bd:
				bd = d
				best = e
	return best

func _aim_at(target: Vector3) -> void:
	var eye := _cam.global_position
	var d := target - eye
	_player.rotation.y = atan2(-d.x, -d.z)
	if _head:
		_head.rotation.x = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)
