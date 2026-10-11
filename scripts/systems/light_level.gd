class_name LightLevel
# @lat: [[level-system#Darkness and Shootable Lights]]
extends RefCounted
## How lit a spot is, and whether the player standing there is hidden from
## robots. Indoors the level's own luminaires (group "level_light") are the
## light; shoot them out (ShootableLight) or lose them to a blackout and the
## room goes dark, and a robot that sees by its optics can no longer pick you
## out past DARK_SIGHT_RANGE (EnemyBase._compute_can_see). Firing gives you away
## for EXPOSE_MS (the muzzle flash) and so does a lit flashlight.
##
## Only a level with shootable lamps can be dark: open-sky levels have none
## (the sky lights them), so outdoors nobody is ever hidden.
##
## Dark is RELATIVE: a spot is dark when its light has fallen under DARK_RATIO
## of what it gets with every luminaire working. An absolute threshold would
## hide the player in 26-48% of every interior with all the lights on (the
## arenas grew 1.4x, the light ranges did not; ambient and emissives light those
## stretches on screen). Only light you took away can hide you: one lamp shot
## out darkens 340-1000 m2 on average per interior (measured from the defs).
##
## Lux is a cheap sum over the lights, energy x (1 - d / range)^2 from a point
## 1 m above the feet, no occlusion. It reads the AUTHORED energy and range
## (meta set by LevelBuilder), so an interior is exactly as dark on LOW (omni
## lights) as on ULTRA (area lights at 2.5x the energy).

const DARK_RATIO := 0.35      ## under this share of the full light the spot is dark
const MIN_FULL_LUX := 0.05    ## a spot no luminaire reaches has nothing to lose
const EXPOSE_MS := 1600       ## a shot keeps you visible this long
const CACHE_MS := 150         ## per-node answer reuse (robots ask every LOS refresh)

static var _cache := {}       ## node id -> [stamp_ms, hidden]
static var _capable_ms := -100000
static var _capable := false

## True while the level can be dark at all: it has shootable lamps.
static func dark_capable() -> bool:
	var now := Time.get_ticks_msec()
	if now - _capable_ms > CACHE_MS:
		_capable_ms = now
		var tree := Engine.get_main_loop() as SceneTree
		_capable = tree != null and tree.get_first_node_in_group("shootable_light") != null
	return _capable

## Summed light at `pos` (feet) from the level's live luminaires.
static func lux_at(pos: Vector3) -> float:
	return _sum(pos, false)

## The light `pos` gets with every luminaire working (none shot out, no blackout).
static func full_lux_at(pos: Vector3) -> float:
	return _sum(pos, true)

static func _sum(pos: Vector3, full: bool) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0.0
	var at := pos + Vector3.UP
	var sum := 0.0
	for n in tree.get_nodes_in_group("level_light"):
		var l := n as Light3D
		if l == null:
			continue
		if not full and (not l.is_visible_in_tree() or l.light_energy <= 0.0):
			continue
		var r: float = l.get_meta("lux_range", l.get_param(Light3D.PARAM_RANGE))
		if r <= 0.0:
			continue
		var d := at.distance_to(l.global_position)
		if d >= r:
			continue
		var f := 1.0 - d / r
		sum += float(l.get_meta("lux_energy", l.light_energy)) * f * f
	return sum

## True when `pos` has lost most of its light (see the class note).
static func is_dark(pos: Vector3) -> bool:
	var full := full_lux_at(pos)
	return full > MIN_FULL_LUX and lux_at(pos) < DARK_RATIO * full

## True when `node` (the player) stands in the dark, has not fired in the last
## EXPOSE_MS and has no flashlight on.
static func is_hidden(node: Node3D) -> bool:
	if node == null or not dark_capable():
		return false
	var gs := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameState")
	if gs and Time.get_ticks_msec() - int(gs.get("_last_shot_ms")) < EXPOSE_MS:
		return false
	if node.has_method("flashlight_on") and node.flashlight_on():
		return false
	var now := Time.get_ticks_msec()
	var id := node.get_instance_id()
	var c = _cache.get(id)
	if c != null and now - int(c[0]) < CACHE_MS:
		return c[1]
	var hidden := is_dark(node.global_position)
	_cache[id] = [now, hidden]
	return hidden
