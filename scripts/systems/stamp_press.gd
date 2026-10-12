class_name StampPress
# @lat: [[level-system#Stamping Presses]]
extends Node3D
## A hydraulic stamping press: two pillars and a crossbeam over a striped
## footprint, and a heavy head that rides up to `clearance`, cocks, and slams
## to the floor once every `period` seconds. A player under it at the slam
## takes `damage` and is shoved out of the side. Robots are never hurt: traps
## are for the player. Every slam is
## telegraphed: the warning lamps go red, the hydraulics whine and the head
## cocks up for `telegraph` seconds before it drops. Pillars and beam are solid
## (cover, and the navmesh bakes round them); the head is not, so nothing ever
## gets wedged inside it. `phase` (0..1 of a period) offsets presses in a line
## so a slam travels down it. Def key `presses` (level_builder `_build_presses`).
## tests/stamp_press_probe.

signal slammed

@export var size: Vector2 = Vector2(4.0, 4.0) ## Footprint (x by z) in metres.
@export var clearance: float = 4.0            ## Head underside at the top of its stroke.
@export var period: float = 3.2               ## Seconds between slams.
@export var phase: float = 0.0                ## 0..1 of a period: offsets a line of presses.
@export var damage: float = 45.0              ## To the player per slam.
@export var shove: float = 10.0               ## m/s the player is thrown out of the side.

const HEAD_THICK := 1.0
const BEAM_THICK := 0.9
const PILLAR := 0.7
const COCK := 0.3               ## m the head lifts while it telegraphs
const FLOOR_GAP := 0.05         ## head underside at the bottom of its stroke
const PLAYER_LAYER := 2

var telegraphing := false
var _t := 0.0
var _u_prev := -1.0
# Stroke timings (s), shrunk together when the period is short.
var _tele := 0.7
var _drop := 0.12
var _dwell := 0.35
var _rise := 1.0
var _head: MeshInstance3D
var _ram: MeshInstance3D
var _lamp_mat: StandardMaterial3D
var _lip_mat: StandardMaterial3D
var _light: OmniLight3D
var _zone: Area3D
var _top := 0.0 ## beam underside

func _ready() -> void:
	add_to_group("hazard")
	var k := minf(1.0, period / 3.2)
	_tele *= k
	_drop *= k
	_dwell *= k
	_rise *= k
	_build()

## World height of the head's underside right now.
func head_bottom() -> float:
	return global_position.y + (_head.position.y - HEAD_THICK * 0.5 if _head else clearance)

func _long_x() -> bool:
	return size.x >= size.y

func _build() -> void:
	var lx := _long_x()
	var span := size.x if lx else size.y   # between the pillars
	var depth := size.y if lx else size.x  # open sides
	_top = clearance + COCK + HEAD_THICK + 0.25
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.22, 0.21, 0.2)
	steel.metallic = 0.75
	steel.roughness = 0.45
	# Pillars wear hazard chevrons (lit, world-space so neighbours line up).
	var paint := ShaderMaterial.new()
	paint.shader = _chevron_shader()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var along := Vector3.RIGHT if lx else Vector3.BACK
	# Pillars at the two ends of the long axis, beam across their tops.
	for s: float in [-1.0, 1.0]:
		var c: Vector3 = along * (s * (span * 0.5 + PILLAR * 0.5))
		var psz: Vector3 = Vector3(PILLAR, _top + BEAM_THICK, depth) if lx else Vector3(depth, _top + BEAM_THICK, PILLAR)
		_box(body, c + Vector3.UP * psz.y * 0.5, psz, paint, true)
		# Warning lamp on each pillar's inner face, just under the beam.
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		lamp.mesh = sm
		if _lamp_mat == null:
			_lamp_mat = StandardMaterial3D.new()
			_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_lamp_mat.emission_enabled = true
		lamp.material_override = _lamp_mat
		lamp.position = along * (s * span * 0.5) + Vector3.UP * (_top - 0.35)
		add_child(lamp)
	var beam := Vector3(span + PILLAR * 2.0, BEAM_THICK, depth) if lx else Vector3(depth, BEAM_THICK, span + PILLAR * 2.0)
	_box(body, Vector3.UP * (_top + BEAM_THICK * 0.5), beam, steel, true)
	# The head and its ram (visual only: nothing collides with them).
	_head = _box(self, Vector3.ZERO, Vector3(size.x - 0.15, HEAD_THICK, size.y - 0.15), steel, false)
	# The die's lip: dull until the press cocks, then it glows like a warning.
	_lip_mat = StandardMaterial3D.new()
	_lip_mat.albedo_color = Color(0.3, 0.12, 0.04)
	_lip_mat.emission_enabled = true
	_lip_mat.emission = Color(1.0, 0.35, 0.05)
	_lip_mat.emission_energy_multiplier = 0.0
	var edge := _box(_head, Vector3(0, -HEAD_THICK * 0.5 + 0.06, 0), Vector3(size.x - 0.1, 0.12, size.y - 0.1), _lip_mat, false)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Chrome guide rods at the head's corners, beam to floor.
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var rod := MeshInstance3D.new()
			var rc := CylinderMesh.new()
			rc.top_radius = 0.07
			rc.bottom_radius = 0.07
			rc.height = _top
			rod.mesh = rc
			rod.material_override = steel
			rod.position = Vector3(cx * (size.x * 0.5 - 0.25), _top * 0.5, cz * (size.y * 0.5 - 0.25))
			add_child(rod)
	_ram = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.32
	cyl.bottom_radius = 0.32
	cyl.height = 1.0
	_ram.mesh = cyl
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.8, 0.82, 0.85)
	chrome.metallic = 1.0
	chrome.roughness = 0.15
	_ram.material_override = chrome
	add_child(_ram)
	_build_stripes()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.15, 0.08)
	_light.omni_range = maxf(size.x, size.y) + 3.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3.UP * (_top - 0.6)
	add_child(_light)
	# The crush zone: the footprint, floor to above the player's head.
	_zone = Area3D.new()
	_zone.collision_layer = 0
	_zone.collision_mask = PLAYER_LAYER
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, 2.4, size.y)
	cs.shape = bs
	cs.position = Vector3.UP * 1.2
	_zone.add_child(cs)
	add_child(_zone)
	_pose(_head_y(_cycle_u()))

func _box(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material, solid: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		cs.position = pos
		parent.add_child(cs)
	return mi

static var _chevron: Shader
static func _chevron_shader() -> Shader:
	if _chevron == null:
		_chevron = Shader.new()
		_chevron.code = """shader_type spatial;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float s = step(0.5, fract((wp.x + wp.y + wp.z) * 1.1));
	ALBEDO = mix(vec3(0.04), vec3(0.95, 0.68, 0.06), s);
	ROUGHNESS = 0.6;
	METALLIC = 0.2;
}
"""
	return _chevron

## Yellow-and-black hazard chevrons flush on the floor under the head.
func _build_stripes() -> void:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec2 size = vec2(4.0);
uniform float pulse = 0.0;
varying vec3 wp;
void vertex() { wp = VERTEX; }
void fragment() {
	float s = step(0.5, fract((wp.x + wp.z) * 1.6));
	vec2 edge = size * 0.5 - abs(wp.xz);
	float rim = step(min(edge.x, edge.y), 0.22);
	vec3 yel = vec3(0.95, 0.66, 0.05) * (0.55 + pulse * 0.9);
	vec3 col = mix(vec3(0.03), yel, max(s, rim));
	ALBEDO = col;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("size", size)
	var pm := PlaneMesh.new()
	pm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3.UP * 0.025
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Stripes"
	add_child(mi)

## Where in the cycle the press is, 0..period. One cycle: up and still, cock
## (telegraph), drop, slam (the instant at _slam_at()), dwell down, rise.
func _cycle_u() -> float:
	return fposmod(_t + phase * period, period)

func _slam_at() -> float:
	return period - _dwell - _rise

func _head_y(u: float) -> float:
	var s := _slam_at()
	var cocked := clearance + COCK
	if u < s - _tele - _drop:
		return clearance
	if u < s - _drop:
		return lerpf(clearance, cocked, smoothstep(0.0, 1.0, (u - (s - _tele - _drop)) / _tele))
	if u < s:
		var f := (u - (s - _drop)) / _drop
		return lerpf(cocked, FLOOR_GAP, f * f)
	if u < s + _dwell:
		return FLOOR_GAP
	return lerpf(FLOOR_GAP, clearance, smoothstep(0.0, 1.0, (u - s - _dwell) / _rise))

func _pose(bottom: float) -> void:
	_head.position = Vector3.UP * (bottom + HEAD_THICK * 0.5)
	var ram_lo := bottom + HEAD_THICK
	var ram_len := maxf(_top - ram_lo, 0.05)
	_ram.scale = Vector3(1.0, ram_len, 1.0)
	_ram.position = Vector3.UP * (ram_lo + ram_len * 0.5)

func _physics_process(delta: float) -> void:
	_t += delta
	var u := _cycle_u()
	var s := _slam_at()
	telegraphing = u >= s - _tele - _drop and u < s
	_pose(_head_y(u))
	var blink := 1.0 if telegraphing and fmod(u * 8.0, 1.0) < 0.5 else 0.0
	_lamp_mat.albedo_color = Color(1.0, 0.12, 0.05) if telegraphing else Color(0.9, 0.55, 0.1)
	_lamp_mat.emission = _lamp_mat.albedo_color
	_lamp_mat.emission_energy_multiplier = 1.0 + blink * 5.0
	_light.light_energy = blink * 2.2
	_lip_mat.emission_energy_multiplier = 3.0 if telegraphing else 0.0
	if _u_prev >= 0.0 and ((_u_prev < s and u >= s) or (u < _u_prev and (_u_prev < s or u >= s))):
		_slam()
	_u_prev = u

func _slam() -> void:
	var center := global_position
	var lx := _long_x()
	for b in _zone.get_overlapping_bodies():
		if not is_instance_valid(b):
			continue
		if b.is_in_group("player"):
			var hp: Node = b.get_node_or_null("Damageable")
			if hp:
				hp.apply_damage(damage, self, false, center + Vector3.UP * 3.0, true)
			# Out of an open side (the pillars close the long ends).
			var off: Vector3 = (b as Node3D).global_position - center
			var side := Vector3(0, 0, signf(off.z) if off.z != 0.0 else 1.0) if lx \
				else Vector3(signf(off.x) if off.x != 0.0 else 1.0, 0, 0)
			if "velocity" in b:
				b.velocity = side * shove + Vector3.UP * 3.0
	_slam_fx()
	slammed.emit()

func _slam_fx() -> void:
	AudioBus.play_synth_at("impact_metal", global_position, 2.0, 0.42)
	AudioBus.play_synth_at("mech_step", global_position, 0.0, 0.5)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl and pl.has_method("shake"):
		var d := pl.global_position.distance_to(global_position)
		if d < 16.0:
			pl.shake(0.55 * (1.0 - d / 16.0))
	# A flat ring of dust squeezed out from under the head.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.55
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.62, 0.45, 0.55)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.position = Vector3.UP * 0.12
	ring.scale = Vector3(size.x * 0.5, 0.4, size.y * 0.5)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(size.x * 1.1, 0.4, size.y * 1.1), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(ring.queue_free)
