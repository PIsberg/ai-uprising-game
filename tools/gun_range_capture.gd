extends Node3D
## Visual playtest at the Armory range: arms a cross-section of the arsenal and
## photographs each gun mid-fire (muzzle flash, tracer/beam, impacts, the
## emissive accent skin) so weapon look/feel can be eyeballed frame by frame.
## Run windowed:
##   godot --path . tools/gun_range_capture.tscn

const OUT := "res://docs/screenshots/gunrange"
const WEAPONS := [
	"res://scenes/weapons/rifle.tscn",
	"res://scenes/weapons/shotgun.tscn",
	"res://scenes/weapons/gauss.tscn",
	"res://scenes/weapons/tesla.tscn",
	"res://scenes/weapons/sniper.tscn",
]
const FRAMES_PER_GUN := 6

var _player: Node3D
var _cam: Camera3D
var _head: Node3D
var _wm: Node

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.time_scale = 0.45 # slow-mo so each shot's flash + tracer reads
	var lvl: Node = load("res://scenes/levels/level_range.tscn").instantiate()
	add_child(lvl)
	var hud := lvl.get_node_or_null("HUD")
	if hud:
		hud.queue_free()
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		print("NO PLAYER"); get_tree().quit(1); return
	if "hp" in _player and _player.hp:
		_player.hp.invulnerable = true
	_cam = _player.get("camera") as Camera3D
	_head = _player.get_node_or_null("Head") as Node3D
	_wm = _find_wm(_player)
	if _cam == null or _wm == null:
		print("NO CAM/WM"); get_tree().quit(1); return
	for path in WEAPONS:
		await _capture_gun(path)
	print("GUN RANGE CAPTURED weapons=", WEAPONS.size())
	get_tree().quit(0)

func _capture_gun(path: String) -> void:
	_wm.add_weapon(load(path) as PackedScene, true)
	if _wm.current == null or _wm.current.scene_file_path != path:
		for i in range(_wm.weapons.size()):
			if _wm.weapons[i].scene_file_path == path:
				_wm._equip(i)
				break
	await get_tree().create_timer(0.7).timeout
	var w: Weapon = _wm.current
	var gun: String = path.get_file().get_basename()
	var shots: Array = [0]
	w.fired.connect(func(_w): shots[0] += 1)
	# Aim down the lane, depressed enough that even short-range beams (tesla)
	# bite the floor inside their range envelope — impact FX included in frame.
	_player.rotation.y = 0.0
	if _head:
		_head.rotation = Vector3(-0.15, 0, 0)
	# One idle beauty frame first (accent skin, heat glow off) — after a beat so
	# the eye-adaptation recovers from the previous gun's muzzle flashes.
	await get_tree().create_timer(1.2).timeout
	_snap("%s_idle" % gun, 0)
	# Fire through the real input action so the WeaponManager drives the gun
	# exactly as in play — calling try_fire directly gets stomped every frame by
	# the manager's own Input-driven call (which killed beam weapons on camera).
	for f in FRAMES_PER_GUN:
		w.mag = maxi(w.mag, 20)
		Input.action_release("fire")
		await get_tree().process_frame
		Input.action_press("fire") # re-press so SEMI guns get a fresh trigger pull
		await get_tree().process_frame
		_snap(gun, f + 1)
		await get_tree().create_timer(0.12).timeout
	# Side view while the trigger is still held: first-person foreshortens the
	# beam/tracer line to a dot — this is the only angle that shows it.
	var side := Camera3D.new()
	add_child(side)
	side.global_position = _cam.global_position + Vector3(3.5, 0.6, -5.0)
	side.look_at(_cam.global_position + Vector3(0, -1.2, -10.0), Vector3.UP)
	side.make_current()
	# Let slow semi guns finish their cooldown, then pull a FRESH trigger per
	# frame — a held trigger never re-fires SEMI weapons, so without this the
	# side view only ever caught auto/beam guns mid-effect.
	Input.action_release("fire")
	await get_tree().create_timer(1.0).timeout
	var side_start: int = shots[0]
	# One fresh shot, then a short burst of snaps so travelling tracer bolts
	# have time to cross the side camera's field of view (~5-15 m downrange).
	w.mag = maxi(w.mag, 20)
	Input.action_press("fire")
	await get_tree().process_frame
	for f in 4:
		_snap("%s_side" % gun, f)
		await get_tree().create_timer(0.04).timeout
	print("SIDE %s shots=%d" % [gun, shots[0] - side_start])
	_cam.make_current()
	side.queue_free()
	Input.action_release("fire")
	await get_tree().create_timer(0.4).timeout

func _snap(name: String, i: int) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%02d.png" % [OUT, name, i])

func _find_wm(root: Node) -> Node:
	var stack: Array = [root]
	while stack:
		var n: Node = stack.pop_back()
		if "current" in n and "weapons" in n:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
