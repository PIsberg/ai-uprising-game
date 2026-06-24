class_name LoreTerminal
extends Area3D
## A recovered data log. Walk up to it and it plays once: the faction's voice
## reads the log through the damaged-comms Broadcast bus while the same text
## types out across the bottom of the screen. Pure worldbuilding — no task,
## no reward beyond knowing what these machines think of us.
##
## Builds its own visuals (white-teal "archive pillar", distinct from the
## hostile consoles) and its own transient CanvasLayer for the typed text.

@export var log_id: String = "" ## assets/audio/lore/<log_id>.wav
@export var title: String = "RECOVERED LOG"
@export var text: String = ""
@export var accent: Color = Color(0.55, 0.95, 0.9)

const CPS := 28.0 # typed characters per second, roughly matching speech pace
const CRT_SHADER := preload("res://shaders/crt_screen.gdshader")

var _played: bool = false
var _holo_mat: StandardMaterial3D
var _screen_mat: ShaderMaterial

func _ready() -> void:
	collision_layer = 64
	collision_mask = 2 # player
	body_entered.connect(_on_body_entered)
	_build_visual()

func _build_visual() -> void:
	# A proper archive console: chamfered pedestal, monitor on a stand with a
	# live CRT screen, plus the hovering holo-cube beacon so it reads as "data"
	# from across the room.
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.16, 0.18, 0.21)
	plastic.metallic = 0.6
	plastic.roughness = 0.4

	var pedestal := MeshInstance3D.new()
	var pm := BeveledBoxMesh.new()
	pm.size = Vector3(0.5, 0.95, 0.42)
	pm.bevel = 0.025
	pm.material = plastic
	pedestal.mesh = pm
	pedestal.position = Vector3(0, 0.475, 0)
	add_child(pedestal)

	# Monitor: stand neck + chamfered housing + emissive shader screen, tilted
	# back a touch. Screen faces +Z; the holo-cube above flags it from any side.
	var neck := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.05, 0.18, 0.05)
	nm.material = plastic
	neck.mesh = nm
	neck.position = Vector3(0, 1.05, 0)
	add_child(neck)

	var monitor := Node3D.new()
	monitor.position = Vector3(0, 1.16, 0)
	monitor.rotation = Vector3(deg_to_rad(-10.0), 0.0, 0.0)
	add_child(monitor)

	var bezel := StandardMaterial3D.new()
	bezel.albedo_color = Color(0.04, 0.045, 0.05)
	bezel.metallic = 0.25
	bezel.roughness = 0.55
	var housing := MeshInstance3D.new()
	var hm := BeveledBoxMesh.new()
	hm.size = Vector3(0.66, 0.5, 0.07)
	hm.bevel = 0.02
	hm.material = bezel
	housing.mesh = hm
	housing.position = Vector3(0, 0.22, 0)
	monitor.add_child(housing)

	var screen := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.56, 0.4)
	_screen_mat = ShaderMaterial.new()
	_screen_mat.shader = CRT_SHADER
	_screen_mat.set_shader_parameter("screen_color", Vector3(accent.r, accent.g, accent.b))
	_screen_mat.set_shader_parameter("bg_color", Vector3(accent.r * 0.06, accent.g * 0.07, accent.b * 0.08))
	_screen_mat.set_shader_parameter("brightness", 1.6)
	_screen_mat.set_shader_parameter("glow", 1.5)
	_screen_mat.set_shader_parameter("scroll_speed", 0.7)
	_screen_mat.set_shader_parameter("content_density", 0.7)
	qm.material = _screen_mat
	screen.mesh = qm
	screen.position = Vector3(0, 0.22, 0.04)
	monitor.add_child(screen)

	# The screen spills its teal light into the room (4.7 AreaLight3D, HIGH+).
	var glow := ScreenGlow.new()
	glow.glow_color = accent
	glow.glow_energy = 2.2
	glow.glow_size = Vector2(0.56, 0.4)
	glow.glow_range = 4.0
	glow.position = Vector3(0, 0.22, 0.06)
	glow.rotation_degrees = Vector3(0, 180, 0)
	monitor.add_child(glow)

	# Slowly pulsing holo-cube hovering above: "data here".
	var cube := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.28, 0.28, 0.28)
	_holo_mat = StandardMaterial3D.new()
	_holo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_holo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_holo_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.75)
	_holo_mat.emission_enabled = true
	_holo_mat.emission = accent
	_holo_mat.emission_energy_multiplier = 2.0
	cm.material = _holo_mat
	cube.mesh = cm
	cube.position = Vector3(0, 1.92, 0)
	add_child(cube)
	var tw := cube.create_tween().set_loops()
	tw.tween_property(cube, "rotation:y", TAU, 4.0).as_relative()
	var light := OmniLight3D.new()
	light.light_color = accent
	light.light_energy = 1.4
	light.omni_range = 4.0
	light.shadow_enabled = false
	light.position = Vector3(0, 1.9, 0)
	add_child(light)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.0, 2.2, 3.0)
	cs.shape = bs
	cs.position = Vector3(0, 1.1, 0)
	add_child(cs)

func _on_body_entered(body: Node) -> void:
	if _played or not body.is_in_group("player"):
		return
	_played = true
	# Dim the beacon — log retrieved. Settle the screen and fade the holo-cube.
	_screen_mat.set_shader_parameter("brightness", 0.7)
	_screen_mat.set_shader_parameter("glow", 0.6)
	_screen_mat.set_shader_parameter("scroll_speed", 0.0)
	_holo_mat.emission_energy_multiplier = 0.5
	_holo_mat.albedo_color.a = 0.3
	AudioBus.play_lore(log_id)
	_show_text()

## Transient bottom-screen panel that types the log out, then fades.
func _show_text() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position = Vector2(-380, -190)
	panel.custom_minimum_size = Vector2(760, 0)
	panel.self_modulate = Color(1, 1, 1, 0.92)
	layer.add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var head := Label.new()
	head.text = "▸ %s" % title
	head.add_theme_color_override("font_color", accent)
	vbox.add_child(head)
	var body_lbl := Label.new()
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 0.94))
	vbox.add_child(body_lbl)
	# Type-on, hold, fade, cleanup — all from one tween.
	var chars := text.length()
	var tw := create_tween()
	tw.tween_method(func(n: float): body_lbl.text = text.substr(0, int(n)),
		0.0, float(chars), chars / CPS)
	tw.tween_interval(3.5)
	tw.tween_property(panel, "self_modulate:a", 0.0, 1.2)
	tw.tween_callback(layer.queue_free)
