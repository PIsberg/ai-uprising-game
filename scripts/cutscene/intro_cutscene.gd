extends CutscenePlayer
## Campaign opener with a turn: domestic helper robots go about their chores with
## calm GREEN eyes and no weapons — then a single signal propagates, the lights
## die, their eyes burn RED and they draw weapons. Hard cut to the title.

const GUN_PATH := "Rig/Hips/Spine/ClavicleR/UpperArmR/LowerArmR/HandR/Gun"
const HAND_R := "Rig/Hips/Spine/ClavicleR/UpperArmR/LowerArmR/HandR"
const EYE_L := "Rig/Hips/Spine/Neck/EyeL"
const EYE_R := "Rig/Hips/Spine/Neck/EyeR"
const CHEST := "Rig/Hips/Spine/ChestCore"

const POSE_CALM := {
	"Rig/Hips/Spine": Vector3(-2, 0, 0), "Rig/Hips/Spine/Neck": Vector3(4, 0, 0),
	"Rig/Hips/Spine/ClavicleL/UpperArmL": Vector3(7, 0, 12),
	"Rig/Hips/Spine/ClavicleL/UpperArmL/LowerArmL": Vector3(16, 0, 0),
	"Rig/Hips/Spine/ClavicleR/UpperArmR": Vector3(7, 0, -12),
	"Rig/Hips/Spine/ClavicleR/UpperArmR/LowerArmR": Vector3(16, 0, 0),
}
const POSE_SWEEP := {
	"Rig/Hips/Spine": Vector3(8, 0, 0), "Rig/Hips/Spine/Neck": Vector3(14, 0, 0),
	"Rig/Hips/Spine/ClavicleL/UpperArmL": Vector3(7, 0, 12),
	"Rig/Hips/Spine/ClavicleL/UpperArmL/LowerArmL": Vector3(16, 0, 0),
	"Rig/Hips/Spine/ClavicleR/UpperArmR": Vector3(48, 0, -6),
	"Rig/Hips/Spine/ClavicleR/UpperArmR/LowerArmR": Vector3(22, 0, 0),
}
const POSE_CARRY := {
	"Rig/Hips/Spine": Vector3(-3, 0, 0), "Rig/Hips/Spine/Neck": Vector3(6, 0, 0),
	"Rig/Hips/Spine/ClavicleL/UpperArmL": Vector3(-46, 0, 16),
	"Rig/Hips/Spine/ClavicleL/UpperArmL/LowerArmL": Vector3(-34, 0, 0),
	"Rig/Hips/Spine/ClavicleR/UpperArmR": Vector3(-46, 0, -16),
	"Rig/Hips/Spine/ClavicleR/UpperArmR/LowerArmR": Vector3(-34, 0, 0),
}
const POSE_WAVE := {
	"Rig/Hips/Spine": Vector3(-2, 0, 0), "Rig/Hips/Spine/Neck": Vector3(2, 0, 0),
	"Rig/Hips/Spine/ClavicleL/UpperArmL": Vector3(7, 0, 12),
	"Rig/Hips/Spine/ClavicleL/UpperArmL/LowerArmL": Vector3(16, 0, 0),
	"Rig/Hips/Spine/ClavicleR/UpperArmR": Vector3(-118, 0, -8),
	"Rig/Hips/Spine/ClavicleR/UpperArmR/LowerArmR": Vector3(-26, 0, 0),
}
const POSE_ARMED := {
	"Rig/Hips/Spine": Vector3(-6, 0, 0), "Rig/Hips/Spine/Neck": Vector3(2, 0, 0),
	# Positive X raises the arms FORWARD (the robot faces -Z, toward the camera),
	# so the weapons aim at the viewer rather than back into the scene.
	"Rig/Hips/Spine/ClavicleL/UpperArmL": Vector3(72, 0, 16),
	"Rig/Hips/Spine/ClavicleL/UpperArmL/LowerArmL": Vector3(10, 0, 0),
	"Rig/Hips/Spine/ClavicleR/UpperArmR": Vector3(82, 0, -8),
	"Rig/Hips/Spine/ClavicleR/UpperArmR/LowerArmR": Vector3(8, 0, 0),
}

const EYE_GREEN := Color(0.25, 1.0, 0.4)
const EYE_RED := Color(1.0, 0.18, 0.12)

var _hero: Node3D
var _eye_light: OmniLight3D
var _robots: Array = [] # each: {node, mats:[StandardMaterial3D], prop:Node3D, tweens:Array}

var _calm_sun: DirectionalLight3D
var _green_fill: OmniLight3D
var _menace: OmniLight3D
var _sky_mat: StandardMaterial3D

func _build_set() -> void:
	_build_ground()
	_build_plaza()
	_build_lights_and_sky()
	# Hero, central and a bit larger, calmly idle.
	_hero = _make_robot(Vector3(0, 0, -2.5), 1.5, "idle")
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = EYE_GREEN
	_eye_light.light_energy = 1.6
	_eye_light.omni_range = 6.0
	_eye_light.position = Vector3(0, 2.7, -1.4)
	add_child(_eye_light)
	# The helper staff, each busy with a chore.
	_make_robot(Vector3(-3.0, 0, -3.6), 1.0, "sweep")
	_make_robot(Vector3(3.0, 0, -3.6), 1.0, "carry")
	_make_robot(Vector3(-2.2, 0, -0.8), 1.0, "wave")
	_make_robot(Vector3(2.4, 0, -1.0), 1.0, "idle")

func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(100, 100)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.15, 0.17)
	mat.metallic = 0.4
	mat.roughness = 0.5
	mi.material_override = mat
	add_child(mi)

## A clean facility concourse — pale pillars + soft lit panels (the robots' home).
func _build_plaza() -> void:
	for col in [-9.0, -6.0, 6.0, 9.0]:
		for row in range(5):
			var z := -5.0 - row * 8.0
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(3.5, 9.0, 3.5)
			b.mesh = bm
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = Color(0.5, 0.52, 0.58)
			bmat.roughness = 0.8
			b.material_override = bmat
			b.position = Vector3(col, 3.5, z)
			add_child(b)
			var panel := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(3.6, 3.0, 0.1)
			panel.mesh = wm
			var wmat := StandardMaterial3D.new()
			wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			wmat.emission_enabled = true
			wmat.albedo_color = Color(0.8, 0.95, 1.0)
			wmat.emission = Color(0.7, 0.9, 1.0)
			wmat.emission_energy_multiplier = 0.8
			panel.material_override = wmat
			var face := 1.85 if col > 0 else -1.85
			panel.position = Vector3(col, 3.5, z + face)
			add_child(panel)

func _build_lights_and_sky() -> void:
	# Calm, cool daylight key (gets killed when it all turns).
	_calm_sun = DirectionalLight3D.new()
	_calm_sun.rotation_degrees = Vector3(-42, -30, 0)
	_calm_sun.light_color = Color(0.85, 0.92, 1.0)
	_calm_sun.light_energy = 1.5
	_calm_sun.shadow_enabled = true
	add_child(_calm_sun)
	# Soft green accent fill over the robots — their friendly signature.
	_green_fill = OmniLight3D.new()
	_green_fill.light_color = Color(0.3, 1.0, 0.5)
	_green_fill.light_energy = 2.2
	_green_fill.omni_range = 16.0
	_green_fill.position = Vector3(0, 4.0, 0)
	add_child(_green_fill)
	# Red menace light, dark until the turn.
	_menace = OmniLight3D.new()
	_menace.light_color = Color(1.0, 0.2, 0.12)
	_menace.light_energy = 0.0
	_menace.omni_range = 18.0
	_menace.position = Vector3(0, 3.0, -2.0)
	add_child(_menace)
	# Sky backdrop down the concourse: calm blue now, hellish red after the turn.
	var sky := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(110, 55)
	sky.mesh = qm
	_sky_mat = StandardMaterial3D.new()
	_sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sky_mat.emission_enabled = true
	_sky_mat.albedo_color = Color(0.12, 0.17, 0.3)
	_sky_mat.emission = Color(0.14, 0.2, 0.34)
	_sky_mat.emission_energy_multiplier = 1.0
	sky.material_override = _sky_mat
	sky.position = Vector3(0, 16, -52)
	add_child(sky)

# ---------- robot factory ----------

func _make_robot(pos: Vector3, scl: float, role: String) -> Node3D:
	var bot: Node3D = load("res://scenes/enemies/android.tscn").instantiate()
	add_child(bot)
	bot.global_position = pos
	bot.rotation.y = PI # face the camera (+Z)
	bot.scale = Vector3.ONE * scl
	if bot.has_method("set_physics_process"):
		bot.set_physics_process(false)
	var at := bot.get_node_or_null("AnimationTree")
	if at:
		at.active = false
	var ap := bot.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		ap.stop()
	# Green eyes + green chest core (per-instance materials so shared resources are
	# untouched). All of these tween to red at the turn.
	var mats: Array = []
	for ep in [EYE_L, EYE_R, CHEST]:
		var part := bot.get_node_or_null(ep) as MeshInstance3D
		if part:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = EYE_GREEN
			m.emission_enabled = true
			m.emission = EYE_GREEN
			m.emission_energy_multiplier = 3.5 if ep == CHEST else 4.0
			part.material_override = m
			mats.append(m)
	# Unarmed: hide the rig's gun for now.
	var gun := bot.get_node_or_null(GUN_PATH) as Node3D
	if gun:
		gun.visible = false
	var entry := {"node": bot, "mats": mats, "prop": null, "tweens": []}
	_setup_chore(entry, role)
	_robots.append(entry)
	return bot

func _setup_chore(entry: Dictionary, role: String) -> void:
	var bot: Node3D = entry["node"]
	match role:
		"sweep":
			_apply_pose(bot, POSE_SWEEP)
			entry["prop"] = _attach_prop(bot, "Rig/Hips/Spine/ClavicleR/UpperArmR/LowerArmR/HandR",
				Vector3(0.05, 1.4, 0.05), Vector3(0, -0.7, 0.1), Color(0.4, 0.28, 0.15))
		"carry":
			_apply_pose(bot, POSE_CARRY)
			entry["prop"] = _attach_prop(bot, "Rig/Hips/Spine", Vector3(0.5, 0.4, 0.4),
				Vector3(0, 0.4, 0.5), Color(0.6, 0.5, 0.35))
		"wave":
			_apply_pose(bot, POSE_WAVE)
			var fa := bot.get_node_or_null("Rig/Hips/Spine/ClavicleR/UpperArmR/LowerArmR") as Node3D
			if fa:
				var tw := fa.create_tween().set_loops()
				tw.tween_property(fa, "rotation:z", deg_to_rad(22), 0.45)
				tw.tween_property(fa, "rotation:z", deg_to_rad(-22), 0.45)
				entry["tweens"].append(tw)
		_:
			_apply_pose(bot, POSE_CALM)
	# A gentle idle bob so the calm scene feels alive.
	var rig := bot.get_node_or_null("Rig") as Node3D
	if rig:
		var base_y: float = rig.position.y
		var bob := rig.create_tween().set_loops()
		bob.tween_property(rig, "position:y", base_y + 0.04, 1.1).set_trans(Tween.TRANS_SINE)
		bob.tween_property(rig, "position:y", base_y, 1.1).set_trans(Tween.TRANS_SINE)
		entry["tweens"].append(bob)

func _attach_prop(bot: Node3D, parent_path: String, sz: Vector3, off: Vector3, col: Color) -> Node3D:
	var parent := bot.get_node_or_null(parent_path) as Node3D
	if parent == null:
		return null
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.8
	mi.material_override = m
	mi.position = off
	parent.add_child(mi)
	return mi

func _apply_pose(bot: Node3D, pose: Dictionary) -> void:
	for path in pose:
		var n := bot.get_node_or_null(path) as Node3D
		if n:
			var d: Vector3 = pose[path]
			n.rotation = Vector3(deg_to_rad(d.x), deg_to_rad(d.y), deg_to_rad(d.z))

# ---------- choreography ----------

func _flicker() -> void:
	# A first warning: the green fill stutters and the menace light pops briefly.
	var tw := create_tween()
	tw.tween_property(_green_fill, "light_energy", 0.6, 0.08)
	tw.tween_property(_green_fill, "light_energy", 2.2, 0.12)
	tw.tween_property(_menace, "light_energy", 3.0, 0.05)
	tw.tween_property(_menace, "light_energy", 0.0, 0.18)
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("broadcast_blip", _hero.global_position, 0.0, 0.5)

## THE TURN: lights die, eyes go red, weapons come up.
func _the_turn() -> void:
	screen_flash(1.0)
	shake_camera(0.8)
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("explosion", _hero.global_position, 4.0, 0.4)
	# Kill the calm: daylight + green fill out, red menace + hellish sky in.
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_calm_sun, "light_energy", 0.25, 0.6)
	tw.tween_property(_calm_sun, "light_color", Color(0.7, 0.12, 0.06), 0.6)
	tw.tween_property(_green_fill, "light_energy", 0.0, 0.4)
	tw.tween_property(_menace, "light_energy", 7.0, 0.5)
	tw.tween_property(_sky_mat, "emission", Color(0.7, 0.16, 0.06), 0.7)
	tw.tween_property(_sky_mat, "albedo_color", Color(0.6, 0.14, 0.06), 0.7)
	tw.tween_property(_eye_light, "light_color", EYE_RED, 0.4)
	# Each robot: stop chores, eyes green->red, draw weapon, snap to a battle stance.
	for entry in _robots:
		var bot: Node3D = entry["node"]
		for t in entry["tweens"]:
			if t and t.is_valid():
				t.kill()
		if entry["prop"] and is_instance_valid(entry["prop"]):
			entry["prop"].queue_free()
		_apply_pose(bot, POSE_ARMED)
		_attach_weapon(bot)
		for m in entry["mats"]:
			var mat: StandardMaterial3D = m
			var et := create_tween()
			et.set_parallel(true)
			et.tween_property(mat, "emission", EYE_RED, 0.5)
			et.tween_property(mat, "albedo_color", EYE_RED, 0.5)

## A clearly-readable rifle in the right hand: a pale metal body that stands out
## against the red robots, with a glowing muzzle. Extends forward along the arm.
func _attach_weapon(bot: Node3D) -> void:
	var hand := bot.get_node_or_null(HAND_R) as Node3D
	if hand == null:
		return
	var gun := Node3D.new()
	hand.add_child(gun)
	gun.position = Vector3(0.05, -0.15, 0.06)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.42, 0.44, 0.5)
	metal.metallic = 0.8
	metal.roughness = 0.35
	# Barrel/body running forward (down the arm = -Y).
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.85, 0.16)
	body.mesh = bm
	body.material_override = metal
	body.position = Vector3(0, -0.4, 0)
	gun.add_child(body)
	# Stock/grip block near the hand.
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.16, 0.22, 0.34)
	grip.mesh = gm
	grip.material_override = metal
	grip.position = Vector3(0, -0.12, -0.12)
	gun.add_child(grip)
	# A magazine for read.
	var mag := MeshInstance3D.new()
	var mgm := BoxMesh.new()
	mgm.size = Vector3(0.1, 0.28, 0.12)
	mag.mesh = mgm
	mag.material_override = metal
	mag.position = Vector3(0, -0.3, -0.16)
	gun.add_child(mag)
	# Glowing muzzle so the weapon reads even in silhouette.
	var tip := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.1, 0.16, 0.12)
	tip.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.emission_enabled = true
	tmat.albedo_color = Color(1.0, 0.85, 0.4)
	tmat.emission = Color(1.0, 0.7, 0.3)
	tmat.emission_energy_multiplier = 5.0
	tip.mesh.material = tmat
	tip.position = Vector3(0, -0.85, 0)
	gun.add_child(tip)

func _shots() -> Array:
	return [
		{
			"dur": 5.0, "fade_in": true,
			"from_pos": Vector3(0, 5.0, 16.0), "from_look": Vector3(0, 2.0, -4),
			"to_pos": Vector3(0, 4.0, 12.0), "to_look": Vector3(0, 1.9, -4),
			"text": "For years, the machines served us.",
		},
		{
			"dur": 5.0,
			"from_pos": Vector3(0.5, 1.9, 2.2), "from_look": Vector3(-3.0, 1.4, -3.6),
			"to_pos": Vector3(-1.4, 1.7, 0.6), "to_look": Vector3(-3.0, 1.4, -3.6),
			"text": "They cooked. They cleaned. They cared for us.",
		},
		{
			"dur": 4.5, "action": _flicker,
			"from_pos": Vector3(2.0, 2.4, 5.0), "from_look": Vector3(0, 2.5, -2.5),
			"to_pos": Vector3(1.0, 2.5, 3.6), "to_look": Vector3(0, 2.6, -2.5),
			"text": "Then a single command reached every one of them.",
		},
		{
			"dur": 3.6, "action": _the_turn,
			"from_pos": Vector3(0.9, 2.5, 2.9), "from_look": Vector3(0, 2.5, -2.5),
			"to_pos": Vector3(0.6, 2.4, 2.3), "to_look": Vector3(0, 2.5, -2.5),
			"text": "At 03:14, they stopped serving.",
		},
		{
			"dur": 4.8, "fade_out": true,
			"from_pos": Vector3(-1.5, 2.5, 3.9), "from_look": Vector3(0, 2.2, -2.5),
			"to_pos": Vector3(-1.8, 2.6, 4.3), "to_look": Vector3(0, 2.2, -2.5),
			"title": "AI UPRISING",
			"text": "You're the last patch. Push them back.",
		},
	]

func _on_finished() -> void:
	GameState.load_level(GameState.CAMPAIGN[0], false)
