class_name EscapeZone
extends HoldZone
# @lat: [[level-system#Escape Countdown]]
## An "escape" task: the moment this stage goes live a purge countdown starts,
## and stepping into the extraction ring (a HoldZone beacon at this node)
## before it runs out completes the task, which is what unlocks the exit. Let
## it run out and the purge burns the player at `purge_dps` until they reach
## the ring, so a late run still lands if there is health to spend.
##
## The HUD line carries the remaining seconds in the task label: a (n/goal)
## meter would read as counting UP, the opposite of what a countdown means.
## The clock only runs while the game is PLAYING (not paused / in a menu),
## and restarts in full when the player dies (see _restart_clock).

@export var seconds: float = 45.0
@export var purge_dps: float = 18.0
var base_label: String = "Reach extraction before the purge"

var remaining: float = 0.0
var purging: bool = false
var _shown: int = -1
var _beep_t: float = 0.0

func _ready() -> void:
	remaining = seconds
	super._ready()
	# Checkpoint respawn is IN PLACE (GameState.respawn_at_checkpoint, no
	# reload), back at the last objective. A clock left at zero would purge the
	# respawned player all the way here, a death loop. Death holds the clock
	# (GAME_OVER is not PLAYING) and this hands the respawn a fresh one.
	GameState.player_died.connect(_restart_clock)
	GameState.skirmish_event.emit("PURGE INITIATED", "%d seconds to extraction." % int(seconds))
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_ui("overlord_glitch", -2.0, 0.7)

func _process(delta: float) -> void:
	_t += delta
	if _done:
		return
	if GameState.current_state != GameState.State.PLAYING:
		return
	if _inside > 0:
		_extract()
		return
	remaining = maxf(0.0, remaining - delta)
	var whole := int(ceil(remaining))
	if whole != _shown:
		_shown = whole
		# Composed from translated parts: the HUD's tr() of the whole string
		# finds no key once the seconds are appended.
		GameState.relabel_task(task_id, "%s (%ds)" % [tr(base_label), whole] if whole > 0 else "%s: %s" % [tr(base_label), tr("PURGE ACTIVE")])
		if whole == 10:
			GameState.skirmish_event.emit("10 SECONDS", "Purge imminent. Get to extraction.")
	# A klaxon tick that speeds up as the clock runs down.
	_beep_t -= delta
	if _beep_t <= 0.0 and has_node("/root/AudioBus"):
		_beep_t = clampf(remaining / 12.0, 0.25, 1.0)
		AudioBus.play_synth_ui("broadcast_blip", -10.0 if remaining > 10.0 else -4.0, 0.7 if remaining > 10.0 else 1.1)
	if remaining <= 0.0:
		if not purging:
			purging = true
			GameState.skirmish_event.emit("PURGE", "The site is burning. Keep moving.")
		var player := get_tree().get_first_node_in_group("player")
		if player and player.get("hp") is Damageable:
			(player.get("hp") as Damageable).apply_damage(purge_dps * delta, self)
	# The beacon strobes harder as time runs out, red once the purge is live.
	var urgency := 1.0 - remaining / maxf(seconds, 0.01)
	var col := Color(1.0, 0.15, 0.1) if purging else accent
	var rate := 2.5 + urgency * 9.0
	if _ring_mat:
		_ring_mat.emission = col
		_ring_mat.emission_energy_multiplier = 3.0 + sin(_t * rate) * 1.5
	if _col_mat:
		_col_mat.emission = col
	if _light:
		_light.light_color = col
		_light.light_energy = 2.0 + sin(_t * rate) * 0.8

func _restart_clock() -> void:
	if _done:
		return
	remaining = seconds
	purging = false
	_shown = -1

func _extract() -> void:
	GameState.relabel_task(task_id, base_label)
	GameState.complete_task(task_id)
	_on_complete()
