extends Node

signal player_died
signal level_completed
signal score_changed(new_score: int)
signal boss_spawned(boss: Node) ## A boss enemy appeared — HUD shows its health bar.
signal player_dealt_damage(amount: float, world_pos: Vector3, killed: bool, crit: bool) ## Player landed a hit — drives hit markers + damage numbers (crit = headshot).
signal enemy_killed(score: int, label: String) ## An enemy was destroyed — drives the HUD kill feed.
signal objective_blocked(text: String) ## Player reached a locked portal — HUD posts why.
signal objective_unlocked(text: String) ## Objective met, portal opened — HUD updates the goal line.
signal upgrades_changed ## Run upgrade ranks changed (armory buy / "imba" cheat) — HUD re-renders the upgrade chips.
signal tasks_changed ## The level task checklist changed — HUD re-renders the objective line.
signal task_completed(label: String) ## A single task was just finished — HUD cheers it.
signal combo_changed(combo: int, mult: float) ## Kill-streak combo updated — HUD shows the multiplier.
signal level_graded(grade: String, stats: Dictionary) ## Level cleared — end-screen grade + breakdown.

func announce_boss(boss: Node) -> void:
	boss_spawned.emit(boss)
	set_checkpoint() # boss arena entered — sane restart point for a death mid-fight

## Called by Damageable when the player damages something. Drives combat feedback.
func report_player_hit(amount: float, world_pos: Vector3, killed: bool, crit: bool = false) -> void:
	register_hit()
	AIDirector.note_hit(crit, world_pos) # feed the adaptive director (range + headshots)
	player_dealt_damage.emit(amount, world_pos, killed, crit)
	add_ultimate_charge(amount * ULT_PER_DAMAGE) # damage dealt smooths the OVERLOAD fill
	if crit:
		add_ultimate_charge(0.02) # precision (headshots/weak-points) charges OVERLOAD faster
	# LIFELEECH track: siphon a slice of the damage you deal back as health, so an
	# aggressive build sustains itself. Clamped by Damageable.heal to max HP.
	var leech := upgrade_mult("leech") - 1.0
	if leech > 0.0:
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			var d = pl.get_node_or_null("Damageable")
			if d and d.has_method("is_alive") and d.is_alive():
				d.heal(amount * leech)
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
		"reaction_mult": 2.0, # slow to open fire — gives you a beat
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

# ---------------------------------------------------------------------
# Campaign progression scaling. The difficulty tiers above are STATIC — they
# hit level 1 and the finale identically. But the player accrues permanent
# power across a run (armory damage +8%/rank, +40 max-HP med-kits, the whole
# weak→strong arsenal, overclock/overdrive), so without a counter-ramp the
# back half of the campaign trivializes once you're funded. This gentle ramp
# scales enemy DURABILITY (and, slightly, attack cadence) with how deep you
# are in the campaign, sized to roughly offset that creep — NOT to spike late
# levels. It stacks on top of the difficulty tier and only applies inside the
# campaign (custom/range/horde test maps are untouched).
# ---------------------------------------------------------------------

## 0.0 on the first campaign level → 1.0 on the finale; -1.0 if the current
## level isn't part of the campaign (so the ramp no-ops off-campaign).
func campaign_progress() -> float:
	var camp := campaign()
	var idx := camp.find(current_level_path)
	if idx < 0:
		return -1.0
	return float(idx) / maxf(1.0, float(camp.size() - 1))

## Multipliers layered on top of difficulty_config() for the current campaign
## depth. Health ramps to +40% by the finale (offsetting the +40% armory damage
## cap and weapon-tier creep); attacks tighten by up to 12% so late robots stay
## on the trigger. Returns 1.0s off-campaign.
func campaign_health_mult() -> float:
	var p := campaign_progress()
	return 1.0 if p < 0.0 else 1.0 + p * 0.40

func campaign_cadence_mult() -> float:
	var p := campaign_progress()
	return 1.0 if p < 0.0 else 1.0 - p * 0.12

## Elite affix odds ramp in over the first third of the campaign: the opening
## level rolls ZERO elites (a shielded spider against the starter pistol ended a
## playtest at first contact), full odds from ~1/3 depth on. Off-campaign
## (horde, custom, warp) elites roll at full strength.
func campaign_elite_mult() -> float:
	var p := campaign_progress()
	return 1.0 if p < 0.0 else clampf(p * 3.0, 0.0, 1.0)

## Onboarding warmup — the mirror of the late-campaign toughness ramp: damage
## the PLAYER takes eases in from ×0.65 on the opening level to ×1.0 by ~25%
## campaign depth. Playtests with the starter pistol died inside 20 s of first
## contact at full incoming damage; this buys the opening levels room to teach
## movement and aim without changing enemy counts or behavior. Off-campaign
## modes take full damage.
func campaign_incoming_mult() -> float:
	var p := campaign_progress()
	return 1.0 if p < 0.0 else lerpf(0.65, 1.0, clampf(p * 4.0, 0.0, 1.0))

## Boss enemy type tokens (matched against a spawner's scene path). Bosses are
## hand-tuned, one-off HP bags with scripted phases, so they're EXEMPT from the
## campaign depth ramp above — that ramp exists to counter player creep on the
## long tail of regular enemies; stacking it onto a 3000-HP boss (on top of the
## difficulty tier) would just make the climax a slog. They still scale with the
## difficulty tier's health_mult like everything else.
const BOSS_TYPES := ["colossus", "titan", "overseer", "archon", "terminator", "smasher"]

func is_boss_scene(path: String) -> bool:
	for b in BOSS_TYPES:
		if b in path:
			return true
	return false

## Campaign order. The player advances through these via the "Continue" button
## on the level-complete screen.
const CAMPAIGN: Array[String] = [
	"res://scenes/levels/level_01.tscn",
	"res://scenes/levels/level_gpt.tscn",
	"res://scenes/levels/level_gemini.tscn",
	"res://scenes/levels/level_mistral.tscn",
	"res://scenes/levels/level_suburb.tscn",
	"res://scenes/levels/level_suburb_boss.tscn",
	"res://scenes/levels/level_convoy.tscn", # rail-shooter ride: fight from a moving hauler
	"res://scenes/levels/level_claude.tscn",
	"res://scenes/levels/level_grok.tscn",
	"res://scenes/levels/level_uplink.tscn",
	"res://scenes/levels/level_overseer.tscn",
	"res://scenes/levels/level_alien.tscn",
	"res://scenes/levels/level_assembly.tscn",
	"res://scenes/levels/level_sublevel.tscn",
	"res://scenes/levels/level_frostbreak.tscn",
	"res://scenes/levels/level_water_world.tscn",
	"res://scenes/levels/level_desert.tscn",
	"res://scenes/levels/level_neon.tscn",
	"res://scenes/levels/level_guardrails.tscn", # Generative Guardrails: anchor-tag a safe path across live-generated hazard terrain
	"res://scenes/levels/level_hivemind.tscn",   # Geofenced Signal Jamming: jam beacons strip shields off the hive-mind flankers
	"res://scenes/levels/level_crucible.tscn",
	"res://scenes/levels/level_lava_world.tscn",
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
## The first-level controls overlay teaches once per campaign run — set true the
## first time the HUD shows it so retries / later levels don't repeat it.
var controls_taught: bool = false

func unlock_weapon(scene_path: String) -> void:
	if not unlocked_weapons.has(scene_path):
		unlocked_weapons.append(scene_path)
	discover_weapon(scene_path) # unlocked = held: reveal its codex dossier too

## The single source of truth for weapon power, weakest → strongest. EVERY weapon
## in the game appears here exactly once (incl. the sniper/magnum that aren't part
## of the warp arsenal). The WeaponManager sorts the player's rack by this order so
## number keys 1-9 always run weak→strong, and the HUD carousel reads it for slots.
const WEAPON_ORDER: Array[String] = [
	"res://scenes/weapons/pistol.tscn",      # M9 Sidearm — starter
	"res://scenes/weapons/rifle.tscn",       # AR-7 Pulse Rifle — the full-auto
	"res://scenes/weapons/shotgun.tscn",     # SG-12 Breacher
	"res://scenes/weapons/magnum.tscn",      # .50 Maelstrom
	"res://scenes/weapons/tesla.tscn",       # VK-7 Tesla Projector (close-range arc)
	"res://scenes/weapons/arccoil.tscn",     # CL-3 Arc Coil (electric burst)
	"res://scenes/weapons/sniper.tscn",      # MK-VII Longshot
	"res://scenes/weapons/plasma.tscn",      # PL-1 Plasma Launcher
	"res://scenes/weapons/gauss.tscn",       # ARC-9 Gauss Lance (piercing laser)
	"res://scenes/weapons/swarm.tscn",       # SW-7 Swarm Launcher
	"res://scenes/weapons/tempest.tscn",     # TPX-9 Tempest Coil (chain lightning)
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
	"res://scenes/weapons/rifle.tscn",
	"res://scenes/weapons/shotgun.tscn",
	"res://scenes/weapons/tesla.tscn",
	"res://scenes/weapons/arccoil.tscn",
	"res://scenes/weapons/plasma.tscn",
	"res://scenes/weapons/gauss.tscn",
	"res://scenes/weapons/swarm.tscn",
	"res://scenes/weapons/tempest.tscn",
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
	# Build-defining tracks: lean into explosives, heal off aggression, or run/rappel
	# longer before gassing out.
	"blast":   {"label": "GRENADE POWER", "per": 0.16, "cost": 1300},
	"leech":   {"label": "LIFELEECH",     "per": 0.03, "cost": 1400},
	"stamina": {"label": "STAMINA",       "per": 0.10, "cost": 900},
}
const UPGRADE_MAX := 5
var upgrades: Dictionary = {"damage": 0, "mag": 0, "reload": 0, "blast": 0, "leech": 0, "stamina": 0}

## "Field supplies" bought in the Armory — banked here and PERMANENT for the run:
## the player re-applies them on every deploy (never cleared until reset_run on a
## new campaign), so a med-kit's max-HP / an ammo crate / a grenade pack follows
## you the rest of the game. Repeatable, uncapped, cheap.
const SUPPLY_DEFS := {
	"ammo":     {"label": "AMMO CRATE",   "amount": 60, "cost": 450},
	"grenades": {"label": "GRENADE PACK", "amount": 1,  "cost": 600},
	"health":   {"label": "MED-KIT",      "amount": 40, "cost": 750},
}
## MED-KITs are the only PERMANENT, repeatable max-HP source, and uncapped they
## let a score-rich player tank to 300-500+ HP — the dominant unbounded purchase
## that outpaces any enemy tuning. Cap the bonus at +160 (4 kits → 260 HP max):
## a generous survivability ceiling that's still bounded, so durability stays a
## meaningful choice instead of a money-dump win button. Ammo/grenades stay
## uncapped (consumed in play; they don't break the power curve).
const SUPPLY_HEALTH_CAP := 160.0

## True once max-HP MED-KITs are banked to the cap (armory shows MAXED, no buy).
func supply_health_maxed() -> bool:
	return supply_health >= SUPPLY_HEALTH_CAP
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
	if k == "health" and supply_health_maxed():
		return false # max-HP banked to the cap — don't take score for a no-op
	score -= cost
	var amt = SUPPLY_DEFS[k]["amount"]
	match k:
		"ammo": supply_ammo += int(amt)
		"grenades": supply_grenades += int(amt)
		"health": supply_health = minf(SUPPLY_HEALTH_CAP, supply_health + float(amt))
	save_progress()
	return true

## True if any upgrade OR supply is affordable right now (gates the armory popup).
func can_buy_anything() -> bool:
	if can_buy_any_upgrade():
		return true
	for k in SUPPLY_DEFS:
		if k == "health" and supply_health_maxed():
			continue # capped — not a real choice anymore
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
	upgrades_changed.emit()
	save_progress()
	return true

## Cheat ("imba"): max every permanent upgrade track for the run, for free.
func max_all_upgrades() -> void:
	for k in UPGRADE_DEFS:
		upgrades[k] = UPGRADE_MAX
	upgrades_changed.emit()
	save_progress()

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

## Grenade blast multiplier (GRENADE POWER track) — scales thrown-charge damage
## and radius. 1.0 with no ranks.
func grenade_mult() -> float:
	return upgrade_mult("blast")

## Max-stamina multiplier (STAMINA track) — a bigger pool to sprint/rappel on.
func stamina_mult() -> float:
	return upgrade_mult("stamina")

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
	_update_rampage()
	add_ultimate_charge(ULT_PER_KILL)

# ---------- RAMPAGE: kill-streak power escalation ----------
## A streak doesn't just multiply score — it cranks YOUR power. Chain kills inside
## the combo window to spike into a tier: +damage, then +fire rate, then +speed,
## each announced with a banner + a top-up heal so momentum sustains itself. It
## all drops the instant the streak breaks — a fun, aggressive "keep killing" loop.
const RAMPAGE_TIERS := [5, 10, 18]                 ## combo counts unlocking tiers 1/2/3
const RAMPAGE_NAMES := ["RAMPAGE", "UNSTOPPABLE", "GODLIKE"]
const RAMPAGE_DMG := [1.0, 1.18, 1.35, 1.55]       ## damage mult by tier 0..3
const RAMPAGE_FIRE := [1.0, 1.0, 1.18, 1.35]       ## fire-rate mult by tier
const RAMPAGE_SPEED := [1.0, 1.0, 1.0, 1.12]       ## move-speed mult by tier
const RAMPAGE_HEAL := [0.0, 12.0, 16.0, 22.0]      ## HP topped up on reaching a tier
signal rampage_changed(tier: int, name: String)    ## Rampage tier changed — HUD banner.
var rampage_tier: int = 0

func _rampage_for_combo() -> int:
	var t := 0
	for i in RAMPAGE_TIERS.size():
		if combo >= RAMPAGE_TIERS[i]:
			t = i + 1
	return t

func _update_rampage() -> void:
	var t := _rampage_for_combo()
	if t <= rampage_tier:
		return # only fires on a NEW, higher tier
	rampage_tier = t
	stat_best_rampage = maxi(stat_best_rampage, t)
	teach_once("rampage", MECHANIC_HINTS["rampage"])
	var nm: String = RAMPAGE_NAMES[t - 1]
	rampage_changed.emit(rampage_tier, nm)
	# Reward: a top-up heal to sustain the aggression + a satisfying hit-stop spike.
	var pl := get_tree().get_first_node_in_group("player")
	if pl:
		var d = pl.get_node_or_null("Damageable")
		if d and d.has_method("heal") and d.has_method("is_alive") and d.is_alive():
			d.heal(RAMPAGE_HEAL[t])
	AudioBus.play_synth_ui("combo_up", -1.0, 1.0 + t * 0.18)
	hit_stop(0.06, 0.4)
	# Top tier (GODLIKE): the pack visibly breaks and scatters around you.
	if t >= RAMPAGE_TIERS.size() and pl:
		startle_enemies((pl as Node3D).global_position, 18.0, 1.0)

## Make nearby hostiles panic-scatter — the world reacting to a player power spike
## (GODLIKE rampage, OVERLOAD). Skips bosses (they don't flinch) and EMP'd/dead
## units (handled in EnemyBase.startle).
func startle_enemies(pos: Vector3, radius: float, duration: float = 0.9) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and e.score_value < 1000 \
				and (e as Node3D).global_position.distance_to(pos) <= radius:
			e.startle(pos, duration)

func rampage_damage_mult() -> float:
	return RAMPAGE_DMG[rampage_tier]

func rampage_fire_mult() -> float:
	return RAMPAGE_FIRE[rampage_tier]

func rampage_speed_mult() -> float:
	return RAMPAGE_SPEED[rampage_tier]

# ---------- ADRENALINE SURGE: clutch near-death comeback ----------
## The defensive counterpart to RAMPAGE. Dropping to critical HP kicks a brief
## bullet-time beat, a small heal, and a short offensive/mobility surge so a
## near-death moment becomes a dramatic comeback instead of a death spiral.
## Cooldown-gated so it stays a rare clutch, never a constant crutch.
const ADRENALINE_TRIGGER_FRAC := 0.25   ## HP fraction the surge fires below
const ADRENALINE_DURATION := 5.0        ## seconds the buff lasts
const ADRENALINE_COOLDOWN := 16.0       ## lockout after it ends
const ADRENALINE_DMG := 1.3             ## damage mult while surging
const ADRENALINE_FIRE := 1.25           ## fire-rate mult while surging
const ADRENALINE_SPEED := 1.15          ## move-speed mult while surging
const ADRENALINE_HEAL := 12.0           ## instant breathing-room heal on trigger
signal adrenaline_changed(active: bool) ## Surge started/ended — HUD banner + vignette.
var adrenaline_left: float = 0.0
var _adrenaline_cd: float = 0.0

## Called by the player when its HP crosses below the critical line. Returns true
## if a fresh surge actually fired (so the caller can skip duplicate cues).
func try_adrenaline() -> bool:
	if current_state != State.PLAYING:
		return false
	if adrenaline_left > 0.0 or _adrenaline_cd > 0.0:
		return false
	adrenaline_left = ADRENALINE_DURATION
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var d = player.get_node_or_null("Damageable")
		if d and d.has_method("heal"):
			d.heal(ADRENALINE_HEAL)
	hit_stop(0.28, 0.5) # a distinct bullet-time beat, slower than a kill's micro-punch
	AudioBus.play_synth_ui("overlord_glitch", -4.0, 0.7)
	teach_once("adrenaline", MECHANIC_HINTS["adrenaline"])
	adrenaline_changed.emit(true)
	return true

func adrenaline_damage_mult() -> float:
	return ADRENALINE_DMG if adrenaline_left > 0.0 else 1.0

func adrenaline_fire_mult() -> float:
	return ADRENALINE_FIRE if adrenaline_left > 0.0 else 1.0

func adrenaline_speed_mult() -> float:
	return ADRENALINE_SPEED if adrenaline_left > 0.0 else 1.0

# ---------- PERFECT DODGE: skill-expression reward ----------
## Rewards a dash that actually phases through an incoming hit (its i-frames
## negate a shot/melee). Skillful, reactive play — the third engagement pillar
## alongside RAMPAGE (winning) and ADRENALINE (surviving). The player calls
## reward_perfect_dodge() from its shield-hit hook, once per dash.
const PERFECT_DODGE_SCORE := 75            ## bonus points per clean dodge
const PERFECT_DODGE_ADREN_REFUND := 3.0    ## seconds shaved off the adrenaline lockout
signal perfect_dodge()                     ## HUD banner + slow-mo cue.

func reward_perfect_dodge() -> void:
	if current_state != State.PLAYING:
		return
	add_score(PERFECT_DODGE_SCORE)
	# A crisp bullet-time snap sells the read; shorter than a kill cinematic.
	combat_hitstop(0.35, 0.09)
	# Reactive play chips away at the clutch-surge lockout, tying the systems.
	if _adrenaline_cd > 0.0:
		_adrenaline_cd = maxf(0.0, _adrenaline_cd - PERFECT_DODGE_ADREN_REFUND)
	stat_dodges += 1
	teach_once("dodge", MECHANIC_HINTS["dodge"])
	AudioBus.play_synth_ui("combo_up", -4.0, 1.35)
	perfect_dodge.emit()

# ---------- EXECUTION: melee finisher on a weakened enemy ----------
## A melee shove into a low-HP non-boss instakills it (see Player._do_melee).
## Small bonus + a heavier crunch + callout so finishing a stagger by hand feels
## like a takedown. The kill's own score/combo still lands via add_kill.
const EXECUTE_BONUS := 60
signal execution(world_pos: Vector3)

func reward_execution(world_pos: Vector3) -> void:
	if current_state != State.PLAYING:
		return
	add_score(EXECUTE_BONUS)
	stat_executions += 1
	teach_once("execution", MECHANIC_HINTS["execution"])
	combat_hitstop(0.35, 0.11) # a beefier crunch than a normal kill
	AudioBus.play_synth_ui("headshot", -2.0, 0.8)
	execution.emit(world_pos)

# ---------- OVERLOAD: charge-and-unleash ultimate ----------
## A meter the player builds by fighting (kills + damage dealt) and unleashes as a
## screen-clearing shockwave (see Player._unleash_overload) — a panic-button power
## peak the arsenal otherwise lacks. Charge is per-level.
const ULT_PER_KILL := 0.085      ## charge gained per kill (~12 kills to fill)
const ULT_PER_DAMAGE := 0.0004   ## charge per point of damage dealt (smooths the fill)
signal ultimate_changed(charge: float) ## 0..1 meter — HUD gauge.
signal ultimate_ready()                 ## crossed to full — HUD prompt + chirp.
signal ultimate_fired()                 ## unleashed — HUD flash.
var ultimate_charge: float = 0.0

func add_ultimate_charge(amount: float) -> void:
	if current_state != State.PLAYING or ultimate_charge >= 1.0 or amount <= 0.0:
		return
	var was := ultimate_charge
	ultimate_charge = clampf(ultimate_charge + amount, 0.0, 1.0)
	ultimate_changed.emit(ultimate_charge)
	if was < 1.0 and ultimate_charge >= 1.0:
		AudioBus.play_synth_ui("combo_up", 0.0, 1.5)
		teach_once("overload", MECHANIC_HINTS["overload"])
		ultimate_ready.emit()

func ultimate_ready_state() -> bool:
	return ultimate_charge >= 1.0

## Spend a full meter (Player calls this on the OVERLOAD keypress). Returns false
## if not charged, so the player can play a denied click instead.
func consume_ultimate() -> bool:
	if ultimate_charge < 1.0:
		return false
	ultimate_charge = 0.0
	ultimate_changed.emit(0.0)
	ultimate_fired.emit()
	return true

# ---------- COMBAT DIRECTIVE: per-level roguelite mutator ----------
## At the start of each (non-boss) level there's a chance the run rolls a DIRECTIVE
## that reshapes the rules — a high-risk/high-reward twist for replay variety. All
## effects route through the mult getters below (damage dealt/taken, move, loot,
## bounty cadence) so a directive is fully contained and reverts on the next level.
const DIRECTIVE_CHANCE := 0.6 ## odds a level rolls one at all
const DIRECTIVES := [
	{"id": "glass_cannon", "name": "GLASS CANNON",
		"desc": "+50% damage dealt — but you take +40% more", "damage": 1.5, "incoming": 1.4},
	{"id": "juggernaut", "name": "JUGGERNAUT",
		"desc": "Take 40% less damage — deal 10% less", "incoming": 0.6, "damage": 0.9},
	{"id": "spoils", "name": "SPOILS OF WAR",
		"desc": "Every kill drops double loot", "pickup": 2.0},
	{"id": "blitz", "name": "BLITZ",
		"desc": "+20% move speed — but +20% damage taken", "move": 1.2, "incoming": 1.2},
	{"id": "most_wanted", "name": "MOST WANTED",
		"desc": "Bounties appear twice as often, worth 50% more", "bounty_interval": 0.4, "bounty_bonus": 1.5},
]
signal directive_set(name: String, desc: String) ## Level's directive (or "" for none) — HUD callout.
var directive_id: String = ""
var directive: Dictionary = {}

func roll_directive() -> void:
	directive = {}
	directive_id = ""
	if randf() <= DIRECTIVE_CHANCE:
		var d: Dictionary = DIRECTIVES[randi() % DIRECTIVES.size()]
		directive = d
		directive_id = String(d["id"])
	directive_set.emit(String(directive.get("name", "")), String(directive.get("desc", "")))

func directive_damage_mult() -> float: return float(directive.get("damage", 1.0))
func directive_incoming_mult() -> float: return float(directive.get("incoming", 1.0))
func directive_move_mult() -> float: return float(directive.get("move", 1.0))
func directive_pickup_mult() -> float: return float(directive.get("pickup", 1.0))

# ---------- BOUNTY: a rotating hunt-the-marked-target sub-goal ----------
## Periodically tags one live non-boss enemy as a BOUNTY: a beacon-marked target
## worth bonus score + a guaranteed rare drop. Gives every drawn-out fight a
## shifting objective ("go get THAT one") on top of the mandatory objectives —
## variety and a pull through the level, distinct from elite THREATS.
const BOUNTY_BONUS := 300               ## bonus score for claiming a bounty
const BOUNTY_INTERVAL := 24.0           ## seconds between bounties
const BOUNTY_LIFETIME := 45.0           ## un-mark if it survives this long (re-roll)
const BOUNTY_MIN_ENEMIES := 3           ## only mark when a fight is actually on
signal bounty_marked(label: String)     ## a target was tagged — HUD callout
signal bounty_claimed(points: int)      ## the tagged target went down — HUD payoff
var _bounty: WeakRef = null
var _bounty_cd: float = BOUNTY_INTERVAL
var _bounty_age: float = 0.0

func _tick_bounty(delta: float) -> void:
	if current_state != State.PLAYING:
		return
	var cur: Node = _bounty.get_ref() if _bounty else null
	if cur != null and is_instance_valid(cur) and not cur.is_queued_for_deletion():
		_bounty_age += delta
		if _bounty_age >= BOUNTY_LIFETIME:
			if cur.has_method("clear_bounty"):
				cur.clear_bounty()
			_bounty = null
			_bounty_cd = _bounty_interval()
		return
	# No live bounty — count down and try to mark a new one.
	_bounty = null
	_bounty_cd -= delta
	if _bounty_cd <= 0.0:
		_try_mark_bounty()

func _try_mark_bounty() -> void:
	var candidates: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and e.score_value < 1000 and e.state != EnemyBase.State.DEAD \
				and not e.is_bounty and e.hp != null and e.hp.is_alive():
			candidates.append(e)
	if candidates.size() < BOUNTY_MIN_ENEMIES:
		_bounty_cd = 4.0 # not enough of a fight yet — check back soon
		return
	var pick: EnemyBase = candidates[randi() % candidates.size()]
	pick.mark_bounty()
	_bounty = weakref(pick)
	_bounty_age = 0.0
	var label: String = pick._kill_label() if pick.has_method("_kill_label") else "TARGET"
	bounty_marked.emit(label)

## Seconds until the next bounty — shortened by the MOST WANTED directive.
func _bounty_interval() -> float:
	return BOUNTY_INTERVAL * float(directive.get("bounty_interval", 1.0))

## The marked target went down (called from EnemyBase._on_died).
func claim_bounty() -> void:
	var pts := int(round(BOUNTY_BONUS * float(directive.get("bounty_bonus", 1.0))))
	add_score(pts)
	stat_bounties += 1
	_bounty = null
	_bounty_cd = _bounty_interval()
	_bounty_age = 0.0
	AudioBus.play_synth_ui("combo_up", -2.0, 0.9)
	bounty_claimed.emit(pts)

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
	if rampage_tier != 0:
		rampage_tier = 0
		rampage_changed.emit(0, "") # rampage collapses when the streak breaks

func _process(delta: float) -> void:
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			_reset_combo()
	_tick_bounty(delta)
	if adrenaline_left > 0.0:
		adrenaline_left = maxf(0.0, adrenaline_left - delta)
		if adrenaline_left <= 0.0:
			_adrenaline_cd = ADRENALINE_COOLDOWN
			adrenaline_changed.emit(false)
	elif _adrenaline_cd > 0.0:
		_adrenaline_cd = maxf(0.0, _adrenaline_cd - delta)
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

const OVERCLOCK_MULT := 3.0
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
## Highlight counters for the new engagement systems — surfaced on the debrief so
## a run's flashy moments (executions, bounties, dodges, best streak) get credit.
var stat_executions: int = 0
var stat_bounties: int = 0
var stat_dodges: int = 0
var stat_best_rampage: int = 0
## Timestamp the current level attempt started. NOTE: this is reset on every
## load_level() call, including a TRY-AGAIN full reload — so the debrief's TIME
## reads "time since the last retry", not a cumulative clock across deaths.
## That's a deliberate simplification: a true cross-retry clock would need to
## survive reset_level_stats() and be threaded through respawn_at_checkpoint's
## in-place path too, for a number the player mostly reads as "how long did
## THAT run take", which per-attempt already answers.
var level_start_ms: int = 0
## Deaths this level attempt, surviving a TRY-AGAIN/RESPAWN retry so the
## debrief can show how rough the level actually was — see load_level()'s
## _deaths_level_id comparison for how retries are told apart from a genuine
## new level.
var level_deaths: int = 0
## Tracks which level `level_deaths` belongs to. Deliberately NOT compared
## against current_level_path: go_to_level() (campaign advance / start) sets
## current_level_path BEFORE routing through the briefing cutscene, which then
## calls load_level(current_level_path) — so by the time load_level() runs,
## current_level_path already equals the incoming scene_path and a same-path
## check would never fire. This field is only ever written inside load_level()
## itself, so it still reflects the level the counter was last reset for.
var _deaths_level_id: String = ""

func reset_level_stats() -> void:
	stat_shots = 0
	stat_hits = 0
	stat_damage_taken = 0.0
	stat_executions = 0
	stat_bounties = 0
	stat_dodges = 0
	stat_best_rampage = 0
	ultimate_charge = 0.0
	ultimate_changed.emit(0.0)
	max_combo = 0
	_reset_combo()
	level_start_ms = Time.get_ticks_msec()
	AIDirector.reset_profile() # the AI re-reads you fresh each level

func register_shot() -> void:
	stat_shots += 1
	AIDirector.note_shot() # feed the adaptive director (shot count + weapon focus)

func register_hit() -> void:
	stat_hits += 1

func register_damage_taken(amount: float) -> void:
	stat_damage_taken += amount

# ---------- opening-seconds fairness (spawn / respawn attack grace) ----------
var _attack_grace_until_ms: int = 0

## Playtests show players lose most of their HP in the first couple of
## seconds after a level starts (or a convoy respawn drops them back into a
## live pack) — before there's been any chance to orient. Enemies still see,
## chase, and jockey for position during grace; they just hold off on
## starting a new telegraph/attack until it lapses.
func start_attack_grace(seconds: float) -> void:
	_attack_grace_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)

func attack_grace_active() -> bool:
	return Time.get_ticks_msec() < _attack_grace_until_ms

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
		"deaths": level_deaths,
		"executions": stat_executions, "bounties": stat_bounties,
		"dodges": stat_dodges, "best_rampage": stat_best_rampage,
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
	_taught.clear()
	adrenaline_left = 0.0
	_adrenaline_cd = 0.0
	_bounty = null
	_bounty_cd = BOUNTY_INTERVAL
	_bounty_age = 0.0
	directive = {}
	directive_id = ""
	clear_checkpoint()

# ---------- first-encounter teaching ----------
## The game has a lot of systems players otherwise learn by dying — elite affixes,
## hazard seas. The first time one matters, the HUD pops a one-off coaching toast
## (each shown once per run). The HUD listens on `teach_hint`.
signal teach_hint(text: String)
var _taught: Dictionary = {}
const ELITE_HINTS := {
	"shielded": "◆ ELITE · SHIELDED — heavy armour. Flank it or bring a bigger gun.",
	"volatile": "◆ ELITE · VOLATILE — detonates on death. Don't be standing next to it.",
	"swift": "◆ ELITE · SWIFT — fast mover. Lead your shots.",
	"warden": "◆ ELITE · WARDEN — can't be staggered. Dodge it, don't trade.",
	"splitter": "◆ ELITE · SPLITTER — splits into skitters on death. Watch the spawn.",
}

## First-time coaching for the engagement systems — each fires once per run the
## moment the mechanic first triggers, so players actually discover the new verbs.
const MECHANIC_HINTS := {
	"rampage": "🔥 RAMPAGE — kill streaks power you up. Keep the chain alive!",
	"adrenaline": "🩸 ADRENALINE — a near-death surge kicked in. Push the counter-attack!",
	"dodge": "✦ PERFECT DODGE — dashing (Q) through an attack dodges it. Time your dashes!",
	"execution": "☠ EXECUTION — melee (F) finishes off weakened enemies instantly.",
	"overload": "⚡ OVERLOAD charged — press [X] to unleash a screen-clearing shockwave.",
}

## Emit a coaching hint the first time `key` comes up this run (idempotent).
func teach_once(key: String, text: String) -> void:
	if text == "" or _taught.has(key):
		return
	_taught[key] = true
	teach_hint.emit(text)

## Convenience: teach an elite affix the first time the player meets one.
func teach_elite(kind: String) -> void:
	teach_once("elite_" + kind, ELITE_HINTS.get(kind, ""))

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
	controls_taught = false # re-teach controls at the start of a fresh campaign
	level_index = 0
	max_level_reached = 0
	# A brand-new run must not inherit a stray death count from whatever level
	# the PREVIOUS run last died on — load_level()'s retry check alone can't
	# tell "same level, new run" apart from "same level, same run", so clear it
	# explicitly here, the one true "wipe everything" entry point.
	level_deaths = 0
	_deaths_level_id = ""
	go_to_level(campaign()[0], false)

## The opener is now a comic-panel flash instead of the old 3D story cutscene.
const INTRO_CUTSCENE := "res://scenes/cutscene/comic_intro.tscn"
const LEVEL_BRIEFING := "res://scenes/cutscene/level_comic_briefing.tscn"
const UPRISING_REVEAL := "res://scenes/cutscene/uprising_reveal.tscn"
## The finale's post-campaign victory sequence (procedural cutscene ->
## "Global Defense Net" broadcast -> credits), reached only when advance_level()
## runs out of campaign levels. It returns to main_menu.tscn itself once it
## ends or is skipped (see victory_cutscene.gd / credits.gd).
const VICTORY_CUTSCENE := "res://scenes/cutscene/victory_cutscene.tscn"
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
	# Starting the game routes through the loading screen too — the cutscene
	# scripts preload full-page comic art, which otherwise stalls on a frozen menu.
	var lid := level_id_from_path(path)
	if lid == "01":
		_enter_level_scene(INTRO_CUTSCENE)
	elif CUTSCENE_FOR_LEVEL.has(lid):
		_enter_level_scene(CUTSCENE_FOR_LEVEL[lid])
	else:
		_enter_level_scene(LEVEL_BRIEFING)

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
	if t == "" or discovered_enemies.has(t) or not EnemyCodex.has(t):
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

## Which weapons the player has ever actually held. Gates the Weapon Codex the
## same way the bestiary gates the Encyclopedia; persisted alongside it.
## Registered by the WeaponManager when a weapon lands in the rack (covers the
## base loadout, pickups and the warp cheat's full-arsenal grant alike).
var discovered_weapons: Dictionary = {}

func is_weapon_discovered(scene_path: String) -> bool:
	return discovered_weapons.has(scene_path)

func discover_weapon(scene_path: String) -> void:
	if scene_path == "" or discovered_weapons.has(scene_path):
		return
	discovered_weapons[scene_path] = true
	_save_bestiary()

func _load_bestiary() -> void:
	var cf := ConfigFile.new()
	if cf.load(BESTIARY_PATH) != OK:
		return
	for t in cf.get_value("bestiary", "discovered", []):
		discovered_enemies[str(t)] = true
	for w in cf.get_value("bestiary", "weapons", []):
		discovered_weapons[str(w)] = true

func _save_bestiary() -> void:
	var cf := ConfigFile.new()
	cf.set_value("bestiary", "discovered", discovered_enemies.keys())
	cf.set_value("bestiary", "weapons", discovered_weapons.keys())
	cf.save(BESTIARY_PATH)

## Load a specific level. `reset` wipes score/kills (used for replays); campaign
## advancement passes false so the running score carries across levels.
func load_level(scene_path: String, reset: bool = true) -> void:
	clear_checkpoint() # a fresh build of the level — any mid-level checkpoint is stale
	# Only wipe the death counter on a genuine new level, not a TRY-AGAIN retry
	# of the one we're already on (see _deaths_level_id's comment above).
	if scene_path != _deaths_level_id:
		level_deaths = 0
		_deaths_level_id = scene_path
	current_level_path = scene_path
	var found := campaign().find(scene_path)
	if found != -1:
		level_index = found
		max_level_reached = maxi(max_level_reached, found)
	if reset:
		reset_run()
		# Roll this level's COMBAT DIRECTIVE (skip bosses — those fights stay pure).
		# Only on a genuine new level; a TRY-AGAIN retry (reset=false) keeps it.
		if not LevelDefs.level_is_boss(level_id_from_path(scene_path)):
			roll_directive()
		else:
			directive = {}
			directive_id = ""
	reset_level_stats()
	set_state(State.PLAYING)
	if found != -1:
		save_progress() # checkpoint at the start of every campaign level
	# Codex entries are NOT pre-unlocked from the level roster here — hostiles
	# register themselves the first time the player actually meets one (enemy
	# engages or dies, see EnemyBase). The warp cheat still unlocks everything.
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
## `target` (a heavy level scene, or the cutscene/briefing leading into one).
## Keeps the grey-window stall off-screen.
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
		# Campaign finished — clear the checkpoint exactly as before, but hand off
		# to the victory sequence (cutscene + broadcast + credits) instead of
		# dropping straight to the main menu. That sequence returns to
		# main_menu.tscn itself once it ends or is skipped.
		clear_save()
		set_state(State.MENU)
		get_tree().change_scene_to_file(VICTORY_CUTSCENE)

var last_killer: String = "" ## Kill-feed label of whatever downed the player (death recap).

func on_player_died(killer: String = "") -> void:
	last_killer = killer
	level_deaths += 1 # counted once per death regardless of which respawn path follows
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
## `staged` marks a later mission stage: it counts toward the exit lock and is
## listed on the HUD (dimmed glyph), but its objects don't exist yet — the level
## unstages it when its prerequisites complete.
func register_task(id: String, label: String, goal: float = 0.0, staged: bool = false) -> void:
	for t in level_tasks:
		if t["id"] == id:
			return
	level_tasks.append({"id": id, "label": label, "done": false, "progress": 0.0, "goal": goal, "staged": staged})
	tasks_changed.emit()

## A staged task's prerequisites are done — it just went live in the world.
func unstage_task(id: String) -> void:
	for t in level_tasks:
		if t["id"] == id and t.get("staged", false):
			t["staged"] = false
			tasks_changed.emit()
			return

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
			# A finished task is the level's natural beat (kill-all, keycard, core, …)
			# — checkpoint here so a later death resumes at this progress instead of
			# the level's very start.
			set_checkpoint()
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
# Mid-level checkpoint. A LIGHTWEIGHT, IN-MEMORY respawn point — no disk write
# (see save_progress() above for the real per-LEVEL save). Long/boss levels
# used to answer every death with a full level reload; this lets a death
# resume from the last task completed or boss arena entered instead. World
# state is left exactly as the death found it — enemy health/positions,
# dropped loot and completed tasks are NOT reset — only the player comes back.
# That's deliberate: undoing kills on a death would let a boss (or a whole
# arena) be farmed down for free by dying on purpose. Cleared on every fresh
# level load so a stale checkpoint can never leak into the next level.
# ---------------------------------------------------------------------

signal checkpoint_set ## HUD pops a small "CHECKPOINT" toast.

## Opaque blob built by Player.checkpoint_snapshot(); {} means "none yet" — a
## death before the first checkpoint falls back to the old full level reload.
var checkpoint: Dictionary = {}

func has_checkpoint() -> bool:
	return not checkpoint.is_empty()

func clear_checkpoint() -> void:
	checkpoint.clear()

## Snapshot the player's respawn state right now. Called on every task
## completion (a level's natural beats — kill-alls, keycards, core
## destructions, …) and when a boss arena is announced, so mid-level and boss
## fights always get a sane restart point instead of only the level's start.
func set_checkpoint() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("checkpoint_snapshot"):
		return
	checkpoint = player.checkpoint_snapshot()
	checkpoint_set.emit()

## Respawn the CURRENT player instance at the checkpoint in place — no scene
## reload. Falls back to a full level reload if there's no checkpoint or no
## player to respawn (defensive; the HUD only calls this when has_checkpoint()
## is already true).
func respawn_at_checkpoint() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not has_checkpoint() or player == null or not player.has_method("respawn_from_checkpoint"):
		load_level(current_level_path, false)
		return
	set_state(State.PLAYING)
	player.respawn_from_checkpoint(checkpoint)

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
