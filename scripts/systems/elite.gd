class_name Elite
extends Object
## Elite enemy affixes: a small random share of spawns come up-tiered with a
## visible identity, double score, and one twist each —
##   SHIELDED — heavier plating: more health + flat armor, icy-blue tint
##   VOLATILE — detonates on death (hurts anything near, including its pack)
##   SWIFT    — faster mover/attacker, teal tint
##   WARDEN   — unstaggerable: heavy fire can't flinch-lock it, so you have to
##              DODGE its attacks instead of suppressing it. Violet-iron tint.
## Call `maybe_apply` on a freshly instantiated enemy BEFORE add_child: export
## tweaks land before _ready wiring, visuals/death-hooks attach on ready.

const KINDS := ["shielded", "volatile", "swift", "warden"]
const TINTS := {
	"shielded": Color(0.55, 0.75, 1.45),
	"volatile": Color(1.5, 0.65, 0.35),
	"swift": Color(0.5, 1.4, 1.05),
	"warden": Color(0.85, 0.6, 1.35),
}
const LIGHTS := {
	"shielded": Color(0.4, 0.65, 1.0),
	"volatile": Color(1.0, 0.5, 0.15),
	"swift": Color(0.3, 1.0, 0.8),
	"warden": Color(0.7, 0.4, 1.0),
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
	apply(enemy, KINDS.pick_random())

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
			eb.move_speed *= 1.35
			eb.attack_cooldown *= 0.85
		"warden":
			# Unstaggerable: poise can never be broken, so suppression won't
			# interrupt it — it walks through your fire and attacks on schedule.
			eb._health_mult *= 1.4
			eb.stagger_threshold = 1.0e9
			eb.move_speed *= 0.92 # relentless, not fast
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
