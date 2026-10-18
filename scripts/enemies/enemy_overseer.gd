class_name EnemyOverseer
extends EnemyBase
## A hovering gunship boss. It floats above the arena, tracks the player, and
## rakes them with escalating projectile volleys; wounded, it fires faster and
## starts vomiting kamikaze Seekers. Three phases keyed to health. Uses the HUD
## boss bar. Visuals are a giant imported EyeDrone ($Model in the scene).

@export var fly_height: float = 6.5
@export var proj_speed: float = 40.0
@export var proj_damage: float = 13.0

@export_group("Rocket Barrage")
## Signature gunship weapon: on a cooldown the OVERSEER rears up and salvos a fan
## of arcing rockets that rain down AROUND the player — a bombing run you have to
## keep moving through, distinct from the direct bolt spray. Denser the more it's
## wounded. The EyeDrone rig acts it out: Charging through the BARRAGE_WINDUP tell
## while it rears nose-up, Attack on each salvo and volley, a BackFlip as it
## enters each new phase. Killed, it crashes: it drops out of the sky spinning,
## shedding fire, and blows apart where it hits (_tick_crash).
@export var barrage_cooldown: float = 8.5
@export var barrage_rockets: int = 6
@export var barrage_spread: float = 6.5
@export var barrage_damage: float = 30.0
var _barrage_cd: float = 4.5
@export var preview: bool = false ## Codex/briefing showcase: hover idle, skip the portal arrival (BossPortal swirl), boss bar + AI.
@export var boss_name: String = "OVERSEER" ## Shown on the HUD boss bar (it read "BOSS" until 2026-10-18: none was set).
@export var boss_epithet: String = "SKYHOLD COMMAND GUNSHIP" ## Under the name on the intro card (BossPresence).

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")
const SEEKER := preload("res://scenes/enemies/seeker.tscn")
const MUZZLES := [
	Vector3(1.3, -0.1, 0.6), Vector3(-1.3, -0.1, 0.6),
	Vector3(0.7, -0.2, 1.1), Vector3(-0.7, -0.2, 1.1),
]

var _summon_cd: float = 0.0
var _arriving: bool = false
var _hover_t: float = 0.0   ## drives the idle vertical hover bob
const BARRAGE_WINDUP := 0.7 ## Charging tell before the rocket barrage fires (s).
const REAR_PITCH := 0.35    ## Nose-up rear through that tell (rad).
const CRASH_GRAVITY := 16.0
const CRASH_TIME := 3.5     ## Longest the wreck falls before it blows anyway (s).
var _barrage_windup := 0.0
var _rear := 0.0
var _last_phase := 1
var _crashing := false
var _crash_t := 0.0
var _crash_vy := 0.0
var _crash_floor := 0.0
var _crash_puff := 0.0

@onready var _eye_light: OmniLight3D = $EyeLight

func _ready() -> void:
	super._ready()
	max_health = 1500.0
	stagger_threshold = 100000.0
	move_speed = 4.0
	turn_speed = 2.4
	sight_range = 90.0
	sight_angle_deg = 320.0
	attack_range = 64.0
	preferred_range = 30.0
	attack_cooldown = 1.7
	score_value = 2500
	head_radius = 0.5
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 4.0
	flinch_knockback = 0.0
	# Codex/briefing: hover idle — skip the portal arrival (which spawns a swirling
	# BossPortal into the scene that would litter/stick in the viewer) + AI.
	if preview:
		hp.invulnerable = true
		set_physics_process(false)
		return
	# Hold the AI until the gate-arrival cinematic finishes.
	_arriving = true
	hp.invulnerable = true
	set_physics_process(false)
	_arrive.call_deferred()

## Portal arrival: a gate blinks open at flight height, the gunship slides out
## of it into the arena, then the gate collapses behind it.
func _arrive() -> void:
	GameState.announce_boss(self)
	AudioBus.play_synth_ui("eas_alert", -6.0)
	var scene := get_tree().current_scene
	if scene == null:
		_finish_arrival()
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var entry := Vector3(global_position.x, global_position.y + fly_height, global_position.z)

	var portal := BossPortal.new()
	portal.radius = 5.0
	portal.color = Color(0.5, 0.8, 1.0)
	scene.add_child(portal)
	portal.global_position = entry
	if p:
		portal.face(p.global_position)
	AudioBus.play_synth_at("explosion", entry, 4.0, 0.75) # gate whoomp
	if p and p.has_method("shake"):
		p.shake(0.9)
	portal.open(0.55)

	# Park the (hidden) gunship just inside the gate, then slide it out toward
	# the arena as the portal finishes opening.
	visible = false
	var out_dir := Vector3.FORWARD
	if p:
		var to := Vector3(p.global_position.x - entry.x, 0.0, p.global_position.z - entry.z)
		if to.length() > 0.1:
			out_dir = to.normalized()
	global_position = entry - out_dir * 2.0
	await get_tree().create_timer(0.45).timeout
	visible = true
	AudioBus.play_synth_at("drone_shot", entry, 0.0, 0.5)
	var emerge := entry + out_dir * 4.0
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", emerge, 0.7)
	await get_tree().create_timer(0.75).timeout
	portal.close(0.5)
	await get_tree().create_timer(0.45).timeout
	_finish_arrival()

func _finish_arrival() -> void:
	if hp:
		hp.invulnerable = false
	_arriving = false
	set_physics_process(true)

func _phase() -> int:
	return boss_phase()

func boss_phase_marks() -> Array:
	return [0.66, 0.33]

func _apply_gravity(_delta: float) -> void:
	pass

func _move_toward(dest: Vector3, delta: float) -> void:
	var flat := Vector3(dest.x - global_position.x, 0.0, dest.z - global_position.z)
	if flat.length() > 0.05:
		var d := flat.normalized()
		velocity.x = move_toward(velocity.x, d.x * move_speed, 8.0 * delta)
		velocity.z = move_toward(velocity.z, d.z * move_speed, 8.0 * delta)
	# Altitude (velocity.y) is owned by the hover servo in _physics_process so the
	# gunship floats with the same idle bob whether it's repositioning or holding.

## Hover servo: always pulls the gunship toward its flight altitude plus a slow
## vertical bob, so it bobs with life instead of holding a dead-still height when
## it strafes in place. Runs after the base AI/move so it's the sole y authority.
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state == State.DEAD or _arriving:
		return
	_hover_t += delta
	var base_y: float = (target.global_position.y if target else 0.0) + fly_height
	var goal := base_y + sin(_hover_t * 1.7) * 0.55   # gentle ±0.55 m float
	velocity.y = clampf((goal - global_position.y) * 3.5, -6.0, 6.0)
	_tick_barrage(delta)
	# Rear nose-up about the craft itself (it hangs fly_height above this body),
	# on top of the base's flinch/stagger pose of _visual_root.
	if _visual_root and _rear > 0.0:
		_visual_root.rotation.x += _rear
		_visual_root.position += Vector3(0.0, fly_height * (1.0 - cos(_rear)), -fly_height * sin(_rear))

func _process(delta: float) -> void:
	if _crashing:
		_tick_crash(delta)
		return
	if state == State.DEAD:
		return
	# Each new phase: a show-off flip.
	var ph := _phase()
	if ph != _last_phase:
		if ph > _last_phase:
			_play_clip("BackFlip")
		_last_phase = ph
	# The eye lamp burns hotter each phase and spikes with every volley.
	if _eye_light:
		_eye_light.light_energy = 3.0 + float(_phase()) * 1.5 + recoil * 6.0
	if _summon_cd > 0.0:
		_summon_cd -= delta
	if _barrage_cd > 0.0:
		_barrage_cd -= delta

## A spreading volley from several muzzles; heavier with each phase, and in the
## final phase it also spits out a Seeker. On its cooldown it instead unloads the
## signature ROCKET BARRAGE.
func _perform_attack() -> void:
	if target == null or _barrage_windup > 0.0:
		return
	recoil = 1.0
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _barrage_cd <= 0.0:
		_begin_barrage()
		return
	_play_clip("Attack")
	var phase := _phase()
	var shots := 2 + phase # 3 / 4 / 5 bolts
	for i in shots:
		var off: Vector3 = MUZZLES[i % MUZZLES.size()]
		var origin: Vector3 = global_transform * Vector3(off.x, off.y + fly_height, off.z)
		var proj := PROJECTILE.instantiate()
		scene.add_child(proj)
		(proj as Node3D).global_position = origin
		var dir := (target.global_position + Vector3.UP * 0.6 - origin).normalized()
		dir = scatter_aim(dir, 3.0 + float(i) * 1.2)
		if proj.has_method("launch"):
			proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	_muzzle_flash()
	AudioBus.play_synth_at("drone_shot", global_position, -2.0, 0.8)
	if phase >= 3:
		_maybe_summon(scene)

## The barrage's tell: it charges (Charging clip, a rising whine, the eye
## flaring) and rears nose-up for BARRAGE_WINDUP, then _tick_barrage lets fly.
func _begin_barrage() -> void:
	_barrage_cd = maxf(4.5, barrage_cooldown - float(_phase() - 1) * 2.0)
	_barrage_windup = BARRAGE_WINDUP
	_play_clip("Charging", BARRAGE_WINDUP)
	AudioBus.play_synth_at("charge", global_position + Vector3.UP * fly_height, 0.0, 0.6)

## Barrage tell: rear up while it charges, then let fly. Ticked from
## _physics_process like every boss windup (an entrance freeze holds it too).
func _tick_barrage(delta: float) -> void:
	if _barrage_windup <= 0.0:
		_rear = move_toward(_rear, 0.0, delta * 2.5)
		return
	_barrage_windup -= delta
	_rear = minf(REAR_PITCH, REAR_PITCH * 1.4 * (1.0 - _barrage_windup / BARRAGE_WINDUP))
	if _barrage_windup <= 0.0:
		var scene := get_tree().current_scene
		if scene and target != null and is_instance_valid(target):
			_barrage(scene)

## Plays an EyeDrone clip once and holds the idle off it (over `seconds` if given).
func _play_clip(clip: String, seconds: float = 0.0) -> void:
	var model := get_node_or_null("Model") as RobotModel
	if model == null:
		return
	if seconds > 0.0:
		model.play_oneshot_over(clip, seconds)
	else:
		model.play_oneshot(clip)

## Rocket barrage: a ring of arcing rockets lobbed to land AROUND the player,
## staggered so the impacts walk across the ground — keep moving or get carpeted.
func _barrage(scene: Node) -> void:
	recoil = 1.0
	_play_clip("Attack")
	var n := barrage_rockets + _phase() # 7 / 8 / 9 rockets
	var base_ang := randf() * TAU
	for i in n:
		var ang := base_ang + TAU * float(i) / float(n)
		var r := barrage_spread * sqrt(randf()) # bias toward the centre on the player
		var land: Vector3 = target.global_position + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var origin := global_position + Vector3(randf_range(-1.2, 1.2), fly_height - 0.5, randf_range(-1.2, 1.2))
		EnemyBomb.lob_at(scene, origin, land, 0.95 + float(i) * 0.07, barrage_damage)
	_muzzle_flash()
	AudioBus.play_synth_at("plasma_fire", global_position, 1.0, 0.55)
	AudioBus.play_synth_at("grenade_throw", global_position, -2.0, 0.7)

func _maybe_summon(scene: Node) -> void:
	if _summon_cd > 0.0:
		return
	_summon_cd = 7.0
	var s := SEEKER.instantiate()
	scene.add_child(s)
	(s as Node3D).global_position = global_position + Vector3(randf_range(-3, 3), fly_height - 1.5, randf_range(-3, 3))
	AudioBus.play_synth_at("broadcast_blip", global_position, -2.0, 0.7)

func _on_died(source: Node) -> void:
	set_state(State.DEAD)
	GameState.add_kill(score_value, _kill_label())
	GameState.hit_stop(0.35, 0.5)
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	_barrage_windup = 0.0
	var scene := get_tree().current_scene
	if scene:
		for i in 3:
			var fx := EXPLOSION.instantiate()
			scene.add_child(fx)
			(fx as Node3D).global_position = global_position + Vector3(randf_range(-2, 2), fly_height + randf_range(-1, 2), randf_range(-2, 2))
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(1.0)
	_play_clip("Hit")
	# Crash: find the deck under the craft, then fall to it (_tick_crash).
	var craft := global_position + Vector3.UP * fly_height
	_crash_floor = craft.y - 30.0
	var q := PhysicsRayQueryParameters3D.create(craft, craft + Vector3.DOWN * 80.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_crash_floor = (hit.position as Vector3).y
	_crashing = true

## The wreck drops out of the sky, spinning and rolling, shedding fire, and
## blows apart where it hits (or after CRASH_TIME, over a pit).
func _tick_crash(delta: float) -> void:
	_crash_t += delta
	_crash_vy += CRASH_GRAVITY * delta
	global_position.y -= _crash_vy * delta
	rotation.y += delta * (2.5 + _crash_t * 2.0)
	if _visual_root:
		_visual_root.rotation.z = minf(_crash_t * 0.6, 0.9)
	var craft := global_position + Vector3.UP * fly_height
	var scene := get_tree().current_scene
	_crash_puff -= delta
	if _crash_puff <= 0.0 and scene:
		_crash_puff = 0.28
		var fx := EXPLOSION.instantiate()
		scene.add_child(fx)
		(fx as Node3D).global_position = craft + Vector3(randf_range(-1.5, 1.5), randf_range(-1, 1), randf_range(-1.5, 1.5))
	if craft.y - 1.5 > _crash_floor and _crash_t < CRASH_TIME:
		return
	_crashing = false
	if scene:
		for i in 5:
			var fx := EXPLOSION.instantiate()
			scene.add_child(fx)
			(fx as Node3D).global_position = Vector3(craft.x, _crash_floor + 0.5, craft.z) + Vector3(randf_range(-3, 3), randf_range(0, 2), randf_range(-3, 3))
	spawn_shockwave_ring(9.0, Color(1.0, 0.5, 0.2), Vector3(craft.x, _crash_floor, craft.z))
	AudioBus.play_synth_at("explosion", craft, 6.0, 0.45)
	var p2 := get_tree().get_first_node_in_group("player")
	if p2 and p2.has_method("shake") and (p2 as Node3D).global_position.distance_to(craft) < 40.0:
		p2.shake(1.5)
	queue_free()
