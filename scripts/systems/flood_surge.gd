class_name FloodSurge
extends Node3D
# @lat: [[level-system#Hazard Surges]]
## A survive-hold wave's "flood": hazard beds that rise out of the floor in the
## middle of the fight, so the hold changes the ground under the player instead
## of only adding enemies. Vulcan Forge floods its walkable cross-lanes with
## magma (the fight moves up onto the catwalks); Tidecore Basin's tide climbs
## over the whole low tier (the reactor cap is the last dry deck).
##
## Lifecycle: WARN (pulsing sheets over each bed's footprint + a HUD alert, so a
## player on the doomed ground has `warn_seconds` to climb), then LIVE (each bed
## is a real LavaHazard that rises `RISE_DEPTH` into place over `rise_seconds`),
## then DRAINED when the survive task completes: the beds sink and free, so the
## walk to the exit and the completion checkpoint are never inside a hazard.
##
## Death clears the beds at once and re-runs the warning when play resumes.
## Checkpoint respawn is IN PLACE, back where the last objective finished, and
## that spot can be on the flooded ground: a bed left standing would be a death
## loop. The clock only runs while the game is PLAYING.

## How far below its final height a bed starts its rise: under the floor plane,
## so the fluid wells up out of the ground rather than fading in.
const RISE_DEPTH := 0.6

@export var task_id: String = "survive"
@export var warn_seconds: float = 3.0
@export var rise_seconds: float = 1.2
## Bed specs, the same format as the level def's "lava" entries:
## {pos, size: Vector2, dmg?, water?, color?}. pos.y is the bed's final height.
var beds: Array = []
var warn_title: String = "SURGE"
var warn_text: String = "The floor is flooding. Get to high ground."
var drain_title: String = ""
var drain_text: String = ""

enum Phase { WARN, LIVE, DRAINED }
var phase: Phase = Phase.WARN
var _t: float = 0.0
var _rearm: bool = false
var _marks: Array[MeshInstance3D] = []
var _mark_mat: StandardMaterial3D
var _live: Array[LavaHazard] = []

func _ready() -> void:
	GameState.player_died.connect(_on_player_died)
	_warn()

func _warn() -> void:
	phase = Phase.WARN
	_t = 0.0
	var water := false
	for b in beds:
		water = water or bool(b.get("water", false))
	var col: Color = Color(0.3, 0.85, 1.0) if water else Color(1.0, 0.35, 0.08)
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mark_mat.albedo_color = Color(col.r, col.g, col.b, 0.15)
	for b in beds:
		var pm := PlaneMesh.new()
		pm.size = b.get("size", Vector2(4, 4))
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = _mark_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Just over where the fluid's surface will stand, so the sheet marks the
		# height the flood reaches, not only its footprint.
		var p: Vector3 = b.get("pos", Vector3.ZERO)
		mi.position = p + Vector3(0, 0.12, 0)
		add_child(mi)
		_marks.append(mi)
	GameState.skirmish_event.emit(warn_title, warn_text)
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_ui("overlord_glitch", -2.0, 0.55)

func _process(delta: float) -> void:
	if phase == Phase.DRAINED:
		return
	if GameState.is_task_done(task_id):
		_drain()
		return
	if GameState.current_state != GameState.State.PLAYING:
		return
	if _rearm:
		_rearm = false
		_warn()
		return
	if phase != Phase.WARN:
		return
	_t += delta
	# The pulse quickens as the surge comes due.
	var k := clampf(_t / maxf(warn_seconds, 0.01), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * (5.0 + 16.0 * k))
	if _mark_mat:
		_mark_mat.albedo_color.a = 0.08 + 0.32 * pulse
	if _t >= warn_seconds:
		_rise()

func _rise() -> void:
	phase = Phase.LIVE
	_clear_marks()
	for b in beds:
		var lava := LavaHazard.new()
		lava.size = b.get("size", Vector2(4, 4))
		lava.shore = false # rises over existing ground and decks: no flush shoreline plane
		if b.has("dmg"):
			lava.damage_per_tick = b["dmg"]
		if b.get("water", false):
			lava.water = true
		if b.has("color"):
			lava.recolor = true
			lava.hazard_color = b["color"]
		var target: Vector3 = b.get("pos", Vector3.ZERO)
		lava.position = target - Vector3(0, RISE_DEPTH, 0)
		add_child(lava)
		lava.create_tween().tween_property(lava, "position:y", target.y, rise_seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_live.append(lava)

func _drain() -> void:
	phase = Phase.DRAINED
	_clear_marks()
	for lava in _live:
		if not is_instance_valid(lava):
			continue
		# Stop burning at once (the hold is won), then sink out of sight.
		lava.set_process(false)
		lava.monitoring = false
		var tw := lava.create_tween()
		tw.tween_property(lava, "position:y", lava.position.y - RISE_DEPTH - 0.2, 1.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(lava.queue_free)
	_live.clear()
	if drain_title != "":
		GameState.skirmish_event.emit(drain_title, drain_text)

func _on_player_died() -> void:
	if phase == Phase.DRAINED:
		return
	_clear_marks()
	for lava in _live:
		if is_instance_valid(lava):
			lava.queue_free()
	_live.clear()
	_rearm = true

func _clear_marks() -> void:
	for m in _marks:
		if is_instance_valid(m):
			m.queue_free()
	_marks.clear()

## Live beds, for probes and debugging.
func live_beds() -> Array[LavaHazard]:
	return _live
