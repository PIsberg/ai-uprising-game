class_name EnemyRollback
extends EnemyAndroid
## ROLLBACK - version control for the robot army. An unarmed white-and-cyan
## mech that hangs back behind its pack and keeps a checkpoint of every robot
## that dies within WATCH_RANGE of it. Every RESTORE_GAP seconds it plants
## itself, aims a rewind beam at the freshest checkpoint and channels for
## CHANNEL_TIME (a VHS rewind column over the spot, the timecode running back
## to the moment of death, a tape spooling backwards), then the robot is
## restored: a fresh copy of the same chassis rebuilds feet-first where it fell
## and rejoins the fight. RESTORES_MAX per ROLLBACK, once per robot, and a
## restored robot is worth RESTORED_SCORE of its score.
##
## The counters: kill the ROLLBACK first (pending checkpoints die with it);
## hurt it for INTERRUPT_DMG while it channels and the checkpoint is corrupted;
## or disintegrate the robot (gauss, Longshot, plasma, OMEGA) and there is no
## checkpoint to restore. Checkpoints expire after CHECKPOINT_TTL. Bosses and
## the self-replicating FORK BOMB are never checkpointed.
##
## Deaths are watched through each robot's hp.died (override-proof: several
## subclasses override _on_died without super), read while the emission is
## still running so the killing hit's KillFx tag is on. A checkpoint carries
## the scene, spot, facing and difficulty multipliers; the dead node itself
## sinks and frees as usual. Covered by tests/rollback_probe.

const WATCH_RANGE := 30.0
const WATCH_EVERY := 0.5
const CHECKPOINT_TTL := 14.0
const CHANNEL_TIME := 2.4
const INTERRUPT_DMG := 45.0
const RESTORES_MAX := 3
const RESTORE_GAP := 3.0 ## seconds between channels (and before the first)
const REBUILD_TIME := 0.9
const RESTORED_SCORE := 0.5
const TAPE := Color(0.35, 0.95, 1.0)
## Label heights on the 2.66 m mech (body_top_probe caps <think> at body top + 0.8).
const STATUS_H := 2.9
const THINK_H := 3.3
const CORRUPT := Color(1.0, 0.3, 0.35)
const VHS_SHADER := preload("res://shaders/vhs_rewind.gdshader")
## Robots that are never checkpointed besides bosses: the fork bomb already
## comes back as its own children.
const NEVER := ["res://scenes/enemies/forkbomb.tscn"]

var checkpoints: Array = [] ## [{scene, pos, yaw, mults, at_ms, parent}]
var restores_left := RESTORES_MAX
var channeling := false
var _cp := {} ## the checkpoint being restored
var _channel_t := 0.0
var _channel_dmg := 0.0
var _watch_t := 0.0
var _gap := RESTORE_GAP
var _watched := {} ## instance id -> true, robots whose hp.died it listens to
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _rewind: Node3D
var _timecode: Label3D
var _status: Label3D

func _ready() -> void:
	super._ready()
	max_health = 160.0
	move_speed = 4.6
	sight_range = 34.0
	attack_range = 30.0
	preferred_range = 20.0 # behind the pack it restores
	flank_chance = 0.35
	score_value = 300
	hp.max_health = max_health
	hp.current_health = max_health
	hp.damaged.connect(_on_hurt)
	hp.died.connect(func(_s: Node) -> void: _end_channel())
	_think_h = THINK_H
	_status = Label3D.new()
	_status.name = "RollbackStatus"
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.font_size = 34
	_status.pixel_size = 0.0045
	_status.outline_size = 8
	_status.outline_modulate = Color(0.0, 0.05, 0.08, 0.8)
	_status.modulate = TAPE * 1.8 # HDR: Label3D takes fog
	_status.text = ""
	add_child(_status)
	_status.position = Vector3.UP * STATUS_H

## No gun: it restores, it does not shoot.
func _start_burst() -> void:
	pass

func status_text() -> String:
	return _status.text if is_instance_valid(_status) else ""

## True for a robot whose death it can checkpoint.
static func can_checkpoint(e: Object) -> bool:
	if not is_instance_valid(e) or not (e is EnemyBase) or e is EnemyRollback:
		return false
	var eb := e as EnemyBase
	return eb.score_value < 1000 and not eb.hijacked and eb.scene_file_path != "" \
			and not (eb.scene_file_path in NEVER) and not eb.has_meta(&"restored")

func _physics_process(delta: float) -> void:
	if channeling:
		if state == State.DEAD:
			return
		if _emp_t > 0.0 or hijacked:
			fail_restore("SIGNAL LOST")
		else:
			_tick_channel(delta)
			return
	super._physics_process(delta)
	if state == State.DEAD:
		return
	_watch_t -= delta
	if _watch_t <= 0.0:
		_watch_t = WATCH_EVERY
		_watch()
	_gap -= delta
	if _gap <= 0.0 and restores_left > 0 and not hijacked and _emp_t <= 0.0 and state != State.STAGGER:
		var cp := pick_checkpoint()
		if not cp.is_empty():
			begin_restore(cp)

## Listens to the death of every robot within WATCH_RANGE it is not already
## watching.
func _watch() -> void:
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as EnemyBase
		if e == null or e == self or e.hp == null or e.state == State.DEAD:
			continue
		var id := e.get_instance_id()
		if _watched.has(id) or e.global_position.distance_to(global_position) > WATCH_RANGE:
			continue
		_watched[id] = true
		e.hp.died.connect(_on_watched_died.bind(e))

func _on_watched_died(_source: Node, e: EnemyBase) -> void:
	if state == State.DEAD or not can_checkpoint(e) or e.has_meta(&"checkpointed"):
		return
	e.set_meta(&"checkpointed", true) # one ROLLBACK per death, however many watch it
	if e.hp.kill_fx == KillFx.DISINTEGRATE:
		_float_tag(e.get_parent(), e.global_position + Vector3.UP * 1.6, "checkpoint deleted", TAPE)
		return
	checkpoints.append({
		"scene": e.scene_file_path, "pos": e.global_position, "yaw": e.rotation.y,
		"mults": [e._health_mult, e._speed_mult, e._cooldown_mult, e.reaction_time],
		"at_ms": Time.get_ticks_msec(), "parent": e.get_parent(),
	})

## The freshest checkpoint still inside its TTL and WATCH_RANGE ({} if none).
## Stale ones are dropped.
func pick_checkpoint() -> Dictionary:
	var now := Time.get_ticks_msec()
	checkpoints = checkpoints.filter(func(cp: Dictionary) -> bool:
		return now - int(cp["at_ms"]) <= int(CHECKPOINT_TTL * 1000.0) \
				and (cp["pos"] as Vector3).distance_to(global_position) <= WATCH_RANGE)
	return checkpoints.back() if not checkpoints.is_empty() else {}

## Plants itself and starts rewinding `cp`. False if it cannot right now.
func begin_restore(cp: Dictionary) -> bool:
	if channeling or state == State.DEAD or hijacked or _emp_t > 0.0 or restores_left <= 0:
		return false
	checkpoints.erase(cp)
	channeling = true
	_cp = cp
	_channel_t = 0.0
	_channel_dmg = 0.0
	_burst_remaining = 0
	velocity = Vector3.ZERO
	_face_spot()
	_status.text = "RESTORING  0%"
	_build_channel_fx()
	AudioBus.play_synth_at("tape_rewind", cp["pos"] + Vector3.UP, -2.0)
	_think("rollback")
	return true

func _tick_channel(delta: float) -> void:
	_channel_t += delta
	velocity = Vector3.ZERO
	_face_spot()
	var k := minf(_channel_t / CHANNEL_TIME, 1.0)
	_status.text = "RESTORING  %d%%" % int(k * 100.0)
	var since := float(int(_cp["at_ms"]) - Time.get_ticks_msec()) / 1000.0
	if is_instance_valid(_timecode):
		# The clock runs back from "now" to the second it died.
		var t := absf(since) * (1.0 - k)
		_timecode.text = "<< REWIND  -00:%05.2f" % t
	if is_instance_valid(_rewind):
		for mi in _rewind.find_children("*", "MeshInstance3D", false, false):
			(mi as MeshInstance3D).set_instance_shader_parameter("progress", k)
	if is_instance_valid(_beam_mat):
		_beam_mat.albedo_color.a = 0.55 + 0.45 * sin(_channel_t * 37.0)
	if k >= 1.0:
		_complete()

func _face_spot() -> void:
	var to: Vector3 = _cp.get("pos", global_position) - global_position
	to.y = 0.0
	if to.length() > 0.1:
		rotation.y = atan2(-to.x, -to.z)

func _on_hurt(amount: float, _source: Node) -> void:
	if not channeling:
		return
	_channel_dmg += amount
	if _channel_dmg >= INTERRUPT_DMG:
		fail_restore("CHECKPOINT CORRUPTED")

## The rewind breaks off; the checkpoint is gone.
func fail_restore(why: String) -> void:
	if not channeling:
		return
	var at: Vector3 = _cp["pos"]
	_end_channel()
	_float_tag(get_parent(), at + Vector3.UP * 1.6, why, CORRUPT)
	AudioBus.play_synth_at("overlord_glitch", at + Vector3.UP, -3.0, 0.7)

func _complete() -> void:
	var cp := _cp
	_end_channel()
	restores_left -= 1
	restore(cp)

func _end_channel() -> void:
	channeling = false
	_cp = {}
	_gap = RESTORE_GAP
	if is_instance_valid(_status):
		_status.text = ""
	for n in [_beam, _rewind]:
		if is_instance_valid(n):
			n.queue_free()
	_beam = null
	_beam_mat = null
	_rewind = null
	_timecode = null

## Brings `cp` back: a fresh copy of the chassis at the spot, on the same
## difficulty multipliers, worth RESTORED_SCORE, rebuilt feet-first over
## REBUILD_TIME and then hunting. Returns it (null if the scene will not load).
func restore(cp: Dictionary) -> EnemyBase:
	var parent: Node = cp["parent"] if is_instance_valid(cp.get("parent")) else get_parent()
	var scene := load(String(cp["scene"])) as PackedScene
	if parent == null or scene == null:
		return null
	var e := scene.instantiate() as EnemyBase
	if e == null:
		return null
	var m: Array = cp["mults"]
	e._health_mult = m[0]
	e._speed_mult = m[1]
	e._cooldown_mult = m[2]
	e.reaction_time = m[3]
	e.set_meta(&"restored", true)
	parent.add_child(e)
	e.global_position = cp["pos"]
	e.rotation.y = cp["yaw"]
	e.score_value = int(e.score_value * RESTORED_SCORE)
	_rebuild(e, _find_player())
	_float_tag(parent, e.global_position + Vector3.UP * 2.2, "RESTORED FROM CHECKPOINT", TAPE)
	return e

## Off the enemy layer and inert while the chassis rebuilds bottom-up behind a
## cyan edge (the disintegration shader run backwards), then whole and hunting.
static func _rebuild(e: EnemyBase, hunt: Node3D) -> void:
	var layer := e.collision_layer
	e.collision_layer = 0
	e.set_physics_process(false)
	var rec := KillFx.swap_to_dissolve(e._visual_root if e._visual_root else e, TAPE, 0.8, 5.0, false)
	var top := RobotModel.body_top(e, e._mesh_instances)
	KillFx.set_dissolve(rec, 1.0, Vector2(e.global_position.y - 0.1, e.global_position.y + top + 0.2))
	var tw := e.create_tween()
	tw.tween_method(func(v: float) -> void: KillFx.set_dissolve(rec, v), 1.0, 0.0, REBUILD_TIME)
	tw.tween_callback(func() -> void:
		KillFx.restore_dissolve(rec)
		if e.state == State.DEAD:
			return
		e.collision_layer = layer
		e.set_physics_process(true)
		if is_instance_valid(hunt):
			e.target = hunt
			e.set_state(State.CHASE)
		e._think("restored"))
	KillFx._flash(e.get_parent(), e.global_position + Vector3.UP * 1.0, TAPE, 3.0, REBUILD_TIME)

## The beam from its chest to the spot, and the rewind column over the spot:
## VHS scanlines, particles streaming IN (debris un-scattering), a timecode.
func _build_channel_fx() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var spot: Vector3 = _cp["pos"]
	var a := global_position + Vector3.UP * 1.7
	var b := spot + Vector3.UP * 1.0
	_beam = MeshInstance3D.new()
	_beam.name = "RollbackBeam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = maxf(a.distance_to(b), 0.1)
	cyl.radial_segments = 6
	cyl.rings = 1
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.albedo_color = Color(TAPE * 2.2, 1.0)
	cyl.material = _beam_mat
	_beam.mesh = cyl
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(_beam)
	_beam.global_transform = Landmark._strut_xform(a, b)

	_rewind = Node3D.new()
	_rewind.name = "RollbackRewind"
	parent.add_child(_rewind)
	_rewind.global_position = spot
	var col := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 1.0
	tube.bottom_radius = 1.1
	tube.height = 2.8
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 20
	var sm := ShaderMaterial.new()
	sm.shader = VHS_SHADER
	sm.set_shader_parameter("tint", TAPE)
	tube.material = sm
	col.mesh = tube
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rewind.add_child(col)
	col.position = Vector3.UP * 1.4

	var p := CPUParticles3D.new()
	p.amount = 30 if GraphicsSettings.is_low() else 80
	p.lifetime = 0.6
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = 2.2
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.radial_accel_min = -10.0 # pulled IN: the scatter running backwards
	p.radial_accel_max = -7.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(TAPE, 0.0))
	fade.add_point(0.3, Color(1.0, 1.0, 1.0, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(TAPE, 0.0))
	p.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.vertex_color_use_as_albedo = true
	q.material = qm
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rewind.add_child(p)
	p.position = Vector3.UP * 1.1
	p.emitting = true

	var glow := OmniLight3D.new()
	glow.light_color = TAPE
	glow.light_energy = 1.6
	glow.omni_range = 5.0
	_rewind.add_child(glow)
	glow.position = Vector3.UP * 1.2

	_timecode = Label3D.new()
	_timecode.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_timecode.font_size = 44
	_timecode.pixel_size = 0.005
	_timecode.outline_size = 10
	_timecode.outline_modulate = Color(0.0, 0.04, 0.06, 0.85)
	_timecode.modulate = TAPE * 1.8
	_rewind.add_child(_timecode)
	_timecode.position = Vector3.UP * 3.1

static func _float_tag(parent: Node, at: Vector3, text: String, col: Color) -> void:
	if parent == null:
		return
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 48
	l.outline_size = 10
	l.pixel_size = 0.005
	l.modulate = col * 1.6
	parent.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "global_position:y", at.y + 0.9, 1.1)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.4)
	tw.tween_callback(l.queue_free)
