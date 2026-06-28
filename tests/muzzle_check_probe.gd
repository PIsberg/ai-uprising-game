extends Node3D
## Dev probe: for each ranged new enemy, drop a bright magenta marker at its
## Muzzle node so I can see whether the gun-effect origin lines up with the
## model's visible weapon.
##   godot --path . res://tests/muzzle_check_probe.tscn

const OUT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/"
const SCENES := ["warbot", "enforcer", "ripper", "optic", "gunslinger"]

var _cam: Camera3D
var _holder: Node3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.1)
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.8
	add_child(sun)
	_cam = Camera3D.new()
	add_child(_cam)
	_holder = Node3D.new()
	add_child(_holder)
	_run.call_deferred()

func _run() -> void:
	for name in SCENES:
		for c in _holder.get_children():
			c.queue_free()
		await get_tree().process_frame
		var bot: Node3D = load("res://scenes/enemies/%s.tscn" % name).instantiate()
		if "preview" in bot:
			bot.set("preview", true)
		_holder.add_child(bot)
		bot.set_physics_process(false)
		bot.rotation.y = PI
		for i in 8:
			await get_tree().process_frame
		# Marker at the Muzzle node.
		var muz := bot.get_node_or_null("Muzzle")
		if muz:
			var mk := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.12; sm.height = 0.24
			mk.mesh = sm
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(1, 0, 1)
			mat.emission_enabled = true
			mat.emission = Color(1, 0, 1)
			mat.emission_energy_multiplier = 4.0
			mk.material_override = mat
			_holder.add_child(mk)
			mk.global_position = (muz as Node3D).global_position
		# Frame the body.
		var aabb := AABB(); var first := true
		for mi in bot.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			if inst.mesh == null: continue
			var wb: AABB = inst.global_transform * inst.mesh.get_aabb()
			if wb.size.length() > 100.0 or wb.size.length() < 0.0001: continue
			if first: aabb = wb; first = false
			else: aabb = aabb.merge(wb)
		if first: continue
		var c := aabb.get_center()
		var r := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5 + 0.3
		var dist := r / tan(deg_to_rad(32.0)) + r
		_cam.position = c + Vector3(dist * 0.3, aabb.size.y * 0.05, dist)
		_cam.look_at_from_position(_cam.position, c, Vector3.UP)
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT_DIR + "mz_" + name + ".png")
		print("SAVED ", name, " muzzle=", (muz as Node3D).global_position if muz else "none")
	get_tree().quit()
