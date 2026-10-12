class_name ShockFloor
# @lat: [[level-system#Shock Floors]]
extends Node3D
## An electrified floor: a grid of `cells` tiles, `cell` metres square, that arc
## in a pattern. Tiles fall into groups (`pattern` "checker": the two colours of
## a chessboard, so every tile's four neighbours are in the other group; "rows":
## one group per row across `cells.y`, a wave). The groups take turns: a group
## glows cyan and buzzes for WARN_TIME, then arcs for ZAP_TIME, then the next
## group does. The rule a player reads is simple: a glowing tile is about to
## arc, a dark tile is safe. Feet on an arcing tile take `damage` every TICK;
## a jump clears it. Robots are not hurt (the floor is keyed to organic
## footprints). Every tile's outline is always lit, so the floor reads before it
## does anything. The first floor a player walks up to teaches the rule once per
## run. A glowing tile has a dim pulsing fill and a thickening border; an
## arcing one turns electric blue with white crackle and throws bolts up off
## it. Nothing about it is solid.
## Def key `shock_floors` (level_builder `_build_shock_floors`).
## tests/shock_floor_probe.

signal warning(group: int)  ## `group`'s tiles start to glow
signal zapped(group: int)   ## `group`'s tiles start to arc

@export var cells: Vector2i = Vector2i(4, 2)   ## tiles along x, along z
@export var cell: float = 2.0                  ## tile size, metres
@export var pattern: String = "checker"        ## "checker" or "rows"
@export var damage: float = 12.0               ## to the player per TICK on an arcing tile

const WARN_TIME := 0.9
const ZAP_TIME := 0.7
const TICK := 0.3
const FEET_REACH := 0.35       ## m over the floor that still counts as standing on it
const TEACH_REACH := 5.0
const TEACH_TEXT := "SHOCK FLOOR: a tile that glows is about to arc. Step onto a dark tile, or jump."

enum Tile { DARK, WARN, ZAP }

var _t := 0.0
var _tick := 0.0
var _group := -1
var _zapping := false
var _mats: Array[ShaderMaterial] = []
var _light: OmniLight3D
var _bolts: Array[MeshInstance3D] = []
const BOLTS_PER_TILE := 3

func _ready() -> void:
	add_to_group("hazard")
	_build()
	_apply()

## How many groups the pattern has.
func group_count() -> int:
	return 2 if pattern == "checker" else maxi(cells.y, 1)

## The group tile (`ix`, `iz`) belongs to.
func group_of(ix: int, iz: int) -> int:
	return (ix + iz) % 2 if pattern == "checker" else iz

## Which group holds the floor now, and whether it warns or arcs.
func active_group() -> int:
	var slot := WARN_TIME + ZAP_TIME
	return int(floor(fposmod(_t, slot * group_count()) / slot))

func tile_state(ix: int, iz: int) -> Tile:
	if group_of(ix, iz) != active_group():
		return Tile.DARK
	var into := fposmod(_t, WARN_TIME + ZAP_TIME)
	return Tile.WARN if into < WARN_TIME else Tile.ZAP

## The tile under a world point, or (-1, -1) off the floor.
func tile_at(p: Vector3) -> Vector2i:
	var local := p - global_position
	var ix := int(floor(local.x / cell + cells.x * 0.5))
	var iz := int(floor(local.z / cell + cells.y * 0.5))
	if ix < 0 or iz < 0 or ix >= cells.x or iz >= cells.y:
		return Vector2i(-1, -1)
	return Vector2i(ix, iz)

## World centre of tile (`ix`, `iz`).
func tile_center(ix: int, iz: int) -> Vector3:
	return global_position + Vector3((ix + 0.5 - cells.x * 0.5) * cell, 0.0, (iz + 0.5 - cells.y * 0.5) * cell)

static var _shader: Shader
static func _tile_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float glow = 0.0;   // 0 dark, 0..1 warning, 2 arcing
uniform float size = 2.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 e = size * 0.5 - abs(lp.xz);
	float edge = 1.0 - smoothstep(0.04, 0.1, min(e.x, e.y));
	vec3 cyan = vec3(0.25, 0.85, 1.0);
	vec3 col = vec3(0.03, 0.04, 0.06) + cyan * edge * 0.55;
	if (glow > 1.5) {
		// Arcing: deep electric blue crawling with thin white crackle lines.
		vec2 q = lp.xz * 3.0;
		float n = hash(floor(q) + floor(TIME * 20.0));
		float line = abs(fract(q.x + q.y * (n - 0.5) * 2.0 + n) - 0.5);
		float crack = 1.0 - smoothstep(0.0, 0.06, line);
		col = vec3(0.06, 0.18, 0.9) + vec3(0.9, 0.95, 1.0) * crack + vec3(0.6, 0.9, 1.0) * edge;
	} else if (glow > 0.0) {
		// Warning: a dim pulsing fill and a bright border that thickens as the
		// tile charges, so "about to arc" never looks like "arcing".
		float pulse = 0.5 + 0.5 * sin(TIME * 16.0);
		float rim = 1.0 - smoothstep(0.05, 0.12 + glow * 0.3, min(e.x, e.y));
		col = vec3(0.03, 0.05, 0.07) + cyan * (0.12 + 0.2 * glow) * pulse + cyan * rim * 0.9;
	}
	ALBEDO = col;
}
"""
	return _shader

func _build() -> void:
	for iz in cells.y:
		for ix in cells.x:
			var mat := ShaderMaterial.new()
			mat.shader = _tile_shader()
			mat.set_shader_parameter("size", cell)
			_mats.append(mat)
			var pm := PlaneMesh.new()
			pm.size = Vector2(cell, cell)
			var mi := MeshInstance3D.new()
			mi.mesh = pm
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = tile_center(ix, iz) - global_position + Vector3.UP * 0.025
			add_child(mi)
	# Bolts that stand up off an arcing tile and jump about: electricity you
	# can read from any angle, not just from above.
	var bolt_mat := StandardMaterial3D.new()
	bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bolt_mat.albedo_color = Color(0.75, 0.9, 1.0)
	for i in cells.x * cells.y * BOLTS_PER_TILE:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.035, 1.0, 0.035)
		b.mesh = bm
		b.material_override = bolt_mat
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.visible = false
		add_child(b)
		_bolts.append(b)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.4, 0.85, 1.0)
	_light.omni_range = maxf(cells.x, cells.y) * cell * 0.8 + 3.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3.UP * 1.2
	add_child(_light)

func _apply() -> void:
	var into := fposmod(_t, WARN_TIME + ZAP_TIME)
	var zap := into >= WARN_TIME
	for iz in cells.y:
		for ix in cells.x:
			var g := 0.0
			match tile_state(ix, iz):
				Tile.WARN:
					g = clampf(into / WARN_TIME, 0.0, 1.0)
				Tile.ZAP:
					g = 2.0
			_mats[iz * cells.x + ix].set_shader_parameter("glow", g)
			var arcing := g > 1.5
			for k in BOLTS_PER_TILE:
				var b := _bolts[(iz * cells.x + ix) * BOLTS_PER_TILE + k]
				b.visible = arcing
				if arcing and randf() < 0.5: # jump to a new spot most ticks
					var h := randf_range(0.4, 1.1)
					var c := tile_center(ix, iz) - global_position
					b.position = c + Vector3(randf_range(-0.4, 0.4) * cell, h * 0.5, randf_range(-0.4, 0.4) * cell)
					b.scale = Vector3(1.0, h, 1.0)
					b.rotation = Vector3(randf_range(-0.35, 0.35), randf() * TAU, randf_range(-0.35, 0.35))
	_light.light_energy = (3.0 + randf() * 2.0) if zap else 0.6 * into / WARN_TIME

func _physics_process(delta: float) -> void:
	_t += delta
	var g := active_group()
	var zap := fposmod(_t, WARN_TIME + ZAP_TIME) >= WARN_TIME
	if g != _group:
		_group = g
		_zapping = false
		AudioBus.play_synth_at("charge", global_position, -8.0, 1.3)
		warning.emit(g)
	if zap and not _zapping:
		_zapping = true
		_tick = 0.0
		AudioBus.play_synth_at("radio_static", global_position, -6.0, 1.6)
		zapped.emit(g)
	_apply()
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return
	var local := pl.global_position - global_position
	var half := Vector2(cells.x, cells.y) * cell * 0.5
	if absf(local.x) <= half.x + TEACH_REACH and absf(local.z) <= half.y + TEACH_REACH:
		GameState.teach_once("shock_floor", TEACH_TEXT)
	if not zap:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	var t := tile_at(pl.global_position)
	var dy := pl.global_position.y - global_position.y
	if t.x < 0 or dy > FEET_REACH or dy < -0.5 or tile_state(t.x, t.y) != Tile.ZAP:
		return
	_tick = TICK
	var php: Node = pl.get_node_or_null("Damageable")
	if php:
		php.apply_damage(damage, self, false, pl.global_position, true)
	AudioBus.play_synth_at("hit_tick", pl.global_position, -2.0, 1.8)
