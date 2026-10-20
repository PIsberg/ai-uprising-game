extends Node3D
## Windowed check for PHOTO MODE: a lit yard with a robot, paused, photo mode on,
## the camera flown a few metres, the NOIR filter, then PhotoMode.capture(). Prints
## the saved path and copies the photo to <out>/photo_mode.png; RESULT FAIL if the
## capture wrote nothing.
##   godot --path . res://tests/photo_mode_shot.tscn -- --out=<dir>

var out := "user://"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.25, 0.32, 0.42)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.35, 0.38, 0.42)
	add_child(we)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	fl.mesh = pm
	add_child(fl)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	add_child(sb)
	for x in [-3.0, 2.5]:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.5, 2.5, 1.5)
		box.mesh = bm
		add_child(box)
		box.position = Vector3(x, 1.25, -9)
	GameState.set_state(GameState.State.PLAYING)
	var p: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector3(0, 0.1, 0)
	var bot: Node3D = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(bot)
	bot.global_position = Vector3(0, 0, -7)
	var hud: Control = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await _frames(40)
	GameState.set_state(GameState.State.PAUSED)
	hud.call("open_photo_mode")
	var photo: PhotoMode = hud.get("photo_mode")
	await _frames(5)
	photo.cycle_filter() # NOIR
	photo.zoom(-1)
	photo.zoom(-1)
	await _frames(10)
	var path: String = await photo.capture()
	print("SAVED ", path)
	var ok := path != "" and FileAccess.file_exists(path)
	if ok:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		img.save_png(out.path_join("photo_mode.png"))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
