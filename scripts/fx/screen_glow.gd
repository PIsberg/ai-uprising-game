class_name ScreenGlow
extends AreaLight3D
## Makes an emissive screen/sign actually spill colored light into the room
## (Godot 4.7 AreaLight3D). Add it as a child of the screen surface and orient
## its local -Z toward the room (the screen's outward normal) — that's the
## direction a rect area light emits. Pure cosmetic fill: no shadows (cheap),
## gated to HIGH/ULTRA via the same "Soft Area Lights" setting as the interior
## luminaires, so it removes itself on LOW/MEDIUM.

@export var glow_color: Color = Color(0.3, 1.0, 0.5)
@export var glow_energy: float = 2.2     ## raw (non-normalized) intensity
@export var glow_size: Vector2 = Vector2(0.7, 0.5)
@export var glow_range: float = 5.0

func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs and gs.has_method("use_area_lights") and not gs.use_area_lights():
		queue_free()
		return
	light_color = glow_color
	light_energy = glow_energy
	area_size = glow_size
	area_normalize_energy = false
	area_range = glow_range
	light_specular = 0.4
	shadow_enabled = false
