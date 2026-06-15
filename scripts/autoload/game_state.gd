extends Node

signal player_died
signal level_completed
signal score_changed(new_score: int)
signal boss_spawned(boss: Node) ## A boss enemy appeared — HUD shows its health bar.
signal player_dealt_damage(amount: float, world_pos: Vector3, killed: bool) ## Player landed a hit — drives hit markers + damage numbers.
signal enemy_killed(score: int, label: String) ## An enemy was destroyed — drives the HUD kill feed.
signal objective_blocked(text: String) ## Player reached a locked portal — HUD posts why.
signal objective_unlocked(text: String) ## Objective met, portal opened — HUD updates the goal line.
signal tasks_changed ## The level task checklist changed — HUD re-renders the objective line.
signal task_completed(label: String) ## A single task was just finished — HUD cheers it.
signal combo_changed(combo: int, mult: float) ## Kill-streak combo updated — HUD shows the multiplier.
signal level_graded(grade: String, stats: Dictionary) ## Level cleared — end-screen grade + breakdown.

func announce_boss(boss: Node) -> void:
	boss_spawned.emit(boss)

## Called by Damageable when the player damages something. Drives combat feedback.
func report_player_hit(amount: float, world_pos: Vector3, killed: bool) -> void:
	register_hit()
	player_dealt_damage.emit(amount, world_pos, killed)

enum State { MENU, PLAYING, PAUSED, GAME_OVER, LEVEL_COMPLETE }

## Campaign-wide difficulty, chosen after "Begin Operation". Each tier scales
## three things on EVERY level: how many enemies spawn, how strong they are
## (health + attack cadence + speed), and how often kills drop supplies.
enum Difficulty { EASY, NORMAL, HARD }

const DIFFICULTY_CONFIG := {
	Difficulty.EASY: {
		"label": "EASY",
		"health_mult": 0.6, "cooldown_mult": 1.45, "speed_mult": 0.88,
		"enemy_count_mult": 0.6, "pickup_mult": 1.5, "aim_spread_deg": 8.0,
	},
	Difficulty.NORMAL: {
		"label": "NORMAL",
		"health_mult": 1.0, "cooldown_mult": 1.0, "speed_mult": 1.0,
		"enemy_count_mult": 1.0, "pickup_mult": 1.0, "aim_spread_deg": 2.5,
	},
	Difficulty.HARD: {
		"label": "HARD",
		"health_mult": 1.6, "cooldown_mult": 0.7, "speed_mult": 1.12,
		"enemy_count_mult": 1.45, "pickup_mult": 0.6, "aim_spread_deg": 0.0,
	},
}

var difficulty: int = Difficulty.NORMAL

func difficulty_config() -> Dictionary:
	return DIFFICULTY_CONFIG.get(difficulty, DIFFICULTY_CONFIG[Difficulty.NORMAL])

func difficulty_label() -> String:
	return difficulty_config().get("label", "NORMAL")

## Campaign order. The player advances through these via the "Continue" button
## on the level-complete screen.
const CAMPAIGN: Array[String] = [
	"res://scenes/levels/level_01.tscn",
	"res://scenes/levels/level_gpt.tscn",
	"res://scenes/levels/level_gemini.tscn",
	"res://scenes/levels/level_mistral.tscn",
	"res://scenes/levels/level_suburb.tscn",
	"res://scenes/levels/level_suburb_boss.tscn",
	"res://scenes/levels/level_claude.tscn",
	"res://scenes/levels/level_grok.tscn",
	"res://scenes/levels/level_uplink.tscn",
	"res://scenes/levels/level_overseer.tscn",
	"res://scenes/levels/level_alien.tscn",
	"res://scenes/levels/level_assembly.tscn",
	"res://scenes/levels/level_titan.tscn",
	"res://scenes/levels/level_archon.tscn",
]

var current_state: State = State.MENU
var score: int = 0
var kills: int = 0
var current_level_path: String = ""
var level_index: int = 0
## Scene paths of bonus weapons picked up this campaign run. The WeaponManager
## re-adds these on every level so the arsenal carries forward.
var unlocked_weapons: Array[String] = []
## Scene path of the weapon the player currently has armed. Persists across
## levels so you keep wielding whatever you switched to (set by WeaponManager).
var equipped_weapon: String = ""
## The opening broadcast plays once per campaign run, not on every retry.
var intro_played: bool = false

func unlock_weapon(scene_path: String) -> void:
	if not unlocked_weapons.has(scene_path):
		unlocked_weapons.append(scene_path)

## Every weapon scene in the game, in roughly ascending power. The warp cheat
## hands the player the whole arsenal so any level can be played with everything.
const ALL_WEAPONS: Array[String] = [
	"res://scenes/weapons/pistol.tscn",
	"res://scenes/weapons/smg.tscn",
	"res://scenes/weapons/rifle.tscn",
	"res://scenes/weapons/shotgun.tscn",
	"res://scenes/weapons/tesla.tscn",
	"res://scenes/weapons/arccoil.tscn",
	"res://scenes/weapons/plasma.tscn",
	"res://scenes/weapons/nova.tscn",
	"res://scenes/weapons/gauss.tscn",
	"res://scenes/weapons/twinrail.tscn",
	"res://scenes/weapons/swarm.tscn",
	"res://scenes/weapons/devastator.tscn",
	"res://scenes/weapons/singularity.tscn",
	"res://scenes/weapons/omega.tscn",
]

func unlock_all_weapons() -> void:
	for path in ALL_WEAPONS:
		unlock_weapon(path)

# ---------- armory upgrades (bought with score between levels) ----------
## Three permanent per-run tracks; every weapon reads the multipliers live
## (Weapon.eff_damage / eff_mag_size / eff_reload_time). Score is the currency,
## so fighting well IS the progression. Reset only on a fresh campaign.

const UPGRADE_DEFS := {
	"damage": {"label": "WEAPON DAMAGE", "per": 0.08, "cost": 1500},
	"mag":    {"label": "MAGAZINE SIZE", "per": 0.15, "cost": 1200},
	"reload": {"label": "RELOAD SPEED",  "per": 0.06, "cost": 1000},
}
const UPGRADE_MAX := 5
var upgrades: Dictionary = {"damage": 0, "mag": 0, "reload": 0}

func upgrade_level(k: String) -> int:
	return int(upgrades.get(k, 0))

## Next-rank price scales linearly with the rank being bought.
func upgrade_cost(k: String) -> int:
	return int(UPGRADE_DEFS[k]["cost"]) * (upgrade_level(k) + 1)

func buy_upgrade(k: String) -> bool:
	if not UPGRADE_DEFS.has(k) or upgrade_level(k) >= UPGRADE_MAX:
		return false
	var cost := upgrade_cost(k)
	if score < cost:
		return false
	score -= cost
	upgrades[k] = upgrade_level(k) + 1
	save_progress()
	return true

## True if at least one track is purchasable right now — the briefing only
## bothers showing the armory when there's an actual decision to make.
func can_buy_any_upgrade() -> bool:
	for k in UPGRADE_DEFS:
		if upgrade_level(k) < UPGRADE_MAX and score >= upgrade_cost(k):
			return true
	return false

## Multiplier for damage/mag tracks (>= 1.0).
func upgrade_mult(k: String) -> float:
	return 1.0 + float(UPGRADE_DEFS[k]["per"]) * upgrade_level(k)

## Reload is a time REDUCTION; floored so it can't break the reload anim.
func upgrade_reload_mult() -> float:
	return maxf(0.55, 1.0 - float(UPGRADE_DEFS["reload"]["per"]) * upgrade_level("reload"))

func set_state(new_state: State) -> void:
	current_state = new_state
	match new_state:
		State.PLAYING:
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		State.PAUSED:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		State.MENU, State.GAME_OVER, State.LEVEL_COMPLETE:
			get_tree().paused = false
			Engine.time_scale = 1.0 # never leave slow-mo running into a menu
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)

func add_kill(points: int = 100, label: String = "HOSTILE") -> void:
	kills += 1
	# Kill-streak combo: each kill inside the window bumps the multiplier.
	combo += 1
	combo_timer = COMBO_WINDOW
	max_combo = maxi(max_combo, combo)
	combo_changed.emit(combo, combo_mult())
	add_score(int(round(points * combo_mult())))
	enemy_killed.emit(points, label)

# ---------- kill-streak combo ----------
const COMBO_WINDOW := 3.5 ## Seconds between kills before the streak resets.
var combo: int = 0
var combo_timer: float = 0.0
var max_combo: int = 0

## Score multiplier from the current streak: 1.0, then +0.25 per extra kill, cap 4x.
func combo_mult() -> float:
	return clampf(1.0 + (combo - 1) * 0.25, 1.0, 4.0)

func _reset_combo() -> void:
	if combo != 0:
		combo = 0
		combo_changed.emit(0, 1.0)

func _process(delta: float) -> void:
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			_reset_combo()
	if overclock_left > 0.0:
		overclock_left = maxf(0.0, overclock_left - delta)
		overclock_changed.emit(overclock_left)
		if overclock_left <= 0.0:
			AudioBus.play_synth_ui("empty_click", -8.0, 0.6) # power-down tick
	if overdrive_left > 0.0:
		overdrive_left = maxf(0.0, overdrive_left - delta)
		overdrive_changed.emit(overdrive_left)
		if overdrive_left <= 0.0:
			AudioBus.play_synth_ui("empty_click", -8.0, 0.6)

# ---------- OVERCLOCK powerup (quad-damage analog) ----------
## While active, every player weapon hits at OVERCLOCK_MULT (Weapon.eff_damage
## reads damage_mult()). Picking another one refreshes the full duration.

signal overclock_changed(seconds_left: float)

const OVERCLOCK_MULT := 4.0
const OVERCLOCK_DURATION := 10.0
var overclock_left: float = 0.0

func activate_overclock() -> void:
	overclock_left = OVERCLOCK_DURATION
	overclock_changed.emit(overclock_left)

func damage_mult() -> float:
	return OVERCLOCK_MULT if overclock_left > 0.0 else 1.0

# ---------- OVERDRIVE powerup (rapid-fire + speed burst) ----------
## While active, weapons fire OVERDRIVE_FIRE_MULT faster (Weapon.eff_fire_rate)
## and the player moves OVERDRIVE_SPEED_MULT faster (Player._current_speed).
## A power-fantasy burst, distinct from OVERCLOCK's raw damage.

signal overdrive_changed(seconds_left: float)

const OVERDRIVE_DURATION := 8.0
const OVERDRIVE_FIRE_MULT := 1.85
const OVERDRIVE_SPEED_MULT := 1.35
var overdrive_left: float = 0.0

func activate_overdrive() -> void:
	overdrive_left = OVERDRIVE_DURATION
	overdrive_changed.emit(overdrive_left)

func fire_rate_mult() -> float:
	return OVERDRIVE_FIRE_MULT if overdrive_left > 0.0 else 1.0

func move_speed_mult() -> float:
	return OVERDRIVE_SPEED_MULT if overdrive_left > 0.0 else 1.0

func overdrive_active() -> bool:
	return overdrive_left > 0.0

# ---------- per-level performance stats (drive the end grade) ----------
var stat_shots: int = 0
var stat_hits: int = 0
var stat_damage_taken: float = 0.0
var level_start_ms: int = 0

func reset_level_stats() -> void:
	stat_shots = 0
	stat_hits = 0
	stat_damage_taken = 0.0
	max_combo = 0
	_reset_combo()
	level_start_ms = Time.get_ticks_msec()

func register_shot() -> void:
	stat_shots += 1

func register_hit() -> void:
	stat_hits += 1

func register_damage_taken(amount: float) -> void:
	stat_damage_taken += amount

## Letter grade from accuracy, best combo, and damage soaked. Returns the grade
## plus a stats dict for the end screen.
func grade_level() -> Dictionary:
	var accuracy := (float(stat_hits) / float(stat_shots)) if stat_shots > 0 else 0.0
	accuracy = clampf(accuracy, 0.0, 1.0)
	var elapsed := float(Time.get_ticks_msec() - level_start_ms) / 1000.0
	# 0..100 performance score: accuracy (45) + best combo (30) + survival (25).
	var score_pts := accuracy * 45.0
	score_pts += clampf(max_combo / 10.0, 0.0, 1.0) * 30.0
	score_pts += clampf(1.0 - stat_damage_taken / 250.0, 0.0, 1.0) * 25.0
	var grade := "D"
	if score_pts >= 90.0: grade = "S"
	elif score_pts >= 75.0: grade = "A"
	elif score_pts >= 55.0: grade = "B"
	elif score_pts >= 35.0: grade = "C"
	var stats := {
		"accuracy": accuracy, "max_combo": max_combo,
		"damage_taken": stat_damage_taken, "time": elapsed,
		"kills": kills, "score": score,
	}
	level_graded.emit(grade, stats)
	return {"grade": grade, "stats": stats}

func reset_run() -> void:
	score = 0
	kills = 0
	seen_enemy_types.clear()

## Brief slow-motion payoff (e.g. boss death). Uses a real-time timer so it
## always restores even though the game clock is slowed.
func hit_stop(scale: float = 0.3, duration: float = 0.4) -> void:
	Engine.time_scale = clampf(scale, 0.05, 1.0)
	# create_timer(sec, process_always, process_in_physics, ignore_time_scale)
	var t := get_tree().create_timer(duration, true, false, true)
	t.timeout.connect(func(): Engine.time_scale = 1.0)

## Start a fresh campaign run from the first level at the chosen difficulty.
func start_campaign(diff: int = Difficulty.NORMAL) -> void:
	difficulty = diff
	reset_run()
	unlocked_weapons.clear() # fresh run starts with only the base arsenal
	equipped_weapon = ""     # ...armed with the default (pistol)
	upgrades = {"damage": 0, "mag": 0, "reload": 0} # armory resets with the run
	intro_played = false
	level_index = 0
	go_to_level(CAMPAIGN[0], false)

const INTRO_CUTSCENE := "res://scenes/cutscene/intro_cutscene.tscn"
const LEVEL_BRIEFING := "res://scenes/cutscene/level_briefing.tscn"

## Enter a campaign level THROUGH its cutscene: level 1 gets the story intro,
## every other level gets a data-driven briefing (new enemies + objective + mood).
## The cutscene calls load_level() when it finishes/skips to enter the level.
func go_to_level(path: String, reset: bool = false) -> void:
	current_level_path = path
	var found := CAMPAIGN.find(path)
	if found != -1:
		level_index = found
	if reset:
		reset_run()
	set_state(State.PLAYING)
	if found != -1:
		save_progress()
	if level_id_from_path(path) == "01":
		get_tree().change_scene_to_file(INTRO_CUTSCENE)
	else:
		get_tree().change_scene_to_file(LEVEL_BRIEFING)

## "res://scenes/levels/level_gpt.tscn" -> "gpt"; level_suburb_boss -> "suburb_boss".
func level_id_from_path(path: String) -> String:
	return path.get_file().trim_prefix("level_").trim_suffix(".tscn")

# New-enemy tracking so briefings can flag first appearances.
var seen_enemy_types: Dictionary = {}

func has_seen_enemy(t: String) -> bool:
	return seen_enemy_types.has(t)

func mark_enemy_seen(t: String) -> void:
	seen_enemy_types[t] = true

## Load a specific level. `reset` wipes score/kills (used for replays); campaign
## advancement passes false so the running score carries across levels.
func load_level(scene_path: String, reset: bool = true) -> void:
	current_level_path = scene_path
	var found := CAMPAIGN.find(scene_path)
	if found != -1:
		level_index = found
	if reset:
		reset_run()
	reset_level_stats()
	set_state(State.PLAYING)
	if found != -1:
		save_progress() # checkpoint at the start of every campaign level
	get_tree().change_scene_to_file(scene_path)

# ---------- save / checkpoint ----------

const SAVE_PATH := "user://savegame.cfg"

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## Write a checkpoint of the current run so the player can Continue later.
func save_progress() -> void:
	var cf := ConfigFile.new()
	cf.set_value("run", "level_index", level_index)
	cf.set_value("run", "difficulty", difficulty)
	cf.set_value("run", "score", score)
	cf.set_value("run", "kills", kills)
	cf.set_value("run", "unlocked_weapons", unlocked_weapons)
	cf.set_value("run", "equipped_weapon", equipped_weapon)
	cf.set_value("run", "upgrades", upgrades)
	# Persist which robots the briefings have introduced — otherwise a resumed
	# run re-plays every "NEW HOSTILE" close-up the player has already seen.
	cf.set_value("run", "seen_enemies", seen_enemy_types.keys())
	cf.save(SAVE_PATH)

func load_progress() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return false
	level_index = int(cf.get_value("run", "level_index", 0))
	difficulty = int(cf.get_value("run", "difficulty", Difficulty.NORMAL))
	score = int(cf.get_value("run", "score", 0))
	kills = int(cf.get_value("run", "kills", 0))
	unlocked_weapons.clear()
	for w in cf.get_value("run", "unlocked_weapons", []):
		unlocked_weapons.append(str(w))
	equipped_weapon = str(cf.get_value("run", "equipped_weapon", ""))
	var up: Dictionary = cf.get_value("run", "upgrades", {})
	for k in upgrades:
		upgrades[k] = int(up.get(k, 0))
	seen_enemy_types.clear()
	for t in cf.get_value("run", "seen_enemies", []):
		seen_enemy_types[str(t)] = true
	return true

func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

## Resume the saved run from the start of its checkpointed level.
func continue_campaign() -> void:
	if not load_progress():
		start_campaign()
		return
	intro_played = true # don't replay the opening broadcast on a resumed run
	level_index = clampi(level_index, 0, CAMPAIGN.size() - 1)
	load_level(CAMPAIGN[level_index], false)

func has_next_level() -> bool:
	return level_index + 1 < CAMPAIGN.size()

## Called by the level-complete "Continue" button.
func advance_level() -> void:
	if has_next_level():
		go_to_level(CAMPAIGN[level_index + 1], false)
	else:
		# Campaign finished — clear the checkpoint and return to the main menu.
		clear_save()
		set_state(State.MENU)
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func on_player_died() -> void:
	set_state(State.GAME_OVER)
	player_died.emit()

func on_level_complete() -> void:
	_reset_combo()
	grade_level() # emits level_graded for the end screen
	set_state(State.LEVEL_COMPLETE)
	level_completed.emit()

# ---------------------------------------------------------------------
# Level tasks. A level registers an ordered checklist (kill all, find the
# keycard, destroy the core, …). The exit Portal stays sealed until every
# task is done. Each task is {id:String, label:String, done:bool}.
# ---------------------------------------------------------------------

var level_tasks: Array = []

func reset_tasks() -> void:
	level_tasks.clear()
	tasks_changed.emit()

## `goal` > 0 gives the task a progress meter (e.g. shards collected, seconds
## held); the HUD shows it as (n/goal) and the task auto-completes at goal.
func register_task(id: String, label: String, goal: float = 0.0) -> void:
	for t in level_tasks:
		if t["id"] == id:
			return
	level_tasks.append({"id": id, "label": label, "done": false, "progress": 0.0, "goal": goal})
	tasks_changed.emit()

func complete_task(id: String) -> void:
	for t in level_tasks:
		if t["id"] == id and not t["done"]:
			t["done"] = true
			t["progress"] = t["goal"]
			task_completed.emit(t["label"])
			tasks_changed.emit()
			# "Area cleared" cinematic beat when the last hostile drops.
			if id == "kill_all":
				hit_stop(0.45, 0.6)
			return

## Set a progress task's value; auto-completes when it reaches the goal.
func set_task_progress(id: String, value: float) -> void:
	for t in level_tasks:
		if t["id"] == id and not t["done"]:
			t["progress"] = clampf(value, 0.0, t["goal"])
			if t["goal"] > 0.0 and t["progress"] >= t["goal"]:
				complete_task(id)
			else:
				tasks_changed.emit()
			return

func advance_task(id: String, amount: float = 1.0) -> void:
	for t in level_tasks:
		if t["id"] == id and not t["done"]:
			set_task_progress(id, t["progress"] + amount)
			return

func is_task_done(id: String) -> bool:
	for t in level_tasks:
		if t["id"] == id:
			return t["done"]
	return false

func has_task(id: String) -> bool:
	for t in level_tasks:
		if t["id"] == id:
			return true
	return false

## All registered tasks finished. Empty list counts as done (no requirements).
func all_tasks_done() -> bool:
	for t in level_tasks:
		if not t["done"]:
			return false
	return true

func incomplete_task_labels() -> Array:
	var out: Array = []
	for t in level_tasks:
		if not t["done"]:
			out.append(t["label"])
	return out

# ---------------------------------------------------------------------
# Difficulty scaling. Levels call apply_level_scaling(self) at the end of
# their _ready to adjust enemy COUNT. Enemy STRENGTH (health / attack
# cadence / move speed) is applied per-spawn inside EnemySpawner so it
# covers hand-placed and code-spawned enemies alike. Supply availability
# (pickup_mult) is applied per-kill in EnemyBase._drop_loot.
# ---------------------------------------------------------------------

## Scale a freshly built level to the active difficulty. Safe on NORMAL (no-op).
## Supply availability is no longer scaled here: pickups drop from kills, and
## EnemyBase._drop_loot applies pickup_mult to its drop chance directly.
func apply_level_scaling(level: Node) -> void:
	var cfg := difficulty_config()
	_scale_enemy_count(level, cfg.get("enemy_count_mult", 1.0))

func _collect_spawners(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is EnemySpawner:
			out.append(c)
		_collect_spawners(c, out)

const BOSS_SCENES := ["terminator", "colossus", "overseer", "archon"]

func _is_boss_spawner(s: EnemySpawner) -> bool:
	if s.enemy_scene == null:
		return false
	for b in BOSS_SCENES:
		if b in s.enemy_scene.resource_path:
			return true
	return false

func _scale_enemy_count(level: Node, mult: float) -> void:
	if is_equal_approx(mult, 1.0):
		return
	var spawners: Array = []
	_collect_spawners(level, spawners)
	if spawners.is_empty():
		return
	var target := int(round(spawners.size() * mult))
	if mult < 1.0:
		# Thin the pack: only drop trigger-spawned, non-boss reinforcements so
		# the opening fight and any boss stay intact.
		var removable := spawners.filter(func(s):
			return s.trigger_radius > 0.0 and not _is_boss_spawner(s))
		var want_removed: int = mini(spawners.size() - maxi(target, 1), removable.size())
		for i in range(want_removed):
			removable[i].queue_free()
	else:
		# Reinforce: clone existing spawners (never the boss) at a small offset.
		var clonable := spawners.filter(func(s): return not _is_boss_spawner(s))
		if clonable.is_empty():
			return
		var to_add := target - spawners.size()
		for i in range(to_add):
			_clone_spawner(clonable[i % clonable.size()], i)

func _clone_spawner(src: EnemySpawner, idx: int) -> void:
	var sp := EnemySpawner.new()
	sp.enemy_scene = src.enemy_scene
	sp.spawn_on_ready = src.spawn_on_ready
	sp.spawn_delay = src.spawn_delay + 0.15
	sp.trigger_radius = src.trigger_radius
	var sx := 1.0 if idx % 2 == 0 else -1.0
	var sz := 1.0 if (idx / 2) % 2 == 0 else -1.0
	sp.position = src.position + Vector3(2.6 * sx, 0.0, 2.6 * sz)
	src.get_parent().add_child(sp)

# ---------- gamepad ----------

func _ready() -> void:
	_setup_gamepad_bindings()

## Add Xbox-style controller bindings to the existing input actions at runtime
## (keyboard/mouse bindings stay). Right-stick look is handled in player.gd.
func _setup_gamepad_bindings() -> void:
	_bind_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_bind_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_bind_axis("aim", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_bind_button("jump", JOY_BUTTON_A)
	_bind_button("crouch", JOY_BUTTON_B)
	_bind_button("reload", JOY_BUTTON_X)
	_bind_button("grenade", JOY_BUTTON_Y)
	_bind_button("interact", JOY_BUTTON_X)
	_bind_button("sprint", JOY_BUTTON_LEFT_STICK)
	_bind_button("weapon_prev", JOY_BUTTON_LEFT_SHOULDER)
	_bind_button("weapon_next", JOY_BUTTON_RIGHT_SHOULDER)
	_bind_button("pause", JOY_BUTTON_START)

func _bind_button(action: String, btn: int) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and e.button_index == btn:
			return
	var ev := InputEventJoypadButton.new()
	ev.button_index = btn
	InputMap.action_add_event(action, ev)

func _bind_axis(action: String, axis: int, value: float) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion and e.axis == axis and signf(e.axis_value) == signf(value):
			return
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)
