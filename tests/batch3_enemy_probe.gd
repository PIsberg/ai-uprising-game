extends Node3D
## Dev probe: stage the 5 batch-3 enemies (orb / bowler / ronin / howitzer /
## manus), screenshot each from the front-left, and unit-check the MANUS
## weak-spot damage gating + the orb's thrown-mode flight.
##   godot --path . --quit-after 2400 res://tests/batch3_enemy_probe.tscn
const OUT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/4f2aa26d-c9cb-4e2f-aeea-a17e19a4e75b/scratchpad/"
const SCENES := {
	"orb": "res://scenes/enemies/orb.tscn",
	"bowler": "res://scenes/enemies/bowler.tscn",
	"ronin": "res://scenes/enemies/ronin.tscn",
	"howitzer": "res://scenes/enemies/howitzer.tscn",
	"manus": "res://scenes/enemies/manus.tscn",
}

var _cam: Camera3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.08, 0.11)
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	e.ambient_light_energy = 1.1
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.7
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 145, 0)
	fill.light_energy = 0.8
	add_child(fill)
	# Ground plane so bodies rest naturally.
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500, 1, 500)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position.y = -0.5
	floor_body.position.x = 100.0
	add_child(floor_body)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(500, 500)
	fm.position.x = 100.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.17, 0.2)
	pm.material = mat
	fm.mesh = pm
	add_child(fm)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	_run.call_deferred()

func _run() -> void:
	var idx := 0
	for key in SCENES:
		var scn: PackedScene = load(SCENES[key])
		var bot: Node3D = scn.instantiate()
		if "preview" in bot:
			bot.set("preview", true)
		add_child(bot)
		bot.global_position = Vector3(idx * 40.0, 0.1, 0)
		# Let it settle + RobotModel auto-fit finish, then FREEZE — idle AI
		# scan-rotates the body, which would poison orientation screenshots.
		for f in 30:
			await get_tree().process_frame
		if key != "orb":  # orb keeps physics for the throw check
			bot.set_physics_process(false)
		bot.rotation = Vector3.ZERO
		# Whole-bot world AABB for framing + a size printout.
		var aabb := AABB(bot.global_position, Vector3(0.1, 0.1, 0.1))
		for mi in bot.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			if inst.mesh == null:
				continue
			aabb = aabb.merge(inst.global_transform * inst.mesh.get_aabb())
		print("%s  size=%v base=%v" % [key, aabb.size, aabb.position])
		var c := aabb.get_center()
		var r := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5
		var dist := r / tan(deg_to_rad(30.0)) + r
		# Straight-on front view (enemy forward = -Z, so it should face the lens).
		_cam.look_at_from_position(c + Vector3(0, aabb.size.y * 0.3, -dist), c, Vector3.UP)
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT_DIR + "b3e_" + key + ".png")
		# Side view for silhouette/orientation.
		_cam.look_at_from_position(c + Vector3(-dist, aabb.size.y * 0.3, 0), c, Vector3.UP)
		await get_tree().create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT_DIR + "b3e_" + key + "_side.png")
		print("SAVED ", key)
		if key == "manus":
			_check_manus(bot)
		if key == "orb":
			await _check_orb_throw(bot)
		idx += 1
	print("BATCH3 ENEMY PROBE DONE")
	get_tree().quit()

## The single-weak-spot contract: body hits deal ZERO, core hits deal amplified.
func _check_manus(bot: Node3D) -> void:
	var d: Damageable = bot.get_node("Damageable")
	d.invulnerable = false
	var hp0: float = d.current_health
	# 1) Splash-style damage with no hit-position report → blocked.
	d.apply_damage(100.0, null)
	var blocked: bool = is_equal_approx(d.current_health, hp0)
	# 2) Body shot: weapons report the hit pos first — far from the core → blocked.
	var body_mult: float = bot.weakpoint_multiplier(bot.global_position + Vector3(0, 0.5, -4.0))
	d.apply_damage(100.0 * body_mult, null)
	var blocked2: bool = is_equal_approx(d.current_health, hp0)
	# 3) Core shot → amplified damage lands.
	var core: Node3D = bot.get_node("WeakSpot/Core")
	var core_mult: float = bot.weakpoint_multiplier(core.global_position)
	d.apply_damage(100.0 * core_mult, null)
	var landed: float = hp0 - d.current_health
	print("MANUS GATE: splash_blocked=%s body_blocked=%s core_mult=%.1f core_damage=%.0f" \
		% [blocked, blocked2, core_mult, landed])
	print("MANUS CORE POS: ", core.global_position - bot.global_position)

## Thrown-mode flight: the orb should sail, land, and come to rest hunting.
func _check_orb_throw(bot: Node3D) -> void:
	var start: Vector3 = bot.global_position
	bot.call("launch_throw", Vector3(6.0, 5.0, -10.0))
	await get_tree().create_timer(1.6).timeout
	var moved: Vector3 = bot.global_position - start
	print("ORB THROW: moved=%v on_floor=%s" % [moved, bot.is_on_floor()])
	bot.global_position = start
