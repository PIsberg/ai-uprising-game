extends Node3D
## Dev probe: frames and renders each newly-added model individually so I can see
## what it is and assign it an enemy role.
##   godot --path . res://tests/new_models_probe.tscn

const OUT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/"
const MODELS := [
	"combat_robot", "reaper_whirlwind", "combat_steampunk", "steampunk_robot",
	"mech_police", "wheeled_robot", "robot_dog", "robot_shark",
	"utility_robot", "robot_minigun",
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
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_energy = 1.8
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.7
	add_child(fill)
	_cam = Camera3D.new()
	add_child(_cam)
	_holder = Node3D.new()
	add_child(_holder)
	_run.call_deferred()

func _run() -> void:
	for name in MODELS:
		for c in _holder.get_children():
			c.queue_free()
		await get_tree().process_frame
		var path := "res://assets/models/robots/%s.glb" % name
		if not ResourceLoader.exists(path):
			print(name, " MISSING")
			continue
		var m: Node3D = load(path).instantiate()
		_holder.add_child(m)
		await get_tree().process_frame
		await get_tree().process_frame
		# Whole-model AABB in world space.
		var aabb := AABB()
		var first := true
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			if inst.mesh == null:
				continue
			var wb: AABB = inst.global_transform * inst.mesh.get_aabb()
			if first:
				aabb = wb; first = false
			else:
				aabb = aabb.merge(wb)
		var c := aabb.get_center()
		var r := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5
		print("%s  center=%v size=%v" % [name, c, aabb.size])
		var dist := r / tan(deg_to_rad(35.0)) + r
		_cam.position = c + Vector3(dist * 0.55, aabb.size.y * 0.15, dist)
		_cam.look_at_from_position(_cam.position, c, Vector3.UP)
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT_DIR + "nm_" + name + ".png")
		print("SAVED ", name)
	get_tree().quit()
