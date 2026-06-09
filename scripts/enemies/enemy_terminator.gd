class_name EnemyTerminator
extends EnemyBase
## Boss android built around an imported glTF model (CC-BY 4.0, "Modular Low-Poly
## Robot Character" by SagePeeker — see CREDITS.md). Heavily armored and fast,
## fires alternating dual-muzzle red beams. The model is a single static mesh
## (no rig), so animation is whole-body (stomp bob + lean + recoil) plus a
## pulsing red eye light. The model is auto-fit at runtime: scaled to
## `target_height` and stood on the floor regardless of its authored scale/pivot.

@export var hitscan_damage: float = 12.0
@export var burst_count: int = 6
@export var burst_interval: float = 0.08
@export var burst_spread_deg: float = 1.4
@export var tracer_scene: PackedScene
@export var muzzle_flash_scene: PackedScene
@export var target_height: float = 2.2   ## The model is scaled to this height (metres).
@export var model_yaw_deg: float = 180.0 ## Flip (0/180) if the model faces the wrong way.
@export var boss_name: String = "APEX ENDOFRAME" ## Shown on the HUD boss bar.

const ENTRANCE_FX := preload("res://scenes/fx/enemy_explosion.tscn")

@onready var _model: Node3D = $Model
@onready var _muzzle_l: Node3D = $MuzzleL
@onready var _muzzle_r: Node3D = $MuzzleR
@onready var _eye_glow: SpotLight3D = $EyeGlow

var _burst_remaining: int = 0
var _burst_timer: float = 0.0
var _fire_left_next: bool = false
var _walk_phase: float = 0.0
var _model_base_y: float = 0.0
var _entrance: float = 0.0

func _ready() -> void:
	super._ready()
	max_health = 700.0
	stagger_threshold = 220.0 # heavy boss: only big/sustained hits stagger it
	move_speed = 6.8
	turn_speed = 9.0
	sight_range = 40.0
	sight_angle_deg = 280.0 # relentless — sees you almost anywhere
	attack_range = 26.0
	preferred_range = 16.0
	attack_cooldown = 1.8
	score_value = 1000
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 6.0
	flinch_knockback = 0.4 # near-immune to stagger
	_fit_model()
	_model_base_y = _model.position.y if _model else 0.0
	# Dramatic entrance: brief invulnerable power-up while alarms blare.
	_entrance = 1.3
	hp.invulnerable = true
	_do_entrance.call_deferred()

func _do_entrance() -> void:
	GameState.announce_boss(self)
	AudioBus.play_synth_ui("eas_alert", -7.0)
	AudioBus.play_synth_at("explosion", global_position, 5.0, 0.65)
	AudioBus.play_synth_at("mech_step", global_position, 2.0, 0.9)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(1.0)
	var fx := ENTRANCE_FX.instantiate()
	get_tree().current_scene.add_child(fx)
	(fx as Node3D).global_position = global_position

## Scale the imported mesh to target_height and stand its feet at y=0, centred.
func _fit_model() -> void:
	if _model == null:
		return
	var mi := _find_mesh(_model)
	if mi == null:
		return
	_model.scale = Vector3.ONE
	_model.rotation = Vector3.ZERO
	_model.position = Vector3.ZERO
	# Mesh AABB expressed in _model's local space (walk up the node chain).
	var t := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != _model:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	var ab: AABB = t * mi.mesh.get_aabb()
	var h := ab.size.y
	if h > 0.001:
		var s := target_height / h
		_model.scale = Vector3(s, s, s)
		var c := ab.get_center()
		_model.position = Vector3(-c.x * s, -ab.position.y * s, -c.z * s)
	_model.rotation.y = deg_to_rad(model_yaw_deg)

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for c in node.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var rate := 4.5 + speed * 1.8
	_walk_phase += delta * rate
	var amp := clampf(speed / move_speed, 0.0, 1.0)
	# Heavy stomp: body dips per step + leans into movement; recoil leans it back.
	if _model:
		_model.position.y = _model_base_y - absf(sin(_walk_phase)) * amp * 0.08
		_model.rotation.x = amp * 0.06 - recoil * 0.12
		_model.rotation.y = deg_to_rad(model_yaw_deg)
	if _eye_glow:
		var flare := _entrance * 6.0 # eyes blaze brighter while powering up
		_eye_glow.light_energy = 4.0 + sin(_walk_phase * 2.5) * 1.5 + recoil * 6.0 + flare
	# Footstep booms on each footfall.
	if speed > 0.1 and is_on_floor():
		var fs := sin(_walk_phase)
		var last := sin(_walk_phase - delta * rate)
		if (fs > 0.0) != (last > 0.0):
			AudioBus.play_synth_at("mech_step", global_position, -2.0, randf_range(1.15, 1.3))

func _physics_process(delta: float) -> void:
	if _entrance > 0.0:
		# Stand and power up; can't be hurt or act yet.
		_entrance -= delta
		velocity.x = move_toward(velocity.x, 0.0, 2.0)
		velocity.z = move_toward(velocity.z, 0.0, 2.0)
		_apply_gravity(delta)
		move_and_slide()
		if _entrance <= 0.0:
			hp.invulnerable = false
		return
	super._physics_process(delta)
	if _burst_remaining > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_fire_one_shot()
			_burst_remaining -= 1
			_burst_timer = burst_interval

func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	_decelerate()
	if _attack_timer <= 0.0:
		_start_burst()
		_attack_timer = attack_interval()

func _start_burst() -> void:
	_burst_remaining = burst_count
	_burst_timer = 0.0

func _fire_one_shot() -> void:
	if target == null or _muzzle_l == null or _muzzle_r == null:
		return
	recoil = 1.0
	var active := _muzzle_l if _fire_left_next else _muzzle_r
	_fire_left_next = not _fire_left_next
	if muzzle_flash_scene:
		active.add_child(muzzle_flash_scene.instantiate())
	AudioBus.play_synth_at("drone_shot", active.global_position, -2.0, randf_range(0.85, 0.95))
	var origin := active.global_position
	var dir := (target.global_position + Vector3.UP * 0.7 - origin).normalized()
	# Inherent burst scatter + difficulty-driven inaccuracy.
	dir = scatter_aim(dir, burst_spread_deg)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 90.0)
	q.collision_mask = 0b0000011 # world + player
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var end_point := origin + dir * 90.0
	if not hit.is_empty():
		end_point = hit.position
		var col: Node = hit.collider
		var d: Node = col.get_node_or_null("Damageable") if col else null
		if d:
			d.apply_damage(hitscan_damage, self)
	if tracer_scene:
		var tr := tracer_scene.instantiate()
		get_tree().current_scene.add_child(tr)
		if tr.has_method("setup"):
			tr.setup(origin, end_point)

func _perform_attack() -> void:
	_start_burst()

func _on_died(source: Node) -> void:
	# Boss kill payoff: a camera kick + brief slow-mo before the base death.
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(1.0)
	GameState.hit_stop(0.3, 0.45)
	super._on_died(source)
