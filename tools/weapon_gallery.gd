extends Node3D
## Equips each named weapon in turn, fires it, and captures the brightest
## (muzzle-flash peak) first-person frame per weapon — so the per-weapon fx
## colour + recoil-kick pass can be eyeballed side by side. Run windowed:
##   godot --path . tools/weapon_gallery.tscn

const OUT := "res://docs/screenshots/weapon"
const LEVEL := "suburb"
# Representative spread: ballistic gold, teal plasma, orange rocket, blue rail.
const WEAPONS := ["Sidearm", "Plasma", "Swarm", "Gauss"]
const PER_WEAPON := 18      # frames sampled per weapon (slow-mo)

var _player: Node3D
var _wm: Node
var _wi := 0
var _f := 0
var _warm := 0
var _best_lum := -1.0
var _ready_done := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.time_scale = 0.4
	var lvl: Node = load("res://scenes/levels/level_%s.tscn" % LEVEL).instantiate()
	add_child(lvl)
	var hud := lvl.get_node_or_null("HUD")
	if hud:
		hud.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		if "hp" in _player and _player.hp:
			_player.hp.invulnerable = true
		_player.set_physics_process(false)
		_wm = _find_wm(_player)
	# Grant the weapons we want to showcase (the suburb loadout is only a subset).
	if _wm:
		for w in ["pistol", "plasma", "swarm", "gauss"]:
			var ps := load("res://scenes/weapons/%s.tscn" % w) as PackedScene
			if ps:
				_wm.add_weapon(ps, false)
	_equip_named(WEAPONS[0])
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


func _equip_named(needle: String) -> void:
	if _wm == null:
		return
	for i in _wm.weapons.size():
		var w = _wm.weapons[i]
		if w.data and needle.to_lower() in String(w.data.display_name).to_lower():
			_wm._equip(i)
			_wm._equip_timer = 0.0   # skip the draw lockout for capture
			return


func _process(delta: float) -> void:
	if not _ready_done or _player == null or not is_instance_valid(_player):
		return
	var cam = _player.get("camera")
	if _wm and _wm.current and cam:
		_wm.current.mag = max(_wm.current.mag, 30)
		_wm._equip_timer = 0.0
		_wm.current.try_fire(true, false, cam, _player)
	_warm += 1
	if _warm < 18:        # let the weapon raise + a couple of shots land
		return
	# Keep the brightest frame of this weapon's burst (the flash peak).
	var img := get_viewport().get_texture().get_image()
	var lum := _frame_lum(img)
	if lum > _best_lum:
		_best_lum = lum
		img.save_png("%s/gallery_%d.png" % [OUT, _wi])
	_f += 1
	if _f >= PER_WEAPON:
		var nm: String = (_wm.current.data.display_name if _wm and _wm.current else "?")
		print("GALLERY weapon=%d '%s' lum=%.3f" % [_wi, nm, _best_lum])
		_wi += 1
		if _wi >= WEAPONS.size():
			print("GALLERY DONE n=", _wi)
			get_tree().quit()
			return
		_equip_named(WEAPONS[_wi])
		_f = 0
		_warm = 0
		_best_lum = -1.0


## Cheap whole-frame luminance (sample a coarse grid) — used to pick the flash peak.
func _frame_lum(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	var n := 0
	var sx := maxi(1, w / 40)
	var sy := maxi(1, h / 40)
	for y in range(0, h, sy):
		for x in range(0, w, sx):
			var c := img.get_pixel(x, y)
			sum += c.r + c.g + c.b
			n += 1
	return sum / maxf(1.0, float(n))
