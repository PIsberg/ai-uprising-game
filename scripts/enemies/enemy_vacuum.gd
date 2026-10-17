class_name EnemyVacuum
extends EnemyBase
## "Custodian" cleaning unit. Idles as a low disc trundling along the floor,
## vacuuming. The instant it senses the player — or takes a hit — it shudders,
## unfolds four legs and rears up into a hostile walker, then chases and fires
## energy bolts. Built entirely from procedural primitives so the transform can
## be animated in code.
## While still a disc it CLEANS UP: any supply pickup (health, ammo, overclock,
## overdrive: kill drops included, never weapons) within SCAVENGE_RANGE in a
## straight line of sight, it trundles to and swallows (`swallowed`), bulging a
## little per item. Destroyed, it spills everything it ate. tests/custodian_loot_probe.

enum Phase { GROUND, RISING, COMBAT }

@export var preview: bool = false ## Codex/briefing showcase: loop the disc->walker rise so the transformation reads in the viewer.
@export var wake_range: float = 13.0
@export var rise_duration: float = 1.4
@export var rise_height: float = 0.95
@export var ground_speed: float = 2.6
@export var proj_speed: float = 40.0
@export var proj_damage: float = 9.0
@export var burst_count: int = 2

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")
## The firing hop. A disc on legs has no business shooting from ankle height, so
## once risen it only fires from the top of a spring: crouch (the tell), launch,
## hang at the apex on its intake while the burst goes out, land, reposition.
## Every shot is a moment it is up at eye height with its underside exposed.
enum Hop { NONE, CROUCH, AIR, LAND }
const HOP_HEIGHT := 1.4      ## apex of the hop, metres above the floor it left
const CROUCH_TIME := 0.35    ## legs compress before it springs: the tell
const HANG_TIME := 0.45      ## hover at the apex while the burst goes out
const HANG_SINK := 0.25      ## m/s it sinks while hovering
const LAND_TIME := 0.3       ## legs absorb the landing: no moving, no hop
const AIR_DAMAGE_MULT := 1.5 ## airborne hits land on the exposed intake (a crit)

var _hop: int = Hop.NONE
var _hop_t: float = 0.0
var _hang_t: float = 0.0
var _hop_fired: bool = false

var _phase: int = Phase.GROUND
var _rise_t: float = 0.0
var _chassis: Node3D
var _legs: Array[Node3D] = []
var _eye_mat: StandardMaterial3D
var _wander: Vector3 = Vector3.FORWARD
var _wander_cd: float = 0.0
var _burst_left: int = 0
var _burst_t: float = 0.0

const SCAVENGE_RANGE := 14.0
const SCAVENGE_SPEED := 3.6
const SWALLOW_RANGE := 0.9
const SCAVENGE_KINDS := {0: "health", 1: "ammo", 3: "overclock", 4: "overdrive"} ## Pickup.Kind -> pickup_scene key
const LOOT_TEACH := "CUSTODIAN: it vacuums up supplies, your kill drops too. Destroy it and it spills everything it ate."
## What it has eaten: [{kind: String, amount: int}], spilled on death.
var swallowed: Array[Dictionary] = []
var _loot_target: Node3D = null


func _ready() -> void:
	max_health = 95.0
	move_speed = 6.5            # combat walk speed (once risen)
	turn_speed = 7.0
	sight_range = 30.0
	sight_angle_deg = 230.0
	attack_range = 22.0
	preferred_range = 12.0
	attack_cooldown = 1.4
	score_value = 110
	stagger_threshold = 60.0
	telegraph_time = 0.0        # the crouch before each hop is its tell
	super._ready()
	_build_model()
	_apply_rise(0.0)
	if preview:
		# Codex showcase: physics is disabled there, so drive the disc->walker rise
		# (and a fold back) on a loop via a tween, so the viewer sees it transform
		# exactly like it does the instant it senses you in-game.
		_preview_rise()


## Looping rise/fold for the encyclopedia (runs off a tween, not physics).
func _preview_rise() -> void:
	if _eye_mat:
		_eye_mat.emission_energy_multiplier = 1.2
	var t := create_tween().set_loops()
	t.tween_interval(0.8)
	t.tween_method(_apply_rise, 0.0, 1.0, rise_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_interval(2.4)              # stand reared up so it reads as the hostile walker
	t.tween_method(_apply_rise, 1.0, 0.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_interval(1.0)


func _build_model() -> void:
	var model: Node3D = get_node_or_null("Model")
	if model == null:
		model = Node3D.new()
		model.name = "Model"
		add_child(model)
	_chassis = Node3D.new()
	_chassis.name = "Chassis"
	model.add_child(_chassis)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.72, 0.74, 0.77)
	body_mat.metallic = 0.6
	body_mat.roughness = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.11, 0.11, 0.13)
	dark.metallic = 0.7
	dark.roughness = 0.5
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.2, 0.9, 1.0)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(0.2, 0.9, 1.0)
	_eye_mat.emission_energy_multiplier = 1.2

	# Disc body (the vacuum-cleaner chassis).
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.52
	dm.bottom_radius = 0.58
	dm.height = 0.2
	dm.material = body_mat
	disc.mesh = dm
	disc.position.y = 0.12
	_chassis.add_child(disc)

	# Dark bumper ring around the rim.
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.6
	rm.bottom_radius = 0.6
	rm.height = 0.06
	rm.material = dark
	ring.mesh = rm
	ring.position.y = 0.19
	_chassis.add_child(ring)

	# Sensor dome / glowing eye on the forward edge.
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.26
	sm.material = _eye_mat
	dome.mesh = sm
	dome.position = Vector3(0, 0.26, -0.18)
	_chassis.add_child(dome)

	# Glowing intake on the underside: hidden against the floor, it shows (and
	# is the crit spot) only while the unit is in the air.
	var intake := MeshInstance3D.new()
	var im := CylinderMesh.new()
	im.top_radius = 0.34
	im.bottom_radius = 0.34
	im.height = 0.02
	var intake_mat := StandardMaterial3D.new()
	intake_mat.albedo_color = Color(1.0, 0.45, 0.15)
	intake_mat.emission_enabled = true
	intake_mat.emission = Color(1.0, 0.45, 0.15)
	intake_mat.emission_energy_multiplier = 3.0
	im.material = intake_mat
	intake.mesh = im
	intake.position.y = 0.015
	_chassis.add_child(intake)

	# Four folded legs that unfold and lock vertical when it rises.
	for i in 4:
		var ang := PI * 0.25 + float(i) * PI * 0.5
		var pivot := Node3D.new()
		pivot.position = Vector3(cos(ang) * 0.5, 0.12, sin(ang) * 0.5)
		_chassis.add_child(pivot)
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.08, 0.55, 0.08)
		lm.material = dark
		leg.mesh = lm
		leg.position = Vector3(0, -0.27, 0)   # extends down from the pivot
		pivot.add_child(leg)
		pivot.rotation = Vector3(0, ang, PI * 0.5)  # folded flat under the disc
		_legs.append(pivot)


## t: 0 = folded disc flat on the ground, 1 = reared up standing on its legs.
func _apply_rise(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)  # smoothstep
	if _chassis:
		_chassis.position.y = e * rise_height
	for i in _legs.size():
		var ang := PI * 0.25 + float(i) * PI * 0.5
		_legs[i].rotation = Vector3(0, ang, lerpf(PI * 0.5, 0.0, e))
	if _eye_mat:
		_eye_mat.emission_energy_multiplier = lerpf(1.2, 3.6, e)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	match _phase:
		Phase.GROUND:
			_ground_tick(delta)
		Phase.RISING:
			_rising_tick(delta)
		Phase.COMBAT:
			super._physics_process(delta)
			_combat_fire(delta)


func _ground_tick(delta: float) -> void:
	_perceive()
	if target and is_instance_valid(target):
		var d := global_position.distance_to(target.global_position)
		if d <= wake_range and _can_see(target):
			_begin_rise()
			return
	if _scavenge(delta):
		return
	# Slow cleaning wander.
	_wander_cd -= delta
	if _wander_cd <= 0.0:
		_wander_cd = randf_range(1.5, 3.0)
		var a := randf() * TAU
		_wander = Vector3(cos(a), 0.0, sin(a))
	velocity.x = _wander.x * ground_speed
	velocity.z = _wander.z * ground_speed
	_face_dir(_wander, delta)
	_apply_gravity(delta)
	move_and_slide()


## Cleaning duty: go for the nearest visible supply pickup and swallow it.
## True while it is busy with one (it owns this frame's movement).
func _scavenge(delta: float) -> bool:
	if _loot_target == null or not is_instance_valid(_loot_target) or not _loot_target.is_inside_tree():
		_loot_target = _nearest_loot()
		if _loot_target == null:
			return false
	var to := _loot_target.global_position - global_position
	to.y = 0.0
	if to.length() <= SWALLOW_RANGE:
		_swallow(_loot_target)
		_loot_target = null
		return true
	var d := to.normalized()
	velocity.x = d.x * SCAVENGE_SPEED
	velocity.z = d.z * SCAVENGE_SPEED
	_face_dir(d, delta)
	_apply_gravity(delta)
	move_and_slide()
	return true

func _nearest_loot() -> Node3D:
	var best: Node3D = null
	var best_d := SCAVENGE_RANGE
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("pickup"):
		var p := n as Pickup
		if p == null or not is_instance_valid(p) or p.is_queued_for_deletion() or p.get("_taken") or not SCAVENGE_KINDS.has(int(p.kind)):
			continue
		var d := p.global_position.distance_to(global_position)
		if d >= best_d or absf(p.global_position.y - global_position.y) > 1.5:
			continue
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.4, p.global_position + Vector3.UP * 0.4, 1)
		q.exclude = [get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue # it wanders on direct velocity: only a straight run is a run
		best = p
		best_d = d
	return best

func _swallow(p: Node3D) -> void:
	var pk := p as Pickup
	swallowed.append({"kind": String(SCAVENGE_KINDS[int(pk.kind)]), "amount": int(pk.amount)})
	pk.set("_taken", true)
	pk.queue_free()
	if _chassis:
		var k := 1.0 + 0.07 * float(mini(swallowed.size(), 4))
		_chassis.scale = Vector3(k, 1.0 + 0.04 * float(mini(swallowed.size(), 4)), k)
	AudioBus.play_synth_at("pickup_clink", global_position, -4.0, 0.6)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl and pl.global_position.distance_to(global_position) <= 35.0:
		GameState.teach_once("custodian_loot", LOOT_TEACH)

## Everything it ate comes back out, on a ring around the wreck.
func _spill() -> void:
	var parent := get_parent()
	if parent == null or swallowed.is_empty():
		return
	var n := swallowed.size()
	for i in n:
		var e: Dictionary = swallowed[i]
		var scene := LevelBuilder.pickup_scene(String(e["kind"]))
		if scene == null:
			continue
		var inst := scene.instantiate() as Pickup
		inst.amount = int(e["amount"])
		parent.add_child(inst)
		var a := TAU * float(i) / float(n)
		inst.global_position = global_position + Vector3(cos(a), 0.0, sin(a)) * (1.2 if n > 1 else 0.0) + Vector3.UP * 0.1
	swallowed.clear()
	AudioBus.play_synth_at("pickup_ammo", global_position, 0.0, 0.7)

func _begin_rise() -> void:
	if _phase != Phase.GROUND:
		return
	_phase = Phase.RISING
	_rise_t = 0.0
	velocity = Vector3.ZERO
	AudioBus.play_synth_at("drone_hum", global_position, -1.0, 0.8)
	_speak("atk", 0.6)


func _rising_tick(delta: float) -> void:
	_rise_t += delta / maxf(0.1, rise_duration)
	if _chassis:
		_chassis.position.x = sin(_rise_t * 38.0) * 0.03 * (1.0 - clampf(_rise_t, 0.0, 1.0))
	_apply_rise(_rise_t)
	_apply_gravity(delta)
	move_and_slide()
	if _rise_t >= 1.0:
		if _chassis:
			_chassis.position.x = 0.0
		_phase = Phase.COMBAT
		set_state(State.CHASE)


func _combat_fire(delta: float) -> void:
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_fire_one()
			_burst_left -= 1
			_burst_t = 0.12


## An attack is a hop; the burst goes out at its apex (_hop_tick).
func _perform_attack() -> void:
	if target == null or _hop != Hop.NONE or not is_on_floor():
		return
	_hop = Hop.CROUCH
	_hop_t = 0.0
	_hop_fired = false
	_begin_telegraph(CROUCH_TIME)


## Mid-hop the spring is committed: the hop replaces the state machine (chase,
## spacing, grenade scramble) until it has landed.
func _run_state(delta: float) -> void:
	if _hop == Hop.NONE:
		super._run_state(delta)
	else:
		_hop_tick(delta)


func _hop_tick(delta: float) -> void:
	_hop_t += delta
	_face_target(delta)
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	match _hop:
		Hop.CROUCH:
			_apply_rise(1.0 - 0.45 * sin(clampf(_hop_t / CROUCH_TIME, 0.0, 1.0) * PI * 0.5))
			if _hop_t >= CROUCH_TIME:
				_hop = Hop.AIR
				_hop_t = 0.0
				_apply_rise(1.0)
				velocity.y = sqrt(2.0 * g * HOP_HEIGHT)
				AudioBus.play_synth_at("servo_step_heavy", global_position, -2.0, 1.4)
		Hop.AIR:
			if not _hop_fired and velocity.y <= 0.0:
				_hop_fired = true
				_hang_t = HANG_TIME
				if target and is_instance_valid(target) and _can_see(target):
					_burst_left = burst_count
					_burst_t = 0.0
			if _hang_t > 0.0:
				_hang_t -= delta
				velocity.y = g * delta - HANG_SINK # EnemyBase takes g*delta off next
			elif _hop_fired and is_on_floor():
				_hop = Hop.LAND
				_hop_t = 0.0
				AudioBus.play_synth_at("servo_step_heavy", global_position, -1.0, 0.8)
			elif _hop_t > 4.0: # fell off something; give up the hop
				_end_hop()
		Hop.LAND:
			_apply_rise(lerpf(0.6, 1.0, clampf(_hop_t / LAND_TIME, 0.0, 1.0)))
			if _hop_t >= LAND_TIME:
				_end_hop()


func _end_hop() -> void:
	_hop = Hop.NONE
	_apply_rise(1.0)
	_attack_timer = attack_interval() # the cooldown runs from landing


func is_airborne() -> bool:
	return _hop == Hop.AIR


func is_hopping() -> bool:
	return _hop != Hop.NONE


## Shot down mid-hop: drop the body to the floor under the death blast, so the
## blast and scorch mark land on the ground, not in the air (the wreck itself
## would fall on its own, WreckBody).
func _on_died(source: Node) -> void:
	_spill()
	if is_hopping():
		_hop = Hop.NONE
		_burst_left = 0
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.2,
				global_position + Vector3.DOWN * 8.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			global_position.y = (hit["position"] as Vector3).y
	super._on_died(source)


## Hits while it is in the air land on the exposed intake.
func weakpoint_multiplier(hit_pos: Vector3) -> float:
	var m := super.weakpoint_multiplier(hit_pos)
	return m * AIR_DAMAGE_MULT if is_airborne() else m


func _fire_one() -> void:
	if target == null or not is_instance_valid(target):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var origin: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP
	var proj := PROJECTILE.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = origin
	var dir := (target.global_position + Vector3.UP * 0.5 - origin).normalized()
	dir = scatter_aim(dir, 3.0)
	if proj.has_method("launch"):
		proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()


## Taking fire while still a disc also triggers the rise.
func _on_damaged(amount: float, source: Node) -> void:
	super._on_damaged(amount, source)
	if _phase == Phase.GROUND:
		_begin_rise()
