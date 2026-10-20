class_name OrbitalStrike
# @lat: [[meta-systems#Orbital Strike]]
extends Node3D
## The overlord's satellite paints the player: a targeting circle on the
## ground under a thin beam from the sky TRACKS them (lagging, so a straight
## run drags it behind you) for TRACK_TIME, then LOCKS where it is for
## LOCK_TIME, turning red, pulsing and whining, then FIRES a column of light
## down the circle. Inside the circle and under open sky it costs DAMAGE.
## Two answers: step out of the circle while it is red, or be under a roof
## (the beam comes straight down; a world-layer ray up from the player's head
## that hits anything means covered). Robots are never hurt. Spawned by the
## ORBITAL STRIKE skirmish event (GameState._event_orbital_strike); it frees
## itself when done. tests/orbital_strike_probe.

enum Phase { TRACK, LOCK, FIRE }

const TRACK_TIME := 4.0
const LOCK_TIME := 1.0
const RADIUS := 3.0
const DAMAGE := 45.0
const FOLLOW := 3.0       ## 1/s: how fast the circle catches up with the player
const SKY := 40.0
const TRACK_COLOR := Color(1.0, 0.65, 0.15)
const LOCK_COLOR := Color(1.0, 0.12, 0.08)

var phase: Phase = Phase.TRACK
var _t := 0.0
var _pos := Vector3.ZERO
var _started := false
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("orbital_strike")
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = TRACK_COLOR
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RADIUS - 0.18
	tm.outer_radius = RADIUS
	_ring.mesh = tm
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.albedo_color = Color(TRACK_COLOR, 0.35)
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.08
	cm.height = SKY
	_beam.mesh = cm
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)

## The player the circle follows: the nearest one to it (co-op).
func _player() -> Node3D:
	return GameState.nearest_player(_pos if _started else global_position)

## Where the circle is centred (on the ground plane under the player).
func reticle_pos() -> Vector3:
	return _pos

func _place() -> void:
	_ring.global_position = _pos + Vector3.UP * 0.06
	_beam.global_position = _pos + Vector3.UP * (SKY * 0.5)

func _physics_process(delta: float) -> void:
	var p := _player()
	if not _started:
		if p == null:
			return
		_pos = p.global_position
		_started = true
	_t += delta
	match phase:
		Phase.TRACK:
			if p:
				_pos = _pos.lerp(p.global_position, 1.0 - exp(-FOLLOW * delta))
			_ring_mat.albedo_color = TRACK_COLOR
			if _t >= TRACK_TIME:
				phase = Phase.LOCK
				_t = 0.0
				AudioBus.play_synth_at("charge", _pos, 0.0, 0.7)
		Phase.LOCK:
			var blink := 0.5 + 0.5 * sin(_t * (12.0 + 30.0 * _t))
			_ring_mat.albedo_color = LOCK_COLOR.lerp(Color.WHITE, blink * 0.4)
			_beam_mat.albedo_color = Color(LOCK_COLOR, 0.35 + 0.4 * (_t / LOCK_TIME))
			if _t >= LOCK_TIME:
				phase = Phase.FIRE
				_t = 0.0
				_fire(p)
		Phase.FIRE:
			_beam_mat.albedo_color.a = maxf(0.0, 0.95 - _t * 1.6)
			if _t >= 0.6:
				queue_free()
	_place()

func _covered(p: Node3D) -> bool:
	return covered(p)

## Is anything (world layer) over `p`'s head within SKY? The event uses it to
## skip indoor players, where a strike could never land.
static func covered(p: Node3D) -> bool:
	var from := p.global_position + Vector3.UP * 2.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * SKY, 1)
	return not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _fire(p: Node3D) -> void:
	# The column of light: the thin beam swells to the circle's width.
	(_beam.mesh as CylinderMesh).top_radius = RADIUS * 0.9
	(_beam.mesh as CylinderMesh).bottom_radius = RADIUS
	_beam_mat.albedo_color = Color(1.0, 0.95, 0.85, 0.95)
	_ring_mat.albedo_color = Color.WHITE
	AudioBus.play_synth_at("explosion", _pos, 2.0, 0.8)
	for q in GameState.players(): # everyone under the circle, not only the one it tracked
		var d := Vector2(q.global_position.x - _pos.x, q.global_position.z - _pos.z).length()
		if d > RADIUS or _covered(q):
			continue
		var hp := q.get_node_or_null("Damageable") as Damageable
		if hp and hp.is_alive():
			hp.apply_damage(DAMAGE, self)
		if q.has_method("shake"):
			q.shake(0.6)

## The death screen's "Taken down by" name and its tip key (player.gd reads it
## off any damage source that has it; hud.gd DEATH_TIPS).
func _kill_label() -> String:
	return "ORBITAL STRIKE"
