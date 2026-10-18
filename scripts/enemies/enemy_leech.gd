class_name EnemyLeech
extends EnemyBase
## TELEMETRY LEECH: a small, fragile flyer that does not shoot. It weaves in at
## the player's head height and, within LATCH_RANGE, LATCHES on behind their
## head. Latched, it has no collision (you cannot shoot your own back), drains
## DRAIN_DPS, slows the player to SLOW (Player._current_speed reads the
## "leech_latched" group) and every BEACON_PERIOD phones the player's position
## home: every unaware robot within BEACON_RANGE turns and comes. Two answers:
## melee rips it off and kills it (Player._handle_melee -> rip_off), a dash
## shakes it loose, stunned for SHAKE_STUN (Player._handle_dash -> shake_off).
## It never latches on during the opening-seconds grace, through dash
## i-frames, or while stunned. Shoot it down before it gets there: 24 hp.
## tests/leech_probe.

const LATCH_RANGE := 1.3
const DRAIN_DPS := 4.0
const SLOW := 0.8
const BEACON_PERIOD := 2.0
const BEACON_RANGE := 45.0
const SHAKE_STUN := 1.5
const SHAKE_FLING := 7.0
const WEAVE := 2.2      ## m/s of sideways weave on the approach
const BACK_OFFSET := Vector3(0, 0.15, 0.35) ## behind the head, camera space
const GREEN := Color(0.55, 1.0, 0.25)
const TEACH_TEXT := "TELEMETRY LEECH: it rides your back and calls every robot to you. Melee [F] rips it off; a dash shakes it loose."

var latched := false
var beacons := 0
var _victim: Node3D
var _drain_acc := 0.0
var _beacon_t := 0.0
var _weave_t := 0.0
var _layer := 4

func _ready() -> void:
	max_health = 24.0
	move_speed = 8.5
	turn_speed = 10.0
	sight_range = 36.0
	sight_angle_deg = 200.0
	attack_range = 30.0
	preferred_range = 0.5
	attack_cooldown = 1.0
	score_value = 120
	stagger_threshold = 99999.0
	super._ready()
	_layer = collision_layer
	_weave_t = randf() * TAU
	_build_claws()
	if hp:
		hp.died.connect(func(_s: Node) -> void: _detach())

## Four dark grapple claws hooked under the shell: the silhouette that says
## "this one clings", apart from the other EyeDrone flyers.
func _build_claws() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.11, 0.1)
	mat.metallic = 0.7
	mat.roughness = 0.35
	for i in 4:
		var a := TAU * float(i) / 4.0 + TAU / 8.0
		var pivot := Node3D.new()
		pivot.position = Vector3(sin(a) * 0.14, -0.08, cos(a) * 0.14)
		pivot.rotation.y = a
		add_child(pivot)
		for seg in 2:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.035, 0.2, 0.035)
			bm.material = mat
			mi.mesh = bm
			# Upper segment splays out, lower one hooks back in.
			mi.rotation.x = 0.9 if seg == 0 else -0.5
			mi.position = Vector3(0, -0.07, 0.07) if seg == 0 else Vector3(0, -0.21, 0.15)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(mi)

func _apply_gravity(_delta: float) -> void:
	pass # it flies

func pilot_flies() -> bool:
	return true # a NeuralUplink pilot climbs and dives on jump/crouch

func _state_chase(delta: float) -> void:
	if target == null:
		set_state(State.IDLE)
		return
	_approach(delta)

func _state_attack(delta: float) -> void:
	_state_chase(delta)

## Straight in at head height with a sideways weave, so it is a hard shot.
func _approach(delta: float) -> void:
	var ty := target.global_position.y + 1.4
	var to := Vector3(target.global_position.x, ty, target.global_position.z) - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > 0.05:
		var d := flat.normalized()
		_weave_t += delta * 5.0
		var side := Vector3(-d.z, 0.0, d.x) * sin(_weave_t) * WEAVE * clampf(flat.length() / 6.0, 0.0, 1.0)
		var want := d * chase_speed() + side
		velocity.x = move_toward(velocity.x, want.x, 20.0 * delta)
		velocity.z = move_toward(velocity.z, want.z, 20.0 * delta)
		_face_dir(d, delta)
	velocity.y = move_toward(velocity.y, (ty - global_position.y) * 5.0, 30.0 * delta)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if latched:
		_ride(delta)
		return
	super._physics_process(delta)
	if target and target.is_in_group("player") and _can_latch(target):
		latch(target)

func _can_latch(p: Node3D) -> bool:
	if _emp_t > 0.0 or hijacked or GameState.attack_grace_active():
		return false
	var head := p.global_position + Vector3.UP * 1.4
	if global_position.distance_to(head) > LATCH_RANGE:
		return false
	var d := p.get_node_or_null("Damageable") as Damageable
	return d == null or not d.invulnerable # dash i-frames slip it

## Clamp on behind the victim's head.
func latch(p: Node3D) -> void:
	if latched:
		return
	latched = true
	_victim = p
	_drain_acc = 0.0
	_beacon_t = 0.0
	add_to_group("leech_latched")
	collision_layer = 0
	# On the head the moment it latches, not one physics frame later (a probe
	# sampling between the two read it 1.31 m off, on CI only).
	_snap()
	GameState.teach_once("leech", TEACH_TEXT)
	if p.has_method("notify_pickup"):
		p.notify_pickup(tr("⚠ LEECH ON YOU: MELEE OR DASH"))
	if p.has_method("shake"):
		p.shake(0.3)
	AudioBus.play_synth_at("acid_spit", global_position, 0.0, 1.6)
	_beacon() # the first call home is the latch itself

## Onto the back of the victim's head.
func _snap() -> void:
	var cam := _victim.get_node_or_null("Head/Camera3D") as Node3D
	var anchor := cam if cam else _victim
	var base: Vector3 = anchor.global_position if cam else _victim.global_position + Vector3.UP * 1.6
	global_position = base + anchor.global_transform.basis * BACK_OFFSET
	velocity = Vector3.ZERO

func _ride(delta: float) -> void:
	if not is_instance_valid(_victim):
		_detach()
		return
	_snap()
	_drain_acc += DRAIN_DPS * delta
	if _drain_acc >= 1.0:
		var d := _victim.get_node_or_null("Damageable") as Damageable
		if d:
			d.apply_damage(floorf(_drain_acc), self)
		_drain_acc -= floorf(_drain_acc)
	_beacon_t += delta
	if _beacon_t >= BEACON_PERIOD:
		_beacon_t = 0.0
		_beacon()

## Phone home: every unaware robot in range learns where the player is.
func _beacon() -> void:
	beacons += 1
	for e in get_tree().get_nodes_in_group("enemy"):
		var r := e as EnemyBase
		if r == null or r == self or r.state == State.DEAD or r.hijacked:
			continue
		if r.global_position.distance_to(_victim.global_position) > BEACON_RANGE:
			continue
		if r.state != State.IDLE and r.state != State.PATROL:
			continue
		r.target = _victim
		r._last_known_target_pos = _victim.global_position
		r._has_last_known = true
		r.set_state(State.ALERT)
	AudioBus.play_synth_at("broadcast_blip", global_position, -2.0, 1.5)

func _detach() -> void:
	if not latched:
		return
	latched = false
	remove_from_group("leech_latched")
	collision_layer = _layer

## Melee: torn off and crushed.
func rip_off(by: Node) -> void:
	if not latched:
		return
	_detach()
	if hp:
		hp.apply_damage(9999.0, by)
	AudioBus.play_synth_at("impact_metal", global_position, 0.0, 1.4)

## Dash: flung off behind the dash, stunned for SHAKE_STUN.
func shake_off(dash_dir: Vector3) -> void:
	if not latched:
		return
	_detach()
	global_position -= dash_dir.normalized() * 1.2
	velocity = -dash_dir.normalized() * SHAKE_FLING + Vector3.UP * 2.0
	emp_disable(SHAKE_STUN)
