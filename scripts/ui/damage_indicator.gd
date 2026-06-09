extends Control
## Red edge wedges that point toward attackers when the player is hit, then fade.
## Each wedge stores the WORLD position of the hit source and recomputes its
## screen angle every frame from the player's current facing — so as you spin to
## face the threat, the wedge slides up to the top of the screen (and vanishes
## when you're looking right at it). Screen angle: 0 = up (facing), +clockwise.

var _marks: Array = [] # each: {world_pos: Vector3, angle: float, alpha: float}
var _player: Node3D = null

## Called once by the HUD so wedges can track threats relative to player facing.
func setup(player: Node3D) -> void:
	_player = player

## Flash an indicator toward a world-space hit source.
func flash(world_pos: Vector3) -> void:
	_marks.append({"world_pos": world_pos, "angle": _angle_to(world_pos), "alpha": 1.0})
	if _marks.size() > 6:
		_marks.pop_front()
	queue_redraw()

## Screen angle (0 = up/facing, +clockwise) from the player toward a world point.
func _angle_to(world_pos: Vector3) -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	var rel: Vector3 = world_pos - _player.global_position
	var flat := Vector2(rel.x, rel.z)
	if flat.length() < 0.05:
		return 0.0
	var yaw: float = _player.global_rotation.y
	var right := Vector2(cos(yaw), -sin(yaw))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	return atan2(flat.dot(right), flat.dot(fwd))

func _process(delta: float) -> void:
	if _marks.is_empty():
		return
	for m in _marks:
		m.angle = _angle_to(m.world_pos) # re-aim as the player turns
		m.alpha = maxf(0.0, m.alpha - delta * 1.1)
	_marks = _marks.filter(func(m): return m.alpha > 0.01)
	queue_redraw()

func _draw() -> void:
	if _marks.is_empty():
		return
	var c := size * 0.5
	var inner := minf(size.x, size.y) * 0.28
	var outer := inner + 46.0
	var half := deg_to_rad(27.0)
	var steps := 12
	for m in _marks:
		var a0: float = clampf(m.alpha, 0.0, 1.0)
		# Bright hot core fading to a soft red, with a faint outline for punch.
		var col := Color(1.0, 0.22, 0.13, a0 * 0.8)
		var pts := PackedVector2Array()
		for i in steps + 1:
			var a: float = m.angle - half + (2.0 * half) * float(i) / steps
			pts.append(c + Vector2(sin(a), -cos(a)) * outer)
		for i in steps + 1:
			var a: float = m.angle + half - (2.0 * half) * float(i) / steps
			pts.append(c + Vector2(sin(a), -cos(a)) * inner)
		draw_colored_polygon(pts, col)
