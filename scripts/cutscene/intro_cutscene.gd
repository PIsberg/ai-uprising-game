extends CutscenePlayer
## Campaign opener with a turn: domestic helper robots go about their chores with
## calm GREEN auras and no aggression — then a single signal propagates, the
## lights die, they burn RED and snap into combat stances. Hard cut to the title.
##
## The cast is the ACTUAL in-game enemy roster (Quaternius models): the same
## android/mech/spider/drone the player fights ten seconds later, so the turn
## lands as "those exact machines". Their imported animation clips do the
## acting — Idle for the calm, their combat clips after the turn.

const EYE_GREEN := Color(0.25, 1.0, 0.4)
const EYE_RED := Color(1.0, 0.18, 0.12)

## Cast: enemy scene, the combat clip it snaps to at the turn, and the blaster
## it picks up from the rack beside it ("" = built-in armament).
const CAST := {
	"android": {"scene": "res://scenes/enemies/android.tscn", "attack": "Shoot",
		"gun": "res://assets/models/weapons/blaster-d.glb", "lamp_y": 0.86, "lamps": 2},
	"mech": {"scene": "res://scenes/enemies/mech.tscn", "attack": "Punch",
		"gun": "res://assets/models/weapons/blaster-p.glb", "lamp_y": 0.78, "lamps": 2},
	"spider": {"scene": "res://scenes/enemies/spider.tscn", "attack": "Attack",
		"gun": "", "lamp_y": 0.6, "lamps": 2}, # no arms — it lunges, never holds a gun
	"drone": {"scene": "res://scenes/enemies/drone.tscn", "attack": "", "gun": "",
		"lamp_y": 0.52, "lamps": 1}, # one central lamp: it IS a flying eye
}

var _hero: Node3D
var _eye_light: OmniLight3D
var _robots: Array = [] # each: {node, model, mats:[StandardMaterial3D], attack, tweens:Array}

var _calm_sun: DirectionalLight3D
var _green_fill: OmniLight3D
var _menace: OmniLight3D
var _sky_mat: StandardMaterial3D
var _turned: bool = false

func _build_set() -> void:
	_build_ground()
	_build_plaza()
	_build_chore_props()
	_build_lights_and_sky()
	# Hero, central and a bit larger, calmly idle — the player's first android.
	_hero = _make_robot("android", Vector3(0, 0, -2.5), 1.35)
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = EYE_GREEN
	_eye_light.light_energy = 1.6
	_eye_light.omni_range = 6.0
	_eye_light.position = Vector3(0, 2.7, -1.4)
	add_child(_eye_light)
	# The helper staff, each by its workstation.
	_make_robot("mech", Vector3(-3.4, 0, -4.6), 0.9)
	_make_robot("android", Vector3(3.0, 0, -3.6), 1.0)
	_make_robot("spider", Vector3(-2.2, 0, -0.8), 1.0)
	# The drone patrols the AIR — high and behind the line, never blocking
	# the ground cast's framing.
	_make_robot("drone", Vector3(2.4, 3.3, -4.6), 1.0)

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

## Domestic set dressing beside each worker: supply crates being moved, a
## cleaning cart, a service trolley — the chores live in the props now that the
## cast uses imported rigs that can't be hand-posed.
func _build_chore_props() -> void:
	var crate_mat := _flat(Color(0.6, 0.5, 0.35), 0.8)
	for c in [[Vector3(-4.4, 0.3, -4.4), 0.6], [Vector3(-4.0, 0.9, -4.5), 0.55], [Vector3(-4.9, 0.3, -3.9), 0.62]]:
		var crate := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * c[1]
		bm.material = crate_mat
		crate.mesh = bm
		crate.position = c[0]
		add_child(crate)
	# Cleaning cart + leaning mop by the spider (low maintenance unit).
	var cart := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.8, 0.7, 0.5)
	cm.material = _flat(Color(0.75, 0.78, 0.8), 0.6)
	cart.mesh = cm
	cart.position = Vector3(-3.1, 0.35, -0.7)
	add_child(cart)
	var mop := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.025
	mm.bottom_radius = 0.025
	mm.height = 1.3
	mm.material = _flat(Color(0.4, 0.28, 0.15), 0.8)
	mop.mesh = mm
	mop.position = Vector3(-2.7, 0.75, -0.55)
	mop.rotation_degrees = Vector3(0, 0, 18)
	add_child(mop)
	# Service trolley near the right-hand android.
	var trolley := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.9, 0.1, 0.5)
	tm.material = _flat(Color(0.55, 0.58, 0.62), 0.4)
	trolley.mesh = tm
	trolley.position = Vector3(3.9, 0.8, -3.4)
	add_child(trolley)

func _flat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

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

## Spawn an in-game enemy as a cutscene actor: AI/physics off, but the model's
## own AnimationPlayer keeps the Idle loop alive (RobotModel drives it). The
## models stay their natural colors — friendliness lives in small green STATUS
## LAMPS mounted on each robot (the lamps, not the bodies, turn red).
func _make_robot(type: String, pos: Vector3, scl: float) -> Node3D:
	var info: Dictionary = CAST[type]
	var bot: Node3D = load(info["scene"]).instantiate()
	add_child(bot)
	bot.global_position = pos
	bot.rotation.y = PI # face the camera (+Z)
	bot.scale = Vector3.ONE * scl
	if bot.has_method("set_physics_process"):
		bot.set_physics_process(false) # no AI — the model node keeps animating
	var entry := {"node": bot, "model": bot.get_node_or_null("Model"),
		"lamp_light": null, "eye_lights": [], "weapon": null,
		"attack": info["attack"], "tweens": []}
	# The combat scenes ship with RED eye/sensor lights (spider omni, mech
	# spotlight, drone eye) — hostile dots that clash with the calm phase.
	# Re-enlist them: green while serving, burned red with everything else.
	for l in bot.find_children("*", "Light3D", true, false):
		var lt := l as Light3D
		lt.light_color = EYE_GREEN
		lt.light_energy = minf(lt.light_energy, 1.2) # gentle in servitude
		entry["eye_lights"].append(lt)
	_add_lamps(bot, entry, info)
	if info["gun"] != "":
		_add_rack_gun(bot, entry, info["gun"])
	# Fliers bob gently; grounded units idle via their animation clip.
	if type == "drone":
		var bob := bot.create_tween().set_loops()
		bob.tween_property(bot, "position:y", pos.y + 0.25, 1.4).set_trans(Tween.TRANS_SINE)
		bob.tween_property(bot, "position:y", pos.y, 1.4).set_trans(Tween.TRANS_SINE)
		entry["tweens"].append(bob)
	_robots.append(entry)
	return bot

## Merged AABB of a model's meshes in the BOT's local space — every chassis is
## a different shape, so lamp placement must be measured, not guessed.
func _local_aabb(bot: Node3D) -> AABB:
	var inv := bot.global_transform.affine_inverse()
	var merged := AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.6, 0.6))
	var first := true
	for mi in bot.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst.mesh:
			var ab: AABB = (inv * mesh_inst.global_transform) * mesh_inst.mesh.get_aabb()
			merged = ab if first else merged.merge(ab)
			first = false
	return merged

## Status glow fitted to the chassis: a soft body light at a measured height
## (no lamp sphere meshes — at cinematic camera angles those read as floating
## dots, and the models' own eye lights already mark the "face").
func _add_lamps(bot: Node3D, entry: Dictionary, info: Dictionary) -> void:
	var ab := _local_aabb(bot)
	var lamp_y: float = ab.position.y + ab.size.y * float(info.get("lamp_y", 0.8))
	# Local front is -Z (the bot is yawed PI to face the camera); sit the glow
	# just proud of the front face.
	var front_z: float = ab.position.z - 0.03
	var light := OmniLight3D.new()
	light.light_color = EYE_GREEN
	light.light_energy = 0.9
	light.omni_range = 2.6
	light.position = Vector3(0, lamp_y * 0.85, front_z - 0.15)
	bot.add_child(light)
	entry["lamp_light"] = light

## A blaster resting on a small rack stand beside the robot — unarmed for now;
## the turn snaps it into the robot's grip.
func _add_rack_gun(bot: Node3D, entry: Dictionary, gun_path: String) -> void:
	var stand := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.5, 0.62, 0.3)
	sb.material = _flat(Color(0.35, 0.37, 0.42), 0.5)
	stand.mesh = sb
	var side := 1.0 if bot.global_position.x >= 0.0 else -1.0
	stand.position = bot.global_position + Vector3(0.9 * side, 0.31, 0.2)
	add_child(stand)
	var gun := (load(gun_path) as PackedScene).instantiate() as Node3D
	add_child(gun)
	# Lying flat on the rack, grip up — clearly "stored", not held. Oversized
	# slightly: these are background props that must read from metres away.
	gun.scale = Vector3.ONE * 1.3
	gun.global_position = stand.position + Vector3(0, 0.4, 0)
	gun.rotation_degrees = Vector3(0, randf_range(-25, 25), 90)
	entry["weapon"] = gun

## The turn's pickup: a beat after the lamps flip, the rack gun FLIES into the
## robot's grip and aims at the camera — slow enough to track, with an
## overshoot snap so the catch reads.
func _arm(entry: Dictionary) -> void:
	var gun: Node3D = entry["weapon"]
	var bot: Node3D = entry["node"]
	if gun == null or not is_instance_valid(gun):
		return
	var xf := gun.global_transform
	gun.get_parent().remove_child(gun)
	bot.add_child(gun)
	gun.global_transform = xf # same world pose, new parent
	# Counter the parent's scale so the gun keeps its world size in the grip.
	gun.scale = Vector3.ONE * (1.3 / maxf(bot.scale.x, 0.01))
	var ab := _local_aabb(bot)
	var hold := Vector3(0.28, ab.position.y + ab.size.y * 0.72, ab.position.z - 0.3)
	var tw := gun.create_tween()
	tw.tween_interval(0.25) # let the red lamps land first, then the grab
	tw.set_parallel(true)
	tw.tween_property(gun, "position", hold, 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(gun, "rotation", Vector3.ZERO, 0.55) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

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

## THE TURN: lights die, auras burn red, the cast snaps into combat clips.
func _the_turn() -> void:
	_turned = true
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
	# Each robot: drop the chore, status lamps green->red, GRAB the rack gun,
	# snap to its combat clip and keep re-striking it through the title card.
	for entry in _robots:
		var bot: Node3D = entry["node"]
		for t in entry["tweens"]:
			if t and t.is_valid():
				t.kill()
		var lamp_light: OmniLight3D = entry["lamp_light"]
		if lamp_light:
			var lt := create_tween()
			lt.set_parallel(true)
			lt.tween_property(lamp_light, "light_color", EYE_RED, 0.45)
			lt.tween_property(lamp_light, "light_energy", 1.8, 0.45)
		# The combat eye/sensor lights flare back to their hostile red.
		for el in entry["eye_lights"]:
			if is_instance_valid(el):
				var et2 := create_tween()
				et2.set_parallel(true)
				et2.tween_property(el, "light_color", EYE_RED, 0.45)
				et2.tween_property(el, "light_energy", 2.2, 0.45)
		_arm(entry)
		_strike(entry)
		# A menacing step toward the camera, staggered so the line surges.
		var step := bot.create_tween()
		step.tween_interval(randf_range(0.1, 0.5))
		step.tween_property(bot, "position:z",
			bot.position.z + randf_range(0.35, 0.7), 1.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Fire the combat clip, and again every couple of seconds while the scene runs.
func _strike(entry: Dictionary) -> void:
	if not _turned or not is_instance_valid(entry["node"]) or not is_inside_tree():
		return
	var model: Node = entry["model"]
	var clip: String = entry["attack"]
	if model and clip != "" and model.has_method("play_named"):
		model.play_named(clip, 0.15)
	# Scene-tree timers outlive a freed cutscene; re-validate before striking.
	var t := get_tree().create_timer(randf_range(1.6, 2.4))
	t.timeout.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			_strike(entry))

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
