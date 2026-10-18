# @lat: [[weapons#Cascade]]
class_name Cascade
extends RefCounted
## The CX-4 CASCADE's chain detonation, the early answer to a horde. A cascade
## round PRIMES the robot it hits (a CascadeCharge child that listens to the
## robot's Damageable.died). If the robot dies to anything inside PRIME_TIME, it
## detonates a beat later: every live hostile within the radius is primed one
## generation deeper and takes the blast. A robot that blast kills detonates in
## turn, so one kill in a packed pack pops the pack. Each generation hits DECAY
## times softer, and MAX_GEN caps the depth, so a long line of robots does not
## all go off one shot.
##
## The blast goes through GameState.apply_secondary_damage (score, leech and
## OVERLOAD like any hit, not counted as a fresh hit) and only ever reaches the
## "enemy" group, so it can't hurt the player directly. It also sets off any
## explosive prop in range (a barrel's own blast can hurt the player, as always). Bosses (BOSS_HP) are never primed:
## their deaths are set pieces. When a chain of two or more pops settles,
## GameState.note_cascade reports its length. Covered by tests/cascade_probe.
##
## Robots are duck-typed, never named as EnemyBase, for the same load-order reason
## as WeaponMods: weapon.gd loads this class.

const PRIME_TIME := 2.5 ## seconds a hit keeps the robot primed
const POP_DELAY := 0.12 ## death -> detonation, so a chain reads as pop-pop-pop
const DECAY := 0.8      ## each generation's blast is this much of the last one's
const MAX_GEN := 6
const SETTLE := 0.6     ## seconds after the last pop before the chain is reported
const BOSS_HP := 500.0  ## same tell as EnemyBase.HIJACK_BOSS_HP
const COLOR := Color(0.55, 0.95, 1.0)
const PROP_MULT := 10.0 ## an explosive prop in range always goes off

## One chain reaction: how many robots have popped and when the last one did.
class Chain extends RefCounted:
	var pops := 0
	var serial := 0
	var origin := Vector3.ZERO

static func _hp(n: Node) -> Damageable:
	return n.get_node_or_null("Damageable") as Damageable

static func _hostile(n) -> bool:
	if not is_instance_valid(n) or not (n is Node3D) or not (n as Node).is_in_group("enemy") \
			or not (n as Node).has_method("hijack") or n.get("hijacked"):
		return false
	var d := _hp(n)
	return d != null and d.is_alive()

static func is_primed(robot: Node) -> bool:
	if not is_instance_valid(robot):
		return false
	var c := robot.get_node_or_null("CascadeCharge") as CascadeCharge
	return c != null and c.live()

## Prime `robot` so its death detonates for `damage` over `radius`. A fresh hit
## re-arms the clock and keeps the stronger of the two charges.
static func prime(robot: Node, damage: float, radius: float, source: Node, gen: int = 0, chain: Chain = null) -> void:
	if gen > MAX_GEN or damage <= 0.0 or not _hostile(robot):
		return
	var d := _hp(robot)
	if d.max_health >= BOSS_HP:
		return
	var c := robot.get_node_or_null("CascadeCharge") as CascadeCharge
	if c == null:
		c = CascadeCharge.new()
		c.name = "CascadeCharge"
		robot.add_child(c)
		d.died.connect(c._on_died)
	if not c.live() or damage >= c.damage:
		c.damage = damage
		c.radius = radius
		c.gen = gen
		c.chain = chain if chain != null else Chain.new()
	c.source = source
	c.expires_ms = Time.get_ticks_msec() + int(PRIME_TIME * 1000.0)
	c.mark()

## The blast at `pos`: prime everything in range one generation deeper, then hit it.
static func _detonate(tree: SceneTree, pos: Vector3, damage: float, radius: float, source: Node, gen: int, chain: Chain) -> void:
	chain.pops += 1
	chain.serial += 1
	if chain.pops == 1:
		chain.origin = pos
	_blast_fx(tree, pos, radius, gen)
	var src = source if is_instance_valid(source) else null
	var victims: Array = []
	for e in tree.get_nodes_in_group("enemy"):
		if _hostile(e) and (e as Node3D).global_position.distance_to(pos) <= radius:
			victims.append(e)
	for e in victims:
		prime(e, damage * DECAY, radius, src, gen + 1, chain)
	for e in victims:
		if is_instance_valid(e):
			GameState.apply_secondary_damage(_hp(e), damage, src, pos)
	# Explosive props in range go off too (Destructible.explode: barrels, gas
	# canisters, cars), and their blasts kill and so pop more primed robots.
	# Plain props (crates, fences) are left standing.
	for p in tree.get_nodes_in_group("destructible"):
		if is_instance_valid(p) and p.get("explode") and (p as Node3D).global_position.distance_to(pos) <= radius:
			GameState.apply_secondary_damage(_hp(p), damage * PROP_MULT, src, pos)
	var mine := chain.serial
	tree.create_timer(SETTLE, false).timeout.connect(func() -> void:
			if chain.serial == mine and chain.pops >= 2:
				GameState.note_cascade(chain.pops, chain.origin))

## A cyan shock shell that swells to the blast radius and fades, a flash, and a
## crack pitched up each generation so a long chain climbs.
static func _blast_fx(tree: SceneTree, pos: Vector3, radius: float, gen: int) -> void:
	AudioBus.play_synth_at("explosion", pos, -4.0 - gen, 1.35 + 0.12 * gen)
	var scene := tree.current_scene
	if scene == null:
		return
	var root := Node3D.new()
	scene.add_child(root)
	root.global_position = pos + Vector3.UP * 1.0
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 10
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(COLOR, 0.55)
	sm.material = m
	shell.mesh = sm
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.scale = Vector3.ONE * 0.3
	root.add_child(shell)
	var light := OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 6.0
	light.omni_range = radius * 1.6
	root.add_child(light)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(shell, "scale", Vector3.ONE * radius, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.32)
	tw.tween_property(light, "light_energy", 0.0, 0.3)
	tw.chain().tween_callback(root.queue_free)

## The prime itself: lives on the robot, glows while live, detonates on death.
class CascadeCharge extends Node3D:
	var damage := 0.0
	var radius := 0.0
	var gen := 0
	var source: Node = null
	var chain: Cascade.Chain = null
	var expires_ms := 0
	var _glow: OmniLight3D

	func live() -> bool:
		return Time.get_ticks_msec() < expires_ms

	## A cyan pilot light on the chassis: the player can see which robots are primed.
	func mark() -> void:
		if _glow == null:
			_glow = OmniLight3D.new()
			_glow.light_color = Cascade.COLOR
			_glow.omni_range = 2.2
			_glow.position = Vector3.UP * 1.1
			add_child(_glow)
		_glow.light_energy = 2.2
		_glow.visible = true

	func _process(_delta: float) -> void:
		if _glow and _glow.visible and not live():
			_glow.visible = false

	func _on_died(_src: Node) -> void:
		if not live() or chain == null:
			return
		expires_ms = 0 # one detonation per robot
		if _glow:
			_glow.visible = false
		var tree := get_tree()
		if tree == null:
			return
		var pos := (get_parent() as Node3D).global_position
		var dmg := damage
		var r := radius
		var src := source
		var g := gen
		var ch := chain
		tree.create_timer(Cascade.POP_DELAY, false).timeout.connect(func() -> void:
				Cascade._detonate(tree, pos, dmg, r, src, g, ch))
