class_name JammerController
extends Node3D
## Grants the player the SIGNAL JAMMER for a level: aim at a wall or floor and fire
## (default [T] / gamepad Y) to plant an ephemeral beacon that projects a geofenced
## JamZone (jam_zone.gd). Beacons are limited and short-lived, so the tactic is
## deciding WHERE to plant them — a chokepoint to strip a whole flank's shields, or
## a heavy hitter to isolate it — while surviving the crossfire. Enemies can also be
## shoved (melee) into a live zone.
##
## Spawned by LevelBuilder when a level def carries a "jammer" key.

@export var zone_radius := 5.0
@export var zone_lifetime := 7.0
@export var max_beacons := 3
@export var cooldown := 1.2
@export var range := 45.0
@export var color := Color(0.35, 0.8, 1.0)

var _player: Node3D
var _cam: Camera3D
var _cd := 0.0
var _beacons: Array = []       ## live JamZone nodes, oldest first
var _hinted := false

func _ready() -> void:
	if not InputMap.has_action("jam_beacon"):
		InputMap.add_action("jam_beacon")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_T
		InputMap.action_add_event("jam_beacon", k)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_Y
		InputMap.action_add_event("jam_beacon", pad)
	get_tree().create_timer(0.8).timeout.connect(_hint)

func _hint() -> void:
	if has_node("/root/GameState"):
		var gs := get_node("/root/GameState")
		if gs.has_method("teach_once"):
			gs.teach_once("signal_jammer",
				"SIGNAL JAMMER ONLINE — fire [T] at a wall or floor to plant a jam beacon. Hive units caught inside lose their shields and scatter. Beacons are few and fade fast — pick your ground.")

func _process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player:
			_cam = _player.find_child("Camera3D", true, false) as Camera3D
		return
	# Prune expired beacons so the cap reflects only live zones.
	_beacons = _beacons.filter(func(b): return is_instance_valid(b))
	if Input.is_action_just_pressed("jam_beacon") and _cd <= 0.0:
		_fire()

func _fire() -> void:
	if _cam == null:
		_cam = _player.find_child("Camera3D", true, false) as Camera3D
	if _cam == null:
		return
	_cd = cooldown
	var from := _cam.global_position
	var to := from - _cam.global_transform.basis.z * range
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 # world geometry only
	q.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		if has_node("/root/AudioBus"):
			get_node("/root/AudioBus").play_synth_ui("empty_click", -12.0, 1.4)
		return
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	_tracer(from - _cam.global_transform.basis.y * 0.2, point)
	# Enforce the ephemeral cap: retire the oldest beacon early.
	if _beacons.size() >= max_beacons:
		var oldest = _beacons.pop_front()
		if is_instance_valid(oldest):
			oldest.lifetime = 0.0 # triggers its own release+free next frame
	# Beacon stake ON the surface; the zone is pushed off the surface so its sphere
	# bulges into the play space (a floor beacon covers the ground, a wall beacon
	# the room in front of it).
	_beacon_stake(point, normal)
	var zone := JamZone.new()
	zone.radius = zone_radius
	zone.lifetime = zone_lifetime
	zone.color = color
	zone.position = point + normal * (zone_radius * 0.5)
	add_child(zone)
	_beacons.append(zone)
	if has_node("/root/AudioBus"):
		var ab := get_node("/root/AudioBus")
		ab.play_synth_at("grenade_throw", point, -5.0, 1.6)
		ab.play_synth_at("impact_metal", point, -6.0, 1.3)

## A short glowing spike marking the physical beacon on the surface it stuck to.
func _beacon_stake(at: Vector3, normal: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.09
	cm.height = 0.7
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.albedo_color = color
	mat.emission_energy_multiplier = 2.0
	cm.material = mat
	mi.mesh = cm
	mi.position = at + normal * 0.3
	# Point the spike out of the surface.
	if absf(normal.dot(Vector3.UP)) < 0.98:
		mi.look_at_from_position(mi.position, at + normal, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Retire the stake with a fade so old anchors don't litter the arena.
	get_tree().create_timer(zone_lifetime).timeout.connect(func():
		if is_instance_valid(mi):
			mi.queue_free())

func _tracer(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var length := from.distance_to(to)
	cm.top_radius = 0.025
	cm.bottom_radius = 0.025
	cm.height = length
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.albedo_color = color
	cm.material = mat
	mi.mesh = cm
	mi.position = (from + to) * 0.5
	mi.look_at_from_position(mi.position, to, Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.16)
	tw.tween_callback(mi.queue_free)
