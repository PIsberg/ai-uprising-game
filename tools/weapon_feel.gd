extends Node3D
## Loads a level, makes the player auto-fire its weapon, and captures the
## first-person view (gun + muzzle flash + recoil kick) to a PNG sequence so the
## weapon look/feel can be inspected. Run windowed:
##   godot --path . tools/weapon_feel.tscn

const OUT := "res://docs/screenshots/weapon"
const LEVEL := "suburb"
const WARMUP := 1.2
const FRAMES := 44

var _player: Node3D
var _wm: Node
var _t := 0.0
var _frame := 0
var _ready_done := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.time_scale = 0.45   # slow-mo so each shot's kick + muzzle flash reads
	var lvl: Node = load("res://scenes/levels/level_%s.tscn" % LEVEL).instantiate()
	add_child(lvl)
	var hud := lvl.get_node_or_null("HUD")
	if hud:
		hud.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		if "hp" in _player and _player.hp:
			_player.hp.invulnerable = true
		_player.set_physics_process(false)
		_wm = _find_wm(_player)
	_ready_done = true


func _find_wm(root: Node) -> Node:
	var stack: Array = [root]
	while stack:
		var n: Node = stack.pop_back()
		if "current" in n and "weapons" in n:
			return n
		for c in n.get_children():
			stack.append(c)
	return null


func _process(delta: float) -> void:
	if not _ready_done or _player == null or not is_instance_valid(_player):
		return
	var cam = _player.get("camera")
	if _wm and _wm.current and cam:
		# Keep it topped up and hammer the trigger.
		_wm.current.mag = max(_wm.current.mag, 30)
		_wm.current.try_fire(true, false, cam, _player)
	_t += delta
	if _t < WARMUP:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/frame_%03d.png" % [OUT, _frame])
	_frame += 1
	if _frame >= FRAMES:
		print("WEAPON FEEL CAPTURED frames=", _frame, " wm=", _wm != null,
			" weapon=", (_wm.current.name if _wm and _wm.current else "none"))
		get_tree().quit()
