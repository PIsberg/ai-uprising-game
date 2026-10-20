class_name GrenadeReturner
# @lat: [[enemies#Elite Affixes]]
extends Node3D
## The RETURNER elite's catch (Elite._finalize adds it under the robot). A
## player frag grenade that comes within CATCH_RANGE of the robot, in its line
## of sight and with more than MIN_FUSE left, is snatched out of the air: the
## charge is held, glowing, at chest height for WINDUP seconds, then lobbed
## back at the player on a RETURN_FUSE fuse with a world + player blast
## (RETURN_DAMAGE + RETURN_SPLASH); it sticks where it lands. Any damage to the robot during the wind-up,
## or its death, makes it FUMBLE: the player's own charge drops at its feet on
## FUMBLE_FUSE, with its original blast and the player as its shooter. Never
## while EMP-stunned, hijacked or dead; one charge at a time, COOLDOWN between.
## tests/returner_probe.

const CATCH_RANGE := 6.0
const MIN_FUSE := 0.5
const WINDUP := 0.7
const COOLDOWN := 1.0
const RETURN_FUSE := 1.8 ## about 0.8 s on the ground at 12 m: time to dash clear
const RETURN_DAMAGE := 10.0
const RETURN_SPLASH := 40.0
const RETURN_RADIUS := 4.0
const FUMBLE_FUSE := 0.3
const FUMBLE_BONUS := 100
const HOLD_HEIGHT := 1.4
const GRENADE_SCENE := preload("res://scenes/weapons/grenade.tscn")
const MAGENTA := Color(1.0, 0.25, 0.75)
const TEACH_TEXT := "RETURNER: it catches your frag grenades and throws them back. Shoot it while it winds up and it drops the grenade on its own squad."

var holding := false
var catches := 0
var returns := 0
var fumbles := 0
var _t := 0.0
var _cd := 0.0
var _held: Dictionary = {} ## the caught charge's blast + shooter
var _orb: MeshInstance3D
var _orb_light: OmniLight3D

func _robot() -> EnemyBase:
	return get_parent() as EnemyBase

func _ready() -> void:
	position = Vector3(0, HOLD_HEIGHT, 0)
	var eb := _robot()
	if eb and eb.hp:
		eb.hp.damaged.connect(func(_a: float, _s: Node) -> void: _fumble())
		eb.hp.died.connect(func(_s: Node) -> void: _fumble())

func _can_act(eb: EnemyBase) -> bool:
	return eb != null and eb.state != EnemyBase.State.DEAD and eb.hp != null and eb.hp.is_alive() \
		and eb._emp_t <= 0.0 and not eb.hijacked

func _physics_process(delta: float) -> void:
	var eb := _robot()
	if holding:
		_t += delta
		if _orb:
			var k := clampf(_t / WINDUP, 0.0, 1.0)
			var s := 1.0 + 0.35 * k + 0.15 * sin(_t * 40.0)
			_orb.scale = Vector3.ONE * s
			_orb_light.light_energy = 1.5 + 3.0 * k
		if not _can_act(eb):
			_fumble()
		elif _t >= WINDUP:
			_throw_back(eb)
		return
	_cd = maxf(0.0, _cd - delta)
	if _cd > 0.0 or not _can_act(eb):
		return
	for n in get_tree().get_nodes_in_group("grenade"):
		var g := n as Grenade
		if g == null or not is_instance_valid(g) or g.hostile or g._dead:
			continue
		if g.fuse - g._t <= MIN_FUSE:
			continue
		if g.global_position.distance_to(global_position) > CATCH_RANGE:
			continue
		if not _sees(g):
			continue
		_catch(g)
		return

func _sees(g: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position, g.global_position, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _catch(g: Grenade) -> void:
	_held = {"damage": g.damage, "splash_damage": g.splash_damage, "splash_radius": g.splash_radius,
		"shooter": g._shooter}
	g._dead = true
	g.queue_free()
	holding = true
	_t = 0.0
	catches += 1
	_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	_orb.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = MAGENTA
	_orb.material_override = mat
	_orb.position = Vector3(0, 0, 0.45) # held out in front (+Z faces forward)
	add_child(_orb)
	_orb_light = OmniLight3D.new()
	_orb_light.light_color = MAGENTA
	_orb_light.omni_range = 4.0
	_orb.add_child(_orb_light)
	GameState.teach_once("returner", TEACH_TEXT)
	AudioBus.play_synth_at("pickup_clink", global_position, 0.0, 0.6)
	AudioBus.play_synth_at("charge", global_position, -4.0, 1.4)

func _drop_orb() -> void:
	holding = false
	_cd = COOLDOWN
	if _orb and is_instance_valid(_orb):
		_orb.queue_free()
	_orb = null
	_orb_light = null

func _throw_back(eb: EnemyBase) -> void:
	_drop_orb()
	var p := GameState.nearest_player(eb.global_position)
	var parent := eb.get_parent()
	if p == null or parent == null:
		return
	returns += 1
	var g := GRENADE_SCENE.instantiate() as Grenade
	g.hostile = true
	g.hit_mask = 0b0000011 # world + player: robots are spared their own throw
	g.fuse = RETURN_FUSE
	g.damage = RETURN_DAMAGE
	g.splash_damage = RETURN_SPLASH
	g.splash_radius = RETURN_RADIUS
	parent.add_child(g)
	g.remove_from_group("grenade") # robots do not scramble from their own throw
	var from := global_position + Vector3.UP * 0.3
	g.global_position = from
	var light := g.get_node_or_null("Light") as OmniLight3D
	if light:
		light.light_color = MAGENTA
	g.throw_grenade(lob_velocity(from, p.global_position, g.gravity_scale), eb)
	# It sticks where it lands (a bouncing frag rolled 6 m past its mark), so
	# the dodge is reading the landing spot, not luck.
	g.contact_monitor = true
	g.max_contacts_reported = 1
	g.body_entered.connect(func(_b: Node) -> void:
		g.linear_velocity = Vector3.ZERO
		g.angular_velocity = Vector3.ZERO
		g.set_deferred("freeze", true), CONNECT_ONE_SHOT)
	AudioBus.play_synth_at("grenade_throw", global_position, 0.0, 0.85)

## Launch velocity that lands a lob at `to`: flight time grows with range.
static func lob_velocity(from: Vector3, to: Vector3, gravity_scale: float = 1.0) -> Vector3:
	var gr := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
	var d := to - from
	var flat := Vector2(d.x, d.z).length()
	var t := clampf(flat / 14.0, 0.5, 1.2)
	return Vector3(d.x / t, d.y / t + 0.5 * gr * t, d.z / t)

func _fumble() -> void:
	if not holding:
		return
	var eb := _robot()
	_drop_orb()
	fumbles += 1
	var parent := eb.get_parent() if eb else null
	if parent == null:
		return
	var g := GRENADE_SCENE.instantiate() as Grenade
	g.fuse = FUMBLE_FUSE
	g.damage = float(_held.get("damage", g.damage))
	g.splash_damage = float(_held.get("splash_damage", g.splash_damage))
	g.splash_radius = float(_held.get("splash_radius", g.splash_radius))
	parent.add_child(g)
	g.global_position = eb.global_position + Vector3.UP * 0.4
	var shooter = _held.get("shooter")
	g.throw_grenade(Vector3.ZERO, shooter if is_instance_valid(shooter) else null)
	GameState.add_score(FUMBLE_BONUS)
	GameState.skirmish_event.emit("FUMBLED", tr("It dropped your grenade at its own feet. +%d") % FUMBLE_BONUS)
