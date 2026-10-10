class_name EnemyDiffusion
extends EnemyAndroid
## DIFFUSION - a robot sampled out of noise. Every DIFFUSE_EVERY seconds in a
## fight it runs its own forward process: the chassis breaks up into static
## (NOISE_TIME), drifts as a cloud of pure noise to a flank around its target
## (CLOUD_TIME), and denoises back into a robot there over DENOISE_TIME, a
## hologram counting the steps. Noise has no body: from the first frame of the
## noising to the first frame of the denoising it is off the enemy layer and
## takes no damage at all. Half-formed it is fragile: HALF_FORMED_MULT damage
## until the last step, which is the window to punish.
##
## The look reuses the disintegration shader (KillFx._to_dissolve) in pure-noise
## mode (height_bias 0), run forwards to noise out and backwards to denoise; the
## robot's own materials are saved first and put back when it is whole, or when
## it dies half-formed. Flank points are snapped to the navmesh and must have
## floor, headroom, no hazard and a clear line to the target.
## A burst rifleman otherwise (the android's kit) on the armed bot chassis.
## Covered by tests/diffusion_probe.

enum Phase { NONE, NOISING, CLOUD, DENOISING }

const NOISE_TIME := 0.45
const CLOUD_TIME := 0.55
const DENOISE_TIME := 0.9
const DIFFUSE_EVERY := 5.5
const HALF_FORMED_MULT := 2.0
const STEPS := 50
const FLANK_DEG := 80.0
const NOISE_EDGE := Color(0.8, 0.45, 1.0)
const STATUS_H := 2.6
const THINK_H := 3.05

var phase: Phase = Phase.NONE
var cloud: CPUParticles3D ## the static cloud while it travels (lives in the level)
var _phase_t := 0.0
var _from := Vector3.ZERO
var _dest := Vector3.ZERO
var _diffuse_cd := DIFFUSE_EVERY * 0.7
var _saved_layer := 4
var _swap := {} ## KillFx.swap_to_dissolve record of the swapped meshes
var _status: Label3D

func _ready() -> void:
	super._ready()
	max_health = 170.0
	move_speed = 5.2
	sight_range = 34.0
	attack_range = 26.0
	preferred_range = 13.0
	attack_cooldown = 1.7
	hitscan_damage = 9.0
	score_value = 250
	hp.max_health = max_health
	hp.current_health = max_health
	_think_h = THINK_H
	_status = Label3D.new()
	_status.name = "DiffusionStatus"
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.font_size = 36
	_status.pixel_size = 0.0045
	_status.outline_size = 8
	_status.outline_modulate = Color(0.05, 0.0, 0.08, 0.8)
	_status.modulate = NOISE_EDGE * 1.8
	_status.text = ""
	add_child(_status)
	_status.position = Vector3.UP * STATUS_H

func is_intangible() -> bool:
	return phase == Phase.NOISING or phase == Phase.CLOUD

func status_text() -> String:
	return _status.text if is_instance_valid(_status) else ""

func modify_incoming_damage(amount: float, _source, _origin = null) -> float:
	if is_intangible():
		return 0.0
	if phase == Phase.DENOISING:
		return amount * HALF_FORMED_MULT
	return amount

func _physics_process(delta: float) -> void:
	if phase != Phase.NONE:
		if state != State.DEAD:
			_tick_phase(delta)
		return
	super._physics_process(delta)
	if state == State.DEAD or hijacked or _emp_t > 0.0:
		return
	if (state == State.ATTACK or state == State.CHASE) and is_instance_valid(target):
		_diffuse_cd -= delta
		if _diffuse_cd <= 0.0:
			var p := pick_destination(target.global_position)
			if p == Vector3.INF or not diffuse_to(p):
				_diffuse_cd = 1.2 # nowhere to go yet; look again shortly
			else:
				_diffuse_cd = DIFFUSE_EVERY * randf_range(0.85, 1.15)

## A flank point round `around` (the target): FLANK_DEG either way from where
## it stands now, at its preferred range, on floor, off hazards, with headroom
## and a clear line back to the target. Vector3.INF if none.
func pick_destination(around: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := global_position - around
	from.y = 0.0
	if from.length() < 0.5:
		from = Vector3.BACK
	var base := atan2(from.x, from.z)
	var r := clampf(preferred_range, 6.0, 16.0)
	var signs := [1.0, -1.0] if randf() < 0.5 else [-1.0, 1.0]
	for s in signs:
		for deg in [FLANK_DEG, FLANK_DEG * 0.6]:
			var ang: float = base + s * deg_to_rad(deg)
			var p := around + Vector3(sin(ang), 0.0, cos(ang)) * r
			var down := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 6.0, 1)
			var hit := space.intersect_ray(down)
			if hit.is_empty():
				continue
			p = hit.position
			var map := nav_agent.get_navigation_map()
			if map.is_valid() and not NavigationServer3D.map_get_regions(map).is_empty():
				var q := NavigationServer3D.map_get_closest_point(map, p)
				if q.distance_to(p) > 1.5:
					continue
				p = q
			if _pos_in_hazard(p):
				continue
			var shape := SphereShape3D.new()
			shape.radius = 0.45
			var sq := PhysicsShapeQueryParameters3D.new()
			sq.shape = shape
			sq.transform = Transform3D(Basis(), p + Vector3.UP * 1.1)
			sq.collision_mask = 1
			if not space.intersect_shape(sq, 1).is_empty():
				continue
			var los := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, around + Vector3.UP * 1.2, 1)
			if not space.intersect_ray(los).is_empty():
				continue
			return p
	return Vector3.INF

## Noise out here and denoise at `dest`. False if it is already diffusing or
## cannot (dead, scrambled, converted).
func diffuse_to(dest: Vector3) -> bool:
	if phase != Phase.NONE or state == State.DEAD or hijacked or _emp_t > 0.0:
		return false
	if hp == null or not hp.is_alive():
		return false
	_from = global_position
	_dest = dest
	_burst_remaining = 0
	_telegraphing = false
	velocity = Vector3.ZERO
	_saved_layer = collision_layer
	collision_layer = 0
	# A hit flash in flight would be saved as the overlay and restored later.
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_clear_hit_flash()
	_to_noise()
	_set_noise(0.0)
	phase = Phase.NOISING
	_phase_t = 0.0
	AudioBus.play_synth_at("overlord_glitch", global_position + Vector3.UP, -3.0, 1.25)
	_think("diffuse")
	return true

func _tick_phase(delta: float) -> void:
	_phase_t += delta
	match phase:
		Phase.NOISING:
			var k := minf(_phase_t / NOISE_TIME, 1.0)
			_set_noise(k)
			_status.text = "ADDING NOISE  t=%d" % int(k * 1000.0)
			if k >= 1.0:
				phase = Phase.CLOUD
				_phase_t = 0.0
				visible = false
				_spawn_cloud()
		Phase.CLOUD:
			var k := minf(_phase_t / CLOUD_TIME, 1.0)
			if is_instance_valid(cloud):
				cloud.global_position = _from.lerp(_dest, smoothstep(0.0, 1.0, k)) + Vector3.UP * 1.0
			if k >= 1.0:
				global_position = _dest
				velocity = Vector3.ZERO
				if is_instance_valid(target):
					var to := target.global_position - global_position
					to.y = 0.0
					if to.length() > 0.1:
						rotation.y = atan2(-to.x, -to.z)
				visible = true
				collision_layer = _saved_layer
				phase = Phase.DENOISING
				_phase_t = 0.0
				_set_noise(1.0)
				if is_instance_valid(cloud):
					cloud.emitting = false
				AudioBus.play_synth_at("charge", global_position + Vector3.UP, -4.0, 1.5)
		Phase.DENOISING:
			var k := minf(_phase_t / DENOISE_TIME, 1.0)
			_set_noise(1.0 - k)
			_status.text = "DENOISING  step %d/%d" % [int(k * STEPS), STEPS]
			if k >= 1.0:
				_formed()

func _formed() -> void:
	phase = Phase.NONE
	_restore()
	_status.text = ""
	_attack_timer = minf(_attack_timer, 0.3) # sampled straight into a shot
	if is_instance_valid(target):
		set_state(State.ATTACK)

## Every visible chassis surface onto the dissolve shader in pure-noise mode;
## the originals are kept for _restore. Additive glows just hide.
func _to_noise() -> void:
	_swap = KillFx.swap_to_dissolve(_visual_root if _visual_root else self, NOISE_EDGE, 0.0, 9.0)

func _set_noise(v: float) -> void:
	KillFx.set_dissolve(_swap, v)

func _restore() -> void:
	KillFx.restore_dissolve(_swap)

## The hit flash is a full-silhouette overlay: it would paint over the holes.
func _play_hit_flash() -> void:
	if phase == Phase.NONE:
		super._play_hit_flash()

func _on_died(source: Node) -> void:
	if phase != Phase.NONE:
		phase = Phase.NONE
		_restore()
		visible = true
		if is_instance_valid(cloud):
			cloud.emitting = false
	if is_instance_valid(_status):
		_status.hide()
	super._on_died(source)

## Static: grey speckle with a few chroma flecks, trailing behind as it moves.
func _spawn_cloud() -> void:
	var parent := get_parent()
	if parent == null:
		return
	cloud = CPUParticles3D.new()
	cloud.name = "DiffusionNoise"
	cloud.amount = 60 if GraphicsSettings.is_low() else 180
	cloud.lifetime = 0.6
	cloud.local_coords = false
	cloud.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	cloud.emission_box_extents = Vector3(0.45, 0.95, 0.45)
	cloud.direction = Vector3.UP
	cloud.spread = 180.0
	cloud.initial_velocity_min = 0.2
	cloud.initial_velocity_max = 0.9
	cloud.gravity = Vector3.ZERO
	cloud.scale_amount_min = 0.6
	cloud.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.08, 0.08, 0.1))
	ramp.add_point(0.45, Color(0.6, 0.6, 0.65))
	ramp.add_point(0.8, Color(0.95, 0.95, 1.0))
	ramp.add_point(0.88, Color(0.4, 1.0, 0.95))
	ramp.set_color(ramp.get_point_count() - 1, NOISE_EDGE)
	cloud.color_initial_ramp = ramp
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	cloud.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	q.material = m
	cloud.mesh = q
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := OmniLight3D.new()
	glow.light_color = NOISE_EDGE
	glow.light_energy = 1.2
	glow.omni_range = 4.0
	cloud.add_child(glow)
	parent.add_child(cloud)
	cloud.global_position = _from + Vector3.UP * 1.0
	cloud.emitting = true
	var tw := cloud.create_tween()
	tw.tween_interval(CLOUD_TIME + cloud.lifetime + 0.4)
	tw.tween_callback(cloud.queue_free)
