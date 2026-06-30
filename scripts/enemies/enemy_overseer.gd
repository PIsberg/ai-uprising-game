class_name EnemyOverseer
extends EnemyBase
## A hovering gunship boss. It floats above the arena, tracks the player, and
## rakes them with escalating projectile volleys; wounded, it fires faster and
## starts vomiting kamikaze Seekers. Three phases keyed to health. Uses the HUD
## boss bar. Visuals are a giant imported EyeDrone ($Model in the scene).

@export var fly_height: float = 6.5
@export var proj_speed: float = 40.0
@export var proj_damage: float = 13.0
@export var preview: bool = false ## Codex/briefing showcase: hover idle, skip the portal arrival (BossPortal swirl), boss bar + AI.

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")
const SEEKER := preload("res://scenes/enemies/seeker.tscn")
const MUZZLES := [
	Vector3(1.3, -0.1, 0.6), Vector3(-1.3, -0.1, 0.6),
	Vector3(0.7, -0.2, 1.1), Vector3(-0.7, -0.2, 1.1),
]

var _summon_cd: float = 0.0
var _arriving: bool = false
var _hover_t: float = 0.0   ## drives the idle vertical hover bob

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
	head_radius = 1.0
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
	if hp == null or hp.max_health <= 0.0:
		return 1
	var frac := hp.current_health / hp.max_health
	if frac <= 0.33:
		return 3
	elif frac <= 0.66:
		return 2
	return 1

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

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	# The eye lamp burns hotter each phase and spikes with every volley.
	if _eye_light:
		_eye_light.light_energy = 3.0 + float(_phase()) * 1.5 + recoil * 6.0
	if _summon_cd > 0.0:
		_summon_cd -= delta

## A spreading volley from several muzzles; heavier with each phase, and in the
## final phase it also spits out a Seeker.
func _perform_attack() -> void:
	if target == null:
		return
	recoil = 1.0
	var scene := get_tree().current_scene
	if scene == null:
		return
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
	var scene := get_tree().current_scene
	if scene:
		for i in 6:
			var fx := EXPLOSION.instantiate()
			scene.add_child(fx)
			(fx as Node3D).global_position = global_position + Vector3(randf_range(-2, 2), fly_height + randf_range(-1, 2), randf_range(-2, 2))
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(1.5)
	queue_free()
