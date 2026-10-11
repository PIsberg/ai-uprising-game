class_name KillSwitch
extends Area3D
# @lat: [[level-system#Kill Switches]]
## One post of a `kill_switch` task: a breaker lever under a tall beacon. Walk
## into it and the lever drops (red beacon turns green). Its KillSwitchBank owns
## the rules: when the watchdog clock runs out before every switch is down, the
## bank re-arms this one (lever back up, beacon red), so the player has to cut
## them all inside one window. The beacon is 14 m tall so a switch can be found
## across a big open level.

signal thrown_now

const ARMED := Color(1.0, 0.16, 0.1)
const SAFE := Color(0.3, 1.0, 0.45)
const BEACON_H := 14.0

var task_id: String = "switches"
var thrown: bool = false
var locked: bool = false ## task done: the switch stays down for good

var _inside: int = 0
var _t: float = 0.0
var _lever: Node3D
var _beacon_mat: StandardMaterial3D
var _knob_mat: StandardMaterial3D
var _light: OmniLight3D
var _tag: Label3D

func _ready() -> void:
	collision_layer = 64
	collision_mask = 2 # player
	add_to_group("objective")
	add_to_group("kill_switch")
	body_entered.connect(func(b): if b.is_in_group("player"): _inside += 1)
	body_exited.connect(func(b): if b.is_in_group("player"): _inside = maxi(0, _inside - 1))
	_build_visual()
	_paint()

func _build_visual() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.14)
	dark.metallic = 0.6
	dark.roughness = 0.45
	var plinth := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.0, 0.25, 1.0)
	plinth.mesh = pm
	plinth.material_override = dark
	plinth.position = Vector3(0, 0.125, 0)
	add_child(plinth)
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 1.25, 0.3)
	post.mesh = bm
	post.material_override = dark
	post.position = Vector3(0, 0.875, 0)
	add_child(post)
	# Yellow/black hazard band: reads as industrial breaker, not a terminal.
	var haz := StandardMaterial3D.new()
	haz.albedo_color = Color(0.95, 0.72, 0.05)
	var band := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.47, 0.12, 0.32)
	band.mesh = hm
	band.material_override = haz
	band.position = Vector3(0, 0.5, 0)
	add_child(band)
	# The lever pivots on the post's front face: up = armed, down = thrown.
	_lever = Node3D.new()
	_lever.position = Vector3(0, 1.15, 0.18)
	add_child(_lever)
	var arm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.035
	cm.height = 0.6
	arm.mesh = cm
	arm.material_override = dark
	arm.position = Vector3(0, 0.3, 0)
	_lever.add_child(arm)
	_knob_mat = StandardMaterial3D.new()
	_knob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var knob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	knob.mesh = sm
	knob.material_override = _knob_mat
	knob.position = Vector3(0, 0.62, 0)
	_lever.add_child(knob)
	# Beacon: a thin additive column of light, no shadow, visible across the map.
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beacon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beacon := MeshInstance3D.new()
	var col := CylinderMesh.new()
	col.top_radius = 0.06
	col.bottom_radius = 0.16
	col.height = BEACON_H
	col.radial_segments = 8
	beacon.mesh = col
	beacon.material_override = _beacon_mat
	beacon.position = Vector3(0, 1.5 + BEACON_H * 0.5, 0)
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)
	_tag = Label3D.new()
	_tag.text = "KILL SWITCH"
	_tag.font_size = 72
	_tag.pixel_size = 0.005
	_tag.outline_size = 12
	_tag.outline_modulate = Color(0, 0, 0, 0.9)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.position = Vector3(0, 2.2, 0)
	add_child(_tag)
	_light = OmniLight3D.new()
	_light.light_energy = 2.0
	_light.omni_range = 5.0
	_light.position = Vector3(0, 1.6, 0.4)
	add_child(_light)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 2.0, 2.4)
	cs.shape = bs
	cs.position = Vector3(0, 1.0, 0)
	add_child(cs)

func _physics_process(_delta: float) -> void:
	if _inside > 0 and not thrown and not locked:
		throw_switch()

func _process(delta: float) -> void:
	_t += delta
	if thrown or _beacon_mat == null:
		return
	# An armed switch pulses so the eye finds it in a busy frame.
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	_beacon_mat.albedo_color = Color(ARMED.r, ARMED.g, ARMED.b, 0.35 + 0.25 * pulse)
	_light.light_energy = 1.4 + pulse * 1.2

func throw_switch() -> void:
	if thrown or locked:
		return
	thrown = true
	_paint()
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("pickup_health", global_position, -2.0, 0.6)
	thrown_now.emit()

## The watchdog put it back: lever up, beacon red.
func rearm() -> void:
	if locked or not thrown:
		return
	thrown = false
	_paint()
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("overlord_glitch", global_position, -6.0, 1.3)

func lock() -> void:
	locked = true
	thrown = true
	_paint()

func _paint() -> void:
	if _lever == null:
		return
	var c := SAFE if thrown else ARMED
	_lever.rotation_degrees.x = 120.0 if thrown else 25.0
	_knob_mat.albedo_color = c
	_beacon_mat.albedo_color = Color(c.r, c.g, c.b, 0.45)
	_light.light_color = c
	_light.light_energy = 2.0
	_tag.modulate = c
	_tag.text = "OFF" if thrown else "KILL SWITCH"
