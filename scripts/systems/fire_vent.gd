class_name FireVent
# @lat: [[level-system#Fire Vents]]
extends Node3D
## A floor fire vent: a round grate inside a yellow-and-black hazard ring that
## erupts a column of flame once every `period` seconds. Every eruption is
## telegraphed for WARN_TIME seconds first, so a player who is paying any
## attention gets off it: the grate glows from dull red to white-hot, small
## flames lick up through it, an orange light swells, the ring pulses and it
## rumbles. During the eruption the player standing on it takes `damage` every
## TICK seconds. Robots are never hurt: traps are for the player. Nothing about
## it is solid. `phase` (0..1 of a period) offsets
## vents in a row so the eruption rolls across it and one is always cold.
## The first vent a player sees warming up teaches the rule once per run.
## `cryo` makes it a coolant vent (a cryo core's): the same beats, but the
## grate frosts over blue and hisses, and the blast is freezing white-blue
## vapour; it teaches its own line.
## Def key `fire_vents` (level_builder `_build_fire_vents`).
## tests/fire_vent_probe.

signal warning   ## the grate starts glowing: WARN_TIME s to the eruption
signal erupted   ## the column goes up

enum Phase { IDLE, WARN, ERUPT }

@export var radius: float = 1.4         ## m, the grate (the ring is drawn outside it)
@export var period: float = 4.0         ## s between eruptions
@export var phase: float = 0.0          ## 0..1 of a period
@export var height: float = 3.2         ## m, the flame column
@export var damage: float = 12.0        ## to the player per TICK while erupting
@export var cryo: bool = false          ## a coolant vent: blue frost and a freezing blast

const WARN_TIME := 1.2
const ERUPT_TIME := 1.2
const TICK := 0.25
const RING := 0.3                ## m, width of the hazard ring outside the grate
const BODY_RADIUS := 0.35        ## player capsule radius
const TEACH_REACH := 7.0         ## m outside the ring where a warming vent teaches
const TEACH_TEXT := "FIRE VENT: when a grate glows and rumbles, get off it. It erupts a second later."
const CRYO_TEXT := "CRYO VENT: when a grate frosts over and hisses, get off it. It blasts a second later."

var state: Phase = Phase.IDLE
var _t := 0.0
var _tick := 0.0
var _floor_mat: ShaderMaterial
var _lick: MeshInstance3D
var _column: MeshInstance3D
var _light: OmniLight3D

func _ready() -> void:
	add_to_group("hazard")
	_build()
	_apply(_cycle_u(), 0.0)

## Where in its cycle the vent is, 0..period: idle, then WARN_TIME of warning,
## then ERUPT_TIME of fire at the end.
func _cycle_u() -> float:
	return fposmod(_t + phase * period, period)

func _phase_at(u: float) -> Phase:
	if u >= period - ERUPT_TIME:
		return Phase.ERUPT
	if u >= period - ERUPT_TIME - WARN_TIME:
		return Phase.WARN
	return Phase.IDLE

## 0..1 through the warning (0 outside it).
func warn_progress() -> float:
	var u := _cycle_u()
	if _phase_at(u) != Phase.WARN:
		return 0.0
	return (u - (period - ERUPT_TIME - WARN_TIME)) / WARN_TIME

## Whether the flame column is drawn (only while erupting).
func column_visible() -> bool:
	return _column.visible

## Whether the warning flames lick up through the grate.
func lick_visible() -> bool:
	return _lick.visible

## The grate's glow, 0 (cold) to 1 (white-hot).
func heat() -> float:
	return float(_floor_mat.get_shader_parameter("heat"))

func _build() -> void:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float radius = 1.4;
uniform float ring = 0.3;
uniform float heat = 0.0;
uniform float pulse = 0.0;
uniform vec3 cool_col = vec3(0.6, 0.05, 0.0);
uniform vec3 hot_col = vec3(1.0, 0.42, 0.04);
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float d = length(lp.xz);
	if (d > radius + ring) { discard; }
	vec3 col;
	if (d > radius) {
		// The hazard ring: yellow and black wedges, pulsing as it warms.
		float a = atan(lp.z, lp.x);
		float s = step(0.5, fract(a * 12.0 / 6.2831853));
		vec3 yel = vec3(0.95, 0.66, 0.05) * (0.6 + pulse * 1.4);
		col = mix(vec3(0.03), yel, s);
	} else {
		// The grate: concentric slots glowing from below with the heat.
		float slot = step(0.55, fract(d * 5.0)) * step(0.12, d);
		vec3 hot = mix(cool_col, hot_col, heat);
		col = mix(vec3(0.05, 0.045, 0.04), hot * (0.4 + heat * 1.8), slot * (0.15 + heat * 0.85));
	}
	ALBEDO = col;
}
"""
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = sh
	_floor_mat.set_shader_parameter("radius", radius)
	_floor_mat.set_shader_parameter("ring", RING)
	if cryo:
		_floor_mat.set_shader_parameter("cool_col", Vector3(0.05, 0.2, 0.55))
		_floor_mat.set_shader_parameter("hot_col", Vector3(0.55, 0.9, 1.0))
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * (radius + RING) * 2.0
	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "Grate"
	floor_mi.mesh = pm
	floor_mi.material_override = _floor_mat
	floor_mi.position = Vector3.UP * 0.03
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mi)
	# Warning: short flames licking up through the grate.
	_lick = _flame(radius * 0.8, 1.2, 4.5, 0.72)
	_lick.name = "Lick"
	# Eruption: the full column, a dense flame round a bright core so it reads
	# as one solid pillar of fire from across the room.
	_column = _flame(radius * 0.9, height, 6.0, 0.85)
	_column.name = "Column"
	var core := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = radius * 0.2
	cc.bottom_radius = radius * 0.55
	cc.height = 1.0
	cc.radial_segments = 16
	core.mesh = cc
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cm.albedo_color = Color(0.6, 0.85, 1.0, 0.85) if cryo else Color(1.0, 0.5, 0.12, 0.85)
	core.material_override = cm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.scale = Vector3(1.0, height * 0.92, 1.0) # rides the column's own stretch
	_column.add_child(core)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.5, 0.8, 1.0) if cryo else Color(1.0, 0.45, 0.12)
	_light.omni_range = radius + 6.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3.UP * 0.8
	add_child(_light)

func _flame(base: float, tall: float, energy: float, density: float) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = base * 0.35
	cm.bottom_radius = base
	cm.height = tall
	cm.radial_segments = 16
	var core_c := Color(0.9, 0.97, 1.0) if cryo else Color(1.0, 0.8, 0.4)
	var edge_c := Color(0.35, 0.7, 1.0) if cryo else Color(1.0, 0.35, 0.08)
	cm.material = FlameMaterial.make(core_c, edge_c,
			energy, Vector2(0.0, 9.0), density, 0.3) # pan base->apex: flames lick upward
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.position = Vector3.UP * tall * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi

func _physics_process(delta: float) -> void:
	var prev := state
	_t += delta
	var u := _cycle_u()
	state = _phase_at(u)
	if state != prev:
		if state == Phase.WARN:
			AudioBus.play_synth_at("charge", global_position, -2.0, 0.8 if cryo else 0.45)
			AudioBus.play_synth_at("acid_spit", global_position, -4.0, 1.1 if cryo else 0.5)
			warning.emit()
		elif state == Phase.ERUPT:
			_tick = 0.0
			AudioBus.play_synth_at("explosion", global_position, -5.0, 0.5)
			AudioBus.play_synth_at("rocket_fire", global_position, -2.0, 0.6)
			erupted.emit()
	_apply(u, delta)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if state == Phase.WARN and pl != null and _flat_dist(pl) <= radius + RING + TEACH_REACH:
		if cryo:
			GameState.teach_once("cryo_vent", CRYO_TEXT)
		else:
			GameState.teach_once("fire_vent", TEACH_TEXT)
	if state == Phase.ERUPT:
		_tick -= delta
		if _tick <= 0.0:
			_tick = TICK
			_burn(pl)

## Look of the vent at cycle time `u`.
func _apply(u: float, _delta: float) -> void:
	var w := warn_progress()
	var flicker := 0.85 + 0.15 * sin(_t * 31.0)
	match _phase_at(u):
		Phase.IDLE:
			_floor_mat.set_shader_parameter("heat", 0.05)
			_floor_mat.set_shader_parameter("pulse", 0.0)
			_lick.visible = false
			_column.visible = false
			_light.light_energy = 0.0
		Phase.WARN:
			_floor_mat.set_shader_parameter("heat", 0.3 + 0.7 * w)
			_floor_mat.set_shader_parameter("pulse", 1.0 if fmod(_t * 6.0, 1.0) < 0.5 else 0.2)
			_lick.visible = true
			_lick.scale = Vector3(1.0, 0.35 + 0.65 * w, 1.0) * flicker
			_lick.position = Vector3.UP * 0.6 * _lick.scale.y
			_column.visible = false
			_light.light_energy = (0.6 + 2.4 * w) * flicker
		Phase.ERUPT:
			var e := (u - (period - ERUPT_TIME)) / ERUPT_TIME
			# Shoots up in the first 0.15 s, gutters in the last 0.2 s.
			var k := clampf(e * ERUPT_TIME / 0.15, 0.0, 1.0) * clampf((1.0 - e) * ERUPT_TIME / 0.2, 0.0, 1.0)
			_floor_mat.set_shader_parameter("heat", 1.0)
			_floor_mat.set_shader_parameter("pulse", 1.0)
			_lick.visible = false
			_column.visible = true
			_column.scale = Vector3(flicker, maxf(k, 0.05), flicker)
			_column.position = Vector3.UP * height * 0.5 * _column.scale.y
			_light.light_energy = 5.0 * flicker

func _flat_dist(n: Node3D) -> float:
	var d := n.global_position - global_position
	d.y = 0.0
	return d.length()

## Whether a body standing at `feet` is inside the column.
func _inside(n: Node3D, reach: float) -> bool:
	var dy := n.global_position.y - global_position.y
	return _flat_dist(n) <= radius + reach and dy > -0.6 and dy < height

func _burn(pl: Node3D) -> void:
	var at := global_position + Vector3.UP * 1.0
	if pl != null and _inside(pl, BODY_RADIUS * 0.5):
		var php: Node = pl.get_node_or_null("Damageable")
		if php:
			php.apply_damage(damage, self, false, at, true)

## The death screen's "Taken down by" name and its tip key (player.gd reads it
## off any damage source that has it; hud.gd DEATH_TIPS).
func _kill_label() -> String:
	return "FIRE VENT"
