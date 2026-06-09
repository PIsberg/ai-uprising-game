extends Control
## On-screen marker over the objective: a diamond + distance when visible, or an
## edge arrow pointing toward it when off-screen / behind the camera.

@export var color: Color = Color(0.4, 1.0, 0.55, 0.92)
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var objs := get_tree().get_nodes_in_group("objective")
	if objs.is_empty():
		return
	var obj := objs[0] as Node3D
	if obj == null:
		return
	var wp := obj.global_position + Vector3.UP * 1.6
	var dist := 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		dist = player.global_position.distance_to(obj.global_position)
	var center := size * 0.5
	var behind := cam.is_position_behind(wp)
	# unproject is in viewport-render pixels; scale to this Control's space.
	var vp_size := get_viewport().get_visible_rect().size
	var sp := cam.unproject_position(wp)
	if vp_size.x > 0.0 and vp_size.y > 0.0:
		sp = sp * (size / vp_size)
	var on_screen := not behind and sp.x >= 0.0 and sp.x <= size.x and sp.y >= 0.0 and sp.y <= size.y
	if on_screen:
		_diamond(sp, 9.0)
		_label(sp + Vector2(0, 30), "OBJECTIVE  %dm" % int(dist))
	else:
		var dir := sp - center
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2(0, -1)
		dir = dir.normalized()
		var edge := center + dir * (minf(size.x, size.y) * 0.42)
		_arrow(edge, dir)
		_label(edge - dir * 26.0 + Vector2(0, 26), "%dm" % int(dist))

func _diamond(p: Vector2, r: float) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	draw_colored_polygon(pts, color)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.6), 1.5)

func _arrow(p: Vector2, dir: Vector2) -> void:
	var perp := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([p + dir * 14.0, p - dir * 9.0 + perp * 9.0, p - dir * 9.0 - perp * 9.0]), color)

func _label(p: Vector2, text: String) -> void:
	if _font == null:
		return
	draw_string(_font, p + Vector2(-46, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 92, 15, color)
