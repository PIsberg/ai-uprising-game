extends Node

signal player_died
signal level_completed
signal score_changed(new_score: int)
signal boss_spawned(boss: Node) ## A boss enemy appeared — HUD shows its health bar.
signal player_dealt_damage(amount: float, world_pos: Vector3, killed: bool, crit: bool) ## Player landed a hit — drives hit markers + damage numbers (crit = headshot).
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
func report_player_hit(amount: float, world_pos: Vector3, killed: bool, crit: bool = false) -> void:
	register_hit()
	player_dealt_damage.emit(amount, world_pos, killed, crit)
	# Combat hit-stop: a crisp per-impact freeze that gives shots real weight —
	# the punch that separates a good-feeling shooter from a flat one. A kill
	# snaps harder than a heavy hit; rate-limited so a fast horde can't slideshow.
	if killed:
		combat_hitstop(0.05, 0.05)
	elif amount >= 40.0:
		combat_hitstop(0.2, 0.03)

enum State { MENU, PLAYING, PAUSED, GAME_OVER, LEVEL_COMPLETE }

## Campaign-wide difficulty, chosen after "Begin Operation". Each tier scales,
## on EVERY level: how many enemies spawn, how strong they are (health + attack
## cadence + move speed), how fast they react and open fire on first contact
## (reaction_mult), their aim accuracy, and how often kills drop supplies.
enum Difficulty { EASY, NORMAL, HARD }

const DIFFICULTY_CONFIG := {
	# Tuned a notch friendlier across the board (2026-06): every tier got slightly
	# slower + fewer enemies and looser enemy aim, while the EASY<NORMAL<HARD
	# scaling is preserved.
	Difficulty.EASY: {
		"label": "EASY",
		# Soft but not empty: it used to cull 70% of every roster (0.3) and miss
		# almost every shot (16deg), which left arenas feeling deserted. Now it
		# fields about half the pack and lands the odd hit, so it still reads as a
		# fight — just a forgiving one (clearly easier than NORMAL).
		"health_mult": 0.5, "cooldown_mult": 1.6, "speed_mult": 0.62,
		"enemy_count_mult": 0.5, "pickup_mult": 1.8, "aim_spread_deg": 12.0,
		"reaction_mult": 2.6, # slow to open fire — gives you a beat
	},
	Difficulty.NORMAL: {
		"label": "NORMAL",
		"health_mult": 1.0, "cooldown_mult": 1.08, "speed_mult": 0.88,
		"enemy_count_mult": 0.82, "pickup_mult": 1.05, "aim_spread_deg": 5.0,
		"reaction_mult": 1.15,
	},
	Difficulty.HARD: {
		"label": "HARD",
		"health_mult": 1.6, "cooldown_mult": 0.75, "speed_mult": 1.1,
		"enemy_count_mult": 1.3, "pickup_mult": 0.65, "aim_spread_deg": 2.0,
		"reaction_mult": 0.5, # snaps onto you and opens fire almost instantly
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
	"res://scenes/levels/level_sublevel.tscn",
	"res://scenes/levels/level_frostbreak.tscn",
	"res://scenes/levels/level_neon.tscn",
	"res://scenes/levels/level_crucible.tscn",
	"res://scenes/levels/level_titan.tscn",
	"res://scenes/levels/level_archon.tscn",
]

var current_state: State = State.MENU
var score: int = 0
var kills: int = 0
var current_level_path: String = ""
var level_index: int = 0
## Furthest campaign level the player has ever entered (0-based). Drives which
## nodes the campaign map unlocks; never walked backward by replaying a level.
var max_level_reached: int = 0
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

## The single source of truth for weapon power, weakest → strongest. EVERY weapon
## in the game appears here exactly once (incl. the sniper/magnum that aren't part
## of the warp arsenal). The WeaponManager sorts the player's rack by this order so
## number keys 1-9 always run weak→strong, and the HUD carousel reads it for slots.
const WEAPON_ORDER: Array[String] = [
	"res://scenes/weapons/pistol.tscn",      # M9 Sidearm — starter
	"res://scenes/weapons/smg.tscn",         # TKN-9 Spitter
	"res://scenes/weapons/rifle.tscn",       # AR-7 Pulse Rifle
	"res://scenes/weapons/shotgun.tscn",     # SG-12 Breacher
	"res://scenes/weapons/magnum.tscn",      # .50 Maelstrom
	"res://scenes/weapons/tesla.tscn",       # VK-7 Tesla Projector (electric beam)
	"res://scenes/weapons/arccoil.tscn",     # CL-3 Arc Coil (electric burst)
	"res://scenes/weapons/sniper.tscn",      # MK-VII Longshot
	"res://scenes/weapons/plasma.tscn",      # PL-1 Plasma Launcher
	"res://scenes/weapons/twinrail.tscn",    # GEM-2 Twin Rail (laser)
	"res://scenes/weapons/nova.tscn",        # NV-X Nova Scatter
	"res://scenes/weapons/gauss.tscn",       # ARC-9 Gauss Lance (laser)
	"res://scenes/weapons/swarm.tscn",       # SW-7 Swarm Launcher
	"res://scenes/weapons/tempest.tscn",     # TPX-9 Tempest Coil (chain lightning)
	"res://scenes/weapons/singularity.tscn", # VOID-9 Singularity Cannon
	"res://scenes/weapons/devastator.tscn",  # GRK-X Devastator
	"res://scenes/weapons/omega.tscn",       # OMEGA-X Annihilator — ultimate
]

## Power rank of a weapon by its scene path (lower = weaker). Unknown weapons sort
## to the end. Used to keep the rack ordered weak→strong everywhere.
func weapon_power_rank(scene_path: String) -> int:
	var i := WEAPON_ORDER.find(scene_path)
	return i if i >= 0 else 999

## Every weapon the warp cheat hands over (the campaign arsenal — sniper/magnum are
## starter sidearms, granted by the loadout, so they're not duplicated here). Listed
## weakest → strongest, the same order the rack uses.
const ALL_WEAPONS: Array[String] = [
	"res://scenes/weapons/pistol.tscn",
	"res://scenes/weapons/smg.tscn",
	"res://scenes/weapons/rifle.tscn",
	"res://scenes/weapons/shotgun.tscn",
	"res://scenes/weapons/tesla.tscn",
	"res://scenes/weapons/arccoil.tscn",
	"res://scenes/weapons/plasma.tscn",
	"res://scenes/weapons/twinrail.tscn",
	"res://scenes/weapons/nova.tscn",
	"res://scenes/weapons/gauss.tscn",
	"res://scenes/weapons/swarm.tscn",
	"res://scenes/weapons/tempest.tscn",
	"res://scenes/weapons/singularity.tscn",
	"res://scenes/weapons/devastator.tscn",
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

## "Field supplies" bought in the Armory — banked here and PERMANENT for the run:
## the player re-applies them on every deploy (never cleared until reset_run on a
## new campaign), so a med-kit's max-HP / an ammo crate / a grenade pack follows
## you the rest of the game. Repeatable, uncapped, cheap.
const SUPPLY_DEFS := {
	"ammo":     {"label": "AMMO CRATE",   "amount": 60, "cost": 450},
	"grenades": {"label": "GRENADE PACK", "amount": 1,  "cost": 600},
	"health":   {"label": "MED-KIT",      "amount": 40, "cost": 750},
}
var supply_ammo: int = 0        # permanent bonus reserve added to every weapon each deploy
var supply_grenades: int = 0    # permanent bonus frag grenades carried each deploy
var supply_health: float = 0.0  # permanent bonus max+current HP each deploy

## Buy a field supply, banking its amount for the next deploy. False if too poor.
func buy_supply(k: String) -> bool:
	if not SUPPLY_DEFS.has(k):
		return false
	var cost := int(SUPPLY_DEFS[k]["cost"])
	if score < cost:
		return false
	score -= cost
	var amt = SUPPLY_DEFS[k]["amount"]
	match k:
		"ammo": supply_ammo += int(amt)
		"grenades": supply_grenades += int(amt)
		"health": supply_health += float(amt)
	save_progress()
	return true

## True if any upgrade OR supply is affordable right now (gates the armory popup).
func can_buy_anything() -> bool:
	if can_buy_any_upgrade():
		return true
	for k in SUPPLY_DEFS:
		if score >= int(SUPPLY_DEFS[k]["cost"]):
			return true
	return false

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
	# Reward the difficulty you cleared on: now that difficulty genuinely changes
	# enemy toughness/speed/cadence, the same play ranks higher on HARD and lower
	# on EASY — so an S means more on HARD than it does on a cakewalk.
	var diff_mult: float = [0.9, 1.0, 1.15][clampi(difficulty, 0, 2)]
	score_pts = clampf(score_pts * diff_mult, 0.0, 100.0)
	var grade := "D"
	if score_pts >= 90.0: grade = "S"
	elif score_pts >= 75.0: grade = "A"
	elif score_pts >= 55.0: grade = "B"
	elif score_pts >= 35.0: grade = "C"
	var lid := level_id_from_path(current_level_path)
	var new_best := record_level_grade(lid, grade)
	var stats := {
		"accuracy": accuracy, "max_combo": max_combo,
		"damage_taken": stat_damage_taken, "time": elapsed,
		"kills": kills, "score": score, "difficulty": difficulty_label(),
		"new_best": new_best, "best_grade": level_bests.get(lid, grade),
	}
	level_graded.emit(grade, stats)
	return {"grade": grade, "stats": stats}

# ---------- per-level best grade (replay incentive, persisted) ----------
const RECORDS_PATH := "user://records.cfg"
const GRADE_RANK := ["D", "C", "B", "A", "S"] ## index = quality, higher is better
var level_bests: Dictionary = {} ## level_id -> best grade letter

func _load_level_bests() -> void:
	var cf := ConfigFile.new()
	if cf.load(RECORDS_PATH) != OK or not cf.has_section("campaign"):
		return
	for k in cf.get_section_keys("campaign"):
		level_bests[k] = str(cf.get_value("campaign", k, "D"))

## Store `grade` as this level's best if it beats the previous; returns true on a
## new record (drives the "NEW BEST" flourish on the win screen).
func record_level_grade(lid: String, grade: String) -> bool:
	if lid == "":
		return false
	var prev_rank := GRADE_RANK.find(str(level_bests.get(lid, "")))
	var new_rank := GRADE_RANK.find(grade)
	if new_rank <= prev_rank:
		return false
	level_bests[lid] = grade
	var cf := ConfigFile.new()
	cf.load(RECORDS_PATH) # preserve the horde section
	cf.set_value("campaign", lid, grade)
	cf.save(RECORDS_PATH)
	return true

func reset_run() -> void:
	score = 0
	kills = 0
	seen_enemy_types.clear()
	supply_ammo = 0
	supply_grenades = 0
	supply_health = 0.0

## Brief slow-motion payoff (e.g. boss death, area clear) AND the primitive
## behind the per-hit combat punch. A guard token means overlapping freezes
## don't restore early — the most recent freeze owns the restore — so a kill's
## micro-freeze can't cut a cinematic beat short, and vice versa. Real-time
## timer so it always restores even though the game clock is slowed.
var _hitstop_token: int = 0
var _last_punch_ms: int = 0

func hit_stop(scale: float = 0.3, duration: float = 0.4) -> void:
	Engine.time_scale = clampf(scale, 0.04, 1.0)
	_hitstop_token += 1
	var mine := _hitstop_token
	# create_timer(sec, process_always, process_in_physics, ignore_time_scale)
	var t := get_tree().create_timer(duration, true, false, true)
	t.timeout.connect(func() -> void:
		if mine == _hitstop_token:
			Engine.time_scale = 1.0)

## Rapid-fire combat hit-stop (per kill / heavy hit). Wall-clock rate-limited
## (real ms, immune to the freeze itself) so a horde of kills can't stutter the
## game into a slideshow. Only while actually playing.
func combat_hitstop(scale: float, duration: float) -> void:
	if current_state != State.PLAYING:
		return
	var now := Time.get_ticks_msec()
	if now - _last_punch_ms < 90:
		return
	_last_punch_ms = now
	hit_stop(scale, duration)

## Start a fresh campaign run from the first level at the chosen difficulty.
func start_campaign(diff: int = Difficulty.NORMAL) -> void:
	difficulty = diff
	reset_run()
	unlocked_weapons.clear() # fresh run starts with only the base arsenal
	equipped_weapon = ""     # ...armed with the default (pistol)
	upgrades = {"damage": 0, "mag": 0, "reload": 0} # armory resets with the run
	intro_played = false
	level_index = 0
	max_level_reached = 0
	go_to_level(campaign()[0], false)

## The opener is now a comic-panel flash instead of the old 3D story cutscene.
const INTRO_CUTSCENE := "res://scenes/cutscene/comic_intro.tscn"
const LEVEL_BRIEFING := "res://scenes/cutscene/level_comic_briefing.tscn"
const UPRISING_REVEAL := "res://scenes/cutscene/uprising_reveal.tscn"
## Scene that builds a custom editor level from a .lvl data file (via
## `custom_level_path`). Campaign entries / paths ending in `.lvl` route here
## instead of being change_scene'd directly (a .lvl is JSON data, not a scene).
const LEVEL_CUSTOM := "res://scenes/levels/level_custom.tscn"
## Lightweight scene shown while a heavy level builds, so the main-thread build
## stall sits on a loading frame instead of a grey window. Reads `pending_scene`.
const LOADING_SCREEN := "res://scenes/ui/loading_screen.tscn"
var pending_scene: String = ""
## Levels that play a bespoke reveal cutscene instead of the standard briefing.
const CUTSCENE_FOR_LEVEL := {"sublevel": UPRISING_REVEAL}

## Enter a campaign level THROUGH its cutscene: level 1 gets the story intro,
## every other level gets a data-driven briefing (new enemies + objective + mood).
## The cutscene calls load_level() when it finishes/skips to enter the level.
func go_to_level(path: String, reset: bool = false) -> void:
	current_level_path = path
	var found := campaign().find(path)
	if found != -1:
		level_index = found
		max_level_reached = maxi(max_level_reached, found)
	if reset:
		reset_run()
	set_state(State.PLAYING)
	if found != -1:
		save_progress()
	var lid := level_id_from_path(path)
	if lid == "01":
		get_tree().change_scene_to_file(INTRO_CUTSCENE)
	elif CUTSCENE_FOR_LEVEL.has(lid):
		get_tree().change_scene_to_file(CUTSCENE_FOR_LEVEL[lid])
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

# ---------- bestiary discovery (persistent, survives new campaigns) ----------
## Which enemy types the player has ever encountered in a real level. Unlocks the
## Encyclopedia entry for that hostile. Stored in its OWN file so it persists
## across runs and isn't wiped by reset_run() like the per-run seen tracking.

const BESTIARY_PATH := "user://bestiary.cfg"
var discovered_enemies: Dictionary = {}

func is_enemy_discovered(t: String) -> bool:
	return discovered_enemies.has(t)

func discovered_enemy_count() -> int:
	return discovered_enemies.size()

## Record an encounter; persists immediately when something new is learned.
func discover_enemy(t: String) -> void:
	if t == "" or discovered_enemies.has(t):
		return
	discovered_enemies[t] = true
	_save_bestiary()

## Unlock the WHOLE bestiary at once (the warp cheat shows off every enemy).
func discover_all_enemies() -> void:
	var changed := false
	for t in EnemyCodex.ORDER:
		if not discovered_enemies.has(t):
			discovered_enemies[t] = true
			changed = true
	if changed:
		_save_bestiary()

## Mark every hostile a campaign level fields as discovered — called the moment
## the player actually drops into the playable level (covers the comic-intro
## level 1 and every briefing-entered level alike).
func _discover_level_enemies(path: String) -> void:
	var lid := level_id_from_path(path)
	var def := LevelDefs.get_def(lid)
	for e in def.get("enemies", []):
		var t: String = e.get("type", "")
		if t != "" and EnemyCodex.has(t):
			discover_enemy(t)

func _load_bestiary() -> void:
	var cf := ConfigFile.new()
	if cf.load(BESTIARY_PATH) != OK:
		return
	for t in cf.get_value("bestiary", "discovered", []):
		discovered_enemies[str(t)] = true

func _save_bestiary() -> void:
	var cf := ConfigFile.new()
	cf.set_value("bestiary", "discovered", discovered_enemies.keys())
	cf.save(BESTIARY_PATH)

## Load a specific level. `reset` wipes score/kills (used for replays); campaign
## advancement passes false so the running score carries across levels.
func load_level(scene_path: String, reset: bool = true) -> void:
	current_level_path = scene_path
	var found := campaign().find(scene_path)
	if found != -1:
		level_index = found
		max_level_reached = maxi(max_level_reached, found)
	if reset:
		reset_run()
	reset_level_stats()
	set_state(State.PLAYING)
	if found != -1:
		save_progress() # checkpoint at the start of every campaign level
		_discover_level_enemies(scene_path) # unlock these hostiles' codex entries
	# A custom editor level is JSON data (.lvl), not a scene — build it through
	# level_custom.tscn (same mechanism as the editor playtest / --level boot),
	# otherwise change_scene_to_file fails on the data file and leaves a black screen.
	# Both routes go via the loading screen: the level's procedural build stalls
	# the main thread, and the loading frame is what stays on screen during it.
	if scene_path.get_extension() == "lvl":
		custom_level_path = scene_path
		_enter_level_scene(LEVEL_CUSTOM)
	else:
		_enter_level_scene(scene_path)

## Switch to the loading screen, which paints a frame and then changes to
## `target` (the heavy level scene). Keeps the grey-window stall off-screen.
func _enter_level_scene(target: String) -> void:
	pending_scene = target
	get_tree().change_scene_to_file(LOADING_SCREEN)

# ---------- save / checkpoint ----------

const SAVE_PATH := "user://savegame.cfg"

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## Write a checkpoint of the current run so the player can Continue later.
func save_progress() -> void:
	var cf := ConfigFile.new()
	cf.set_value("run", "level_index", level_index)
	cf.set_value("run", "max_level_reached", max_level_reached)
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
	max_level_reached = int(cf.get_value("run", "max_level_reached", level_index))
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
	level_index = clampi(level_index, 0, campaign().size() - 1)
	load_level(campaign()[level_index], false)

func has_next_level() -> bool:
	return level_index + 1 < campaign().size()

## Called by the level-complete "Continue" button.
func advance_level() -> void:
	if has_next_level():
		go_to_level(campaign()[level_index + 1], false)
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

## Plentiful grunt types — thinned first on lower difficulties so rarer special
## enemies (spider, brute, gunner, mender, …) stay in the mix.
const COMMON_ENEMIES := ["drone", "android", "seeker", "skitter"]

## Lower rank = removed first when thinning. Common+trigger goes first, rare and
## hand-placed enemies last, so Easy still shows the full roster.
func _cull_rank(s: EnemySpawner) -> int:
	var path: String = s.enemy_scene.resource_path if s.enemy_scene else ""
	var common := false
	for c in COMMON_ENEMIES:
		if c in path:
			common = true
			break
	var rank := 0 if common else 2
	if s.trigger_radius <= 0.0:
		rank += 1 # spare hand-placed/immediate before trigger reinforcements
	return rank

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
		# Thin the pack to hit the target. Bosses are always spared. Cull the
		# plentiful grunts first (and trigger-spawned reinforcements before
		# hand-placed ones) so rarer enemies — spider, brute, gunner, … — survive
		# and the player still meets the full roster even on Easy.
		var removable := spawners.filter(func(s): return not _is_boss_spawner(s))
		removable.sort_custom(func(a, b): return _cull_rank(a) < _cull_rank(b))
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

## Set before loading level_custom.tscn (by the editor playtest or the --level
## CLI boot) so LevelBuilder knows which .lvl file to build.
var custom_level_path: String = ""
## True when the current custom level was launched from the editor's Playtest, so
## the pause menu / F2 offer "Return to Editor" instead of "Quit to Menu".
var from_editor: bool = false

const EDITOR_SCENE := "res://scenes/editor/level_editor.tscn"

## Leave a playtest and go back to the level editor (state intact in the editor).
func return_to_editor() -> void:
	from_editor = false
	set_state(State.MENU)
	get_tree().change_scene_to_file(EDITOR_SCENE)

## Campaign order override authored by the level editor (res://dev_levels/
## campaign.json). When present it replaces the built-in CAMPAIGN. Read via
## campaign().
var _campaign_override: Array[String] = []

## The active campaign level list (editor override if any, else the built-in).
func campaign() -> Array:
	return _campaign_override if not _campaign_override.is_empty() else CAMPAIGN

## Load an optional editor-authored campaign order from dev_levels/campaign.json.
## STRICTLY validated: a malformed, empty, or partly-broken file is REJECTED
## (we keep the built-in campaign) instead of silently hijacking/truncating the
## game. This is the safety net for "I saved something in the editor and it
## broke the game" — a bad save can no longer take the campaign down with it.
func _load_campaign_override() -> void:
	var p := "res://dev_levels/campaign.json"
	if not FileAccess.file_exists(p):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (v is Array) or (v as Array).is_empty():
		push_warning("campaign.json ignored (not a non-empty JSON array) — using built-in campaign.")
		return
	var valid: Array[String] = []
	for e in v:
		var lvl := str(e)
		# Built-in levels are res:// scenes; editor levels are .lvl data files.
		if ResourceLoader.exists(lvl) or FileAccess.file_exists(lvl):
			valid.append(lvl)
		else:
			push_warning("campaign.json references a missing level: '%s'" % lvl)
	# Apply ONLY if every listed level resolves. A single bad/typo'd entry rejects
	# the whole override so play always falls back to the known-good campaign.
	if valid.size() == (v as Array).size():
		_campaign_override = valid
		print("[GameState] campaign.json override active: %d levels." % valid.size())
	else:
		push_warning("campaign.json REJECTED (%d of %d levels valid) — using built-in campaign. Fix or delete dev_levels/campaign.json." % [valid.size(), (v as Array).size()])

func _ready() -> void:
	_setup_gamepad_bindings()
	_load_bestiary()
	_load_level_bests()
	_load_campaign_override()
	_handle_cli_boot()

## `AIUprising.exe --level res://dev_levels/foo.lvl` boots straight into that
## custom level (the editor's Playtest shells out this way).
func _handle_cli_boot() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	# "--editor" (or a dedicated editor build, custom feature "editor_build") boots
	# straight into the level editor — the dev "separate program" entry.
	if "--editor" in args or OS.has_feature("editor_build"):
		set_state(State.MENU)
		get_tree().change_scene_to_file.call_deferred(EDITOR_SCENE)
		return
	var i := args.find("--level")
	if i != -1 and i + 1 < args.size():
		custom_level_path = args[i + 1]
		set_state(State.PLAYING)
		get_tree().change_scene_to_file.call_deferred(LEVEL_CUSTOM)

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
	_bind_button("dash", JOY_BUTTON_RIGHT_STICK)
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
