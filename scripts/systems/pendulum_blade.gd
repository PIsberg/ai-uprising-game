class_name PendulumBlade
# @lat: [[level-system#Pendulum Blades]]
extends Node3D
## A swinging blade on a gantry across a walkway. Two posts stand either side
## (`width` apart, across the path) under a crossbeam `pivot_h` up; a blade on
## an arm `arm` long hangs from its middle and swings across the path,
## `amplitude` degrees either side, once every `period` seconds. Swinging
## through the bottom it sweeps the whole walkway at body height, so there is
## no going round it: you time it. The gantry tells you when: a big sign on the
## crossbeam reads GO (green) when the blade will not touch where you stand for
## the next LOOKAHEAD seconds and WAIT (red) when it will, with lamps on both
## posts to match, and a striped band on the floor marks the cut. A blade that
## catches the player costs `damage` and throws them along the path. Robots are
## not hit. The first gantry a player walks up to teaches the rule once per run.
## Def key `pendulums` (level_builder `_build_pendulums`).
## tests/pendulum_blade_probe.

@export var width: float = 4.0          ## m between the posts (across the path)
@export var path_axis: String = "z"     ## world axis the path runs along
@export var pivot_h: float = 4.0        ## m from the walkway to the pivot
@export var arm: float = 3.25           ## m from the pivot to the blade's centre
@export var amplitude: float = 70.0     ## degrees either side of straight down
@export var period: float = 2.6         ## s for a full swing there and back
@export var phase: float = 0.0          ## 0..1 of a period
@export var damage: float = 30.0

const BLADE_R := 0.75
const BODY_R := 0.35
const SLICE := 0.45            ## m either side of the swing plane that is in the cut
const LOOKAHEAD := 0.5         ## s ahead the GO sign promises a clear swing
const HIT_GAP := 0.8
const SHOVE := 6.0
const TEACH_REACH := 7.0
const TEACH_TEXT := "SWINGING BLADE: cross when its sign says GO. WAIT means it is about to sweep through."

var _t := 0.0
var _cool := 0.0
var _go := true
var _arm_pivot: Node3D
var _sign: Label3D
var _lamp_mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("hazard")
	_build()
	_pose()

func _path() -> Vector3:
	return Vector3.BACK if path_axis == "z" else Vector3.RIGHT

func _across() -> Vector3:
	return Vector3.RIGHT if path_axis == "z" else Vector3.BACK

## Yaw that turns local +X onto _across() (and the swing plane across the path).
func _yaw() -> float:
	return 0.0 if path_axis == "z" else -PI * 0.5

## The blade's swing angle (degrees) at time `t`.
func angle_at(t: float) -> float:
	return amplitude * sin(TAU * (t / period + phase))

## The blade's centre, relative to the node, at angle `deg`: (across, up).
func blade_offset(deg: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(sin(a) * arm, pivot_h - cos(a) * arm)

## Whether the blade at `deg` reaches a body standing `across` m off the
## path's centre line with its feet `feet` m up and `tall` m tall (the body is
## taken to be in the swing plane).
func reaches(deg: float, across: float, feet: float, tall: float) -> bool:
	var c := blade_offset(deg)
	var dy := clampf(c.y, feet, feet + tall) - c.y
	return Vector2(across - c.x, dy).length() < BLADE_R + BODY_R * 0.8

## GO: the blade will not reach `across` at standing height for LOOKAHEAD s.
func clear_for(across: float, from_t: float) -> bool:
	var k := 0.0
	while k <= LOOKAHEAD:
		if reaches(angle_at(from_t + k), across, 0.0, 1.8):
			return false
		k += 0.05
	return true

## Whether the sign reads GO now (for the player's spot, or the centre line).
func is_go() -> bool:
	return _go

func sign_text() -> String:
	return _sign.text

func _build() -> void:
	var across := _across()
	var yaw := _yaw()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.16, 0.15, 0.15)
	steel.metallic = 0.7
	# Posts reach down past the walkway (into whatever it crosses) and up to
	# the crossbeam; neither is solid.
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, pivot_h + 3.3, 0.3)
		post.mesh = bm
		post.material_override = steel
		post.position = across * (side * width * 0.5) + Vector3.UP * ((pivot_h + 0.3) - (pivot_h + 3.3) * 0.5)
		add_child(post)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(width + 0.3, 0.35, 0.35)
	beam.mesh = bb
	beam.material_override = steel
	beam.position = Vector3.UP * (pivot_h + 0.15)
	beam.rotation.y = yaw
	add_child(beam)
	# The arm and blade swing in the plane across the path.
	_arm_pivot = Node3D.new()
	_arm_pivot.position = Vector3.UP * pivot_h
	add_child(_arm_pivot)
	var rod := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.12, arm, 0.12)
	rod.mesh = rm
	rod.material_override = steel
	rod.position = Vector3.DOWN * arm * 0.5
	_arm_pivot.add_child(rod)
	var blade := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = BLADE_R
	cm.bottom_radius = BLADE_R
	cm.height = 0.05
	cm.radial_segments = 32
	blade.mesh = cm
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.38, 0.39, 0.42)
	disc_mat.metallic = 1.0
	disc_mat.roughness = 0.3
	blade.material_override = disc_mat
	blade.rotation.x = PI * 0.5 # disc face across the path: it sweeps edge-on
	blade.position = Vector3.DOWN * arm
	_arm_pivot.add_child(blade)
	# A glowing cutting edge and teeth, so it reads as a blade, not a plate.
	var hot := StandardMaterial3D.new()
	hot.albedo_color = Color(1.0, 0.45, 0.1)
	hot.emission_enabled = true
	hot.emission = Color(1.0, 0.4, 0.08)
	hot.emission_energy_multiplier = 2.5
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = BLADE_R - 0.07
	tm.outer_radius = BLADE_R
	rim.mesh = tm
	rim.material_override = hot
	rim.rotation.x = PI * 0.5
	rim.position = Vector3.DOWN * arm
	_arm_pivot.add_child(rim)
	for i in 16:
		var a := TAU * float(i) / 16.0
		var tooth := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.14, 0.14, 0.06)
		tooth.mesh = tb
		tooth.material_override = hot
		tooth.position = Vector3.DOWN * arm + Vector3(cos(a), sin(a), 0.0) * BLADE_R
		tooth.rotation.z = a + PI * 0.25
		_arm_pivot.add_child(tooth)
	# The cut, striped on the floor.
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float s = step(0.5, fract((wp.x + wp.z) * 1.4));
	ALBEDO = mix(vec3(0.03), vec3(0.95, 0.66, 0.05) * 0.8, s);
}
"""
	var band_mat := ShaderMaterial.new()
	band_mat.shader = sh
	var pm := PlaneMesh.new()
	pm.size = Vector2(width, SLICE * 2.0)
	var band := MeshInstance3D.new()
	band.mesh = pm
	band.material_override = band_mat
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	band.position = Vector3.UP * 0.03
	band.rotation.y = yaw
	add_child(band)
	# GO / WAIT: lamps on both posts and a sign on the crossbeam.
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in [-1.0, 1.0]:
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.4
		lamp.mesh = sm
		lamp.material_override = _lamp_mat
		lamp.position = across * (side * width * 0.5) + Vector3.UP * 2.3
		add_child(lamp)
	_sign = Label3D.new()
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.font_size = 72
	_sign.pixel_size = 0.007
	_sign.outline_size = 12
	_sign.outline_modulate = Color(0, 0, 0, 0.9)
	_sign.position = Vector3.UP * (pivot_h + 0.75)
	add_child(_sign)
	_set_go(true)

func _set_go(go: bool) -> void:
	_go = go
	var col := Color(0.2, 1.0, 0.35) if go else Color(1.0, 0.15, 0.1)
	_lamp_mat.albedo_color = col
	_sign.text = "GO" if go else "WAIT"
	_sign.modulate = col * 1.6 # HDR: Label3D takes fog

func _pose() -> void:
	# YXZ order: swing about the path (local Z), then turn the plane across it.
	_arm_pivot.rotation = Vector3(0.0, _yaw(), deg_to_rad(angle_at(_t)))

func _physics_process(delta: float) -> void:
	var prev := angle_at(_t)
	_t += delta
	_cool = maxf(0.0, _cool - delta)
	_pose()
	var now := angle_at(_t)
	if signf(prev) != signf(now):
		AudioBus.play_synth_at("rotor_whir", global_position + Vector3.UP * (pivot_h - arm), -2.0, 0.5)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var across_m := 0.0
	if pl != null:
		var rel := pl.global_position - global_position
		across_m = rel.dot(_across())
		var along := rel.dot(_path())
		if absf(along) <= TEACH_REACH and absf(across_m) <= width * 0.5 + TEACH_REACH:
			GameState.teach_once("pendulum", TEACH_TEXT)
		var tall := 1.0 if pl.get("_is_crouching") == true else 1.8
		if _cool <= 0.0 and absf(along) <= SLICE and reaches(now, across_m, rel.y, tall):
			_cool = HIT_GAP
			var php: Node = pl.get_node_or_null("Damageable")
			if php:
				php.apply_damage(damage, self, false, global_position + Vector3.UP * (pivot_h - arm), true)
			if "velocity" in pl:
				pl.velocity = _path() * (signf(along) if along != 0.0 else 1.0) * SHOVE + Vector3.UP * 3.0
			AudioBus.play_synth_at("impact_metal", pl.global_position, 2.0, 1.2)
		across_m = clampf(across_m, -width * 0.5, width * 0.5)
	var go := clear_for(across_m, _t)
	if go != _go:
		_set_go(go)

## The death screen's "Taken down by" name and its tip key (player.gd reads it
## off any damage source that has it; hud.gd DEATH_TIPS).
func _kill_label() -> String:
	return "PENDULUM BLADE"
