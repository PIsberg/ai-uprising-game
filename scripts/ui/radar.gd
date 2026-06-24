extends Control
## Player-relative HUD radar: enemies (red) + objective (green) blips around a
## central player arrow. "Up" is always the direction the player faces.

@export var world_range: float = 45.0  ## metres mapped to the radar edge
@export var enemy_color: Color = Color(1.0, 0.3, 0.25)
@export var elite_color: Color = Color(1.0, 0.82, 0.2) ## Elites: a bigger gold blip.
@export var objective_color: Color = Color(0.4, 1.0, 0.55)

var _player: Node3D
var _sweep_mat: ShaderMaterial
var _sweep_angle: float = 0.0

func _ready() -> void:
	_build_sweep()

## A rotating conic-gradient beam (4.7 GradientTexture2D FILL_CONIC) sweeping the
## dish, masked to the circle by shaders/radar_sweep.gdshader.
func _build_sweep() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.4, 1.0])
	grad.colors = PackedColorArray([
		Color(0.5, 1.0, 1.0, 0.0),   # just behind the beam: clear
		Color(0.45, 1.0, 1.0, 0.55), # bright leading edge
		Color(0.3, 0.85, 1.0, 0.12), # trailing afterglow
		Color(0.3, 0.85, 1.0, 0.0),  # faded out
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_CONIC
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	_sweep_mat = ShaderMaterial.new()
	_sweep_mat.shader = preload("res://shaders/radar_sweep.gdshader")
	var tr := TextureRect.new()
	tr.texture = tex
	tr.material = _sweep_mat
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _sweep_mat:
		_sweep_angle = fmod(_sweep_angle + delta * 1.8, TAU) # ~3.5s per revolution
		_sweep_mat.set_shader_parameter("angle", _sweep_angle)
	queue_redraw()

func _draw() -> void:
	var r := size.x * 0.5
	var c := Vector2(r, r)
	# Dish + ring.
	draw_circle(c, r, Color(0.0, 0.0, 0.0, 0.45))
	draw_arc(c, r, 0.0, TAU, 48, Color(0.4, 0.9, 1.0, 0.55), 2.0, true)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0.4, 0.9, 1.0, 0.12), 1.0)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0.4, 0.9, 1.0, 0.12), 1.0)
	if _player == null or not is_instance_valid(_player):
		return
	var yaw := _player.global_rotation.y
	var right := Vector2(cos(yaw), -sin(yaw))   # world XZ of player's right
	var fwd := Vector2(-sin(yaw), -cos(yaw))    # world XZ of player's forward
	var pp := _player.global_position
	var scale := r / world_range

	for o in get_tree().get_nodes_in_group("objective"):
		if o is Node3D:
			_blip(o as Node3D, pp, right, fwd, scale, c, r, objective_color, 4.0)
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and not (e as EnemyBase).hp.is_alive():
			continue
		if e is Node3D:
			# Elites read as a bigger gold blip so a priority threat is spottable
			# on the radar, not just by its in-world glow.
			var is_elite: bool = e is EnemyBase and (e as EnemyBase).elite != ""
			var col := elite_color if is_elite else enemy_color
			_blip(e as Node3D, pp, right, fwd, scale, c, r, col, 4.5 if is_elite else 3.5)

	# Player marker (triangle pointing up = forward).
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -7), c + Vector2(-5, 6), c + Vector2(5, 6)]),
		Color(1, 1, 1, 0.95))

func _blip(n: Node3D, pp: Vector3, right: Vector2, fwd: Vector2, scale: float, c: Vector2, r: float, col: Color, radius: float) -> void:
	var rel := n.global_position - pp
	var flat := Vector2(rel.x, rel.z)
	var screen := Vector2(flat.dot(right), -flat.dot(fwd)) * scale
	# Clamp out-of-range blips to the rim so off-radar threats still show.
	if screen.length() > r - radius:
		screen = screen.normalized() * (r - radius)
	draw_circle(c + screen, radius, col)
