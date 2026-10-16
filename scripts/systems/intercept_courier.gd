class_name InterceptCourier
extends Node3D
# @lat: [[level-system#Intercept Courier]]
## An `intercept` task: a hostile robot grabs the data and RUNS. It follows
## the authored `route` leg by leg (EnemyBase.courier_goal: no perception, no
## attacks, a sideways weave) at `speed`, which beats the player's walk but not
## their sprint, so the chase is a stamina and aim problem rather than a timer.
##
## At the `uplink` it stops and UPLOADS for `upload_seconds` (an EMP pauses the
## upload as well as the run). A finished upload is a copy that escaped: the
## courier restarts at the route start at full health, `escaped` fires (the
## level spawns the task's `penalty` squad on it) and the task stays open.
## Killing it completes the task; a kill with no copy escaped also pays
## CLEAN_BONUS. Hijacking it completes the task too: the data is yours.
##
## This node stays at `pos` (the route start, and where the task probes judge
## the task); the robot is its sibling under the level.
##
## Adopt mode (the DATA LEAK skirmish event, GameState._event_data_leak): `adopt`
## is a robot already in the fight, `task_id` is empty (no checklist entry, no
## CLEAN bonus) and `restart_on_escape` is false, so a finished upload takes the
## courier off the map instead of restarting it. The caller pays out on `caught`.

signal escaped(copies: int)
## The courier went down (`killed`) or was hijacked, at `at`.
signal caught(killed: bool, at: Vector3)

const DEFAULT_SPEED := 7.4
const DEFAULT_UPLOAD := 10.0
const HEALTH_MULT := 3.0
const CLEAN_BONUS := 400
const UPLINK_RADIUS := 2.2
const COURIER_ACCENT := Color(1.0, 0.72, 0.18)
## The idle uplink beam has to read against a bright dusk sky from the far
## bank (0.12 was invisible from the bridge in tests/intercept_shot).
const BEAM_IDLE_ALPHA := 0.4

var task_id: String = "courier"
var base_label: String = "Run down the data courier"
var unit_scene: PackedScene
## Waypoints between `pos` and the uplink, in order.
var route: Array = []
var uplink: Vector3 = Vector3.ZERO
var upload_seconds: float = DEFAULT_UPLOAD
var speed: float = DEFAULT_SPEED
var health_mult: float = HEALTH_MULT
## A live robot to turn into the courier instead of spawning `unit_scene`.
var adopt: EnemyBase = null
## A finished upload restarts the run (task) or takes the courier away (event).
var restart_on_escape: bool = true
## Spawn toast and one-time hint (the event announces itself).
var announce: bool = true

var unit: EnemyBase
## Index of the waypoint it is running for; route.size() means the uplink.
var leg: int = 0
var uploading: bool = false
var upload_t: float = 0.0
var copies: int = 0
var done: bool = false
var _state_key: String = ""
var _pad: Node3D
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _t: float = 0.0

func _ready() -> void:
	_build_uplink()
	_spawn_unit.call_deferred()

func _accent_mat(energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = COURIER_ACCENT
	m.emission_enabled = true
	m.emission = COURIER_ACCENT
	m.emission_energy_multiplier = energy
	return m

## The uplink pad the courier is running for: an amber ring on the ground and a
## faint beam that brightens as the upload fills, so the player can read the
## destination (and the deadline) from across the map.
func _build_uplink() -> void:
	_pad = Node3D.new()
	_pad.name = "UplinkPad"
	add_child(_pad)
	_pad.global_position = uplink
	_ring_mat = _accent_mat(2.5)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = UPLINK_RADIUS - 0.15
	tm.outer_radius = UPLINK_RADIUS
	ring.mesh = tm
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3.UP * 0.08
	_pad.add_child(ring)
	_beam_mat = _accent_mat(2.0)
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.albedo_color.a = BEAM_IDLE_ALPHA
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 0.9
	cm.height = 40.0
	cm.radial_segments = 12
	_beam.mesh = cm
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3.UP * 20.0
	_pad.add_child(_beam)
	var tag := Label3D.new()
	tag.text = "UPLINK"
	tag.font_size = 64
	tag.pixel_size = 0.005
	tag.modulate = COURIER_ACCENT
	tag.outline_size = 10
	tag.outline_modulate = Color(0, 0, 0, 0.9)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 3.2, 0)
	_pad.add_child(tag)

func _spawn_unit() -> void:
	if not is_inside_tree():
		return
	if adopt != null:
		if not is_instance_valid(adopt) or adopt.state == EnemyBase.State.DEAD:
			done = true
			return
		unit = adopt
		unit.target = null
		unit.courier_speed = speed
		unit.courier_goal = _goal()
	else:
		if unit_scene == null:
			return
		unit = unit_scene.instantiate() as EnemyBase
		if unit == null:
			return
		# Stat scaling must ride _health_mult: subclasses hardcode stats in _ready
		# and _sync_stats applies the multiplier after them.
		unit._health_mult *= health_mult
		unit.courier_speed = speed
		unit.courier_goal = _goal()
		unit.position = position
		get_parent().add_child(unit)
	unit.add_to_group("objective") # the HUD waypoint follows the courier
	unit.add_to_group("intercept_courier")
	if unit.hp:
		unit.hp.died.connect(_on_unit_died)
	_dress(unit)
	if not announce:
		return
	GameState.teach_once("intercept", "DATA COURIER: it runs for the uplink and never fights back. Sprint, dash and shoot. An EMP stops it cold.")
	GameState.skirmish_event.emit("DATA COURIER RUNNING", "It has the data and it is running for the uplink. Run it down.")
	AudioBus.play_synth_at("overlord_glitch", unit.global_position, -2.0, 1.2)

## A glowing data core on its back plus a tag, so the runner reads as THE
## target in a crowd.
func _dress(u: EnemyBase) -> void:
	var core := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.34, 0.42, 0.22)
	core.mesh = bm
	core.material_override = _accent_mat(3.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.position = Vector3(0, 1.35, -0.32)
	u.add_child(core)
	var glow := OmniLight3D.new()
	glow.light_color = COURIER_ACCENT
	glow.light_energy = 1.4
	glow.omni_range = 4.0
	glow.position = Vector3(0, 1.4, -0.4)
	u.add_child(glow)
	var tag := Label3D.new()
	tag.text = "DATA COURIER"
	tag.font_size = 64
	tag.pixel_size = 0.004
	tag.modulate = COURIER_ACCENT
	tag.outline_size = 10
	tag.outline_modulate = Color(0, 0, 0, 0.9)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position = Vector3(0, 2.6, 0)
	u.add_child(tag)

func _goal() -> Vector3:
	return route[leg] if leg < route.size() else uplink

func _physics_process(delta: float) -> void:
	_t += delta
	if _ring_mat:
		_ring_mat.emission_energy_multiplier = 2.0 + sin(_t * (9.0 if uploading else 3.0)) * 0.8
	if done or unit == null or not is_instance_valid(unit):
		return
	if unit.hijacked:
		_finish(false)
		return
	if unit.state == EnemyBase.State.DEAD:
		return
	if uploading:
		# An EMP scrambles the transfer as well as the legs.
		if unit._emp_t <= 0.0:
			upload_t += delta
		if _beam_mat:
			_beam_mat.albedo_color.a = BEAM_IDLE_ALPHA + (1.0 - BEAM_IDLE_ALPHA) * clampf(upload_t / upload_seconds, 0.0, 1.0)
		_relabel("upload:%d" % ceili(upload_seconds - upload_t))
		if upload_t >= upload_seconds:
			_escape()
		return
	unit.courier_goal = _goal()
	var reach := UPLINK_RADIUS if leg >= route.size() else maxf(1.0, unit.nav_agent.target_desired_distance + 0.4)
	var flat := unit.global_position - _goal()
	flat.y = 0.0
	if flat.length() <= reach:
		if leg < route.size():
			leg += 1
			unit.courier_goal = _goal()
		else:
			uploading = true
			upload_t = 0.0
			unit.courier_goal = unit.global_position # hold on the pad
			GameState.skirmish_event.emit("UPLOAD STARTED",
				tr("%d seconds to kill the courier before the data is out.") % ceili(upload_seconds))
			AudioBus.play_synth_at("overlord_glitch", unit.global_position, 0.0, 0.8)
	_relabel("fleeing")

## A finished upload: one copy is out. The backup courier spins up at the
## route start, at full health, and runs again.
func _escape() -> void:
	copies += 1
	uploading = false
	upload_t = 0.0
	if not restart_on_escape:
		# Gone with the data: off the map, no kill credit.
		done = true
		escaped.emit(copies)
		AudioBus.play_synth_at("overlord_glitch", unit.global_position, 0.0, 0.7)
		unit.courier_goal = null
		unit.queue_free()
		queue_free()
		return
	leg = 0
	if _beam_mat:
		_beam_mat.albedo_color.a = BEAM_IDLE_ALPHA
	unit.global_position = position
	unit.velocity = Vector3.ZERO
	unit.courier_goal = _goal()
	unit.hp.heal(unit.hp.max_health)
	_relabel("fleeing")
	escaped.emit(copies)
	GameState.skirmish_event.emit("COPY ESCAPED", "A backup courier spun up at the start. It runs again, and it called for help.")
	AudioBus.play_synth_at("overlord_glitch", position, 0.0, 0.7)

func _on_unit_died(_source: Node) -> void:
	if not done:
		_finish(true)

func _finish(killed: bool) -> void:
	done = true
	uploading = false
	if is_instance_valid(unit):
		unit.courier_goal = null
		# The wreck lingers: off the waypoint, and no longer a live courier
		# (the DATA LEAK event refuses to start a second one while one runs).
		unit.remove_from_group("intercept_courier")
		unit.remove_from_group("objective")
	if _pad:
		_pad.queue_free()
	caught.emit(killed, unit.global_position if is_instance_valid(unit) else position)
	if task_id == "":
		queue_free() # adopt mode: the caller pays out on `caught`
		return
	GameState.relabel_task(task_id, base_label)
	GameState.complete_task(task_id)
	if copies == 0:
		GameState.add_score(CLEAN_BONUS)
		GameState.skirmish_event.emit("CLEAN INTERCEPT", tr("Not one byte got out. +%d") % CLEAN_BONUS)
	elif killed:
		GameState.skirmish_event.emit("COURIER DOWN", "The data is yours. The copies are someone else's problem.")
	if not killed:
		GameState.skirmish_event.emit("COURIER TURNED", "It works for you now, and so does what it carried.")

func _relabel(key: String) -> void:
	if task_id == "":
		return
	var full := key + ":%d" % copies
	if full == _state_key:
		return
	_state_key = full
	var state_text: String
	if key.begins_with("upload:"):
		state_text = tr("UPLOADING %ds: kill it") % int(key.get_slice(":", 1))
	else:
		state_text = tr("fleeing")
	if copies > 0:
		state_text += "; " + (tr("%d copy escaped") if copies == 1 else tr("%d copies escaped")) % copies
	# Composed from translated parts: tr() of the whole string finds no key.
	GameState.relabel_task(task_id, "%s (%s)" % [tr(base_label), state_text])
