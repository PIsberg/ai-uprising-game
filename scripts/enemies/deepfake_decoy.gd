class_name DeepfakeDecoy
extends CharacterBody3D
## A DEEPFAKE's projected copy (see enemy_deepfake.gd). It wears its maker's
## model and materials, mirrors its movement, raises the gun and fires tracers
## whenever the real one does, and does no damage. One hit shatters it.
##
## Deliberately NOT in the "enemy" group: it never holds a kill_all exit shut,
## never pays score or loot, never counts for the AI Director, and radar and
## homing rounds see straight through it. Hits on it are not counted as player
## hits for accuracy (Damageable skips the "deepfake_decoy" group).
##
## The tell: a copy glitches every second or so (a sideways tear, a magenta
## flash, no shadow ever); the real one never does.

signal shattered

const GLITCH_COLOR := Color(1.0, 0.25, 0.85)

var maker: Node3D = null ## the EnemyDeepfake that projected it
var life: float = 14.0
var _target: Node3D = null
var _visual: Node3D = null
var _anim: AnimationPlayer = null
var _anim_walk := ""
var _anim_idle := ""
var _anim_attack := ""
var _muzzle_local := Vector3(0, 1.4, -0.8)
var _eye_light: OmniLight3D = null ## copy of the maker's EyeLight: without its floor glow the real one is obvious
var _tracer: PackedScene = null
var _flash_scene: PackedScene = null
var _glitch_cd := 0.8
var _glitch_t := 0.0
var _glitch_mat: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _burst_left := 0
var _burst_timer := 0.0
var _gone := false

## Builds the copy from the maker's visual (`visual`: its RobotModel root).
func setup(from: Node3D, visual: Node3D, muzzle_local: Vector3, tracer: PackedScene,
		flash: PackedScene) -> void:
	maker = from
	var eye := from.get_node_or_null("EyeLight") as OmniLight3D
	if eye:
		_eye_light = eye.duplicate() as OmniLight3D
		_eye_light.shadow_enabled = false
	_muzzle_local = muzzle_local
	_tracer = tracer
	_flash_scene = flash
	if visual is RobotModel:
		_anim_walk = (visual as RobotModel).anim_walk
		_anim_idle = (visual as RobotModel).anim_idle
		_anim_attack = (visual as RobotModel).anim_attack
	# Copy without the RobotModel script (it would look for an EnemyBase parent);
	# materials are shared, so the copy wears the maker's tint and damage blink.
	_visual = visual.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS) as Node3D
	_visual.set_script(null)
	_visual.transform = visual.transform

func _ready() -> void:
	add_to_group("deepfake_decoy")
	collision_layer = 4 # player fire masks world + enemy
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 1.9
	cs.shape = cap
	cs.position.y = 1.0
	add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1.0
	add_child(hp)
	hp.died.connect(func(_s: Node) -> void: shatter())
	if _visual:
		add_child(_visual)
		_anim = _visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
		for n in _visual.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_meshes.append(mi)
		for n in _visual.find_children("*", "OmniLight3D", true, false):
			(n as OmniLight3D).queue_free() # the damage-flare light; it never flares on a copy
	if _eye_light:
		add_child(_eye_light)
	_glitch_mat = StandardMaterial3D.new()
	_glitch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glitch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glitch_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glitch_mat.albedo_color = Color(GLITCH_COLOR, 0.7)
	_glitch_cd = randf_range(0.3, 1.0)
	_play(_anim_idle)

func set_target(t: Node3D) -> void:
	_target = t

func _physics_process(delta: float) -> void:
	if _gone:
		return
	life -= delta
	if life <= 0.0 or not is_instance_valid(maker):
		shatter(false)
		return
	_mirror_move(delta)
	_face(delta)
	_tick_glitch(delta)
	if _burst_left > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_fake_shot()
			_burst_left -= 1
			_burst_timer = 0.08

## Moves as the maker's reflection across the line from the target to the
## maker, so the three of them fan out and close in together.
func _mirror_move(delta: float) -> void:
	var v := Vector3.ZERO
	var src = maker.get("velocity")
	if src is Vector3:
		v = src
	if is_instance_valid(_target):
		var axis := maker.global_position - _target.global_position
		axis.y = 0.0
		if axis.length() > 0.1:
			var n := axis.normalized().cross(Vector3.UP) # normal of the mirror plane
			v = v - 2.0 * v.dot(n) * n
	velocity.x = v.x
	velocity.z = v.z
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	var flat := Vector2(velocity.x, velocity.z).length()
	_play(_anim_walk if flat > 0.8 else _anim_idle)

func _face(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	var to := _target.global_position - global_position
	to.y = 0.0
	if to.length() < 0.1:
		return
	var want := atan2(-to.x, -to.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(8.0 * delta, 0.0, 1.0))

func _tick_glitch(delta: float) -> void:
	if _glitch_t > 0.0:
		_glitch_t -= delta
		if _visual:
			_visual.position.x = randf_range(-0.18, 0.18)
		if _glitch_t <= 0.0:
			_set_overlay(null)
			if _visual:
				_visual.position.x = 0.0
		return
	_glitch_cd -= delta
	if _glitch_cd <= 0.0:
		_glitch_cd = randf_range(0.7, 1.5)
		_glitch_t = randf_range(0.07, 0.13)
		_set_overlay(_glitch_mat)

func _set_overlay(m: Material) -> void:
	for mi in _meshes:
		if is_instance_valid(mi):
			mi.material_overlay = m

func _play(anim_name: String) -> void:
	if _anim and anim_name != "" and _anim.has_animation(anim_name) \
			and _anim.current_animation != anim_name:
		_anim.play(anim_name, 0.2)

## Mirrors the maker's burst: the same count of tracers, aimed loosely at the
## target, hurting nothing.
func fake_burst(count: int) -> void:
	if _gone:
		return
	_burst_left = count
	_burst_timer = randf_range(0.0, 0.05)
	_play(_anim_attack)

func muzzle_position() -> Vector3:
	return global_transform * _muzzle_local

func _fake_shot() -> void:
	if not is_instance_valid(_target):
		return
	var origin := muzzle_position()
	var aim := (_target.global_position + Vector3.UP * 0.6 - origin).normalized()
	aim = aim.rotated(Vector3.UP, randf_range(-0.06, 0.06))
	var end := origin + aim * 60.0
	var q := PhysicsRayQueryParameters3D.create(origin, end)
	q.collision_mask = 0b0000011
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		end = hit.position
	AudioBus.play_synth_at("drone_shot", origin, -6.0, randf_range(1.05, 1.15))
	if _flash_scene:
		var f := _flash_scene.instantiate() as Node3D
		add_child(f)
		f.position = _muzzle_local
	if _tracer:
		var t := _tracer.instantiate()
		get_tree().current_scene.add_child(t)
		if t.has_method("setup"):
			t.setup(origin, end)

## Breaks the copy apart in a magenta glitch burst. `hit`: shot by the player
## (shows the FAKE tag); false when it times out or its maker dies.
func shatter(hit: bool = true) -> void:
	if _gone:
		return
	_gone = true
	collision_layer = 0
	shattered.emit()
	var at := global_position + Vector3.UP * 1.1
	var parent := get_parent()
	if parent:
		_burst(parent, at)
		if hit:
			var tag := Label3D.new()
			tag.text = "FAKE"
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.no_depth_test = true
			tag.font_size = 72
			tag.outline_size = 12
			tag.modulate = GLITCH_COLOR
			tag.pixel_size = 0.006
			parent.add_child(tag)
			tag.global_position = at + Vector3.UP * 0.6
			var tt := tag.create_tween()
			tt.tween_property(tag, "global_position:y", tag.global_position.y + 1.0, 0.8)
			tt.parallel().tween_property(tag, "modulate:a", 0.0, 0.8).set_delay(0.3)
			tt.tween_callback(tag.queue_free)
	AudioBus.play_synth_at("overlord_glitch", at, -4.0 if hit else -10.0, 1.6)
	_set_overlay(_glitch_mat)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.6, 0.05, 1.6), 0.12).set_trans(Tween.TRANS_EXPO)
	tw.tween_callback(queue_free)

static func _burst(parent: Node, at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 40
	p.lifetime = 0.55
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.45, 0.9, 0.45)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3.ZERO
	p.damping_min = 4.0
	p.damping_max = 6.0
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.05) # pixel shards, wider than tall
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = GLITCH_COLOR
	q.material = m
	p.mesh = q
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.2)
	tw.tween_callback(p.queue_free)
