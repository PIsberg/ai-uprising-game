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
##     on the range floor hide in its glitter), and still fires and reloads.
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
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _drone_run() -> void:
	var clip: Node = (load(CLIP) as PackedScene).instantiate()
	clip.gun = "shotgun"
	clip.enemy = "drone"
	clip.quit_when_done = false
	add_child(clip)
	await clip.marked
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
