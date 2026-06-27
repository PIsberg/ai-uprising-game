class_name Elite
extends Object
## Elite enemy affixes: a small random share of spawns come up-tiered with a
## visible identity, double score, and one twist each —
##   SHIELDED — heavier plating: more health + flat armor, icy-blue tint
##   VOLATILE — detonates on death (hurts anything near, including its pack)
##   SWIFT    — faster mover/attacker, teal tint
##   WARDEN   — unstaggerable: heavy fire can't flinch-lock it, so you have to
##              DODGE its attacks instead of suppressing it. Violet-iron tint.
##   SPLITTER — forks into two skitters on death, so you can't just nuke a
##              cluster without watching the spawn. Acid-green tint.
## Call `maybe_apply` on a freshly instantiated enemy BEFORE add_child: export
## tweaks land before _ready wiring, visuals/death-hooks attach on ready.

const SKITTER := preload("res://scenes/enemies/skitter.tscn")

const KINDS := ["shielded", "volatile", "swift", "warden", "splitter"]
const TINTS := {
	"shielded": Color(0.55, 0.75, 1.45),
	"volatile": Color(1.5, 0.65, 0.35),
	"swift": Color(0.5, 1.4, 1.05),
	"warden": Color(0.85, 0.6, 1.35),
	"splitter": Color(0.55, 1.35, 0.45),
}
const LIGHTS := {
	"shielded": Color(0.4, 0.65, 1.0),
	"volatile": Color(1.0, 0.5, 0.15),
	"swift": Color(0.3, 1.0, 0.8),
	"warden": Color(0.7, 0.4, 1.0),
	"splitter": Color(0.4, 1.0, 0.3),
}

## Per-difficulty elite share (EASY, NORMAL, HARD).
const CHANCE := [0.05, 0.1, 0.16]

static func roll_chance() -> float:
	return CHANCE[clampi(GameState.difficulty, 0, CHANCE.size() - 1)]

static func maybe_apply(enemy: Node3D, chance: float = -1.0) -> void:
	var eb := enemy as EnemyBase
	if eb == null or eb.score_value >= 500:
		return # bosses stay as authored — they have their own identity
	if chance < 0.0:
		chance = roll_chance()
	if randf() > chance:
		return
	# Adaptive AI Director: most elites come up as the affix that COUNTERS the
	# player's current style (snipe -> swift rushers, out-aim it -> wardens you
	# can't stagger, spam one gun -> shielded armour). Falls back to a random
	# affix while the director is still calibrating or for variety.
	var kind: String = KINDS.pick_random()
	var ad := enemy.get_node_or_null("/root/AIDirector")
	if ad and ad.has_method("counter_affix"):
		var c: String = ad.counter_affix()
		if c != "" and c in KINDS and randf() < 0.7:
			kind = c
	apply(enemy, kind)

static func apply(enemy: Node3D, kind: String) -> void:
	var eb := enemy as EnemyBase
	if eb == null or eb.is_inside_tree():
		return # must be applied pre-add so _ready reads the boosted exports
	eb.elite = kind
	eb.score_value *= 2
	# Health boosts stack a multiplier (applied after the subclass sets its base),
	# NOT max_health directly — a subclass's `max_health = N` in _ready would
	# otherwise wipe the boost.
	match kind:
		"shielded":
			eb._health_mult *= 1.7
		"volatile":
			eb._health_mult *= 1.15
		"swift":
			eb._speed_mult *= 1.35
			eb._cooldown_mult *= 0.85
		"warden":
			# Unstaggerable: poise can never be broken, so suppression won't
			# interrupt it — it walks through your fire and attacks on schedule.
			eb._health_mult *= 1.4
			eb.stagger_threshold = 1.0e9
			eb._speed_mult *= 0.92 # relentless, not fast
		"splitter":
			eb._health_mult *= 1.2 # the death-fork is the twist (see _finalize)
	# Recolor the imported model: tint is read by RobotModel._ready, so setting
	# the export now (pre-add) is enough.
	var model := eb.get_node_or_null("Model")
	if model and "tint" in model:
		model.tint = TINTS.get(kind, Color.WHITE)
	eb.ready.connect(func(): _finalize(eb, kind))

## Runs after the enemy's own _ready: live nodes (Damageable etc.) exist now.
static func _finalize(eb: EnemyBase, kind: String) -> void:
	if kind == "shielded" and eb.hp:
		eb.hp.armor += 4.0
	if kind == "volatile" and eb.hp:
		eb.hp.died.connect(func(_src: Node): _detonate(eb))
	if kind == "splitter" and eb.hp:
		eb.hp.died.connect(func(_src: Node): _split(eb))
	# Identity glow so an elite reads at a distance.
	var light := OmniLight3D.new()
	light.light_color = LIGHTS.get(kind, Color.WHITE)
	light.light_energy = 2.2
	light.omni_range = 5.0
	light.shadow_enabled = false
	light.position = Vector3(0, 1.2, 0)
	eb.add_child(light)
	# Slightly larger silhouette (visual only — model node, not the collider).
	var model := eb.get_node_or_null("Model") as Node3D
	if model:
		model.scale *= 1.12

## Splitter death: the wreck forks into two skitters that scuttle out of the
## debris — so wiping a clustered pack can briefly make MORE targets, not fewer.
## Spawned directly (small, weak adds); deferred add so it's safe during `died`.
static func _split(eb: EnemyBase) -> void:
	var parent := eb.get_parent()
	if parent == null or not parent.is_inside_tree():
		return
	var pos := eb.global_position
	for i in 2:
		var sk := SKITTER.instantiate() as Node3D
		sk.position = pos + Vector3(cos(i * PI), 0.0, sin(i * PI)) * 1.1 + Vector3(0, 0.3, 0)
		parent.add_child.call_deferred(sk)
	AudioBus.play_synth_at("explosion", pos, -6.0, 1.6) # a small wet pop

## Volatile death: a real AoE at the wreck, on top of the standard death FX.
## Friendly to no one — it damages player AND nearby robots, so baiting a
## volatile into its own pack is a legitimate play.
static func _detonate(eb: EnemyBase) -> void:
	var pos := eb.global_position
	var parent := eb.get_parent()
	if parent == null:
		return
	AudioBus.play_synth_at("explosion", pos, 3.0, randf_range(0.65, 0.8))
	var space := eb.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 4.5
	q.shape = s
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = 0b0000111 # world + player + enemy
	var seen := {}
	for h in space.intersect_shape(q, 24):
		var col: Node = h.get("collider")
		if col == null or col == eb:
			continue
		var d = col.get_node_or_null("Damageable")
		if d == null or seen.has(d):
			continue
		seen[d] = true
		var falloff := clampf(1.0 - (col as Node3D).global_position.distance_to(pos) / 4.5, 0.0, 1.0)
		d.apply_damage(40.0 * falloff, eb)
	var p := eb.get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		var pd := (p as Node3D).global_position.distance_to(pos)
		if pd < 14.0:
			p.shake(clampf(1.0 - pd / 14.0, 0.0, 1.0))
