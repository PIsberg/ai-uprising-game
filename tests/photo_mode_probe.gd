extends Node3D
## Probe: PHOTO MODE (scripts/ui/photo_mode.gd) from the pause menu, with a real
## player and the real HUD:
## (1) the pause menu offers Photo Mode;
## (2) entering it keeps the game paused, makes the free camera current at the
##     player's eye, hides the HUD and every other overlay;
## (3) holding forward flies the camera forward while the world stays frozen (a
##     robot does not move); it never strays past RADIUS from where it started;
## (4) the wheel zooms within FOV_MIN..FOV_MAX; the filter key cycles every filter
##     on the overlay shader and wraps;
## (5) leaving restores the player's camera, the HUD and the overlays as they were,
##     back on the pause menu.
## (The PNG capture needs a real framebuffer: tests/photo_mode_shot, windowed.)
##   godot --headless --path . --audio-driver Dummy res://tests/photo_mode_probe.tscn

const PLAYER := "res://scenes/player/player.tscn"
const HUD := "res://scenes/ui/hud.tscn"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

## Real seconds (the tree is paused in photo mode, so no physics frames to count).
func _wait(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await get_tree().process_frame

func _run() -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	add_child(sb)
	GameState.set_state(GameState.State.PLAYING)
	var p: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector3(0, 0.1, 0)
	var bot: Node3D = (load("res://scenes/enemies/drone.tscn") as PackedScene).instantiate()
	add_child(bot)
	bot.global_position = Vector3(3, 2, -8)
	var hud: Control = (load(HUD) as PackedScene).instantiate()
	add_child(hud)
	var feed := CanvasLayer.new() # stands in for the other overlays (machine feed, breach bar)
	add_child(feed)
	var hidden_layer := CanvasLayer.new()
	hidden_layer.visible = false
	add_child(hidden_layer)
	await _wait(0.5)
	var player_cam: Camera3D = p.get("camera")

	# 1. The pause menu offers it.
	GameState.set_state(GameState.State.PAUSED)
	var btn := hud.find_child("PhotoMode", true, false) as Button
	_check("the pause menu offers Photo Mode", btn != null)
	if btn == null:
		print("RESULT FAIL")
		get_tree().quit(1)
		return
	btn.pressed.emit()
	await _wait(0.2)
	var pm: PhotoMode = hud.get("photo_mode")
	_check("photo mode is on", pm != null and pm.active)
	_check("the game stays paused", get_tree().paused and GameState.current_state == GameState.State.PAUSED)
	var cam := get_viewport().get_camera_3d()
	_check("the free camera is current, at the eye", cam != player_cam and cam.global_position.distance_to(player_cam.global_position) < 0.05)
	_check("the HUD and the overlays are hidden", not hud.visible and not feed.visible)
	# The gun hangs under the player's camera in world space: the free camera at the
	# same spot filmed it (and its ammo readout) in photo_mode_shot.
	var wm := p.find_children("*", "WeaponManager", true, false)[0] as Node3D
	_check("the gun in your hands is hidden", not wm.is_visible_in_tree())

	# 3. Fly; the world stays frozen.
	var start := cam.global_position
	var bot0 := bot.global_position
	Input.action_press("move_forward")
	await _wait(1.0)
	Input.action_release("move_forward")
	var moved := cam.global_position - start
	var fwd := -player_cam.global_transform.basis.z
	_check("forward flies the camera forward", moved.dot(fwd) > 1.0, "%.2f m" % moved.dot(fwd))
	_check("the world stays frozen", bot.global_position.distance_to(bot0) < 0.01)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait(4.0)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_check("the camera stays within RADIUS", cam.global_position.distance_to(start) <= PhotoMode.RADIUS + 0.05, "%.2f m" % cam.global_position.distance_to(start))

	# 4. Zoom and filters.
	for i in 40:
		pm.zoom(-1)
	_check("zoom stops at FOV_MIN", is_equal_approx(cam.fov, PhotoMode.FOV_MIN), "%.1f" % cam.fov)
	for i in 80:
		pm.zoom(1)
	_check("zoom stops at FOV_MAX", is_equal_approx(cam.fov, PhotoMode.FOV_MAX), "%.1f" % cam.fov)
	var seen := {}
	for i in PhotoMode.FILTERS.size():
		seen[pm.filter_mode()] = true
		pm.cycle_filter()
	_check("the filter key steps through every filter and wraps", seen.size() == PhotoMode.FILTERS.size() and pm.filter_mode() == 0, str(seen.keys()))

	# 5. Leave.
	pm.leave()
	await _wait(0.2)
	_check("the player's camera is back", get_viewport().get_camera_3d() == player_cam)
	_check("the HUD and the overlays are back", hud.visible and feed.visible and not hidden_layer.visible)
	_check("the gun is back", wm.is_visible_in_tree())
	_check("back on the pause menu", get_tree().paused and (hud.get("pause_menu") as Control).visible)

	GameState.set_state(GameState.State.MENU)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
