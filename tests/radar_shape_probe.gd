extends Node
## Windowed: radar blips must differ by SHAPE, not only colour (#150). Enemies
## were red dots (r 3.5 px) and objectives green dots (r 4.0 px), the exact
## red/green pair protanopia and deuteranopia confuse, and elites a gold dot
## only 1 px larger than an enemy's.
##
## The probe draws the real HUD radar (scaled x4 so a blip spans dozens of
## pixels, sweep beam hidden) with an enemy, an elite and an objective at known
## bearings, renders it, and cuts the pixel mask of each blip from the frame
## after passing it through a protanopia simulation (Machado 2009) and a
## brightness threshold, i.e. what a protanope can tell is "lit". Every pair of
## blip masks must overlap by at most MAX_IOU (intersection over union), so the
## three read as different marks with the colour taken away.
##   godot --path . res://tests/radar_shape_probe.tscn [-- <out.png>]
## (pass a path after `--` to save the rendered frame for a look)

const MAX_IOU := 0.5
const ZOOM := 4.0
const SIZE := 160.0 # radar control size before ZOOM
const WIN := 13     # half-size of the cut-out window, in radar pixels
const PROTAN := [Vector3(0.152286, 1.052583, -0.204868), Vector3(0.114503, 0.786281, 0.099216), Vector3(-0.003882, -0.048116, 1.051998)]

var _fail: Array[String] = []
var _k := 1.0

func _check(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _marker(group: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.add_to_group(group)
	add_child(n)
	n.global_position = pos
	return n

func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var player := _marker("player", Vector3.ZERO) # yaw 0: radar up = -Z
	var r := SIZE * 0.5
	var world_range := 45.0
	var spots := {
		"enemy": Vector3(-20, 0, -20),
		"objective": Vector3(20, 0, -20),
		"elite": Vector3(0, 0, 20),
	}
	_marker("enemy", spots["enemy"])
	_marker("objective", spots["objective"])
	var elite: EnemyBase = load("res://scenes/enemies/android.tscn").instantiate()
	elite.elite = "swift"
	add_child(elite)
	elite.set_physics_process(false)
	elite.process_mode = Node.PROCESS_MODE_DISABLED
	elite.global_position = spots["elite"]

	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var radar: Control = Control.new()
	radar.set_script(load("res://scripts/ui/radar.gd"))
	radar.size = Vector2(SIZE, SIZE)
	radar.position = Vector2(20, 20)
	radar.scale = Vector2(ZOOM, ZOOM)
	radar.set("world_range", world_range)
	layer.add_child(radar)
	await get_tree().process_frame
	for ch in radar.get_children():
		if ch is CanvasItem:
			(ch as CanvasItem).visible = false # the rotating sweep beam

	for i in 6:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if OS.get_cmdline_user_args().size() > 0:
		img.save_png(OS.get_cmdline_user_args()[0])
	# The frame can be larger than the canvas (stretch mode, window scale):
	# map canvas pixels to image pixels.
	_k = float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var masks := {}
	var s := r / world_range
	for key in spots:
		var p: Vector3 = spots[key]
		var centre := Vector2(r + p.x * s, r + p.z * s) # yaw 0: screen = (x, z)
		masks[key] = _mask(img, (radar.position + centre * ZOOM) * _k)
		print("       %s blip: %d lit px" % [key, (masks[key] as PackedByteArray).count(1)])
		_check((masks[key] as PackedByteArray).count(1) > 0, "%s blip is drawn" % key)

	var keys: Array = masks.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var iou := _iou(masks[keys[i]], masks[keys[j]])
			_check(iou <= MAX_IOU, "%s vs %s blips overlap %.2f with colour removed (max %.2f)"
				% [keys[i], keys[j], iou, MAX_IOU])

	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit(0 if _fail.is_empty() else 1)

## Lit/unlit mask around `at` as a protanope sees it: simulated colour, then
## "lit" = brighter than the dish background by a clear margin.
func _mask(img: Image, at: Vector2) -> PackedByteArray:
	var out := PackedByteArray()
	var half := int(WIN * ZOOM * _k)
	var bg := _seen(img.get_pixel(int(at.x) + half, int(at.y) + half))
	for y in range(-half, half + 1):
		for x in range(-half, half + 1):
			var px := clampi(int(at.x) + x, 0, img.get_width() - 1)
			var py := clampi(int(at.y) + y, 0, img.get_height() - 1)
			out.append(1 if _seen(img.get_pixel(px, py)) - bg > 0.15 else 0)
	return out

static func _seen(c: Color) -> float:
	var v := Vector3(c.r, c.g, c.b)
	var sim := Vector3(PROTAN[0].dot(v), PROTAN[1].dot(v), PROTAN[2].dot(v))
	return sim.dot(Vector3(0.2126, 0.7152, 0.0722))

static func _iou(a: PackedByteArray, b: PackedByteArray) -> float:
	var inter := 0
	var uni := 0
	for i in a.size():
		if a[i] == 1 and b[i] == 1:
			inter += 1
		if a[i] == 1 or b[i] == 1:
			uni += 1
	return float(inter) / maxf(1.0, float(uni))
