extends Node3D
## Renders every enemy model as an auto-framed portrait PNG into
## docs/screenshots/models/<name>.png. Each model is centred and the camera
## pulled back to fit its bounding box, so a tiny skitter and a towering titan
## both fill the frame.
##
## Run (needs a window/GPU): godot --path . tools/capture_gallery.tscn

const OUT_DIR := "res://docs/screenshots/models"

# Every enemy scene except legacy/backup chassis.
const MODELS := [
	"drone", "spider", "android", "skitter", "mech", "brute", "sniper", "server",
	"strider", "seeker", "gunner", "raptor", "dog", "vacuum", "reaper", "hunter",
	"sentinel", "mauler", "ravager", "gunslinger", "breaker", "ripper", "roller",
	"smasher", "whirlwind", "enforcer", "optic", "shark", "fishbot", "mender",
	"warbot", "alien", "warmech",
	# Bosses (preview-posed; no sky-drop / boss bar).
	"colossus", "overseer", "terminator", "titan", "archon",
]

var _cam: Camera3D
var _holder: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)
	_cam.make_current()

	# Three-point-ish lighting + a neutral studio sky.
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-45), deg_to_rad(40), 0)
	key.light_energy = 1.6
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(-150), 0)
	rim.light_energy = 0.8
	rim.light_color = Color(0.7, 0.8, 1.0)
	add_child(rim)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.12, 0.16)
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.7
	env.glow_enabled = true
	env.glow_intensity = 0.6
	we.environment = env
	add_child(we)

	# Faint ground disc so models don't float in void.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.16, 0.17, 0.2)
	pm.material = gmat
	ground.mesh = pm
	add_child(ground)

	_holder = Node3D.new()
	add_child(_holder)

	await _capture_all()
	print("GALLERY DONE")
	get_tree().quit()


func _capture_all() -> void:
	for name in MODELS:
		# Swap in the next model.
		for c in _holder.get_children():
			c.queue_free()
		await get_tree().process_frame

		var path := "res://scenes/enemies/%s.tscn" % name
		var ps := load(path)
		if ps == null:
			push_warning("missing scene: " + path)
			continue
		var bot: Node3D = ps.instantiate()
		# Bosses: skip the cinematic sky-drop / boss bar / thrusters so they pose still.
		if "preview" in bot:
			bot.preview = true
		_holder.add_child(bot)
		bot.global_position = Vector3.ZERO
		bot.rotation.y = PI + deg_to_rad(20)  # 3/4 view, facing camera-ish
		_freeze(bot)

		# Let the model rise/settle and any rise-tween or material init run.
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.35).timeout

		_frame_camera(bot)
		await get_tree().process_frame
		await get_tree().create_timer(0.1).timeout

		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [OUT_DIR, name])
		print("captured: ", name)


func _freeze(n: Node) -> void:
	if n is Node3D and n.has_method("set_physics_process"):
		n.set_physics_process(false)
	if "_apply_rise" in n:  # custodian/vacuum: show fully risen
		n.call("_apply_rise", 1.0)
	for c in n.get_children():
		_freeze(c)


## Aggregate the world-space AABB of every visual in the model, then pull the
## camera back to fit it with a margin.
func _frame_camera(root: Node3D) -> void:
	var aabb := _world_aabb(root)
	if aabb.size == Vector3.ZERO:
		aabb = AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	# Anchor on the origin (where the model stands) so an offset outlier mesh — a
	# weapon muzzle, a far FX quad — can't drag the look-at off the body. Clamp the
	# radius so such outliers can't blow the camera out to infinity either.
	var height := clampf(aabb.position.y + aabb.size.y, 1.4, 8.0)
	var center := Vector3(0, height * 0.5, 0)
	var radius := clampf(maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5, 1.1, 5.0)
	var dist := radius / tan(deg_to_rad(_cam.fov * 0.5)) * 1.35 + 1.2
	var dir := Vector3(0.55, 0.35, 1).normalized()
	_cam.global_position = center + dir * dist
	_cam.look_at(center, Vector3.UP)


func _world_aabb(node: Node) -> AABB:
	var out := AABB()
	var has := false
	# Only frame on actual geometry — Light3D / GPUParticles3D are VisualInstance3D too
	# and their influence/visibility AABBs are huge, which would balloon the framing.
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var a: AABB = mi.global_transform * mi.get_aabb()
		out = a
		has = true
	for c in node.get_children():
		var ca := _world_aabb(c)
		if ca.size != Vector3.ZERO:
			out = out.merge(ca) if has else ca
			has = true
	return out
