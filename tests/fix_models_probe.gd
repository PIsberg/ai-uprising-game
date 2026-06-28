extends Node3D
## Re-render the models whose auto-framing broke (odd rig/scale transforms):
## normalize each to ~2m, recenter, fixed 3/4 camera. Discards degenerate
## skinned-mesh AABBs so one bad bound doesn't blow up the frame.
##   godot --path . res://tests/fix_models_probe.tscn

const OUT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/"
const MODELS := [
	"combat_steampunk", "steampunk_robot", "reaper_whirlwind",
	"robot_dog", "utility_robot", "robot_minigun",
]

var _cam: Camera3D
var _holder: Node3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.1)
	e.ambient_light_color = Color(0.62, 0.64, 0.72)
	e.ambient_light_energy = 1.1
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.9
	add_child(sun)
	_cam = Camera3D.new()
	_cam.position = Vector3(1.7, 0.5, 2.6)
	_cam.look_at_from_position(_cam.position, Vector3(0, 0, 0), Vector3.UP)
	add_child(_cam)
	_holder = Node3D.new()
	add_child(_holder)
	_run.call_deferred()

func _run() -> void:
	for name in MODELS:
		for c in _holder.get_children():
			c.queue_free()
		await get_tree().process_frame
		var m: Node3D = load("res://assets/models/robots/%s.glb" % name).instantiate()
		_holder.add_child(m)
		await get_tree().process_frame
		await get_tree().process_frame
		# Merge per-mesh world AABBs, ignoring degenerate (huge) skinned bounds.
		var aabb := AABB()
		var first := true
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			if inst.mesh == null:
				continue
			var wb: AABB = inst.global_transform * inst.mesh.get_aabb()
			if wb.size.length() > 200.0 or wb.size.length() < 0.0001:
				continue
			if first:
				aabb = wb; first = false
			else:
				aabb = aabb.merge(wb)
		if first:
			print(name, " NO_VALID_AABB")
			continue
		var maxd := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		var s := 2.0 / maxf(maxd, 0.0001)
		m.scale = Vector3(s, s, s)
		# Recenter so the (scaled) center sits at origin.
		m.position = -aabb.get_center() * s
		await get_tree().process_frame
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT_DIR + "fm_" + name + ".png")
		print("SAVED ", name, " maxd=", maxd, " size=", aabb.size)
	get_tree().quit()
