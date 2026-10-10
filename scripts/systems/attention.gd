class_name Attention
extends RefCounted
## Whether an ATTENTION HEAD (enemy_attention.gd) has the player in its gaze.
## While it does, every robot's aim error shrinks to ATTENDED_SPREAD of itself
## (EnemyBase.scatter_aim). A head refreshes the hold every frame its cone is
## on the player, so the attention ends HOLD_MS after the gaze breaks. Lives
## outside EnemyBase so the base never names a subclass. tests/attention_probe.

const ATTENDED_SPREAD := 0.45
const HOLD_MS := 300

static var until_ms := 0

static func is_attended() -> bool:
	return Time.get_ticks_msec() < until_ms

static func hold() -> void:
	until_ms = Time.get_ticks_msec() + HOLD_MS

static func spread_mult() -> float:
	return ATTENDED_SPREAD if is_attended() else 1.0
