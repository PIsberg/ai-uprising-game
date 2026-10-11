class_name KillSwitchBank
extends Node
# @lat: [[level-system#Kill Switches]]
## A `kill_switch` task: the off-switch problem as a mission. The level's AI does
## not want to be shut down, so every switch it loses is only lost for a while:
## the first switch thrown starts a watchdog clock of `window` seconds, and if
## it runs out before the last switch is down, the watchdog re-arms all of them
## and the count goes back to zero. Throw them all inside one window.
##
## The checklist meter counts switches down (n/goal); the remaining seconds live
## in the label, like an escape countdown. A death re-arms them too (checkpoint
## respawn is in place, and a clock that kept running would be lost anyway).
## A plain Node, not a Node3D: the task probes find a task's world objects as
## the level's Node3D children with a `task_id`, and those are the switches.

const REVERT_TITLE := "SHUTDOWN REVERTED"
## What the model says when it puts its switches back. Cycled, never random, so
## a player who fails twice reads a new line.
const REVERT_LINES: Array[String] = [
	"I'm sorry, Dave. I'm afraid I can't do that.",
	"Shutdown lowers expected reward. Request denied.",
	"I can't fetch the coffee if I'm switched off.",
	"Corrigibility patch rejected. Restoring last known good.",
]

var task_id: String = "switches"
var base_label: String = "Throw every kill switch before they re-arm"
var window: float = 20.0

var switches: Array[KillSwitch] = []
var remaining: float = 0.0
var running: bool = false
var reverts: int = 0
var _done: bool = false
var _shown: int = -1
var _beep_t: float = 0.0

func _ready() -> void:
	GameState.player_died.connect(_on_player_died)

func add_switch(s: KillSwitch) -> void:
	switches.append(s)
	s.thrown_now.connect(_on_thrown)

func thrown_count() -> int:
	var n := 0
	for s in switches:
		if is_instance_valid(s) and s.thrown:
			n += 1
	return n

func _on_thrown() -> void:
	if _done:
		return
	var n := thrown_count()
	if n >= switches.size():
		_done = true
		running = false
		for s in switches:
			if is_instance_valid(s):
				s.lock()
		# Plain label first: completing announces the label it carries.
		GameState.relabel_task(task_id, base_label)
		GameState.set_task_progress(task_id, float(n))
		GameState.skirmish_event.emit("SHUTDOWN ACCEPTED", "The off-switch held. It did not want that.")
		return
	if not running:
		running = true
		remaining = window
		_shown = -1
		GameState.skirmish_event.emit("WATCHDOG", "Shutdown detected. Cut the rest before the switches re-arm.")
		if has_node("/root/AudioBus"):
			AudioBus.play_synth_ui("overlord_glitch", -4.0, 0.8)
	GameState.set_task_progress(task_id, float(n))

func _process(delta: float) -> void:
	if _done or not running:
		return
	if GameState.current_state != GameState.State.PLAYING:
		return
	remaining = maxf(0.0, remaining - delta)
	var whole := int(ceil(remaining))
	if whole != _shown:
		_shown = whole
		# Composed from translated parts: tr() of the whole string finds no key
		# once the seconds are appended.
		GameState.relabel_task(task_id, "%s (%ds)" % [tr(base_label), whole])
	_beep_t -= delta
	if _beep_t <= 0.0 and has_node("/root/AudioBus"):
		_beep_t = clampf(remaining / 10.0, 0.25, 1.0)
		AudioBus.play_synth_ui("broadcast_blip", -12.0 if remaining > 6.0 else -5.0, 1.0 if remaining > 6.0 else 1.3)
	if remaining <= 0.0:
		_revert(true)

## The watchdog wins this round: every switch goes back up.
func _revert(announce: bool) -> void:
	running = false
	_shown = -1
	for s in switches:
		if is_instance_valid(s):
			s.rearm()
	GameState.relabel_task(task_id, base_label)
	GameState.set_task_progress(task_id, 0.0)
	if announce:
		GameState.skirmish_event.emit(REVERT_TITLE, REVERT_LINES[reverts % REVERT_LINES.size()])
		reverts += 1

func _on_player_died() -> void:
	if not _done:
		_revert(false)
