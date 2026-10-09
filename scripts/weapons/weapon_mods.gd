class_name WeaponMods
# @lat: [[weapons#Weapon Mods]]
extends RefCounted
## What a fitted weapon mod DOES when its gun lands a hit (GameState.MOD_DEFS for
## the Armory side). Weapon calls on_enemy_hit / on_world_hit from its hitscan and
## beam paths; projectile launchers take no mod.
##
## Every proc's damage goes through GameState.apply_secondary_damage: it pays score,
## leech and OVERLOAD charge like any hit, but is not counted as a fresh hit, so
## accuracy and the AI Director's read stay honest. Procs are rate-limited per gun
## (PROC_INTERVAL_MS) so a shotgun's eight pellets, or a beam's ticks, fire one
## proc instead of eight. The limit thins the effects, not the damage: hits in
## between are banked and the next proc carries them (_bank). THERMITE needs no
## limit: a hit only adds to the burn already on the robot.

const PROC_INTERVAL_MS := 120
const ARC_FRACTION := 0.35
const ARC_RANGE := 7.0
const BURN_FRACTION := 0.3
const BURN_TIME := 3.0
const BURN_TICK := 0.5
const RICOCHET_FRACTION := 0.6
const RICOCHET_RANGE := 15.0
const RICOCHET_CONE_DEG := 35.0
const OVERRIDE_HP_FRACTION := 0.25
const OVERRIDE_SECONDS := 6.0
const OVERRIDE_COOLDOWN_MS := 8000
const BOSS_HP := 500.0 ## same tell as EnemyBase.HIJACK_BOSS_HP

# Robots are duck-typed (the "enemy" group + a hijack method), never named as
# EnemyBase: weapon.gd loads this class, and EnemyBase preloads the pickup scenes,
# whose script loads Weapon again mid-load, so naming it broke pickup.gd ("Busy").

static func _is_robot(n) -> bool:
	return is_instance_valid(n) and n is Node3D and (n as Node).is_in_group("enemy") \
		and (n as Node).has_method("hijack")

static func _hp(n: Node) -> Damageable:
	return n.get_node_or_null("Damageable") as Damageable

## A live, hostile, non-hijacked robot (the arc and ricochet's target filter).
static func _hostile(n) -> bool:
	if not _is_robot(n):
		return false
	var d := _hp(n)
	return d != null and d.is_alive() and not n.get("hijacked")

static func _ready_to_proc(w: Weapon, now: int) -> bool:
	if now - w.mod_last_proc_ms < PROC_INTERVAL_MS:
		return false
	w.mod_last_proc_ms = now
	return true

## Add `dmg` to the gun's bank; when a proc is due, return everything banked
## (and empty it), else 0. Without it a gun firing faster than one round per
## PROC_INTERVAL_MS (rifle, tesla, arc coil, every shotgun pellet after the first)
## arced or bounced about half its share: ARC on the rifle measured +18% against
## +35% on the pistol (tests/mod_value_probe).
static func _bank(w: Weapon, dmg: float, now: int) -> float:
	w.mod_bank += dmg
	if not _ready_to_proc(w, now):
		return 0.0
	var out := w.mod_bank
	w.mod_bank = 0.0
	return out

## `target` is the robot the round hit, `dmg` what that hit dealt.
static func on_enemy_hit(w: Weapon, target: Node, hit_pos: Vector3, dmg: float) -> void:
	if w.mod_id == "" or not _is_robot(target):
		return
	var now := Time.get_ticks_msec()
	match w.mod_id:
		"arc":
			var banked := _bank(w, dmg, now)
			if banked > 0.0:
				_arc(w, target, hit_pos, banked)
		"thermite":
			ignite(target, dmg * BURN_FRACTION, w.get_active_shooter())
		"override":
			_override(w, target, now)

## Only RICOCHET reacts to a round that hit the world.
static func on_world_hit(w: Weapon, hit_pos: Vector3, normal: Vector3, dir: Vector3, dmg: float) -> void:
	if w.mod_id != "ricochet":
		return
	var banked := _bank(w, dmg, Time.get_ticks_msec())
	if banked <= 0.0:
		return
	var bounce := dir.bounce(normal).normalized()
	var best: Node3D = null
	var best_d := INF
	var cos_cone := cos(deg_to_rad(RICOCHET_CONE_DEG))
	for e in w.get_tree().get_nodes_in_group("enemy"):
		if not _hostile(e):
			continue
		var aim := (e as Node3D).global_position + Vector3.UP * 1.0
		var to := aim - hit_pos
		var d := to.length()
		if d > RICOCHET_RANGE or d < 0.3 or to.normalized().dot(bounce) < cos_cone:
			continue
		var q := PhysicsRayQueryParameters3D.create(hit_pos + normal * 0.05, aim)
		q.collision_mask = 1 # world only: anything in the way stops the bounce
		if not w.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	var to_pos := best.global_position + Vector3.UP * 1.0
	w._spawn_tracer(hit_pos, to_pos)
	AudioBus.play_synth_at("impact_metal", hit_pos, -6.0, randf_range(1.3, 1.6))
	GameState.apply_secondary_damage(_hp(best), banked * RICOCHET_FRACTION, w.get_active_shooter())

static func _arc(w: Weapon, target: Node, hit_pos: Vector3, dmg: float) -> void:
	var best: Node3D = null
	var best_d := ARC_RANGE
	for e in w.get_tree().get_nodes_in_group("enemy"):
		if e == target or not _hostile(e):
			continue
		var d := (e as Node3D).global_position.distance_to(hit_pos)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	var to_pos := best.global_position + Vector3.UP * 1.1
	var root := Node3D.new()
	var scene := w.get_tree().current_scene
	if scene:
		scene.add_child(root)
		w._spawn_arc_overlay(root, hit_pos, to_pos, Color(0.45, 0.8, 1.0))
		w.get_tree().create_timer(0.12).timeout.connect(root.queue_free)
	AudioBus.play_synth_at("charge", to_pos, -10.0, randf_range(1.8, 2.2))
	GameState.apply_secondary_damage(_hp(best), dmg * ARC_FRACTION, w.get_active_shooter())

## A hit that leaves a non-boss robot alive below OVERRIDE_HP_FRACTION turns it for
## OVERRIDE_SECONDS (EnemyBase.hijack), at most once per OVERRIDE_COOLDOWN_MS per gun.
static func _override(w: Weapon, e: Node, now: int) -> void:
	if now - w.mod_override_ms < OVERRIDE_COOLDOWN_MS or not _hostile(e):
		return
	var d := _hp(e)
	if d.max_health >= BOSS_HP or d.current_health > d.max_health * OVERRIDE_HP_FRACTION:
		return
	if e.hijack(OVERRIDE_SECONDS, w.get_active_shooter()):
		w.mod_override_ms = now
		GameState.note_hijack()

## Add `total` damage to `target`'s burn. One fire per robot: a fresh hit pours its
## share into the burn already there and restarts the BURN_TIME clock, so the burn
## delivers 30% of every hit (it used to keep only the larger of the old and new
## totals, which left a fast gun burning 2-4% of its damage). Ticks burn through
## armour: flat plating swallowed a rifle hit's 1-point ticks whole.
static func ignite(target: Node, total: float, source: Node) -> void:
	if not is_instance_valid(target) or total <= 0.0:
		return
	var b := target.get_node_or_null("ThermiteBurn") as Burn
	if b == null:
		b = Burn.new()
		b.name = "ThermiteBurn"
		# Burns on the game clock (stops on pause) whatever the robot's own mode is:
		# an EMP'd or frozen chassis keeps burning.
		b.process_mode = Node.PROCESS_MODE_PAUSABLE
		target.add_child(b)
	b.light(total, source)

class Burn extends Node3D:
	## Counted in ticks, not seconds: a float countdown landed a 7th tick on the
	## 3.0 s boundary about half the time, a 17% overburn.
	var pool := 0.0 ## burn damage still to deliver
	var ticks_left := 0
	var tick := 0.0
	var source: Node = null
	var fx: CPUParticles3D

	func light(amount: float, src: Node) -> void:
		pool = (pool if ticks_left > 0 else 0.0) + amount
		ticks_left = int(round(WeaponMods.BURN_TIME / WeaponMods.BURN_TICK))
		source = src
		if fx == null:
			fx = CPUParticles3D.new()
			fx.amount = 14
			fx.lifetime = 0.5
			fx.local_coords = false
			fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			fx.emission_sphere_radius = 0.35
			fx.direction = Vector3.UP
			fx.spread = 25.0
			fx.initial_velocity_min = 1.0
			fx.initial_velocity_max = 2.2
			fx.gravity = Vector3(0, 1.5, 0)
			var sm := SphereMesh.new()
			sm.radius = 0.07
			sm.height = 0.14
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.55, 0.15)
			sm.material = m
			fx.mesh = sm
			fx.position = Vector3.UP * 1.0
			add_child(fx)
		fx.emitting = true

	func _process(delta: float) -> void:
		if ticks_left <= 0:
			return
		tick -= delta
		if tick > 0.0:
			return
		tick += WeaponMods.BURN_TICK
		var dmg := pool / ticks_left
		pool -= dmg
		ticks_left -= 1
		var d: Node = get_parent().get_node_or_null("Damageable")
		if d and d.has_method("is_alive") and d.is_alive():
			var src = source if is_instance_valid(source) else null
			GameState.apply_secondary_damage(d, dmg, src, null, true)
		if ticks_left <= 0 and fx:
			fx.emitting = false
