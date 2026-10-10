class_name EnemyAttention
extends EnemyDrone
## ATTENTION HEAD - "attention is all you need". A gold eye drone that does not
## shoot: it looks. Its gaze is a visible cone (HALF_ANGLE, RANGE) that swings
## after the player with a lag (FOCUS_RATE), so a sidestep or a dash breaks it.
## While the cone is on the player with a clear line:
##   - the player is attended (Attention): every robot's aim error shrinks;
##   - idle robots within ALERT_RADIUS wake onto the player, and engaged ones
##     are fed the player's position every FEED_EVERY s, through walls;
##   - it holds position and keeps looking.
## Unalerted, the cone sweeps the floor like a searchlight, and walking into
## it is how it finds you. EMP, hijack and death put the gaze out.
## Covered by tests/attention_probe.

const HALF_ANGLE := 9.0 ## degrees
const RANGE := 38.0
const FOCUS_RATE := 1.6 ## how fast the gaze swings after the player (lerp per second)
const ALERT_RADIUS := 40.0
const FEED_EVERY := 0.4
const IDLE_COLOR := Color(1.0, 0.78, 0.3)
const LOCK_COLOR := Color(1.0, 0.22, 0.12)
const CONE_SHADER := preload("res://shaders/gaze_cone.gdshader")

var locked := false ## the cone is on the player right now
var _focus := Vector3.INF
var _cone_dir := Vector3.FORWARD
var _los_t := 0.0
var _los_ok := false
var _len_t := 0.0
var _feed_t := 0.0
var _sweep := 0.0
var _cone_root: Node3D
var _cone_scale: Node3D
var _cone_mat: ShaderMaterial
var _spot: SpotLight3D

func _ready() -> void:
	super._ready()
	max_health = 110.0
	move_speed = 4.2
	sight_range = RANGE
	attack_range = RANGE * 0.8
	preferred_range = 16.0
	attack_cooldown = 99.0
	score_value = 220
	hover_height = 3.6
	hp.max_health = max_health
	hp.current_health = max_health
	_sweep = randf() * TAU
	_build_cone()
	hp.died.connect(func(_s: Node) -> void: _gaze_off())

## It looks; it does not shoot.
func _perform_attack() -> void:
	pass

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	gaze_tick(delta)

func cone_visible() -> bool:
	return is_instance_valid(_cone_root) and _cone_root.visible

## One frame of the gaze: aim the cone, test it against the player, attend.
func gaze_tick(delta: float) -> void:
	if hp == null or not hp.is_alive() or state == State.DEAD or _dying:
		return
	if _emp_t > 0.0 or hijacked:
		_cone_root.visible = false
		_set_locked(false)
		return
	_cone_root.visible = true
	var src := eye.global_position if eye else global_position
	var engaged := (state == State.ALERT or state == State.CHASE or state == State.ATTACK) \
			and is_instance_valid(target) and target.is_in_group("player")
	if engaged:
		var chest := target.global_position + Vector3.UP * 1.1
		if _focus == Vector3.INF:
			_focus = src + _cone_dir * 10.0
		_focus = _focus.lerp(chest, clampf(FOCUS_RATE * delta, 0.0, 1.0))
	else:
		# Searchlight: a slow pan either side of its facing, pitched at the floor.
		_sweep += delta * 0.45
		var fwd := (-global_basis.z).rotated(Vector3.UP, sin(_sweep) * deg_to_rad(55.0))
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		_focus = src + (fwd + Vector3.DOWN * 0.5).normalized() * 12.0
	if _focus.distance_to(src) > 0.01:
		_cone_dir = (_focus - src).normalized()
	_aim_cone(src, delta)

	var p := _find_player()
	if p == null:
		_set_locked(false)
		return
	var chest := p.global_position + Vector3.UP * 1.1
	var to := chest - src
	var in_cone := to.length() <= RANGE and rad_to_deg(_cone_dir.angle_to(to)) <= HALF_ANGLE
	if in_cone:
		_los_t -= delta
		if _los_t <= 0.0:
			_los_t = 0.1
			_los_ok = _clear_line(src, chest)
		in_cone = _los_ok
	_set_locked(in_cone)
	if not in_cone:
		return
	Attention.hold()
	if not engaged:
		target = p
		set_state(State.ALERT)
	_feed_t -= delta
	if _feed_t <= 0.0:
		_feed_t = FEED_EVERY
		_feed(p)

## Wakes the idle robots in range onto `p`, and tells the engaged ones where it is.
func _feed(p: Node3D) -> void:
	_alert_allies(ALERT_RADIUS, p)
	for e in get_tree().get_nodes_in_group("enemy"):
		var ally := e as EnemyBase
		if ally == null or ally == self or ally.state == State.DEAD or ally.hijacked:
			continue
		if ally.global_position.distance_to(global_position) > ALERT_RADIUS:
			continue
		ally._last_known_target_pos = p.global_position
		ally._has_last_known = true

func _clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _set_locked(v: bool) -> void:
	if v == locked:
		return
	locked = v
	var col := LOCK_COLOR if v else IDLE_COLOR
	_cone_mat.set_shader_parameter("color", col)
	_cone_mat.set_shader_parameter("intensity", 0.85 if v else 0.4)
	if _spot:
		_spot.light_color = col
		_spot.light_energy = 6.0 if v else 3.0
	if v:
		AudioBus.play_synth_at("broadcast_blip", global_position, -2.0, 0.7)
		GameState.teach_once("attention", "◆ ATTENTION HEAD — while its gaze is on you, every robot near it knows where you are and aims truer. Sidestep the cone, break line of sight, or shoot the eye.")
		_think("alert")

func _gaze_off() -> void:
	_set_locked(false)
	Attention.until_ms = 0
	if is_instance_valid(_cone_root):
		_cone_root.visible = false

## The cone runs from the eye along _cone_dir, cut at the first wall.
func _aim_cone(src: Vector3, delta: float) -> void:
	_cone_root.global_position = src
	var up := Vector3.UP if absf(_cone_dir.y) < 0.98 else Vector3.FORWARD
	_cone_root.global_basis = Basis.looking_at(_cone_dir, up)
	_len_t -= delta
	if _len_t <= 0.0:
		_len_t = 0.1
		var q := PhysicsRayQueryParameters3D.create(src, src + _cone_dir * RANGE, 1)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var length := src.distance_to(hit.position) if hit else RANGE
		_cone_scale.scale = Vector3.ONE * maxf(length, 0.5)

func _build_cone() -> void:
	_cone_root = Node3D.new()
	_cone_root.name = "Gaze"
	_cone_root.top_level = true # the drone banks and bobs; its gaze holds steady
	add_child(_cone_root)
	_cone_scale = Node3D.new()
	_cone_root.add_child(_cone_scale)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = tan(deg_to_rad(HALF_ANGLE)) # far end, at unit length
	cm.bottom_radius = 0.015
	cm.height = 1.0
	cm.radial_segments = 20
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	_cone_mat = ShaderMaterial.new()
	_cone_mat.shader = CONE_SHADER
	_cone_mat.set_shader_parameter("color", IDLE_COLOR)
	_cone_mat.set_shader_parameter("intensity", 0.4)
	cm.material = _cone_mat
	mi.mesh = cm
	mi.rotation.x = -PI * 0.5 # the cylinder's +Y (its wide top) points down local -Z
	mi.position.z = -0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cone_scale.add_child(mi)
	if not GraphicsSettings.is_low():
		_spot = SpotLight3D.new()
		_spot.light_color = IDLE_COLOR
		_spot.light_energy = 3.0
		_spot.spot_range = RANGE
		_spot.spot_angle = HALF_ANGLE * 1.3
		_spot.shadow_enabled = false
		_cone_root.add_child(_spot)
	_cone_dir = -global_basis.z
