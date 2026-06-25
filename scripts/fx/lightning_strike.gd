class_name LightningStrike
extends Node3D
## A brief lightning-strike VFX (shaders/lightning.gdshader): a few crossed
## vertical jagged bolts that flash bright blue-white, light the area, then fade
## out and free themselves. Drop one at a point to punctuate a boss arrival:
##   var s := LightningStrike.new(); parent.add_child(s); s.global_position = pos

const SHADER := preload("res://shaders/lightning.gdshader")

@export var height: float = 12.0
@export var color: Color = Color(0.55, 0.72, 1.0)
@export var lifetime: float = 0.75
@export var bolts: int = 4

func _ready() -> void:
	var col := Vector3(color.r, color.g, color.b)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.0
	light.omni_range = height * 1.3
	light.shadow_enabled = false
	light.position = Vector3(0, height * 0.4, 0)
	add_child(light)
	# Flash the light bright, then decay over the lifetime.
	var lt := create_tween()
	lt.tween_property(light, "light_energy", 7.0, 0.06)
	lt.tween_property(light, "light_energy", 0.0, lifetime)

	for i in bolts:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.orientation = PlaneMesh.FACE_Z   # stand the quad up (vertical bolt)
		pm.size = Vector2(height * 0.4, height)
		mi.mesh = pm
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("Effect_Color", col)
		mat.set_shader_parameter("Main_Color", Vector3(1, 1, 1))
		mat.set_shader_parameter("Emission_Power", 4.5)
		mat.set_shader_parameter("Speed", randf_range(7.0, 11.0))
		mat.set_shader_parameter("Y_Size", 4.0)
		mat.set_shader_parameter("X_Size", randf_range(0.8, 1.4))
		mi.material_override = mat
		mi.position = Vector3(0, height * 0.5, 0)
		mi.rotation.y = float(i) / float(bolts) * PI + randf() * 0.5  # cross them
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		# Fade the whole bolt out (Effect_Color drives albedo, emission AND alpha).
		var bt := create_tween()
		bt.tween_interval(0.1)
		bt.tween_property(mat, "shader_parameter/Effect_Color", Vector3.ZERO, lifetime - 0.1) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	if has_node("/root/AudioBus"):
		var ab := get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("overlord_glitch", global_position, 1.0, 0.7)

	await get_tree().create_timer(lifetime + 0.15).timeout
	queue_free()
