class_name CoopHud
extends CanvasLayer
## Player two's HUD in co-op split screen (#402, stage 3): health, stamina,
## ammo, a crosshair, and the revive state (down, or reviving the partner).
## Player one keeps the full HUD (hud.gd), which also owns the shared overlays:
## score, objectives, toasts and the pause, game-over and win menus.

var player: Node3D
var _health: ProgressBar
var _stamina: ProgressBar
var _ammo: Label
var _status: Label
var _revive: ProgressBar

func _ready() -> void:
	layer = 1
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 28)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(cross)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(24, -120)
	box.custom_minimum_size = Vector2(260, 0)
	root.add_child(box)
	var tag := Label.new()
	tag.text = tr("PLAYER %d") % (int(player.get("player_index")) + 1 if player else 2)
	box.add_child(tag)
	_health = _bar(box, Color(0.85, 0.2, 0.2))
	_stamina = _bar(box, Color(0.3, 0.8, 1.0))
	_ammo = Label.new()
	_ammo.add_theme_font_size_override("font_size", 22)
	box.add_child(_ammo)
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_CENTER)
	_status.position.y += 60
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status)
	_revive = ProgressBar.new()
	_revive.set_anchors_preset(Control.PRESET_CENTER)
	_revive.position += Vector2(-100, 90)
	_revive.custom_minimum_size = Vector2(200, 12)
	_revive.max_value = 1.0
	_revive.show_percentage = false
	_revive.visible = false
	root.add_child(_revive)

func _bar(parent: Control, col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(260, 14)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	b.add_theme_stylebox_override("fill", fill)
	parent.add_child(b)
	return b

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	var hp: Damageable = player.get("hp")
	if hp:
		_health.max_value = hp.max_health
		_health.value = hp.current_health
	var st = player.get("_stamina")
	var st_max = player.get("max_stamina")
	if st != null and st_max != null:
		_stamina.max_value = float(st_max)
		_stamina.value = float(st)
	var wm = player.get_node_or_null("Head/Camera3D/WeaponHolder")
	if wm and wm.get("current"):
		_ammo.text = "%d / %d" % [int(wm.current.mag), int(wm.current.reserve)]
	# Revive state: this player is down, or is holding the button over a downed partner.
	var progress := 0.0
	var text := ""
	if player.get("downed") == true:
		progress = float(player.get("revive_progress"))
		text = tr("DOWN: your partner can revive you")
	else:
		for p in GameState.players():
			if p != player and p.get("downed") == true:
				progress = maxf(progress, float(p.get("revive_progress")))
				text = tr("Partner down: hold interact beside them")
	_status.text = text
	_revive.visible = progress > 0.0
	_revive.value = progress
