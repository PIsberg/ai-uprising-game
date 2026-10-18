# @lat: [[weapons#Damage Matchups]]
class_name DamageMatrix
extends RefCounted
## Which gun for which robot. Every weapon deals one DAMAGE CLASS
## (WeaponData.damage_class) and every robot wears one ARMOUR CLASS (ARMOUR,
## keyed by EnemyBase.codex_key); TABLE scales each player weapon hit by the
## pair. Rule of thumb the player learns from the hit feedback:
##   HEAVY PLATE (brutes, gunners, the big walkers) - shrugs off bullets and
##     pellets; rockets, rail slugs and plasma go through it.
##   LIGHTWEIGHT (drones, hounds, swarmers, flyers) - shotgun pellets and
##     bullets shred it, arcs leap through it; rockets over-penetrate a frame
##     that light and rails punch clean through it.
##   NETWORKED (support drones, the model-concept robots, ARCHON) - arc
##     current fries the electronics, rails crack the emitters; plasma is
##     soaked by the heat sinks.
##   CHASSIS (infantry androids, duelists) - neutral, every gun at face value.
##
## Applied once, in Damageable.apply_damage, from the hit's tagged WeaponData
## (Damageable.hit_weapon via KillFx.tag), so hitscan, beams, projectiles and
## splash all go through it and untagged damage (grenades, melee, hazards,
## mods) never does. Bosses take half the swing (BOSS_DAMP) so no single gun
## trivialises a set piece. Covered by tests/weapon_matchup_probe.

enum Armour { CHASSIS, PLATED, LIGHT, NETWORKED }

const ARMOUR_NAMES := ["CHASSIS", "HEAVY PLATE", "LIGHTWEIGHT", "NETWORKED"]
const ARMOUR_COLORS := [Color(0.8, 0.82, 0.86), Color(1.0, 0.62, 0.3), Color(0.55, 1.0, 0.6), Color(0.45, 0.75, 1.0)]
const CLASS_NAMES := ["KINETIC", "SHRED", "THERMAL", "ARC", "EXPLOSIVE", "RAIL"]

## TABLE[armour][damage_class]; columns follow WeaponData.DamageClass
## (KINETIC, SHRED, THERMAL, ARC, EXPLOSIVE, RAIL).
const TABLE := [
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0],      # CHASSIS
	[0.8, 0.75, 1.35, 0.85, 1.5, 1.4],   # PLATED
	[1.25, 1.5, 1.0, 1.25, 0.85, 0.9],   # LIGHT
	[1.0, 0.9, 0.85, 1.6, 1.0, 1.25],    # NETWORKED
]

## Every enemy type the level builder can spawn (EnemyBase.codex_key).
const ARMOUR := {
	"android": Armour.CHASSIS, "mech": Armour.CHASSIS, "vacuum": Armour.CHASSIS,
	"hunter": Armour.CHASSIS, "sniper": Armour.CHASSIS, "server": Armour.CHASSIS,
	"warbot": Armour.CHASSIS, "gunslinger": Armour.CHASSIS, "ronin": Armour.CHASSIS,
	"orb": Armour.CHASSIS,
	"brute": Armour.PLATED, "gunner": Armour.PLATED, "sentinel": Armour.PLATED,
	"mauler": Armour.PLATED, "ravager": Armour.PLATED, "warmech": Armour.PLATED,
	"enforcer": Armour.PLATED, "ripper": Armour.PLATED, "howitzer": Armour.PLATED,
	"bowler": Armour.PLATED, "terminator": Armour.PLATED, "colossus": Armour.PLATED,
	"manus": Armour.PLATED, "smasher": Armour.PLATED, "titan": Armour.PLATED,
	"drone": Armour.LIGHT, "spider": Armour.LIGHT, "skitter": Armour.LIGHT,
	"reaper": Armour.LIGHT, "seeker": Armour.LIGHT, "raptor": Armour.LIGHT,
	"dog": Armour.LIGHT, "alien": Armour.LIGHT, "fishbot": Armour.LIGHT,
	"roller": Armour.LIGHT, "shark": Armour.LIGHT, "whirlwind": Armour.LIGHT,
	"breaker": Armour.LIGHT,
	"leech": Armour.NETWORKED, "mender": Armour.NETWORKED, "aegis": Armour.NETWORKED,
	"optic": Armour.NETWORKED, "hive": Armour.NETWORKED, "deepfake": Armour.NETWORKED,
	"forkbomb": Armour.NETWORKED, "overfitter": Armour.NETWORKED, "attention": Armour.NETWORKED,
	"moe": Armour.NETWORKED, "reward": Armour.NETWORKED, "diffusion": Armour.NETWORKED,
	"rollback": Armour.NETWORKED, "quantizer": Armour.NETWORKED, "overseer": Armour.NETWORKED,
	"archon": Armour.NETWORKED,
}

## Set pieces: the matchup still counts, at half strength.
const BOSSES := ["terminator", "overseer", "colossus", "manus", "smasher", "titan", "archon"]
const BOSS_DAMP := 0.5

## A multiplier at or past these reads as a counter / a resist in the feedback.
const WEAK_AT := 1.1
const RESIST_AT := 0.95

## The robot's hit flash takes the colour of what hit it (EnemyBase._on_damaged),
## so you can see which gun is landing: columns follow WeaponData.DamageClass.
const CLASS_COLORS := [
	Color(1.0, 1.0, 1.0),     # KINETIC: white
	Color(1.0, 0.8, 0.5),     # SHRED: hot scrap
	Color(1.0, 0.42, 0.1),    # THERMAL: molten
	Color(0.35, 0.7, 1.0),    # ARC: electric
	Color(1.0, 0.65, 0.2),    # EXPLOSIVE: fireball
	Color(0.45, 1.0, 0.95),   # RAIL: ionised
]
## How much poise a hit adds by its matchup: the right gun rocks a robot into a
## stagger sooner, the wrong one barely moves it.
const POISE_WEAK := 1.35
const POISE_RESIST := 0.7

static func poise_mult(matchup: float) -> float:
	if matchup >= WEAK_AT:
		return POISE_WEAK
	if matchup <= RESIST_AT:
		return POISE_RESIST
	return 1.0

static func armour_of(key: String) -> int:
	return int(ARMOUR.get(key, Armour.CHASSIS))

static func has_armour(key: String) -> bool:
	return ARMOUR.has(key)

static func armour_name(key: String) -> String:
	return ARMOUR_NAMES[armour_of(key)]

## The damage multiplier for a `damage_class` hit on enemy type `key`.
static func mult(key: String, damage_class: int) -> float:
	var m: float = TABLE[armour_of(key)][clampi(damage_class, 0, CLASS_NAMES.size() - 1)]
	if key in BOSSES:
		m = 1.0 + (m - 1.0) * BOSS_DAMP
	return m

## The multiplier for the hit `weapon` is landing on `victim` (an enemy node);
## 1.0 for untagged hits and for anything that is not a robot.
static func mult_for(victim: Node, weapon: WeaponData) -> float:
	if weapon == null or victim == null or not victim.has_method("codex_key"):
		return 1.0
	return mult(victim.codex_key(), weapon.damage_class)

## Damage classes that hit `key` harder than face value, best first.
static func counters(key: String) -> Array:
	var out: Array = []
	for c in CLASS_NAMES.size():
		if mult(key, c) >= WEAK_AT:
			out.append(c)
	out.sort_custom(func(a: int, b: int) -> bool: return mult(key, a) > mult(key, b))
	return out

## Armour classes `damage_class` beats / is resisted by (codex + weapon dossier).
static func strong_vs(damage_class: int) -> Array:
	var out: Array = []
	for a in TABLE.size():
		if TABLE[a][damage_class] >= WEAK_AT:
			out.append(a)
	return out

static func weak_vs(damage_class: int) -> Array:
	var out: Array = []
	for a in TABLE.size():
		if TABLE[a][damage_class] <= RESIST_AT:
			out.append(a)
	return out

## One line for the weapon dossier: "STRONG VS LIGHTWEIGHT · WEAK VS HEAVY PLATE".
static func describe_class(damage_class: int) -> String:
	var s := PackedStringArray()
	for a in strong_vs(damage_class):
		s.append(TranslationServer.translate(ARMOUR_NAMES[a]))
	var w := PackedStringArray()
	for a in weak_vs(damage_class):
		w.append(TranslationServer.translate(ARMOUR_NAMES[a]))
	var line := TranslationServer.translate(CLASS_NAMES[damage_class])
	if not s.is_empty():
		line += "  ·  " + TranslationServer.translate("STRONG VS %s") % ", ".join(s)
	if not w.is_empty():
		line += "  ·  " + TranslationServer.translate("WEAK VS %s") % ", ".join(w)
	return line

## The guns in `weapon_paths` (scene paths) that counter `key`, best first:
## the codex's "recommended weapons", computed from the table so it can never
## name a gun that does not exist or one the table resists.
static func recommended(key: String, weapon_paths: Array) -> Array:
	var rows: Array = []
	for p in weapon_paths:
		var d := weapon_data_of(String(p))
		if d and mult(key, d.damage_class) >= WEAK_AT:
			rows.append(d)
	rows.sort_custom(func(a: WeaponData, b: WeaponData) -> bool:
		return mult(key, a.damage_class) > mult(key, b.damage_class))
	return rows

## "ARMOUR: HEAVY PLATE" (translated): the codex and field manual lead with it.
static func armour_line(key: String) -> String:
	return TranslationServer.translate("ARMOUR: %s") % TranslationServer.translate(armour_name(key))

## The damage classes that counter `key`, translated and joined ("EXPLOSIVE, RAIL,
## THERMAL"); "" for CHASSIS, which nothing counters.
static func counters_text(key: String) -> String:
	var names := PackedStringArray()
	for c in counters(key):
		names.append(TranslationServer.translate(CLASS_NAMES[c]))
	return ", ".join(names)

## Codex bullets: the armour line, then every gun in the game that counters
## `key` with its class and multiplier ("GRK-X Devastator  ·  EXPLOSIVE x1.5").
static func codex_lines(key: String) -> Array:
	var out: Array = [armour_line(key)]
	var guns := recommended(key, GameState.WEAPON_ORDER)
	if guns.is_empty():
		out.append(TranslationServer.translate("No armour edge: every gun hits at face value"))
	for d: WeaponData in guns:
		out.append("%s  ·  %s x%s" % [d.display_name, TranslationServer.translate(CLASS_NAMES[d.damage_class]),
			String.num(mult(key, d.damage_class), 2)])
	return out

## The WeaponData a weapon scene is configured with (read from the scene state,
## no instancing).
static func weapon_data_of(scene_path: String) -> WeaponData:
	var ps := load(scene_path) as PackedScene
	if ps == null:
		return null
	var st := ps.get_state()
	for i in st.get_node_property_count(0):
		if st.get_node_property_name(0, i) == &"data":
			return st.get_node_property_value(0, i) as WeaponData
	return null
