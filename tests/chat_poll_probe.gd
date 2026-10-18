extends Node
## Probe: CHAT POLL. When a mid-level surprise event comes due, the MACHINE FEED
## audience votes between two of them for GameState.POLL_TIME; the winner runs.
## (1) every event id has a title;
## (2) a due event opens a poll between two different events and runs nothing yet;
## (3) votes tick up through the poll; at the end the leading option wins, runs
##     (a GRID SURGE that won leaves the surge live) and counts as the level's event;
## (4) the poll clock stops while the game is paused;
## (5) the feed shows the poll with both titles while it is open, hides it after,
##     and posts the result.
##   godot --headless --path . --audio-driver Dummy res://tests/chat_poll_probe.tscn

var ok := true
var _started: Array = []
var _votes: Array = []
var _ended: Array = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# 1. Data.
	_check("seven events", GameState.EVENT_IDS.size() == 7, str(GameState.EVENT_IDS))
	_check("every event has a title", GameState.EVENT_IDS.all(
			func(id) -> bool: return String(GameState.EVENT_TITLES.get(id, "")) != ""))

	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(300, 1, 300)
	cs.shape = sh
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	add_child(player)
	player.global_position = Vector3(0, 1, 0)
	var feed := MachineFeed.new()
	add_child(feed)
	GraphicsSettings.combat_callouts_enabled = true
	GameState.chat_poll_started.connect(func(opts: Array) -> void: _started.append(opts))
	GameState.chat_poll_votes.connect(func(v: Array) -> void: _votes.append(v.duplicate()))
	GameState.chat_poll_ended.connect(func(id: String) -> void: _ended.append(id))
	GameState.current_level_path = "res://scenes/levels/level_gpt.tscn"
	GameState.set_state(GameState.State.PLAYING)
	await get_tree().process_frame

	# 2. A due event opens a poll.
	GameState._level_events = 0
	GameState._event_cd = 0.0
	GameState._surge_t = 0.0
	var enemies0 := get_tree().get_nodes_in_group("enemy").size()
	GameState._tick_events(0.1)
	_check("a poll opened", _started.size() == 1, str(_started))
	var opts: Array = _started[0] if _started.size() > 0 else []
	_check("two different options", opts.size() == 2 and opts[0] != opts[1], str(opts))
	_check("nothing ran yet", GameState._surge_t == 0.0 and get_tree().get_nodes_in_group("enemy").size() == enemies0)
	await get_tree().process_frame
	_check("the feed shows the poll", feed.poll_visible() and feed.poll_text().contains(tr(GameState.EVENT_TITLES[opts[0]])), feed.poll_text())

	# Make the outcome known: GRID SURGE against the SUPPLY FLARE, surge ahead.
	GameState._poll["options"] = ["surge", "supply"]
	GameState._poll["votes"] = [500, 0]

	# 4. Paused: the clock stops.
	var t0: float = GameState._poll["t"]
	GameState.set_state(GameState.State.PAUSED)
	GameState._tick_events(3.0)
	_check("poll waits while paused", GameState._poll.get("t", -1.0) == t0, "%.1f -> %.1f" % [t0, GameState._poll.get("t", -1.0)])
	GameState.set_state(GameState.State.PLAYING)

	# 3. Run it out.
	var steps := int(GameState.POLL_TIME / 0.5) + 2
	for i in steps:
		GameState._tick_events(0.5)
	_check("votes ticked up", _votes.size() >= 3 and int(_votes[-1][0]) + int(_votes[-1][1]) > 500, "%d updates" % _votes.size())
	_check("the leader won", _ended == ["surge"], str(_ended))
	_check("the winner ran", GameState._surge_t > 0.0, "%.1f" % GameState._surge_t)
	_check("it counts as the level's event", GameState._level_events == 1, "%d" % GameState._level_events)
	_check("poll closed", GameState._poll.is_empty())
	await get_tree().process_frame

	# 5. Feed after.
	_check("the feed hides the poll", not feed.poll_visible())
	_check("the feed posts the result", feed.last_kind == "poll" and feed.last_text.contains(tr("GRID SURGE")), feed.last_text)
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
