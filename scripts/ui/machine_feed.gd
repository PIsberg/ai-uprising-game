# @lat: [[meta-systems#Machine Feed]]
class_name MachineFeed
extends VBoxContainer
## MACHINE FEED: the rogue AI livestreams your fight to its robot network, and the
## audience chats about it down the left of the HUD. Lines come from MachineChat,
## picked by what you just did (GameState signals plus on_salvage from the HUD);
## the viewer count climbs with the hype each event brings (MachineChat.HYPE) and
## settles back to the level's base audience. It is the crowd's voice; the
## overlord's own lines stay in the subtitle.
##
## One line per MIN_GAP: a burst of events posts the first and drops the rest, so
## a CASCADE x8 is one shout, not eight. Small talk (CHATTER) never blocks an
## event line: a cascade right after the stream's opening line still posts. At most MAX_LINES show, each fading after
## LINE_LIFE. Off with the combat callouts setting (GraphicsSettings).
## Covered by tests/machine_feed_probe.
##
## CHAT POLL: while GameState runs a poll between two surprise events, a tally
## block sits under the header (bars of POLL_BAR cells); when it closes the feed
## posts the winner as a "poll" line. tests/chat_poll_probe.

const MIN_GAP := 1.2      ## seconds between posts
const POLL_BAR := 12      ## cells in a poll option's bar
const MAX_LINES := 5
const LINE_LIFE := 7.0    ## seconds a line stays before it fades
const IDLE_GAP := 22.0    ## a quiet stretch this long gets an idle line
const BASE_VIEWERS := 140 ## + VIEWERS_PER_LEVEL per campaign level
const VIEWERS_PER_LEVEL := 85
const CHATTER := ["intro", "idle"] ## kinds that yield to any event inside MIN_GAP
const DEATH_KEEP := 0.7   ## share of the audience that stays when you die
const DECAY := 0.04       ## share of the hype above base that leaves per DECAY_TICK
const DECAY_TICK := 0.5

var viewers: int = 0
var posted: int = 0 ## lines posted so far (the probe counts them)
var last_kind: String = ""
var last_text: String = ""
var idle_gap: float = IDLE_GAP

var _header: Label
var _poll_box: Label
var _poll_opts: Array = []
var _since_post: float = 99.0
var _quiet: float = 0.0
var _decay_t: float = 0.0
var _base: int = 0
var _last_line := {} ## kind -> index of the line it posted last

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	custom_minimum_size = Vector2(330, 0)
	_base = BASE_VIEWERS + VIEWERS_PER_LEVEL * maxi(0, GameState.level_index)
	viewers = _base
	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 13)
	_header.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_header.add_theme_constant_override("outline_size", 4)
	_header.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_header)
	_refresh_header()
	_poll_box = Label.new()
	_poll_box.add_theme_font_size_override("font_size", 14)
	_poll_box.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_poll_box.add_theme_constant_override("outline_size", 4)
	_poll_box.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_poll_box.visible = false
	add_child(_poll_box)
	GameState.chat_poll_started.connect(_on_poll_started)
	GameState.chat_poll_votes.connect(_draw_poll)
	GameState.chat_poll_ended.connect(_on_poll_ended)
	GameState.cascade_chain.connect(func(pops: int, _p: Vector3) -> void:
		if pops >= GameState.CASCADE_CALLOUT:
			_event("cascade", MachineChat.HYPE["cascade"] * pops))
	GameState.execution.connect(func(_p: Vector3) -> void: _event("execution"))
	GameState.environmental_kill.connect(func(_w: bool, _p: Vector3) -> void: _event("meltdown"))
	GameState.perfect_dodge.connect(func() -> void: _event("dodge"))
	GameState.rampage_changed.connect(func(tier: int, _n: String) -> void:
		if tier > 0:
			_event("rampage", MachineChat.HYPE["rampage"] * tier))
	GameState.adrenaline_changed.connect(func(active: bool) -> void:
		if active:
			_event("clutch"))
	GameState.boss_spawned.connect(func(_b: Node) -> void: _event("boss"))
	GameState.player_died.connect(_on_player_died)
	_event.call_deferred("intro")

func _on_poll_started(options: Array) -> void:
	_poll_opts = options
	_draw_poll([0, 0])

## "CHAT POLL" and one bar per option, its share of the votes so far.
func _draw_poll(votes: Array) -> void:
	if _poll_opts.size() < 2:
		return
	var total := maxi(1, int(votes[0]) + int(votes[1]))
	var rows: Array = ["▶ " + tr("CHAT POLL")]
	for i in 2:
		var share := float(votes[i]) / total
		var cells := int(round(share * POLL_BAR))
		rows.append("%d  %s  %s %d%%" % [i + 1, tr(String(GameState.EVENT_TITLES.get(_poll_opts[i], ""))),
				"█".repeat(cells) + "░".repeat(POLL_BAR - cells), int(round(share * 100.0))])
	_poll_box.text = "\n".join(rows)
	_poll_box.visible = GraphicsSettings.combat_callouts_enabled

func _on_poll_ended(winner: String) -> void:
	_poll_box.visible = false
	_poll_opts = []
	if GraphicsSettings.combat_callouts_enabled:
		visible = true
		_post("poll", "%s: %s" % [tr("CHAT VOTED"), tr(String(GameState.EVENT_TITLES.get(winner, winner)))])

func poll_visible() -> bool:
	return _poll_box.visible

func poll_text() -> String:
	return _poll_box.text

## The HUD calls this when a salvage gun lands in your hands.
func on_salvage() -> void:
	_event("salvage")

func _on_player_died() -> void:
	viewers = int(viewers * DEATH_KEEP)
	_event("death", 0, true)

## Post a line for `kind` unless one went up under MIN_GAP ago (`force` skips
## that: a death always gets its line; so does any event after mere CHATTER).
func _event(kind: String, hype: int = -1, force: bool = false) -> void:
	viewers += MachineChat.HYPE.get(kind, 0) if hype < 0 else hype
	_refresh_header()
	if not GraphicsSettings.combat_callouts_enabled:
		visible = false
		return
	visible = true
	var over_chatter := last_kind in CHATTER and not kind in CHATTER
	if _since_post < MIN_GAP and not force and not over_chatter:
		return
	var pool: Array = MachineChat.LINES.get(kind, [])
	if pool.is_empty():
		return
	var i := randi() % pool.size()
	if pool.size() > 1 and i == int(_last_line.get(kind, -1)):
		i = (i + 1 + randi() % (pool.size() - 1)) % pool.size()
	_last_line[kind] = i
	_post(kind, tr(String(pool[i])))

func _post(kind: String, text: String) -> void:
	var handle: String = MachineChat.HANDLES[randi() % MachineChat.HANDLES.size()]
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(330, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_size_override("normal_font_size", 14)
	line.add_theme_constant_override("outline_size", 4)
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	var col := Color.from_hsv(float(abs(hash(handle)) % 360) / 360.0, 0.55, 1.0)
	line.text = "[color=#%s]%s[/color]: %s" % [col.to_html(false), handle, text]
	add_child(line)
	line.set_meta("age", 0.0)
	while _lines().size() > MAX_LINES:
		var old: Control = _lines()[0]
		remove_child(old)
		old.queue_free()
	posted += 1
	last_kind = kind
	last_text = text
	_since_post = 0.0
	_quiet = 0.0

## A faint dark backing so the chat reads over bright walls and skies.
func _draw() -> void:
	if shown_lines() > 0:
		draw_rect(Rect2(Vector2(-8, -4), size + Vector2(16, 8)), Color(0, 0, 0, 0.32))

func _lines() -> Array:
	return get_children().filter(func(c) -> bool: return c != _header and c != _poll_box)

func shown_lines() -> int:
	return _lines().size()

func _refresh_header() -> void:
	if _header:
		_header.text = "● %s · %s %s" % [tr("MACHINE FEED"), _group(viewers), tr("watching")]

## 12345 -> "12,345".
static func _group(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

func _process(delta: float) -> void:
	_since_post += delta
	if GameState.current_state == GameState.State.PLAYING:
		_quiet += delta
		if _quiet >= idle_gap:
			_quiet = 0.0
			_event("idle")
	# The audience drifts back toward the level's base between hype spikes:
	# DECAY of the excess leaves every DECAY_TICK seconds.
	_decay_t += delta
	if _decay_t >= DECAY_TICK:
		_decay_t = 0.0
		if viewers > _base:
			viewers = maxi(_base, viewers - maxi(1, int((viewers - _base) * DECAY)))
			_refresh_header()
	queue_redraw() # the backing follows the lines as they come and go
	for c in _lines():
		var age: float = float(c.get_meta("age", 0.0)) + delta
		c.set_meta("age", age)
		c.modulate.a = clampf((LINE_LIFE - age) / 1.0, 0.0, 1.0)
		if age >= LINE_LIFE:
			remove_child(c)
			c.queue_free()
