extends Control
## Pool of red arcs that flare toward an attacker's screen-relative heading, then
## fade over ~0.7s. Off-screen hits are otherwise invisible, so this is the only
## cue telling the player which way to turn. Heading is camera-yaw-relative
## (screen-up = the direction the player's camera faces, flattened to XZ; pitch
## is irrelevant here) and is computed once at the moment of the hit — arcs do
## NOT re-track as the player turns, since a single flash is enough signal and
## constant re-aiming would fight the fade-out.
## A fixed pool (not one-shot spawns) means a burst of hits can't leak nodes;
## the oldest slot is recycled first so rapid multi-hits still all read.

const POOL_SIZE := 4
const ARC_RADIUS := 70.0
const ARC_SPAN := deg_to_rad(40.0)
const ARC_WIDTH := 7.0
const ARC_COLOR := Color(1.0, 0.15, 0.1)
const FADE_TIME := 0.7
const PEAK_ALPHA := 0.9

var _player: Node3D = null
var _arcs: Array[Control] = []
var _next: int = 0 ## Round-robin index into the pool.

## Called once by the HUD so arcs can compute heading from the player's facing.
func setup(player: Node3D) -> void:
	_player = player

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in POOL_SIZE:
		var arc := Control.new()
		arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arc.modulate.a = 0.0
		add_child(arc)
		arc.draw.connect(_draw_arc.bind(arc))
		_arcs.append(arc)

## Authored pointing "up" (local angle -90 deg); the arc Control's own rotation
## then carries it to the actual damage heading.
func _draw_arc(arc: Control) -> void:
	arc.draw_arc(Vector2.ZERO, ARC_RADIUS, -PI / 2.0 - ARC_SPAN / 2.0, -PI / 2.0 + ARC_SPAN / 2.0, 24, ARC_COLOR, ARC_WIDTH, true)

## Flash an indicator toward a world-space hit source (recycles the oldest slot).
func flash(world_pos: Vector3) -> void:
	var arc := _arcs[_next]
	_next = (_next + 1) % _arcs.size()
	arc.position = size * 0.5
	arc.rotation = _heading_to(world_pos)
	# Accessibility: flash_intensity 0 must fully hide the arc, so it's baked into
	# the peak rather than only scaling the eventual fade target.
	arc.modulate.a = PEAK_ALPHA * GraphicsSettings.flash_intensity
	var tw := create_tween()
	tw.tween_property(arc, "modulate:a", 0.0, FADE_TIME)

## Screen-space heading (0 = up/facing, +clockwise) from the player toward a
## world point, flattened to XZ and relative to camera yaw only.
func _heading_to(world_pos: Vector3) -> float:
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
