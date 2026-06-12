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

var _played: bool = false
var _screen_mat: StandardMaterial3D

func _ready() -> void:
	collision_layer = 64
	collision_mask = 2 # player
	body_entered.connect(_on_body_entered)
	_build_visual()

func _build_visual() -> void:
	var pillar := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.5, 1.3, 0.5)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.2, 0.22, 0.25)
	bmat.metallic = 0.7
	bmat.roughness = 0.35
	pm.material = bmat
	pillar.mesh = pm
	pillar.position = Vector3(0, 0.65, 0)
	add_child(pillar)
	# Slowly pulsing holo-cube hovering above: "data here".
	var cube := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.28, 0.28, 0.28)
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_screen_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.75)
	_screen_mat.emission_enabled = true
	_screen_mat.emission = accent
	_screen_mat.emission_energy_multiplier = 2.0
	cm.material = _screen_mat
	cube.mesh = cm
	cube.position = Vector3(0, 1.62, 0)
	add_child(cube)
	var tw := cube.create_tween().set_loops()
	tw.tween_property(cube, "rotation:y", TAU, 4.0).as_relative()
	var light := OmniLight3D.new()
	light.light_color = accent
	light.light_energy = 1.4
	light.omni_range = 4.0
	light.shadow_enabled = false
	light.position = Vector3(0, 1.6, 0)
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
	# Dim the beacon — log retrieved.
	_screen_mat.emission_energy_multiplier = 0.5
	_screen_mat.albedo_color.a = 0.3
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
