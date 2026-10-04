class_name FirewallBarrier
# @lat: [[level-system#Security Firewalls]]
extends StaticBody3D
## A security firewall across a route: a full-height energy sheet between two
## emitter pylons that stops the PLAYER and nothing else. It sits on its own
## collision layer (FIREWALL_LAYER), which only the player's body masks, so
## robots walk through it (the firewall whitelists machine traffic), rounds and
## grenades pass through it, and the navmesh bake (world layer only) never sees
## it. It drops when its relay node is shot (`node_pos`) or when every task in
## `opens_on` completes, whichever comes first.
##
## Authoring rule the probe enforces (tests/firewall_probe): a firewall's opener
## must be reachable from spawn without crossing any firewall authored after it.

signal opened

const FIREWALL_LAYER := 128 ## layer 8 "firewall"; the player body masks it, nothing else does
const PLAYER_LAYER := 2
const SHADER := preload("res://shaders/firewall.gdshader")

@export var length: float = 8.0
@export var height: float = 3.4
@export var accent: Color = Color(1.0, 0.18, 0.12)
@export var opens_on: Array[String] = []
@export var has_relay: bool = false
@export var node_pos: Vector3 = Vector3.ZERO ## relay position, in the PARENT's space
@export var label: String = ""

var is_open: bool = false
var relay: FirewallNode
var _mat: ShaderMaterial
var _shape: CollisionShape3D
var _touch: Area3D
var _light: OmniLight3D
var _strip_mats: Array[StandardMaterial3D] = []
var _zap_t: float = 0.0
var _hum: AudioStreamPlayer3D

func _ready() -> void:
	collision_layer = FIREWALL_LAYER
	collision_mask = 0
	add_to_group("firewall")
	_build_visual()
	_build_collision()
	_build_audio()
	if has_relay:
		_spawn_relay.call_deferred()
	if not opens_on.is_empty():
		GameState.tasks_changed.connect(_check_tasks)
		# A checkpoint resume can rebuild the level with the opener already done.
		_check_tasks()

func _build_visual() -> void:
	var sheet := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(length, height)
	sheet.mesh = qm
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("wall_color", Vector3(accent.r, accent.g, accent.b))
	_mat.set_shader_parameter("wall_size", Vector2(length, height))
	sheet.material_override = _mat
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.position.y = height * 0.5
	add_child(sheet)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.09, 0.1, 0.12)
	metal.metallic = 0.85
	metal.roughness = 0.3
	for side in [-1.0, 1.0]:
		var x: float = side * (length * 0.5 + 0.22)
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.44, height + 0.5, 0.7)
		post.mesh = pm
		post.material_override = metal
		post.position = Vector3(x, (height + 0.5) * 0.5, 0)
		add_child(post)
		# Emitter strips on both faces of the post: the feed the sheet hangs off.
		for face in [-1.0, 1.0]:
			var strip := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.1, height - 0.2, 0.04)
			strip.mesh = sm
			var smat := StandardMaterial3D.new()
			smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			smat.albedo_color = accent
			smat.emission_enabled = true
			smat.emission = accent
			smat.emission_energy_multiplier = 3.0
			strip.material_override = smat
			strip.position = Vector3(x, height * 0.5 + 0.1, face * 0.37)
			add_child(strip)
			_strip_mats.append(smat)
		# Solid collision on the posts: they are real hardware and stay after the drop.
		var pcs := CollisionShape3D.new()
		var pbs := BoxShape3D.new()
		pbs.size = pm.size
		pcs.shape = pbs
		pcs.position = post.position
		var post_body := StaticBody3D.new()
		post_body.collision_layer = 1
		post_body.collision_mask = 0
		post_body.add_child(pcs)
		add_child(post_body)

	# Hazard sill across the floor so the line reads even when the sheet is edge-on.
	var sill := MeshInstance3D.new()
	var slm := BoxMesh.new()
	slm.size = Vector3(length, 0.04, 0.5)
	sill.mesh = slm
	var sill_mat := StandardMaterial3D.new()
	sill_mat.albedo_color = Color(0.9, 0.6, 0.1)
	sill_mat.emission_enabled = true
	sill_mat.emission = Color(0.9, 0.55, 0.08)
	sill_mat.emission_energy_multiplier = 0.8
	sill.material_override = sill_mat
	sill.position.y = 0.02
	add_child(sill)

	_light = OmniLight3D.new()
	_light.light_color = accent
	_light.light_energy = 1.8
	_light.omni_range = maxf(5.0, length * 0.6)
	_light.shadow_enabled = false
	_light.position.y = height * 0.6
	add_child(_light)

func _build_collision() -> void:
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	# 1.5 m taller than the sheet: a jump peaks ~1.2 m, so it can't be hopped,
	# yet a sky-bridge well above the sheet still passes over it.
	bs.size = Vector3(length, height + 1.5, 0.4)
	_shape.shape = bs
	_shape.position.y = (height + 1.5) * 0.5
	add_child(_shape)
	# Contact zone a little thicker than the wall: pressing into it stings.
	_touch = Area3D.new()
	_touch.collision_layer = 0
	_touch.collision_mask = PLAYER_LAYER
	var tcs := CollisionShape3D.new()
	var tbs := BoxShape3D.new()
	tbs.size = Vector3(length, height, 1.5)
	tcs.shape = tbs
	tcs.position.y = height * 0.5
	_touch.add_child(tcs)
	add_child(_touch)

func _build_audio() -> void:
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = AudioBus.synth("drone_hum")
	_hum.volume_db = -14.0
	_hum.pitch_scale = 0.55
	_hum.max_distance = 22.0
	_hum.position.y = height * 0.5
	add_child(_hum)
	if is_inside_tree() and _hum.stream:
		_hum.play()

func _spawn_relay() -> void:
	if is_open or not is_inside_tree():
		return
	relay = FirewallNode.new()
	relay.accent = accent
	get_parent().add_child(relay)
	relay.position = node_pos
	relay.destroyed.connect(open)

func _check_tasks() -> void:
	if is_open or opens_on.is_empty():
		return
	for id in opens_on:
		if not GameState.is_task_done(id):
			return
	open()

## Drop the firewall: collision off at once, the sheet drains top-down.
func open() -> void:
	if is_open:
		return
	is_open = true
	if _shape:
		_shape.set_deferred("disabled", true)
	if _touch:
		_touch.set_deferred("monitoring", false)
	if _hum:
		_hum.stop()
	opened.emit()
	if is_inside_tree():
		AudioBus.play_synth_at("overlord_glitch", global_position + Vector3.UP * 1.5, 2.0, 0.7)
		GameState.skirmish_event.emit("FIREWALL BREACHED",
			label if label != "" else "The route ahead is open.")
		var tw := create_tween()
		tw.tween_method(_set_collapse, 0.0, 1.0, 1.1)
		tw.parallel().tween_property(_light, "light_energy", 0.0, 1.1)
	else:
		_set_collapse(1.0)
		_light.light_energy = 0.0
	for m in _strip_mats:
		m.emission_energy_multiplier = 0.25
	if is_instance_valid(relay):
		relay.queue_free()

func _set_collapse(v: float) -> void:
	_mat.set_shader_parameter("collapse", v)

func _process(delta: float) -> void:
	if is_open:
		return
	_zap_t = maxf(0.0, _zap_t - delta)
	_mat.set_shader_parameter("hit_flash", _zap_t / 0.5)
	if _zap_t > 0.0 or not _touch.monitoring:
		return
	for body in _touch.get_overlapping_bodies():
		if not body.is_in_group("player"):
			continue
		var d := body.get_node_or_null("Damageable") as Damageable
		if d and d.is_alive():
			d.apply_damage(6.0, self)
		AudioBus.play_synth_at("impact_metal", body.global_position + Vector3.UP, -4.0, 1.6)
		if body.has_method("shake"):
			body.shake(0.25)
		GameState.teach_once("firewall",
			"FIREWALL: it only stops you. Shoot its relay node (follow the light column) or finish the linked objective to drop it.")
		_zap_t = 0.5
		break