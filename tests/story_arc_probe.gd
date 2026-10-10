extends Node
## Dev probe: the campaign's red thread (StoryArc).
## (1) every campaign level has a story beat: a tagline, and a trace log entry
##     for every level after the first (what the last level uncovered);
## (2) the acts run in campaign order, start at act I, end at the last act and
##     skip none, so the thread never jumps back or leaves an act empty;
## (3) the comic briefing prints the act header, the level's own tagline, the
##     trace card numbered by campaign position and the thread bar;
## (4) a level outside the story (the range) gets none of it.
##   godot --headless --path . --audio-driver Dummy res://tests/story_arc_probe.tscn

const BRIEFING := "res://scenes/cutscene/level_comic_briefing.tscn"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	var campaign: Array = GameState.CAMPAIGN

	# 1. Every level has its beat.
	var missing: Array = []
	for i in campaign.size():
		var id := GameState.level_id_from_path(campaign[i])
		var b := StoryArc.beat(id)
		if b.is_empty() or String(b.get("tagline", "")) == "" \
				or (i > 0 and String(b.get("trace", "")) == ""):
			missing.append(id)
	print("BEATS: levels=%d missing=%s" % [campaign.size(), missing])
	if not missing.is_empty():
		ok = false

	# 2. Acts in order, no gaps.
	var acts: Array[int] = StoryArc.campaign_acts(campaign)
	var ordered := acts[0] == 0 and acts[acts.size() - 1] == StoryArc.ACTS.size() - 1
	for i in range(1, acts.size()):
		if acts[i] < acts[i - 1] or acts[i] > acts[i - 1] + 1:
			ordered = false
	print("ACTS: %s ordered=%s" % [acts, ordered])
	if not ordered:
		ok = false

	# 3. The briefing tells it. GUARDRAILS has no comic art of its own, so this
	# also covers a level that only exists in the thread.
	var idx := campaign.find("res://scenes/levels/level_guardrails.tscn")
	var seen := await _brief("guardrails")
	var beat := StoryArc.beat("guardrails")
	var told: bool = seen["texts"].has(String(beat["tagline"])) \
		and seen["texts"].has("ACT V · THE RELAY CHAIN") \
		and seen["texts"].has(String(beat["trace"])) \
		and seen["texts"].has("◆ THE 03:14 TRACE · LOG %d/%d" % [idx + 1, campaign.size()]) \
		and seen["thread"] and seen["trace_panel"]
	print("BRIEF guardrails: told=%s thread=%s trace_panel=%s" % [told, seen["thread"], seen["trace_panel"]])
	if not told:
		ok = false

	# 4. Outside the story: no act, no trace card, the generic line.
	seen = await _brief("range")
	var quiet: bool = not seen["trace_panel"] \
		and seen["texts"].has("Hostile machines detected. Move in.") \
		and not seen["texts"].any(func(t: String) -> bool: return t.begins_with("ACT "))
	print("BRIEF range: quiet=%s" % quiet)
	if not quiet:
		ok = false

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## Opens the briefing for `id` and reports what is on screen once the trace has
## typed out (visible_ratio aside, the text is set when the card is built).
func _brief(id: String) -> Dictionary:
	GameState.pending_patch_notes = []
	GameState.current_level_path = "res://scenes/levels/level_%s.tscn" % id
	var briefing: Node = load(BRIEFING).instantiate()
	get_tree().root.add_child(briefing)
	for i in 10:
		await get_tree().process_frame
	var texts: Array = []
	for lbl in briefing.find_children("*", "Label", true, false):
		texts.append(String((lbl as Label).text))
	var out := {
		"texts": texts,
		"thread": briefing.find_child("StoryThread", true, false) != null,
		"trace_panel": briefing.find_child("TracePanel", true, false) != null,
	}
	briefing.queue_free()
	await get_tree().process_frame
	return out
