class_name SignalTransmitter
# @lat: [[level-system#Signal Hunt]]
extends StaticBody3D
## A "trace_signal" task: a hidden transmitter the player has to find by its
## signal. While HIDDEN it is a squat dark box with a stub aerial, NOT in the
## "objective" group (no waypoint, no radar blip). Every ping interval it
## pings from where it stands (positional audio, so the player can steer by
## ear) and blinks a faint LED; the interval shortens and the pitch rises as
## the player closes in, and the task label carries a five-bar SIGNAL meter
## (bars_for). The player within REVEAL_RANGE with line of sight, or any
## damage, REVEALS it: the aerial telescopes up under a red beacon, it joins
## the objective group, and `revealed` fires (the builder calls in the task's
## `alarm` squad). HEALTH damage destroys it and completes the task.
## tests/signal_hunt_probe.

signal revealed

const REVEAL_RANGE := 6.0
const HEALTH := 150.0
const BAR_RANGES := [60.0, 42.0, 28.0, 16.0, 8.0] ## within each: one more bar
const PING_SLOW := 2.0
const PING_FAST := 0.3
const COLOR := Color(1.0, 0.2, 0.15)
const TEACH_TEXT := "SIGNAL HUNT: no waypoint. Follow the ping by ear and the SIGNAL bars on the task list. Get close and it shows itself."

@export var task_id: String = "signal"
@export var base_label: String = "Trace and destroy the hidden transmitter"

var hp: Damageable
var hidden := true
var dead := false
var bars := -1
var pings := 0
var _ping_t := 1.0
var _mast: MeshInstance3D
var _led_mat: StandardMaterial3D
var _beacon: OmniLight3D

## Signal bars (0-5) at distance `d`.
static func bars_for(d: float) -> int:
	var n := 0
	for r in BAR_RANGES:
		if d <= r:
			n += 1
	return n

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("signal_transmitter")
	_build()
	hp = Damageable.new()
	hp.name = "Damageable"
	hp.max_health = HEALTH
	add_child(hp)
	hp.damaged.connect(func(_a: float, _s: Node) -> void: reveal())
	hp.died.connect(_on_destroyed)

func _build() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, 0.7, 0.9)
	cs.shape = bs
	cs.position.y = 0.35
	add_child(cs)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.7, 0.9)
	body.mesh = bm
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.13, 0.13, 0.12)
	skin.roughness = 0.8
	skin.metallic = 0.4
	body.material_override = skin
	body.position.y = 0.35
	add_child(body)
	_mast = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.04
	cm.height = 1.0
	_mast.mesh = cm
	_mast.material_override = skin
	_mast.position = Vector3(0.25, 0.7 + 0.5 * 0.35, 0.25)
	_mast.scale = Vector3(1, 0.35, 1) # stubbed down until revealed
	add_child(_mast)
	_led_mat = StandardMaterial3D.new()
	_led_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_led_mat.albedo_color = Color(0.25, 0.05, 0.04)
	var led := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	led.mesh = sm
	led.material_override = _led_mat
	led.position = Vector3(-0.2, 0.72, -0.2)
	add_child(led)

func _player() -> Node3D:
	return GameState.nearest_player(global_position)

func _physics_process(delta: float) -> void:
	if dead:
		return
	var p := _player()
	if p == null:
		return
	var d := p.global_position.distance_to(global_position)
	var b := bars_for(d)
	if b != bars:
		bars = b
		_relabel()
		# Feedback now: a closer step must not wait out the slow ping it had.
		_ping_t = minf(_ping_t, _interval(b))
	if hidden:
		if b > 0:
			GameState.teach_once("signal_hunt", TEACH_TEXT)
		if d <= REVEAL_RANGE and _sees(p):
			reveal()
			return
		_ping_t -= delta
		if _ping_t <= 0.0:
			_ping_t = _interval(b)
			_ping(b)
	else:
		_beacon.light_energy = 2.0 + 1.5 * sin(Time.get_ticks_msec() * 0.012)

static func _interval(b: int) -> float:
	return lerpf(PING_SLOW, PING_FAST, float(b) / 5.0)

func _sees(p: Node3D) -> bool:
	var from := p.global_position + Vector3.UP * 1.5
	var q := PhysicsRayQueryParameters3D.create(from, global_position + Vector3.UP * 0.5, 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _ping(b: int) -> void:
	pings += 1
	AudioBus.play_synth_at("broadcast_blip", global_position + Vector3.UP * 0.6, -2.0, 0.8 + 0.12 * float(b))
	_led_mat.albedo_color = COLOR
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_callback(func() -> void: _led_mat.albedo_color = Color(0.25, 0.05, 0.04))

func _relabel() -> void:
	if hidden:
		var meter := "■".repeat(bars) + "□".repeat(5 - bars)
		# Composed from translated parts, like EscapeZone's countdown.
		GameState.relabel_task(task_id, "%s · %s %s" % [tr(base_label), tr("SIGNAL"), meter])
	else:
		GameState.relabel_task(task_id, base_label)

## The transmitter shows itself: waypoint on, beacon up, alarm called.
func reveal() -> void:
	if not hidden or dead:
		return
	hidden = false
	add_to_group("objective")
	_relabel()
	var tw := create_tween()
	tw.tween_property(_mast, "scale", Vector3(1, 2.6, 1), 0.5).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(_mast, "position:y", 0.7 + 0.5 * 2.6, 0.5).set_trans(Tween.TRANS_BACK)
	_led_mat.albedo_color = COLOR
	_beacon = OmniLight3D.new()
	_beacon.light_color = COLOR
	_beacon.light_energy = 3.0
	_beacon.omni_range = 7.0
	_beacon.position = Vector3(0.25, 3.4, 0.25)
	add_child(_beacon)
	GameState.skirmish_event.emit("TRANSMITTER FOUND", tr("It knows you found it. Destroy it before help arrives."))
	AudioBus.play_synth_at("eas_alert", global_position, -2.0, 1.2)
	revealed.emit()

func _on_destroyed(_source: Node) -> void:
	if dead:
		return
	dead = true
	remove_from_group("objective")
	GameState.complete_task(task_id)
	var fx := ObjectiveCore.EXPLOSION.instantiate()
	get_parent().add_child(fx)
	(fx as Node3D).global_position = global_position + Vector3.UP * 0.5
	AudioBus.play_synth_at("explosion", global_position, 0.0, 1.1)
	queue_free()
