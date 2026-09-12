extends Node3D
## Visual-audit capture: loads campaign levels one at a time and saves an
## eye-level, forward-looking screenshot of each so the environment, models and
## lighting can be reviewed (by eye, or scored by tools/look_metrics.py).
## Run WINDOWED (needs a GPU) — headless produces black frames:
##   godot --path . res://tests/look_capture.tscn -- --out=<abs dir> --levels=gpt,neon
## --out   absolute output directory (default: user://looks)
## --levels comma-separated level ids (default: the full campaign order)
## Frames are downscaled to 1920 wide so a full run stays a few MB.

const DEFAULT_LEVELS := ["01", "gpt", "gemini", "mistral", "suburb", "suburb_boss", "convoy",
	"claude", "grok", "uplink", "overseer", "alien", "assembly", "sublevel",
	"frostbreak", "water_world", "desert", "neon", "guardrails", "hivemind",
	"crucible", "lava_world", "titan", "archon"]

# Boss levels stage an entrance right at the spawn camera on the first frames;
# give them longer to settle so the shot shows the arena, not the drop-pod.
const SETTLE_OVERRIDE := {"overseer": 6.0, "titan": 6.0, "archon": 6.0, "crucible": 6.0,
	"suburb_boss": 5.0, "assembly": 5.0}
const SETTLE_DEFAULT := 2.4
const OUT_WIDTH := 1920

func _ready() -> void:
	var out_dir := "user://looks"
	var levels: Array = DEFAULT_LEVELS.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--levels="):
			levels = Array(a.substr(9).split(",", false))
	if out_dir.begins_with("user://"):
		out_dir = ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 72.0
	# Match the player camera's auto-exposure so brightness reads like real play.
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 50.0
	ca.auto_exposure_max_sensitivity = 400.0
	ca.auto_exposure_scale = 0.38
	cam.attributes = ca
	add_child(cam)
	for id in levels:
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			print("skip ", id); continue
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		var pdmg := lvl.find_child("Damageable", true, false)
		if pdmg: pdmg.invulnerable = true
		# Park the player far above the arena and stop it ticking for the whole
		# settle: otherwise the robots engage it during those seconds and the
		# blast screen-warp (post_process shockwaves) smears the frame into rings.
		# The spawn is read first so the camera still stands where the player would.
		var player := lvl.find_child("Player", false, false) as Node3D
		var spawn: Vector3 = player.global_position if player else Vector3(16, 2, 16)
		if player:
			player.process_mode = Node.PROCESS_MODE_DISABLED
			player.global_position = spawn + Vector3(0, 300, 0)
			player.visible = false
		var settle: float = SETTLE_OVERRIDE.get(id, SETTLE_DEFAULT)
		# Short timer loops: one long SceneTreeTimer stalls autoload ticking.
		var waited := 0.0
		while waited < settle:
			await get_tree().create_timer(0.3).timeout
			waited += 0.3
		var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
		if pcam: pcam.current = false
		# Stand at the spawn (eye height) and look toward the arena centre — the
		# real player's-eye first impression. Corner spawns and partition rings
		# put a wall a metre in front of that line, so sweep the yaw and take the
		# clearest sightline (longest world raycast); the centre view wins ties.
		cam.current = true
		var eye := Vector3(spawn.x, maxf(spawn.y, 0.0) + 1.6, spawn.z)
		cam.global_position = eye
		var to_centre := (Vector3(0, eye.y, 0) - eye)
		to_centre.y = 0.0
		if to_centre.length() < 1.0:
			to_centre = Vector3(0, 0, -1)
		var best_dir := to_centre.normalized()
		var best_len := _clear_len(eye, best_dir)
		if best_len < 12.0:
			for deg in [30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180]:
				var d := to_centre.rotated(Vector3.UP, deg_to_rad(float(deg))).normalized()
				var l := _clear_len(eye, d)
				if l > best_len + 2.0:
					best_len = l
					best_dir = d
		# Step 3 m out along the sightline and push any robot that gathered on the
		# spawn during the settle back out of the lens so the frame shows the
		# arena, not one chassis.
		eye += best_dir * minf(3.0, best_len * 0.25)
		cam.global_position = eye
		for en in get_tree().get_nodes_in_group("enemy"):
			var n3 := en as Node3D
			if n3 == null or not is_instance_valid(n3):
				continue
			var flat := n3.global_position - eye
			flat.y = 0.0
			if flat.length() < 8.0:
				var away := flat.normalized() if flat.length() > 0.1 else best_dir
				n3.global_position = Vector3(eye.x, n3.global_position.y, eye.z) + away * 12.0
		cam.look_at(eye + best_dir * 20.0 + Vector3(0, -1.2, 0), Vector3.UP)
		print("FRAME ", id, " clear=", snappedf(best_len, 0.1))
		# Let auto-exposure converge on the new framing before sampling.
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img.get_width() > OUT_WIDTH:
			var h := int(round(float(img.get_height()) * OUT_WIDTH / img.get_width()))
			img.resize(OUT_WIDTH, h, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s/%s.png" % [out_dir, id])
		print("SAVED ", id)
		lvl.queue_free()
		await get_tree().process_frame
	print("LOOK_CAPTURE_DONE")
	get_tree().quit()

## Length of the clear line of sight from `from` along `dir` (world layer 1),
## capped at 60 m.
func _clear_len(from: Vector3, dir: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 60.0
	return from.distance_to(hit["position"])
