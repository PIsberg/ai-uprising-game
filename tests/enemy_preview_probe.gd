extends Node3D
## Dev probe: instantiate each new/changed enemy scene (AI frozen), let RobotModel
## auto-fit run, then frame + render it so I can tune scale/orientation/offsets.
##   godot --path . res://tests/enemy_preview_probe.tscn

const OUT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/"
const SCENES := [
	"whirlwind", "breaker",
]

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
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 150, 0)
	fill.light_energy = 0.6
	add_child(fill)
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
		var path := "res://scenes/enemies/%s.tscn" % name
		var ps: PackedScene = load(path)
		var bot: Node3D = ps.instantiate()
		# Skip boss eruption / enable showcase pose where supported.
		if "preview" in bot:
			bot.set("preview", true)
		_holder.add_child(bot)
		bot.set_physics_process(false)
		bot.rotation.y = PI  # enemy faces -Z; spin so it faces the +Z camera
		# Let the deferred auto-fit + a few frames settle.
		for i in 8:
			await get_tree().process_frame
		# Frame on the fitted body.
		var aabb := AABB()
		var first := true
		for mi in bot.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			if inst.mesh == null:
				continue
			var wb: AABB = inst.global_transform * inst.mesh.get_aabb()
			if wb.size.length() > 100.0 or wb.size.length() < 0.0001:
				continue
			if first:
				aabb = wb; first = false
			else:
				aabb = aabb.merge(wb)
		if first:
			print(name, " NO_AABB"); continue
		var c := aabb.get_center()
		var r := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5 + 0.2
		var dist := r / tan(deg_to_rad(32.0)) + r
		_cam.position = c + Vector3(dist * 0.35, aabb.size.y * 0.1, dist)
		_cam.look_at_from_position(_cam.position, c, Vector3.UP)
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT_DIR + "en_" + name + ".png")
		print("SAVED %s size=%v center=%v" % [name, aabb.size, c])
	get_tree().quit()
