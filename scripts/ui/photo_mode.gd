class_name PhotoMode
extends Node
## PHOTO MODE, opened from the pause menu (or P while paused): the game stays
## frozen, the HUD and every other overlay hide, and a free camera starts at the
## player's eye. WASD flies it (sprint for speed, jump/crouch for up/down), the
## mouse looks, the wheel zooms (FOV_MIN..FOV_MAX), TAB cycles a filter, ENTER
## saves a PNG to user://screenshots/ and ESC returns to the pause menu. The camera
## stays within RADIUS of where it started, so it shows the moment, not the level
## layout. Runs while the tree is paused (PROCESS_MODE_ALWAYS). The HUD builds one
## (hud.gd `photo_mode`). Covered by tests/photo_mode_probe and photo_mode_shot.
# @lat: [[player#Photo Mode]]

signal left

const RADIUS := 12.0
const SPEED := 4.0
const SPRINT_MULT := 3.0
const LOOK := 0.0025 ## rad per pixel of mouse motion
const FOV_MIN := 20.0
const FOV_MAX := 100.0
const FOV_STEP := 4.0
const FILTERS := ["NONE", "NOIR", "SEPIA", "PUNCH", "VIGNETTE"]
const SHOTS_DIR := "user://screenshots"
const FILTER_SHADER := preload("res://shaders/photo_filter.gdshader")

var active := false
var hud: Control = null

var _cam: Camera3D
var _prev_cam: Camera3D
var _origin := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _hidden: Array = [] ## [node, was_visible] for everything hidden on entry
var _layer: CanvasLayer
var _filter: ColorRect
var _mat: ShaderMaterial
var _help: Label
var _flash: Label
var _flash_t := 0.0
var _mouse_before: Input.MouseMode

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.visible = false
	add_child(_layer)
	_filter = ColorRect.new()
	_filter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = FILTER_SHADER
	_filter.material = _mat
	_layer.add_child(_filter)
	_help = Label.new()
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.anchor_right = 1.0
	_help.offset_top = -40
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_constant_override("outline_size", 6)
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_layer.add_child(_help)
	_flash = Label.new()
	_flash.anchor_right = 1.0
	_flash.offset_top = 24
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.add_theme_font_size_override("font_size", 18)
	_flash.add_theme_constant_override("outline_size", 6)
	_flash.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_flash.visible = false
	_layer.add_child(_flash)

## Start from `from` (the player's camera): freeze, hide the UI, take over the view.
func enter(from: Camera3D) -> void:
	if active or from == null:
		return
	active = true
	get_tree().paused = true
	_prev_cam = from
	_cam = Camera3D.new()
	_cam.process_mode = Node.PROCESS_MODE_ALWAYS
	_cam.fov = from.fov
	var host: Node = from.get_tree().current_scene
	if host:
		host.add_child(_cam)
	else:
		add_child(_cam)
	_cam.global_transform = from.global_transform
	_origin = _cam.global_position
	var e := from.global_transform.basis.get_euler()
	_pitch = e.x
	_yaw = e.y
	_cam.make_current()
	_hide_ui()
	# The gun and hands hang under the player's camera in world space: the free
	# camera, starting at the same spot, would film them (tests/photo_mode_shot).
	for c in from.get_children():
		if c is Node3D:
			_hidden.append([c, (c as Node3D).visible])
			(c as Node3D).visible = false
	_mat.set_shader_parameter("mode", 0)
	_layer.visible = true
	_refresh_help()
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Back to the pause menu: the player's camera, the UI as it was, the mouse free.
func leave() -> void:
	if not active:
		return
	active = false
	_layer.visible = false
	for pair in _hidden:
		if is_instance_valid(pair[0]):
			pair[0].visible = pair[1]
	_hidden.clear()
	if is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	if is_instance_valid(_cam):
		_cam.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	left.emit()

## Hide the HUD and every CanvasLayer but ours, remembering each one's visibility.
func _hide_ui() -> void:
	_hidden.clear()
	if hud:
		_hidden.append([hud, hud.visible])
		hud.visible = false
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if n == _layer or _layer.is_ancestor_of(n) or n.is_ancestor_of(_layer):
			continue
		_hidden.append([n, (n as CanvasLayer).visible])
		(n as CanvasLayer).visible = false

func filter_mode() -> int:
	return int(_mat.get_shader_parameter("mode"))

func cycle_filter() -> void:
	_mat.set_shader_parameter("mode", (filter_mode() + 1) % FILTERS.size())
	_refresh_help()

## `dir` -1 zooms in, +1 out.
func zoom(dir: int) -> void:
	if _cam:
		_cam.fov = clampf(_cam.fov + FOV_STEP * dir, FOV_MIN, FOV_MAX)

func _refresh_help() -> void:
	_help.text = tr("WASD fly · mouse look · wheel zoom · TAB filter: %s · ENTER save · ESC back") % tr(String(FILTERS[filter_mode()]))

## Save the frame (without the help line) to SHOTS_DIR; "" if there is no frame to read.
func capture() -> String:
	_help.visible = false
	_flash.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	_help.visible = true
	if img == null or img.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var path := SHOTS_DIR.path_join("photo-%s.png" % Time.get_datetime_string_from_system().replace(":", ""))
	img.save_png(path)
	_flash.text = tr("Saved %s") % ProjectSettings.globalize_path(path)
	_flash.visible = true
	_flash_t = 2.5
	AudioBus.play_synth_ui("pickup_clink", -4.0, 0.6) # the shutter
	return path

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		_yaw -= (event as InputEventMouseMotion).relative.x * LOOK
		_pitch = clampf(_pitch - (event as InputEventMouseMotion).relative.y * LOOK, -1.5, 1.5)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := (event as InputEventMouseButton).button_index
		if mb == MOUSE_BUTTON_WHEEL_UP:
			zoom(-1)
		elif mb == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_TAB:
			cycle_filter()
		elif k == KEY_ENTER or k == KEY_KP_ENTER:
			capture()
		elif event.is_action("pause"):
			leave()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	if not active or not is_instance_valid(_cam):
		return
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := _cam.global_transform.basis * Vector3(v.x, 0.0, v.y)
	if Input.is_action_pressed("jump"):
		dir += Vector3.UP
	if Input.is_action_pressed("crouch"):
		dir += Vector3.DOWN
	if dir.length() > 0.01:
		var speed := SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
		var next := _cam.global_position + dir.normalized() * speed * delta
		var off := next - _origin
		if off.length() > RADIUS:
			next = _origin + off.normalized() * RADIUS
		_cam.global_position = next
