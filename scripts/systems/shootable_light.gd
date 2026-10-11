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
