extends Node
## Probe: MACHINE FEED, the rogue AI's livestream of your fight. Robot viewers
## chat about what you actually do; the viewer count climbs with your style.
## (1) data: every event kind has at least MIN_LINES lines, and every line has a
##     strings.csv row with all five languages filled;
## (2) a CASCADE x6 puts a cascade line in the feed and lifts the viewer count;
##     an EXECUTION, a PERFECT DODGE and a salvage grab each post their own pool;
## (3) ten events in one frame post one line now, not ten (rate limit), and the
##     feed never shows more than MAX_LINES;
## (4) the same event twice in a row never repeats the line it just posted;
## (5) the player dying posts a death line and drops the viewer count;
## (6) with nothing happening, an idle line turns up after idle_gap;
## (7) with combat callouts switched off in Settings, nothing posts.
##   godot --headless --path . --audio-driver Dummy res://tests/machine_feed_probe.tscn

const MIN_LINES := 4
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().create_timer(0.25).timeout
		t += 0.25

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	GraphicsSettings.combat_callouts_enabled = true
	# 1. Data.
	var rows := _csv_rows()
	var missing: Array = []
	for kind in MachineChat.LINES:
		var pool: Array = MachineChat.LINES[kind]
		_check("%s has %d+ lines" % [kind, MIN_LINES], pool.size() >= MIN_LINES, "%d" % pool.size())
		for line in pool:
			var r: Array = rows.get(String(line), [])
			if r.size() < 6 or r.slice(1).any(func(c) -> bool: return String(c).strip_edges() == ""):
				missing.append(line)
	_check("every chat line translated", missing.is_empty(), str(missing.slice(0, 3)))
	_check("handles to chat under", MachineChat.HANDLES.size() >= 12, "%d" % MachineChat.HANDLES.size())

	# 2. Events post lines and lift viewers.
	var feed := MachineFeed.new()
	add_child(feed)
	await get_tree().process_frame
	var v0: int = feed.viewers
	GameState.cascade_chain.emit(6, Vector3.ZERO)
	await _wait(0.5)
	_check("a cascade posts a line", _last_kind(feed) == "cascade", _last(feed))
	_check("a cascade lifts the viewers", feed.viewers > v0, "%d -> %d" % [v0, feed.viewers])
	for ev in [["execution", func() -> void: GameState.execution.emit(Vector3.ZERO)],
			["dodge", func() -> void: GameState.perfect_dodge.emit()],
			["salvage", func() -> void: feed.on_salvage()]]:
		await _wait(MachineFeed.MIN_GAP + 0.25)
		(ev[1] as Callable).call()
		await _wait(0.5)
		_check("%s posts its own line" % ev[0], _last_kind(feed) == ev[0], _last(feed))

	# 3. Rate limit and cap.
	await _wait(MachineFeed.MIN_GAP + 0.25)
	var n0: int = feed.posted
	for i in 10:
		GameState.perfect_dodge.emit()
	await get_tree().process_frame
	_check("ten events post one line now", feed.posted - n0 == 1, "%d" % (feed.posted - n0))
	for i in 12:
		await _wait(MachineFeed.MIN_GAP + 0.1)
		GameState.execution.emit(Vector3.ZERO)
	await get_tree().process_frame
	_check("never more than MAX_LINES shown", feed.shown_lines() <= MachineFeed.MAX_LINES, "%d" % feed.shown_lines())

	# 4. No back-to-back repeat.
	var repeats := 0
	var prev := ""
	for i in 8:
		await _wait(MachineFeed.MIN_GAP + 0.1)
		GameState.execution.emit(Vector3.ZERO)
		await get_tree().process_frame
		if feed.last_text == prev:
			repeats += 1
		prev = feed.last_text
	_check("no line twice in a row", repeats == 0, "%d repeats" % repeats)

	# 5. Death.
	await _wait(MachineFeed.MIN_GAP + 0.25)
	var v1: int = feed.viewers
	GameState.player_died.emit()
	await _wait(0.5)
	_check("death posts a death line", _last_kind(feed) == "death", _last(feed))
	_check("death drops the viewers", feed.viewers < v1, "%d -> %d" % [v1, feed.viewers])

	# 6. Idle chatter.
	feed.idle_gap = 1.0
	var n1: int = feed.posted
	await _wait(2.0)
	_check("idle chatter turns up", feed.posted > n1 and _last_kind(feed) == "idle", _last(feed))

	# 7. Settings off.
	GraphicsSettings.combat_callouts_enabled = false
	await _wait(MachineFeed.MIN_GAP + 0.25)
	var n2: int = feed.posted
	GameState.cascade_chain.emit(8, Vector3.ZERO)
	await _wait(2.0)
	_check("callouts off: nothing posts", feed.posted == n2 and not feed.visible, "%d" % (feed.posted - n2))
	GraphicsSettings.combat_callouts_enabled = true
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _last(feed: MachineFeed) -> String:
	return "%s: %s" % [feed.last_kind, feed.last_text]

func _last_kind(feed: MachineFeed) -> String:
	return feed.last_kind

func _csv_rows() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://assets/i18n/strings.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var r := f.get_csv_line()
		if r.size() > 0 and r[0] != "":
			out[r[0]] = Array(r)
	return out
