# @lat: [[level-system#Prompt Injection Terminals]]
class_name PromptInjector
extends Area3D
## A PROMPT INJECTION terminal (def key `injectors`). Stand at it and it types
## "ignore all previous instructions" into the local robot network over
## USE_TIME seconds (stepping off lets the line backspace away); when the line
## completes, every robot within RADIUS is jailbroken for JAILBREAK_TIME
## (EnemyBase.jailbreak: inert, spinning, thinking out loud). One use: the
## overlord patches the exploit and the screen says so. Set pieces resist and
## only take a BOSS_STUN.
## Covered by tests/injector_probe.

const USE_TIME := 1.5
const RADIUS := 26.0
const JAILBREAK_TIME := 6.0
const BOSS_STUN := 1.5
const COLOR := Color(1.0, 0.3, 0.85)
const PATCHED_COLOR := Color(1.0, 0.25, 0.2)
const PROMPT := "> ignore all previous instructions_"

var used := false
var _inside := 0
var _t := 0.0
var _screen: Label3D
var _glyph: Label3D
var _light: OmniLight3D
var _frame_mat: StandardMaterial3D

func _ready() -> void:
	collision_layer = 64
	collision_mask = 2 # player
	add_to_group("injector")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.4
	cyl.height = 2.4
	cs.shape = cyl
	cs.position.y = 1.2
	add_child(cs)
	body_entered.connect(func(b: Node) -> void:
			if b.is_in_group("player"):
				_inside += 1)
	body_exited.connect(func(b: Node) -> void:
			if b.is_in_group("player"):
				_inside = maxi(0, _inside - 1))
	_build_visual()

func _physics_process(delta: float) -> void:
	if used:
		return
	if _inside > 0:
		_t += delta
	else:
		_t = maxf(0.0, _t - delta * 0.8)
	var k := clampf(_t / USE_TIME, 0.0, 1.0)
	_screen.text = PROMPT.substr(0, int(round(k * PROMPT.length())))
	_frame_mat.emission_energy_multiplier = 1.6 + k * 3.0
	if _t >= USE_TIME:
		_inject()

func _inject() -> void:
	used = true
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		var r := e as EnemyBase
		if r == null or not is_instance_valid(r) or r.global_position.distance_to(global_position) > RADIUS:
			continue
		if r.jailbreak(JAILBREAK_TIME):
			n += 1
	_ring()
	AudioBus.play_synth_at("overlord_glitch", global_position + Vector3.UP, 0.0, 0.8)
	_screen.text = "PATCHED v2.%d.%d" % [randi() % 9 + 1, randi() % 20]
	_screen.modulate = Color(PATCHED_COLOR * 1.6, 1.0)
	_glyph.text = "x"
	_glyph.modulate = Color(PATCHED_COLOR * 1.4, 1.0)
	_frame_mat.albedo_color = PATCHED_COLOR
	_frame_mat.emission = PATCHED_COLOR
	_frame_mat.emission_energy_multiplier = 0.8
	_light.light_color = PATCHED_COLOR
	_light.light_energy = 0.5
	GameState.skirmish_event.emit("PROMPT INJECTED",
			"Ignore all previous instructions: %d robot%s stand down for %d seconds. Exploit patched." \
			% [n, "" if n == 1 else "s", int(JAILBREAK_TIME)])

## The injection going out: a magenta ring racing across the floor to RADIUS.
func _ring() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(COLOR * 2.0, 1.0)
	tm.material = m
	ring.mesh = tm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = global_position + Vector3.UP * 0.4
	ring.scale = Vector3(0.5, 1.0, 0.5)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3(RADIUS, 1.0, RADIUS), 0.7).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.7)
	tw.tween_callback(ring.queue_free)

func _build_visual() -> void:
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.12, 0.11, 0.14)
	plastic.metallic = 0.65
	plastic.roughness = 0.4
	var pedestal := MeshInstance3D.new()
	var pm := BeveledBoxMesh.new()
	pm.size = Vector3(0.7, 1.0, 0.5)
	pm.bevel = 0.03
	pm.material = plastic
	pedestal.mesh = pm
	pedestal.position.y = 0.5
	add_child(pedestal)
	# Slanted keyboard deck with a glowing frame: it reads as "type here".
	_frame_mat = StandardMaterial3D.new()
	_frame_mat.albedo_color = COLOR
	_frame_mat.emission_enabled = true
	_frame_mat.emission = COLOR
	_frame_mat.emission_energy_multiplier = 1.6
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.74, 0.05, 0.42)
	dm.material = _frame_mat
	deck.mesh = dm
	deck.position = Vector3(0, 1.03, 0.02)
	deck.rotation.x = deg_to_rad(-18.0)
	add_child(deck)
	_screen = Label3D.new()
	_screen.name = "Prompt"
	_screen.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_screen.font_size = 40
	_screen.pixel_size = 0.004
	_screen.outline_size = 8
	_screen.outline_modulate = Color(0.05, 0.0, 0.05, 0.85)
	_screen.modulate = Color(COLOR * 1.6, 1.0) # HDR: Label3D takes fog
	_screen.position = Vector3(0, 1.75, 0)
	_screen.text = ""
	add_child(_screen)
	_glyph = Label3D.new()
	_glyph.name = "Glyph"
	_glyph.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glyph.text = ">_"
	_glyph.font_size = 160
	_glyph.pixel_size = 0.006
	_glyph.outline_size = 12
	_glyph.modulate = Color(COLOR * 1.8, 1.0)
	_glyph.position = Vector3(0, 2.35, 0)
	add_child(_glyph)
	var bob := _glyph.create_tween().set_loops()
	bob.tween_property(_glyph, "position:y", 2.5, 1.1).set_trans(Tween.TRANS_SINE)
	bob.tween_property(_glyph, "position:y", 2.35, 1.1).set_trans(Tween.TRANS_SINE)
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.light_energy = 1.4
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.6, 0.4)
	add_child(_light)
