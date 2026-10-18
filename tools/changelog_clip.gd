extends Node3D
## Changelog clip: a scripted, repeatable few seconds of weapon play, filmed
## with Godot's Movie Maker on two commits so a before/after pair can be played
## frame-locked (the changelog-clip skill, .claude/skills/changelog-clip). In
## the Armory range it parks a target robot 9 m down the lane with its AI off,
## aims at it, fires a burst and reloads. enemy=none fires into a plain wall
## slab there instead, for impact changes. Run windowed through Movie Maker:
##   godot --path . --write-movie out.avi --fixed-fps 60 \
##       res://tools/changelog_clip.tscn -- gun=shotgun enemy=drone burst=1.6
## or via tools/changelog_record.sh. Prints "CLIP MARK frame=N" where the setup
## ends (the recorder trims everything before it) and "CLIP DONE" at the end.
## tests/changelog_clip_probe pins the aim, burst, reload and input lock.

signal marked
signal finished

@export var gun := "rifle"
@export var enemy := "drone"      # an id in LevelBuilder.ENEMY_SCENES, or "none"
@export var burst := 1.6          # seconds of trigger
@export var quit_when_done := true

var player: Node3D
var target: Node3D
var wall: StaticBody3D            # enemy=none only
var shots := 0
var reloads := 0
var mark_frame := -1
var first_shot_frame := -1
var wm: Node                   # the player's WeaponManager


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			match kv[0]:
				"gun": gun = kv[1]
				"enemy": enemy = kv[1]
				"burst": burst = float(kv[1])
	var lvl: Node = load("res://scenes/levels/level_range.tscn").instantiate()
	add_child(lvl)
	var hud := lvl.get_node_or_null("HUD")
	if hud:
		hud.queue_free()
	_run.call_deferred()


func _run() -> void:
	await _wait(0.5)
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		print("CLIP FAIL no player")
		_end(1)
		return
	if "hp" in player and player.hp:
		player.hp.invulnerable = true
	wm = _find_wm(player)
	# A stray OS mouse event in the recording window would swing the camera
	# (player.gd mouse-look): the clip owns the aim, so cut live input.
	player.set_process_input(false)
	wm.set_process_input(false)
	var path := "res://scenes/weapons/%s.tscn" % gun
	wm.add_weapon(load(path) as PackedScene, true)
	for i in range(wm.weapons.size()):
		if wm.weapons[i].scene_file_path == path:
			wm._equip(i)
	var w: Weapon = wm.current
	w.fired.connect(_on_fired)
	w.reload_started.connect(func(_w: Weapon) -> void: reloads += 1)
	var p := player.global_position
	var aim_at: Vector3
	if enemy == "none":
		# Impacts on the range floor vanish into its glitter: give them a plain,
		# dark wall at the robot's distance.
		wall = _wall(Vector3(p.x, p.y + 0.6, p.z - 9.0))
		aim_at = wall.global_position
	else:
		# AI off so it holds still in frame; _process (hit flash) keeps running.
		target = (load(LevelBuilder.ENEMY_SCENES[enemy]) as PackedScene).instantiate()
		add_child(target)
		target.global_position = Vector3(p.x + 0.6, p.y + (1.2 if enemy == "drone" else 0.0), p.z - 9.0)
		target.set_physics_process(false)
		await get_tree().process_frame
		target.hp.max_health = 100000.0
		target.hp.current_health = 100000.0
		aim_at = target.global_position + Vector3.UP * 0.6
	var head := player.get_node_or_null("Head") as Node3D
	var cam := player.get("camera") as Camera3D
	if head and cam:
		var to := aim_at - cam.global_position
		player.rotation.y = atan2(-to.x, -to.z)
		head.rotation = Vector3(atan2(to.y, Vector2(to.x, to.z).length()), 0, 0)
	await _wait(0.6)
	# Everything before this frame is setup; the recorder trims it off.
	mark_frame = Engine.get_process_frames()
	print("CLIP MARK frame=%d" % Engine.get_frames_drawn())
	marked.emit()
	await _wait(0.4)
	# Re-press every 0.15 s so SEMI guns get fresh trigger pulls; AUTO stays hot.
	var t := 0.0
	while t < burst:
		Input.action_press("fire")
		await _wait(0.15)
		Input.action_release("fire")
		await get_tree().process_frame
		t += 0.15
	await _wait(0.6)
	w.mag = mini(w.mag, 1)
	w.start_reload()
	await _wait(w.eff_reload_time() + 0.9)
	print("CLIP DONE gun=%s enemy=%s shots=%d" % [gun, enemy, shots])
	_end(0)


func _wall(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.5, 0.4)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.17, 0.19)
	mat.roughness = 0.85
	bm.material = mat
	mesh.mesh = bm
	body.add_child(mesh)
	add_child(body)
	body.global_position = at
	return body


func _on_fired(_w: Weapon) -> void:
	shots += 1
	if first_shot_frame < 0:
		first_shot_frame = Engine.get_process_frames()


func _end(code: int) -> void:
	Input.action_release("fire")
	finished.emit()
	if quit_when_done:
		get_tree().quit(code)


## Waits on game time. Under --fixed-fps every frame advances exactly 1/fps,
## so a wait lands on the same frame in every run, on every commit.
func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()


func _find_wm(root: Node) -> Node:
	var stack: Array = [root]
	while stack:
		var n: Node = stack.pop_back()
		if "current" in n and "weapons" in n:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
