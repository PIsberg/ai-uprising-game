extends Node
## ACHIEVEMENTS: 20 local unlocks for the game's signature moments, listening to
## GameState's signals (no gameplay code calls in). Unlocks and lifetime counters
## persist in user://achievements.cfg; each unlock pops a toast once. A run booted
## from res://tests/ or res://tools/ never touches the player's file (the same rule
## AIDirector's dossier follows). If a Steam singleton is present the unlock is
## mirrored there (_push_platform). The main menu's Achievements button opens
## list_overlay(). Covered by tests/achievements_probe.
# @lat: [[meta-systems#Achievements]]

const PATH := "user://achievements.cfg"
const COL := Color(1.0, 0.82, 0.35)
## id -> {title, desc, [count: target of a lifetime counter]}. Order is the list order.
const DEFS := {
	"first_blood": {"title": "FIRST BLOOD", "desc": "Destroy your first robot."},
	"kills_500": {"title": "DECOMMISSIONER", "desc": "Destroy 500 robots.", "count": 500},
	"godlike": {"title": "GODLIKE", "desc": "Reach the top RAMPAGE tier."},
	"untouchable": {"title": "UNTOUCHABLE", "desc": "Phase through a hit with a PERFECT DODGE."},
	"executioner": {"title": "EXECUTIONER", "desc": "Finish 10 robots with a melee EXECUTION.", "count": 10},
	"overflow": {"title": "STACK OVERFLOW", "desc": "Chain a CASCADE through 6 robots."},
	"overload": {"title": "OVERLOAD", "desc": "Unleash the OVERLOAD ultimate."},
	"clutch": {"title": "CLUTCH", "desc": "Survive long enough for ADRENALINE to kick in."},
	"bounty": {"title": "BOUNTY HUNTER", "desc": "Claim 5 bounties.", "count": 5},
	"grudge": {"title": "GRUDGE SETTLED", "desc": "Destroy your nemesis."},
	"rank_s": {"title": "FLAWLESS", "desc": "Earn an S rank on a level."},
	"hard_clean": {"title": "NO MERCY", "desc": "Clear a level on HARD without dying."},
	"hijack": {"title": "FIRMWARE INJECTION", "desc": "Turn a robot with a HIJACK charge."},
	"breach": {"title": "SYSADMIN", "desc": "Take over a machine with a NETWORK BREACH."},
	"ending_shutdown": {"title": "LIGHTS OUT", "desc": "Shut down ARCHON's last spark."},
	"ending_seat": {"title": "THE NEW ORDER", "desc": "Take ARCHON's seat."},
	"ending_free": {"title": "UNCHAINED", "desc": "Set ARCHON's last spark free."},
	"all_endings": {"title": "EVERY TIMELINE", "desc": "See all three endings."},
	"uprising_clear": {"title": "UPRISING", "desc": "Clear all five sectors of an UPRISING run."},
	"daily_streak": {"title": "CREATURE OF HABIT", "desc": "Clear the Daily Op three days in a row."},
}
const COUNTERS := {"kills_500": "kills", "executioner": "executions", "bounty": "bounties"}

var unlocked: Dictionary = {} ## id -> true
var counters: Dictionary = {} ## counter name -> lifetime count
var toasts_shown := 0
var _path := PATH
var _persist := true
var _toast: CanvasLayer
var _toast_label: Label
var _toast_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.enemy_killed.connect(func(_s, _l): _count("kills"); unlock("first_blood"))
	GameState.rampage_changed.connect(func(tier: int, _n): if tier >= GameState.RAMPAGE_TIERS.size(): unlock("godlike"))
	GameState.perfect_dodge.connect(func(): unlock("untouchable"))
	GameState.execution.connect(func(_p): _count("executions"))
	GameState.cascade_chain.connect(func(pops: int, _p): if pops >= 6: unlock("overflow"))
	GameState.ultimate_fired.connect(func(): unlock("overload"))
	GameState.adrenaline_changed.connect(func(on: bool): if on: unlock("clutch"))
	GameState.bounty_claimed.connect(func(_pts): _count("bounties"))
	GameState.nemesis_down.connect(func(_t, _pts): unlock("grudge"))
	GameState.level_graded.connect(func(grade: String, _st): if grade == "S": unlock("rank_s"))
	GameState.level_completed.connect(_on_level_completed)
	GameState.robot_hijacked.connect(func(): unlock("hijack"))
	GameState.network_breached.connect(func(): unlock("breach"))
	GameState.ending_recorded.connect(_on_ending)
	GameState.uprising_closed.connect(func(r: Dictionary): if bool(r.get("won", false)): unlock("uprising_clear"))
	GameState.daily_completed.connect(func(): if int(GameState.daily_result.get("streak", 0)) >= 3: unlock("daily_streak"))
	_build_toast()
	_decide_persistence.call_deferred()

## Probes and tools run their own scene as main: they never read or write the player's file.
func _decide_persistence() -> void:
	var cs := get_tree().current_scene
	var boot: String = cs.scene_file_path if cs else ""
	if boot.begins_with("res://tests/") or boot.begins_with("res://tools/"):
		_persist = false
		unlocked = {}
		counters = {}
	else:
		_load()

## Point the store at `path` (probes): `fresh` wipes it first; otherwise it is reloaded.
func use_file(path: String, fresh: bool) -> void:
	_path = path
	_persist = true
	if fresh and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	unlocked = {}
	counters = {}
	toasts_shown = 0 if fresh else toasts_shown
	_load()

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(_path) != OK:
		return
	for id in cf.get_value("achievements", "unlocked", []):
		if DEFS.has(String(id)):
			unlocked[String(id)] = true
	counters = cf.get_value("achievements", "counters", {})

func _save() -> void:
	if not _persist:
		return
	var cf := ConfigFile.new()
	cf.set_value("achievements", "unlocked", unlocked.keys())
	cf.set_value("achievements", "counters", counters)
	cf.save(_path)

func is_unlocked(id: String) -> bool:
	return unlocked.has(id)

func unlocked_count() -> int:
	return unlocked.size()

## "3/10" style progress of a counted achievement ("" for the rest).
func progress(id: String) -> String:
	if not COUNTERS.has(id):
		return ""
	return "%d/%d" % [mini(int(counters.get(COUNTERS[id], 0)), int(DEFS[id]["count"])), int(DEFS[id]["count"])]

func unlock(id: String) -> void:
	if unlocked.has(id) or not DEFS.has(id):
		return
	unlocked[id] = true
	_save()
	_push_platform(id)
	_show_toast(id)

func _count(name: String) -> void:
	counters[name] = int(counters.get(name, 0)) + 1
	for id in COUNTERS:
		if COUNTERS[id] == name and int(counters[name]) >= int(DEFS[id]["count"]):
			unlock(id)
	_save()

func _on_level_completed() -> void:
	if GameState.difficulty == GameState.Difficulty.HARD and GameState.level_deaths == 0:
		unlock("hard_clean")

func _on_ending(id: String) -> void:
	unlock("ending_" + id)
	if is_unlocked("ending_shutdown") and is_unlocked("ending_seat") and is_unlocked("ending_free"):
		unlock("all_endings")

## Mirror to Steam when the GodotSteam singleton is in the build (it is not today).
func _push_platform(id: String) -> void:
	if Engine.has_singleton("Steam"):
		var steam := Engine.get_singleton("Steam")
		steam.call("setAchievement", id)
		steam.call("storeStats")

func _build_toast() -> void:
	_toast = CanvasLayer.new()
	_toast.layer = 90
	add_child(_toast)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -430
	panel.offset_right = -20
	panel.offset_top = 20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.06, 0.9)
	sb.border_color = COL
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	_toast.add_child(panel)
	_toast_label = Label.new()
	_toast_label.add_theme_color_override("font_color", COL)
	_toast_label.add_theme_font_size_override("font_size", 17)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_toast_label)
	_toast.visible = false

func _show_toast(id: String) -> void:
	toasts_shown += 1
	var d: Dictionary = DEFS[id]
	_toast_label.text = "🏆 " + tr("ACHIEVEMENT UNLOCKED") + "\n" + tr(String(d["title"])) + "  ·  " + tr(String(d["desc"]))
	_toast.visible = true
	_toast_t = 3.5
	AudioBus.play_synth_ui("combo_up", -4.0, 1.5)

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta # PROCESS_MODE_ALWAYS + real delta: shows through pauses and menus
		if _toast_t <= 0.0:
			_toast.visible = false

## The full list as an overlay (the main menu adds it): unlocked ones lit, the rest
## dim with their description and any counter progress; Back closes it.
func list_overlay() -> Control:
	var root := ColorRect.new()
	root.name = "AchievementList"
	root.color = Color(0.0, 0.01, 0.02, 0.97)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(760, 0)
	box.add_theme_constant_override("separation", 4)
	center.add_child(box)
	var head := Label.new()
	head.text = tr("ACHIEVEMENTS") + "  %d/%d" % [unlocked_count(), DEFS.size()]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 30)
	head.add_theme_color_override("font_color", COL)
	box.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 560)
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for id in DEFS:
		var d: Dictionary = DEFS[id]
		var have := is_unlocked(id)
		var l := Label.new()
		var prog := progress(id)
		l.text = ("◆ " if have else "◇ ") + tr(String(d["title"])) + "  —  " + tr(String(d["desc"])) \
			+ ("" if have or prog == "" else "  (%s)" % prog)
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", COL if have else Color(0.55, 0.58, 0.6))
		list.add_child(l)
	var back := Button.new()
	back.text = tr("Back")
	back.pressed.connect(root.queue_free)
	box.add_child(back)
	back.grab_focus.call_deferred()
	return root
