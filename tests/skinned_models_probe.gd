extends Node3D
## Render the skinned models by PLAYING their animation first (their rest pose is
## misleading), then framing on the posed Skeleton3D's bone bounds.
##   godot --path . res://tests/skinned_models_probe.tscn

const OUT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/"
const MODELS := ["steampunk_robot", "combat_steampunk", "reaper_whirlwind"]

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
		# Play first animation so the skeleton poses out of its bind pose.
		var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var anims: PackedStringArray = ap.get_animation_list() if ap else PackedStringArray()
		if ap and anims.size() > 0:
			ap.play(anims[0])
			ap.seek(0.1, true)
		for i in 4:
			await get_tree().process_frame
		# AABB from posed skeleton bone origins (reliable for skinned meshes).
		var skel := m.find_child("Skeleton3D", true, false) as Skeleton3D
		var aabb := AABB()
		var first := true
		if skel:
			for b in skel.get_bone_count():
				var p: Vector3 = (skel.global_transform * skel.get_bone_global_pose(b)).origin
				if first:
					aabb = AABB(p, Vector3.ZERO); first = false
				else:
					aabb = aabb.expand(p)
		print("%s anims=%s skel_size=%v center=%v" % [name, anims, aabb.size, aabb.get_center()])
		var c := aabb.get_center()
		var r := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5 + 0.3
		var dist := r / tan(deg_to_rad(33.0)) + r
		_cam.position = c + Vector3(dist * 0.5, aabb.size.y * 0.1, dist)
		_cam.look_at_from_position(_cam.position, c, Vector3.UP)
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT_DIR + "sk_" + name + ".png")
		print("SAVED ", name)
	get_tree().quit()
