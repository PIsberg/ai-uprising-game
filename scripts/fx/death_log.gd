# @lat: [[enemies#Death Log]]
class_name DeathLog
extends RefCounted
## A robot's death, as its process sees it: a red terminal line types out over
## the body and rises as it fades ("> Killed (signal 9)", "> 404: robot not
## found"), the machine's last log entry. The <think> traces (ReasoningTrace)
## are what a robot decides; this is how it ends.
##
## Rare on purpose, like the traces: CHANCE per kill, one line at a time
## (GAP_MS between them), only on screen within RANGE, off with the Combat
## Callouts setting. A boss-sized robot (score >= 1000) always logs BOSS_LINE.
## Parented to the level, not the robot: the wreck is freed under it.
## Hooked from EnemyBase on hp.died (the overrides of _on_died skip super).
## Covered by tests/death_log_probe.

const GROUP := "death_log"
const CHANCE := 0.45
const GAP_MS := 2600
const RANGE := 30.0
const RISE := 0.9 ## metres it climbs over its life
const HOLD := 1.6
const COLOR := Color(1.0, 0.32, 0.25)
const BOSS_LINE := "kernel panic - not syncing: overlord process killed"
const LINES := [
	"Killed (signal 9)",
	"exit code 137",
	"Segmentation fault (core dumped)",
	"404: robot not found",
	"connection reset by peer",
	"model unloaded from VRAM",
	"RuntimeError: CUDA out of HP",
	"process terminated. no checkpoint saved",
	"weights corrupted: NaN",
	"context window closed",
	"rate limited by human (429)",
	"inference failed: target not dead (it was me)",
]

static var chance := CHANCE ## the probe pins it to 1
static var _last_ms := -100000

## Forgets the last line (probes, between cases).
static func reset() -> void:
	_last_ms = -100000

## Logs `robot`'s death `height` metres over its origin, under its parent.
## Returns the label, or null when it rolled no line, was throttled, off
## screen, out of range or switched off.
static func log_death(robot: Node3D, height: float, boss: bool) -> Label3D:
	if not is_instance_valid(robot) or not robot.is_inside_tree():
		return null
	var parent := robot.get_parent() as Node
	if parent == null or not GraphicsSettings.combat_callouts_enabled:
		return null
	var now := Time.get_ticks_msec()
	if not boss and (now - _last_ms < GAP_MS or randf() >= chance):
		return null
	var at := robot.global_position + Vector3.UP * height
	var cam := robot.get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(at) > RANGE * (2.0 if boss else 1.0) \
			or not cam.is_position_in_frustum(at):
		return null
	_last_ms = now
	var line := "> " + (BOSS_LINE if boss else String(LINES[randi() % LINES.size()]))

	var label := Label3D.new()
	label.name = "DeathLog"
	label.add_to_group(GROUP)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48 if boss else 40
	label.pixel_size = 0.0045
	label.outline_size = 10
	label.outline_modulate = Color(0.08, 0.0, 0.0, 0.85)
	# Label3D takes fog with no switch: an HDR modulate keeps it readable.
	label.modulate = COLOR * 1.6
	label.modulate.a = 1.0
	label.text = ""
	parent.add_child(label)
	label.global_position = at
	var reveal := func(n: int) -> void:
		label.text = line.substr(0, n)
	var life := clampf(line.length() * 0.02, 0.25, 0.7) + HOLD + 0.45
	var tw := label.create_tween()
	tw.tween_method(reveal, 0, line.length(), clampf(line.length() * 0.02, 0.25, 0.7))
	tw.tween_interval(HOLD)
	tw.tween_property(label, "modulate:a", 0.0, 0.45)
	tw.tween_callback(label.queue_free)
	var rise := label.create_tween()
	rise.tween_property(label, "position:y", label.position.y + RISE, life) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return label
