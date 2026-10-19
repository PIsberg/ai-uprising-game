extends Node3D
## Changelog clip: a scripted, repeatable few seconds of play, filmed with
## Godot's Movie Maker on two commits so a before/after pair can be played
## frame-locked (the changelog-clip skill, .claude/skills/changelog-clip).
## mode=weapon (default): in the Armory range it parks a target robot 9 m down
##   the lane with its AI off, aims at it, fires a burst and reloads. enemy=none
##   fires into a plain wall slab there instead, for impact changes.
## mode=robot enemy=<id> dur=<s>: the robot spawns 12 m down the range with its
##   AI on and plays against the invulnerable player, who never fires; the
##   camera keeps it in frame. For robot AI, movement and attack changes.
## mode=level level=<id> [at=x,y,z] [look=x,y,z] dur=<s> dolly=<m>: loads
##   res://scenes/levels/level_<id>.tscn and dollies a free camera from `at`
##   toward `look`. World coordinates (already WORLD_SCALEd); both default off
##   the player's spawn, and the mark line prints them. For level, hazard and
##   lighting changes. Run windowed through Movie Maker:
##   godot --path . --write-movie out.avi --fixed-fps 60 \
##       res://tools/changelog_clip.tscn -- gun=shotgun enemy=drone burst=1.6
## or via tools/changelog_record.sh. Prints "CLIP MARK frame=N" where the setup
## ends (the recorder trims everything before it) and "CLIP DONE" at the end.
## tests/changelog_clip_probe pins each mode: aim, burst, reload, input lock,
## the robot's own AI, the level and the dolly.

## The global RNG seed at the trim mark (see the mark, #360).
const CLIP_SEED := 358
signal marked
signal finished

@export var mode := "weapon"     # weapon | robot | level
@export var gun := "rifle"
@export var enemy := "drone"      # an id in LevelBuilder.ENEMY_SCENES, or "none"
@export var burst := 1.6          # seconds of trigger
@export var dur := 5.0            # robot/level: seconds filmed after the mark
@export var level := ""          # level: the id in res://scenes/levels/level_<id>.tscn
@export var at := Vector3.INF     # level: camera start (INF: 8 m above the player's spawn)
@export var look := Vector3.INF   # level: what it looks at (INF: the level centre)
@export var dolly := 4.0          # level: metres the camera travels toward `look`
@export var quit_when_done := true

var player: Node3D
var target: Node3D
var wall: StaticBody3D            # enemy=none only
var shots := 0
var reloads := 0
var mark_frame := -1
var first_shot_frame := -1
var wm: Node                   # the player's WeaponManager
var level_node: Node           # the loaded level (the range unless mode=level)
var fly_cam: Camera3D          # mode=level only


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			match kv[0]:
				"gun": gun = kv[1]
				"enemy": enemy = kv[1]
				"burst": burst = float(kv[1])
				"mode": mode = kv[1]
				"dur": dur = float(kv[1])
				"level": level = kv[1]
				"at": at = _vec(kv[1])
				"look": look = _vec(kv[1])
				"dolly": dolly = float(kv[1])
	var path := "res://scenes/levels/level_range.tscn"
	if mode == "level":
		path = "res://scenes/levels/level_%s.tscn" % level
		if not ResourceLoader.exists(path):
			print("CLIP FAIL no level %s" % path)
			_end(1)
			return
	var lvl: Node = load(path).instantiate()
	level_node = lvl
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
	match mode:
		"robot": await _robot_shot()
		"level": await _level_shot()
		_: await _weapon_shot()


func _weapon_shot() -> void:
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
	_aim(aim_at)
	await _wait(0.6)
	await _mark()
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


## Points the player's view (body yaw, head pitch) at `at_pos`.
func _aim(at_pos: Vector3) -> void:
	var head := player.get_node_or_null("Head") as Node3D
	var cam := player.get("camera") as Camera3D
	if head and cam:
		var to := at_pos - cam.global_position
		player.rotation.y = atan2(-to.x, -to.z)
		head.rotation = Vector3(atan2(to.y, Vector2(to.x, to.z).length()), 0, 0)


func _mark() -> void:
	# SoundSynth builds its streams on a worker thread, and a ref older than #360
	# draws that noise from the global RNG, which would spend the seed below in
	# the background. Let the pass finish first (setup is trimmed off anyway).
	var synth_wait := 0.0
	while SoundSynth.has_method("is_all_ready") and not SoundSynth.is_all_ready() and synth_wait < 30.0:
		await get_tree().process_frame
		synth_wait += get_process_delta_time()
	# Everything before this frame is setup; the recorder trims it off.
	mark_frame = Engine.get_process_frames()
	print("CLIP MARK frame=%d" % Engine.get_frames_drawn())
	# Both commits' rolls (pellet scatter, damage numbers, sparks) start from the
	# same seed here, so a pair matches wherever their draw order is the same; a
	# change that adds or removes draws still diverges after it (#360).
	seed(CLIP_SEED)
	marked.emit()


## mode=robot: the robot's own AI against the invulnerable player, who never fires.
func _robot_shot() -> void:
	var p := player.global_position
	target = (load(LevelBuilder.ENEMY_SCENES[enemy]) as PackedScene).instantiate()
	add_child(target)
	target.global_position = Vector3(p.x + 0.6, p.y + (1.2 if enemy == "drone" else 0.0), p.z - 12.0)
	await get_tree().process_frame
	_aim(target.global_position + Vector3.UP * 0.8)
	await _wait(0.6)
	await _mark()
	var t := 0.0
	while t < dur:
		if is_instance_valid(target):
			_aim(target.global_position + Vector3.UP * 0.8)
		await get_tree().process_frame
		t += get_process_delta_time()
	print("CLIP DONE mode=robot enemy=%s" % enemy)
	_end(0)


## mode=level: a free camera dollies from `at` toward `look` by `dolly` m.
func _level_shot() -> void:
	var cam := player.get("camera") as Camera3D
	var eye: Vector3 = cam.global_position if cam else player.global_position + Vector3.UP * 1.6
	# Defaults: over the walls from above the spawn, onto the level centre (levels
	# are laid out round the origin). Straight ahead from the spawn often meets a wall.
	if not at.is_finite():
		at = eye + Vector3.UP * 8.0
	if not look.is_finite():
		look = Vector3(0.0, eye.y, 0.0)
	fly_cam = Camera3D.new()
	add_child(fly_cam)
	fly_cam.global_position = at
	fly_cam.look_at(look)
	fly_cam.make_current()
	print("CLIP LEVEL %s at=%.1f,%.1f,%.1f look=%.1f,%.1f,%.1f" % [level, at.x, at.y, at.z, look.x, look.y, look.z])
	await _wait(0.6)
	await _mark()
	var dir := (look - at).normalized()
	var t := 0.0
	while t < dur:
		await get_tree().process_frame
		t += get_process_delta_time()
		fly_cam.global_position = at + dir * dolly * minf(t / dur, 1.0)
		# A level's own intro or kill-cam can take the view; the clip keeps it.
		if not fly_cam.is_current():
			fly_cam.make_current()
	print("CLIP DONE mode=level level=%s" % level)
	_end(0)


func _vec(s: String) -> Vector3:
	var f := s.split_floats(",")
	return Vector3(f[0], f[1], f[2]) if f.size() == 3 else Vector3.INF


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
