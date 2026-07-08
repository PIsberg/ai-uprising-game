class_name OverloadDirector
extends Node
## Drives a level's climactic OVERLOAD. When a trigger objective completes, the
## whole arena snaps to RED ALERT: every static light bleeds to emergency red and
## strobes, a klaxon loops, and the core erupts with periodic blasts + screen
## shake — the set-piece that turns a survive phase into a memorable finish.
##
## Reusable, opt-in via the level def:
##   def["overload"] = {"trigger_label": String, "core": Vector3}
## trigger_label matches the objective whose completion ignites it (e.g. the
## weights-exfil task); core is where the blasts erupt.

var trigger_label: String = ""
var core_pos: Vector3 = Vector3.ZERO

var _lights: Array = []          # [{node, color, energy}] captured static lights
var _armed := false
var _t := 0.0
var _blast_t := 0.0
var _core_glow: OmniLight3D
var _core_orb: MeshInstance3D
var _env: Environment          # the level's WorldEnvironment (bled to red on ignite)
var _amb0: Color               # base ambient, for the strobe

func setup(cfg: Dictionary) -> void:
	trigger_label = str(cfg.get("trigger_label", ""))
	core_pos = cfg.get("core", Vector3.ZERO)

func _ready() -> void:
	# Capture the level's static lights once the build has settled.
	await get_tree().create_timer(0.6).timeout
	var root := get_parent()
	if root:
		for l in root.find_children("*", "OmniLight3D", true, false):
			var ol := l as OmniLight3D
			_lights.append({"node": ol, "color": ol.light_color, "energy": ol.light_energy})
		var we := root.find_children("*", "WorldEnvironment", true, false)
		if not we.is_empty():
			_env = (we[0] as WorldEnvironment).environment
			if _env:
				_amb0 = _env.ambient_light_color
	if GameState.has_signal("task_completed"):
		GameState.task_completed.connect(_on_task_completed)

func _on_task_completed(label: String) -> void:
	if _armed:
		return
	if trigger_label == "" or label == trigger_label:
		_ignite()

func _ignite() -> void:
	_armed = true
	AudioBus.play_synth_ui("eas_alert", -3.0)
	var red := Color(1.0, 0.16, 0.1)
	for e in _lights:
		var l = e["node"]
		if is_instance_valid(l):
			create_tween().tween_property(l, "light_color", red, 0.6)
	# Bleed the whole environment to red alert — this is what actually flips the
	# hall's read from green to emergency, since ambient/fog dominate the look.
	if _env:
		_amb0 = Color(0.55, 0.11, 0.08)   # strobe target base (see _process)
		create_tween().tween_property(_env, "ambient_light_color", _amb0, 0.7)
		create_tween().tween_property(_env, "fog_light_color", Color(0.6, 0.13, 0.09), 0.7)
	# A swelling red core: a bright emissive orb + light that grows and throbs.
	var scene := get_tree().current_scene
	if scene:
		_core_orb = MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 1.2; sm.height = 2.4
		_core_orb.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.3, 0.12, 0.85)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.25, 0.1)
		m.emission_energy_multiplier = 8.0
		_core_orb.material_override = m
		_core_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(_core_orb)
		_core_orb.global_position = core_pos + Vector3(0, 2.2, 0)
		_core_glow = OmniLight3D.new()
		_core_glow.light_color = Color(1.0, 0.28, 0.1)
		_core_glow.light_energy = 9.0
		_core_glow.omni_range = 32.0
		_core_orb.add_child(_core_glow)

func _process(delta: float) -> void:
	if not _armed:
		return
	_t += delta
	# Klaxon strobe: pulse every captured light off its base energy.
	var pulse := 0.55 + 0.45 * absf(sin(_t * 5.0))
	for e in _lights:
		var l = e["node"]
		if is_instance_valid(l):
			(l as OmniLight3D).light_energy = float(e["energy"]) * pulse
	if is_instance_valid(_core_orb):
		var s := 1.0 + 0.18 * sin(_t * 7.0)
		_core_orb.scale = Vector3(s, s, s)
	# Periodic core detonation: blast FX + shake + a fresh klaxon blip.
	_blast_t -= delta
	if _blast_t <= 0.0:
		_blast_t = 2.3
		_core_blast()

func _core_blast() -> void:
	AudioBus.play_synth_at("explosion", core_pos, 4.0, 0.55)
	AudioBus.play_synth_ui("eas_alert", -10.0)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(0.7)
	# An expanding red shock ring at the core.
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.3; tm.outer_radius = 0.7
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.35, 0.12, 0.9)
	mat.emission_enabled = true; mat.emission = Color(1.0, 0.3, 0.1)
	mat.emission_energy_multiplier = 6.0
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(ring)
	ring.global_position = Vector3(core_pos.x, 0.15, core_pos.z)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(14, 1, 14), 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(ring.queue_free)
