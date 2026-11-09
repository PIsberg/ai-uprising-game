class_name ShootableLight
# @lat: [[level-system#Darkness and Shootable Lights]]
extends StaticBody3D
## An interior ceiling luminaire you can shoot out: dark housing, a glowing
## diffuser panel and the light it feeds. A couple of rounds and it pops in a
## shower of sparks; its light goes out and its god-ray shaft with it, and the
## pool of floor under it goes dark (LightLevel), which is where robots lose you.
##
## Only the player's fire breaks one: robots miss a lot, and a squad shooting
## the room dark around you would be noise, not a tactic.
## The light goes to energy 0 rather than hidden, because a blackout
## (WeatherShift) hides and later re-shows every "level_light".

const HP := 20.0
const SIZE := Vector3(1.2, 0.12, 1.2)
const DEPTH := 0.25 ## metres the collider's underside sits below the fixture's origin
const SETTLE_TRIES := 3 ## lifts tried before a fixture that still has no room is dropped
const ROD_MIN := 0.05 ## a fixture this close under its ceiling is flush: no rod
const ROD_WIDTH := 0.08

var light: Light3D
var _panel: MeshInstance3D
var _panel_mat: StandardMaterial3D
var _broken := false

## Build the fixture on the ceiling at `ceiling_y` straight over `l` (default:
## 0.8 m above it) and add it to `parent`.
static func build(parent: Node, l: Light3D, color: Color, ceiling_y: float = -1.0) -> ShootableLight:
	var sl := ShootableLight.new()
	sl.name = "ShootableLight"
	sl.light = l
	var lp := l.position if not l.is_inside_tree() else l.global_position
	var top := ceiling_y if ceiling_y >= 0.0 else lp.y + 0.8
	sl.position = Vector3(lp.x, top, lp.z)
	var housing := MeshInstance3D.new()
	housing.name = "Housing"
	var hb := BoxMesh.new()
	hb.size = SIZE
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.1, 0.1, 0.12)
	hm.roughness = 0.5
	hb.material = hm
	housing.mesh = hb
	housing.position = Vector3(0, -0.06, 0)
	sl.add_child(housing)
	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var pb := BoxMesh.new()
	pb.size = Vector3(1.0, 0.04, 1.0)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = color
	pm.emission_enabled = true
	pm.emission = color
	pm.emission_energy_multiplier = 2.4
	pb.material = pm
	panel.mesh = pb
	panel.position = Vector3(0, -0.13, 0)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.add_to_group("level_light") # the lit panel goes dark with its light in a blackout
	sl.add_child(panel)
	sl._panel = panel
	sl._panel_mat = pm
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x, 0.3, SIZE.z)
	cs.shape = box
	cs.position = Vector3(0, -0.1, 0)
	sl.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = HP
	sl.add_child(hp)
	parent.add_child(sl)
	return sl

## Give the fixture headroom and something to hang from, once every solid of
## the level is in the physics space (the builder places luminaires first, at
## the stock ceiling height, before any tower, deck or bridge exists).
##
## Anything solid within `clearance` under the fixture's footprint, or round the
## fixture itself, lifts it until it clears by `clearance`: a ramp or deck under
## a lamp otherwise puts a solid box in the player's headroom (#436). When that
## would take it above `ceiling_y` the fixture is freed and "removed" returned;
## the light it fed is untouched. A fixture left hanging under its ceiling (a
## room raised for a tower, or the underside of a bridge) gets a drop rod up to
## it. Returns "kept", "lifted" or "removed".
func settle(clearance: float, ceiling_y: float) -> String:
	var space := get_world_3d().direct_space_state
	var lifted := false
	var clear := false
	for _try in SETTLE_TRIES:
		var top := _solid_under(space, clearance, ceiling_y)
		if is_nan(top):
			clear = true
			break
		var y := top + clearance + DEPTH + 0.02
		if y > ceiling_y:
			break
		global_position.y = y
		lifted = true
	if not clear and is_nan(_solid_under(space, clearance, ceiling_y)):
		clear = true
	if not clear:
		queue_free()
		return "removed"
	_hang(space, ceiling_y)
	return "lifted" if lifted else "kept"

## Every fixture in the level, this one included: a luminaire is never a solid
## for another one to be lifted over.
func _fixtures() -> Array[RID]:
	var out: Array[RID] = [get_rid()]
	for n in get_tree().get_nodes_in_group("shootable_light"):
		if n != self and n is CollisionObject3D:
			out.append((n as CollisionObject3D).get_rid())
	return out

## Height of the tallest solid that takes the fixture's room: one the fixture
## stands inside, else one within `clearance` under its footprint. NAN when it
## hangs clear.
func _solid_under(space: PhysicsDirectSpaceState3D, clearance: float, ceiling_y: float) -> float:
	var at := global_position
	# Round the fixture itself, below the ceiling plane it is mounted on.
	var body := BoxShape3D.new()
	body.size = Vector3(SIZE.x - 0.04, DEPTH - 0.05, SIZE.z - 0.04)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = body
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3.DOWN * (DEPTH * 0.5 + 0.01))
	q.collision_mask = 1
	q.exclude = _fixtures()
	var buried := not space.intersect_shape(q, 1).is_empty()
	# Buried: look for the top of what buries it from just under the ceiling.
	# Clear of that: look down from the fixture's own underside.
	var from_y := ceiling_y - 0.01 if buried else at.y - DEPTH - 0.01
	var to_y := at.y - DEPTH - clearance
	var top := NAN
	for ix in [-0.5, 0.0, 0.5]:
		for iz in [-0.5, 0.0, 0.5]:
			var x: float = at.x + ix * SIZE.x
			var z: float = at.z + iz * SIZE.z
			var rq := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, to_y, z), 1)
			rq.exclude = _fixtures()
			var hit := space.intersect_ray(rq)
			if not hit.is_empty() and (is_nan(top) or hit.position.y > top):
				top = hit.position.y
	if buried and is_nan(top):
		return ceiling_y # inside something the rays miss: no height will clear it
	return top

## A rod from the fixture up to whatever is over it, when that is not flush.
func _hang(space: PhysicsDirectSpaceState3D, ceiling_y: float) -> void:
	var at := global_position
	var rq := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.06, Vector3(at.x, ceiling_y + 0.1, at.z), 1)
	rq.exclude = _fixtures()
	var hit := space.intersect_ray(rq)
	var gap: float = (hit.position.y if not hit.is_empty() else ceiling_y) - at.y
	if gap <= ROD_MIN:
		return
	var rod := MeshInstance3D.new()
	rod.name = "Rod"
	var rb := BoxMesh.new()
	rb.size = Vector3(ROD_WIDTH, gap, ROD_WIDTH)
	var rm := StandardMaterial3D.new()
	# Lighter than the housing: against a dark ceiling a housing-black rod is
	# invisible and the fixture reads as floating again.
	rm.albedo_color = Color(0.3, 0.31, 0.34)
	rm.metallic = 0.5
	rm.roughness = 0.45
	rb.material = rm
	rod.mesh = rb
	rod.position = Vector3(0, gap * 0.5, 0)
	add_child(rod)

func _ready() -> void:
	collision_layer = 1 # world: hitscan and splash find it like any prop
	collision_mask = 0
	add_to_group("shootable_light")
	var hp := get_node_or_null("Damageable") as Damageable
	if hp:
		hp.died.connect(_on_broken)

## Only the player's rounds and blasts break it (see the class note).
func modify_incoming_damage(amount: float, source, _origin = null) -> float:
	if source is Node and (source as Node).is_in_group("player"):
		return amount
	return 0.0

func _on_broken(_source: Node) -> void:
	if _broken:
		return
	_broken = true
	GameState.teach_once("lights_out", GameState.MECHANIC_HINTS["lights_out"])
	var at := global_position + Vector3.DOWN * 0.15
	Destructible.burst_debris(get_parent(), at, Color(1.0, 0.85, 0.5), 8, 3.0)
	AudioBus.play_synth_at("impact_metal", at, 2.0, 1.6)
	AudioBus.play_synth_at("drone_shot", at, -2.0, 0.55)
	# The god-ray under it goes now (freed, so a blackout lifting cannot bring it back).
	for s in get_tree().get_nodes_in_group("light_shaft_meshes"):
		var mi := s as Node3D
		if mi and Vector2(mi.global_position.x - global_position.x, mi.global_position.z - global_position.z).length() < 0.6:
			mi.queue_free()
	_panel_mat.emission_enabled = false
	_panel_mat.albedo_color = Color(0.08, 0.08, 0.09)
	if not is_instance_valid(light):
		return
	# LightLevel measures darkness against the light it gave when working.
	if not light.has_meta("lux_energy"):
		light.set_meta("lux_energy", light.light_energy)
	# A faulty-wiring flicker (LevelBuilder._flicker_light) would relight it.
	if light.has_meta("flicker_tween"): # get_meta(key, null) still logs a missing key
		var flicker = light.get_meta("flicker_tween")
		if flicker is Tween and (flicker as Tween).is_valid():
			(flicker as Tween).kill()
	# Sputter, then out.
	var e0 := light.light_energy
	var tw := create_tween()
	tw.tween_property(light, "light_energy", e0 * 1.6, 0.04)
	tw.tween_property(light, "light_energy", e0 * 0.2, 0.06)
	tw.tween_property(light, "light_energy", e0 * 0.9, 0.05)
	tw.tween_property(light, "light_energy", 0.0, 0.08)
