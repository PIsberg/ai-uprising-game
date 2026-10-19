extends Node3D
## Probe: the changelog clip scene (tools/changelog_clip.gd) films what the
## changelog-clip skill promises, so a before/after pair shows the change:
## (1) at the trim mark the camera is aimed at the parked target (within 3 deg),
##     and the mark comes before the first shot, so trimming never cuts a shot;
## (2) the burst fires (2+ shots) and lands on the target (its health drops),
##     and the target holds its spot (AI off);
## (3) the clip reloads before it finishes;
## (4) the player and weapon manager take no live input during the clip (a stray OS
##     mouse event once turned a recording to the ceiling mid-reload);
## (5) enemy=none parks a plain wall slab in the line of fire instead (impacts
##     on the range floor hide in its glitter), and still fires and reloads;
## (6) mode=robot films a robot's own AI against the invulnerable player, who
##     never fires, with the camera keeping it in frame (#359);
## (7) mode=level loads a campaign level and dollies a free camera from `at`
##     toward `look` by `dolly` m (#359).
##   godot --headless --path . --audio-driver Dummy res://tests/changelog_clip_probe.tscn

const CLIP := "res://tools/changelog_clip.tscn"

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ResourceLoader.exists(CLIP):
		_check("clip scene exists", false, CLIP)
		print("RESULT FAIL")
		get_tree().quit()
		return
	await _drone_run()
	await _lane_run()
	await _robot_run()
	await _level_run()
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _drone_run() -> void:
	var clip: Node = (load(CLIP) as PackedScene).instantiate()
	clip.gun = "shotgun"
	clip.enemy = "drone"
	clip.quit_when_done = false
	add_child(clip)
	await clip.marked
	# The rolls (pellet scatter, damage numbers, sparks) start from one seed at the
	# mark, so a before/after pair matches wherever both commits draw in the same
	# order (#360): the first draw after the mark is the seed's first draw.
	var got := randi()
	var clip_seed = (clip.get_script() as Script).get_script_constant_map().get("CLIP_SEED")
	seed(int(clip_seed) if clip_seed != null else -1)
	var want := randi()
	_check("the global RNG is seeded at the mark", clip_seed != null and got == want, str(got))
	var cam: Camera3D = clip.player.get("camera")
	var target: Node3D = clip.target
	var aim_to := (target.global_position + Vector3.UP * 0.6 - cam.global_position).normalized()
	var off := rad_to_deg((-cam.global_basis.z).angle_to(aim_to))
	_check("camera aimed at the target at the mark", off < 3.0, "%.1f deg off" % off)
	var start_pos := target.global_position
	var hp0: float = target.hp.current_health
	# A stray OS mouse event swings the camera through player.gd's _input, but
	# only while the mouse is captured, and headless never captures it: a pushed
	# motion event moves nothing with or without the lock. So check the lock.
	var wm: Node = clip.wm
	_check("player and weapon manager ignore live input",
			not clip.player.is_processing_input() and wm != null and not wm.is_processing_input(),
			"player %s wm %s" % [clip.player.is_processing_input(), wm.is_processing_input() if wm else "missing"])
	await clip.finished
	_check("mark comes before the first shot", clip.mark_frame >= 0 and clip.mark_frame < clip.first_shot_frame,
			"mark %d first shot %d" % [clip.mark_frame, clip.first_shot_frame])
	_check("burst fires 2+ shots", clip.shots >= 2, "shots=%d" % clip.shots)
	_check("burst lands on the target", target.hp.current_health < hp0,
			"%.0f -> %.0f" % [hp0, target.hp.current_health])
	_check("target holds its spot", target.global_position.distance_to(start_pos) < 0.1,
			"moved %.2f m" % target.global_position.distance_to(start_pos))
	_check("clip reloads", clip.reloads >= 1, "reloads=%d" % clip.reloads)
	clip.queue_free()
	await get_tree().process_frame

func _lane_run() -> void:
	var clip: Node = (load(CLIP) as PackedScene).instantiate()
	clip.gun = "rifle"
	clip.enemy = "none"
	clip.burst = 0.6
	clip.quit_when_done = false
	add_child(clip)
	await clip.marked
	var cam: Camera3D = clip.player.get("camera")
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 30.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_check("enemy=none aims at its wall slab", clip.wall != null and not hit.is_empty() and hit.collider == clip.wall,
			str(hit.get("collider")))
	await clip.finished
	_check("enemy=none parks no target", clip.target == null)
	_check("enemy=none still fires and reloads", clip.shots >= 2 and clip.reloads >= 1,
			"shots=%d reloads=%d" % [clip.shots, clip.reloads])
	clip.queue_free()

## mode=robot (#359): the robot's own AI runs against the invulnerable player,
## who never fires, and the camera keeps the robot in frame.
func _robot_run() -> void:
	var clip: Node = (load(CLIP) as PackedScene).instantiate()
	clip.set("mode", "robot")
	clip.enemy = "android"
	clip.set("dur", 4.0)
	clip.quit_when_done = false
	add_child(clip)
	await clip.marked
	var robot: Node3D = clip.target
	_check("mode=robot spawns the robot", robot != null and is_instance_valid(robot))
	if robot == null or not is_instance_valid(robot):
		clip.queue_free()
		await clip.tree_exited
		return
	_check("mode=robot leaves the robot's AI on", robot.is_physics_processing())
	var cam: Camera3D = clip.player.get("camera")
	_check("mode=robot frames the robot at the mark", _off_deg(cam, robot) < 6.0, "%.1f deg off" % _off_deg(cam, robot))
	_check("mode=robot locks live input", not clip.player.is_processing_input())
	var start_pos := robot.global_position
	var php: Node = clip.player.get("hp")
	var hp0: float = php.current_health if php else 0.0
	await clip.finished
	_check("mode=robot: the robot acts on its own (moves or leaves IDLE)",
			robot.global_position.distance_to(start_pos) > 1.0 or robot.state != EnemyBase.State.IDLE,
			"moved %.2f m, state %d" % [robot.global_position.distance_to(start_pos), robot.state])
	_check("mode=robot still frames the robot at the end", _off_deg(cam, robot) < 10.0, "%.1f deg off" % _off_deg(cam, robot))
	_check("mode=robot: the player never fires", clip.shots == 0, "shots=%d" % clip.shots)
	_check("mode=robot: the player takes no damage", php != null and php.current_health >= hp0,
			"%.0f -> %.0f" % [hp0, php.current_health if php else -1.0])
	clip.queue_free()
	await clip.tree_exited

## mode=level (#359): a campaign level loads and a free camera dollies from
## `at` toward `look`; the player is parked out of the way.
func _level_run() -> void:
	var clip: Node = (load(CLIP) as PackedScene).instantiate()
	clip.set("mode", "level")
	clip.set("level", "gpt")
	clip.set("dur", 2.0)
	clip.set("dolly", 4.0)
	clip.quit_when_done = false
	add_child(clip)
	await clip.marked
	var lvl: Node = clip.get("level_node")
	_check("mode=level loads the requested level", lvl != null and lvl.scene_file_path.ends_with("level_gpt.tscn"),
			lvl.scene_file_path if lvl else "none")
	var cam: Camera3D = clip.get("fly_cam")
	_check("mode=level films through its own current camera", cam != null and cam.is_current())
	if cam == null:
		clip.queue_free()
		await clip.tree_exited
		return
	var look: Vector3 = clip.get("look")
	var at0 := cam.global_position
	var aim_off := rad_to_deg((-cam.global_basis.z).angle_to((look - at0).normalized()))
	_check("mode=level looks at `look` at the mark", aim_off < 3.0, "%.1f deg off" % aim_off)
	_check("mode=level starts at `at`", at0.distance_to(clip.get("at")) < 0.05, "%.2f m off" % at0.distance_to(clip.get("at")))
	await clip.finished
	var moved := cam.global_position.distance_to(at0)
	_check("mode=level dollies `dolly` m toward `look`", absf(moved - 4.0) < 0.3, "moved %.2f m" % moved)
	_check("mode=level: the camera is still current at the end", cam.is_current())
	clip.queue_free()
	await clip.tree_exited

func _off_deg(cam: Camera3D, n: Node3D) -> float:
	var to := (n.global_position + Vector3.UP * 0.8 - cam.global_position).normalized()
	return rad_to_deg((-cam.global_basis.z).angle_to(to))
