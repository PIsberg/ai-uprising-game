# @lat: [[enemies#Elite Affixes]]
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
## Persistent on-body marker colours (a floating spinning gem, separate from the
## LIGHTS glow above and the TINTS material recolor). Kept distinct from both so
## a marker reads at combat range even when the tint/light are hard to make out
## against a busy level — this is the identity cue the first-encounter toast
## ("ELITE · SHIELDED — ...") promises the player they can then rely on. warden/
## splitter reuse their existing LIGHTS tone so every affix still gets a marker.
const AFFIX_COLORS := {
	"shielded": Color(0.35, 0.75, 1.0),  # cold shield blue
	"volatile": Color(1.0, 0.45, 0.12),  # detonation orange
	"swift": Color(0.55, 1.0, 0.35),     # stim green
	"warden": Color(0.7, 0.4, 1.0),
	"splitter": Color(0.4, 1.0, 0.3),
}

## Per-difficulty elite share (EASY, NORMAL, HARD).
const CHANCE := [0.05, 0.1, 0.16]

static func roll_chance() -> float:
	return CHANCE[clampi(GameState.difficulty, 0, CHANCE.size() - 1)] \
		* GameState.campaign_elite_mult()

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
	# Referenced as the autoload global (like GameState/AudioBus elsewhere here),
	# NOT via get_node: maybe_apply runs BEFORE the enemy enters the tree, where an
	# absolute node path would error.
	var c: String = AIDirector.counter_affix()
	if c != "" and c in KINDS and randf() < 0.7:
		kind = c
	apply(enemy, kind)

# ---------- nemesis (the promoted elite that came back for you) ----------
## Dress a spawn as the player's NEMESIS: its recorded affix twist plus
## rank-scaled stat gains, its name in the kill feed, and a burning red-gold
## identity so it reads as PERSONAL the moment it warps in. Pre-add, like apply.
# @lat: [[enemies#Nemesis System]]
static func apply_nemesis(enemy: Node3D, data: Dictionary) -> void:
	var eb := enemy as EnemyBase
	if eb == null or eb.is_inside_tree():
		return
	var kind := String(data.get("kind", "warden"))
	if kind not in KINDS:
		kind = "warden"
	apply(enemy, kind) # base affix twist + elite visuals/death hooks
	var rank := maxi(1, int(data.get("rank", 1)))
	eb.nemesis_name = String(data.get("name", "NEMESIS"))
	eb.score_value *= 2 # on top of the elite double — a grudge pays well
	eb._health_mult *= 1.0 + 0.45 * float(rank)
	eb._speed_mult *= 1.0 + 0.05 * float(rank)
	eb._cooldown_mult *= maxf(0.6, 1.0 - 0.07 * float(rank))
	eb.drop_chance = 1.0 # settling a grudge always pays out supplies
	eb.ready.connect(func(): _finalize_nemesis(eb))

## Post-_ready nemesis dressing: announce the return, wire the grudge
## settlement, and stack a furnace-red glow over the affix identity.
static func _finalize_nemesis(eb: EnemyBase) -> void:
	if eb.hp:
		eb.hp.died.connect(func(_src: Node): GameState.nemesis_slain())
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.25, 0.1)
	light.light_energy = 3.2
	light.omni_range = 7.0
	light.shadow_enabled = false
	light.position = Vector3(0, 1.4, 0)
	eb.add_child(light)
	var model := eb.get_node_or_null("Model") as Node3D
	if model:
		model.scale *= 1.1 # on top of the elite bump — visibly the biggest of its pack
	GameState.announce_nemesis()
	AudioBus.play_synth_at("overlord_glitch", eb.global_position, 2.0, 0.7)

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
	# Slightly larger silhouette (visual only — model node, not the collider) —
	# the marker below is the readable identity cue; this just makes the
	# silhouette itself whisper "bigger threat" before the toast explains it.
	var model := eb.get_node_or_null("Model") as Node3D
	if model:
		model.scale *= 1.12
	_add_marker(eb, kind)

## Persistent on-body marker so an elite reads at combat range, not just from
## the one-off coaching toast: a small spinning emissive gem floating above the
## chassis, colour-coded per affix. NOT a material tint — damage_blink() owns
## emission_energy_multiplier and the hit-flash owns material_overlay on the
## model's own meshes, so a marker baked into those channels would get clobbered
## every time the enemy takes a hit. A separate mesh sidesteps that entirely.
static func _add_marker(eb: EnemyBase, kind: String) -> void:
	# elite.apply runs pre-add (no tree yet), and a RobotModel with fit_height
	# resizes its mesh across a few DEFERRED frames after its own _ready — so wait
	# a beat before measuring the silhouette, or the AABB scan below reads the
	# model's pre-fit (often wildly wrong) scale.
	for i in 4:
		if not is_instance_valid(eb):
			return
		await eb.get_tree().process_frame
	if not is_instance_valid(eb) or eb.state == EnemyBase.State.DEAD:
		return
	var top := 0.0
	for mi in _collect_meshes(eb):
		if mi.mesh:
			var ab: AABB = mi.global_transform * mi.mesh.get_aabb()
			top = maxf(top, ab.end.y - eb.global_position.y)
	if top <= 0.0:
		top = 2.15 # conservative fallback if the scan finds nothing to measure
	var col: Color = AFFIX_COLORS.get(kind, Color.WHITE)
	var pivot := Node3D.new()
	pivot.name = "EliteMarker"
	pivot.position = Vector3(0, top + 0.45, 0)
	eb.add_child(pivot)
	var gem := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.22, 0.28, 0.22)
	gem.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # reads the same colour from every angle
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.92)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.0
	gem.material_override = mat
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(gem)
	# Slow identity spin (~1.5 rad/s): a full TAU turn every TAU/1.5 seconds.
	# `as_relative()` keeps looping without snapping back to 0 each cycle.
	var tw := pivot.create_tween().set_loops()
	tw.tween_property(pivot, "rotation:y", TAU, TAU / 1.5).as_relative()
	# Dies with the enemy: the marker still rides the wreck down (that's fine —
	# a fading light sinking with the topple reads as "powering off"), but the
	# spin stops and it fades out instead of looking like a still-live implant.
	if eb.hp:
		eb.hp.died.connect(func(_src): _fade_marker(pivot, tw))

static func _fade_marker(pivot: Node3D, tw: Tween) -> void:
	if tw and tw.is_valid():
		tw.kill()
	if not is_instance_valid(pivot) or pivot.get_child_count() == 0:
		return
	var gem := pivot.get_child(0) as MeshInstance3D
	var mat := gem.material_override as StandardMaterial3D if gem else null
	if mat == null:
		return
	var ftw := pivot.create_tween()
	ftw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	ftw.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.5)

static func _collect_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_collect_meshes(c))
	return out

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
