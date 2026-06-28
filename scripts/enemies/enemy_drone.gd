class_name EnemyDrone
extends EnemyBase

@export var hover_height: float = 2.5
@export var hover_amplitude: float = 0.3
@export var hover_freq: float = 2.0
@export var strafe_speed: float = 2.5

@export_group("Attack")
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 35.0
@export var projectile_damage: float = 10.0

var _hover_phase: float = 0.0
var _strafe_dir: float = 1.0
var _strafe_change_timer: float = 0.0
var _diving: bool = false
var _dive_timer: float = 2.0
var _dive_time: float = 0.0
var _hum_player: AudioStreamPlayer3D
var _dying: bool = false        ## True while plummeting after death.
var _fall_time: float = 0.0


@onready var _eye_light: OmniLight3D = $Eye/EyeLight

func _ready() -> void:
	super._ready()
	max_health = 40.0
	move_speed = 6.6
	sight_range = 38.0
	attack_range = 20.0
	preferred_range = 11.0
	attack_cooldown = 0.45
	score_value = 75
	hp.max_health = max_health
	hp.current_health = max_health
	_hover_phase = randf() * TAU
	_setup_hum()
	_make_exhaust()

## A faint world-space thruster trail that streaks behind the drone as it swoops.
func _make_exhaust() -> void:
	var p := CPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.5
	p.local_coords = false
	p.direction = Vector3(0, -1, 0)
	p.spread = 18.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.gravity = Vector3.ZERO
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0)); curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.scale_amount_min = 0.5; p.scale_amount_max = 0.9
	var mesh := SphereMesh.new()
	mesh.radius = 0.05; mesh.height = 0.1; mesh.radial_segments = 6; mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.5, 0.3, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.2)
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	p.mesh = mesh
	add_child(p)
	p.position = Vector3(0, -0.15, 0)


func _process(_delta: float) -> void:
	if state == State.DEAD:
		return
	if _eye_light:
		# Steady throb, plus a bright spike from firing recoil.
		_eye_light.light_energy = 0.8 + sin(_hover_phase * 3.0) * 0.4 + recoil * 1.5


func _setup_hum() -> void:
	_hum_player = AudioStreamPlayer3D.new()
	_hum_player.stream = AudioBus.synth("drone_hum")
	_hum_player.volume_db = -10.0
	_hum_player.unit_size = 4.0
	_hum_player.max_distance = 35.0
	_hum_player.pitch_scale = randf_range(0.92, 1.1)
	_hum_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_hum_player)
	if _hum_player.stream:
		_hum_player.play()

func _apply_gravity(_delta: float) -> void:
	pass # drones float

func _move_toward(dest: Vector3, delta: float) -> void:
	_hover_phase += delta * hover_freq
	var desired_y := dest.y + hover_height + sin(_hover_phase) * hover_amplitude
	if target:
		desired_y = target.global_position.y + hover_height + sin(_hover_phase) * hover_amplitude
	var to := dest - global_position
	to.y = 0
	var dir := to.normalized() if to.length() > 0.01 else Vector3.ZERO
	velocity.x = move_toward(velocity.x, dir.x * move_speed, 12.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * move_speed, 12.0 * delta)
	velocity.y = move_toward(velocity.y, (desired_y - global_position.y) * 4.0, 30.0 * delta)
	_face_dir(dir, delta * 0.8)

## Periodic diving swoop cycle: every few seconds, commit to an ~0.85s dive.
func _update_dive(delta: float) -> void:
	_dive_timer -= delta
	if not _diving and _dive_timer <= 0.0:
		_diving = true
		_dive_time = 0.85
		AudioBus.play_synth_at("drone_hum", global_position, 2.0, 1.6)
	if _diving:
		_dive_time -= delta
		if _dive_time <= 0.0:
			_diving = false
			_dive_timer = randf_range(2.5, 4.5)

func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	_strafe_change_timer -= delta
	if _strafe_change_timer <= 0.0:
		_strafe_change_timer = randf_range(1.0, 2.5)
		_strafe_dir = -_strafe_dir
	_update_dive(delta)
	# Strafe + maintain preferred range (or bear straight in while diving)
	var to_target := target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()
	var forward_pull: float = 0.0
	if dist > preferred_range * 1.1:
		forward_pull = 1.0
	elif dist < preferred_range * 0.85:
		forward_pull = -1.0
	var strafe := strafe_speed
	var fly_height := hover_height
	if _diving:
		forward_pull = 1.6           # commit to the rush
		strafe *= 0.3
		fly_height = 1.1             # swoop down to the player's level
	var right := to_target.normalized().cross(Vector3.UP)
	var rush := move_speed * (1.5 if _diving else 0.7)
	var move_dir := (right * _strafe_dir * strafe + to_target.normalized() * forward_pull * rush)
	velocity.x = move_toward(velocity.x, move_dir.x, 18.0 * delta)
	velocity.z = move_toward(velocity.z, move_dir.z, 18.0 * delta)
	_hover_phase += delta * hover_freq
	var desired_y := target.global_position.y + fly_height + sin(_hover_phase) * hover_amplitude
	velocity.y = move_toward(velocity.y, (desired_y - global_position.y) * 5.0, 30.0 * delta)
	if _attack_timer <= 0.0:
		_perform_attack()
		_attack_timer = attack_interval()

func _physics_process(delta: float) -> void:
	if _dying:
		_fall_dead(delta)
		return
	super._physics_process(delta)

## A killed drone loses lift and tumbles to the ground, then bursts on impact
## instead of tipping over in mid-air.
func _fall_dead(delta: float) -> void:
	velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	velocity.x = move_toward(velocity.x, 0.0, 5.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 5.0 * delta)
	# Erratic tumble as it plummets.
	rotation.x += delta * 5.5
	rotation.z += delta * 7.5
	move_and_slide()
	_fall_time += delta
	if is_on_floor() or _fall_time > 4.0:
		_explode_on_impact()

## Beefier flyer variants (e.g. fishbot) set this so they leave a supply drop
## like ground specials do — basic recon drones stay loot-free (they're plentiful).
## The drop is landed safely on a walkway by _drop_loot's hazard relocation.
@export var drops_loot: bool = false

func _on_died(_source: Node) -> void:
	if _dying:
		return
	_dying = true
	set_state(State.DEAD)
	GameState.add_kill(score_value, _kill_label())
	if drops_loot:
		_drop_loot()
	# Stop colliding with the player / shots, but keep hitting the world so it lands.
	collision_layer = 0
	collision_mask = 1
	if _hum_player and is_instance_valid(_hum_player):
		_hum_player.stop()
	# A dying lurch + a trailing smoke plume on the way down.
	velocity += Vector3(randf_range(-2.0, 2.0), 1.5, randf_range(-2.0, 2.0))
	if _damaged_emitter == null or not is_instance_valid(_damaged_emitter):
		_damaged_emitter = DAMAGED_FX.instantiate()
		add_child(_damaged_emitter)

func _explode_on_impact() -> void:
	if not _dying:
		return
	_dying = false
	var fx := EXPLOSION.instantiate()
	get_parent().add_child(fx)
	(fx as Node3D).global_position = global_position
	AudioBus.play_synth_at("explosion", global_position, 0.0, 1.1)
	queue_free()

func _perform_attack() -> void:
	if target == null or muzzle == null or projectile_scene == null:
		return
	recoil = 1.0
	_muzzle_flash()
	var proj := projectile_scene.instantiate()
	get_tree().current_scene.add_child(proj)
	proj.global_position = muzzle.global_position
	var dir := (target.global_position + Vector3.UP * 0.8 - muzzle.global_position).normalized()
	# Lead a tiny bit upward to compensate for player crouch
	dir = scatter_aim(dir) # difficulty-driven inaccuracy
	if proj.has_method("launch"):
		proj.launch(dir * projectile_speed, self, projectile_damage, 0.0, 0.0)
	AudioBus.play_synth_at("drone_shot", muzzle.global_position, -4.0, randf_range(0.95, 1.05))
