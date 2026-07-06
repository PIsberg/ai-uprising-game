class_name EnemyOrb
extends EnemyDog
## MOLTEN ORB — a spherical crusher wheel: black armour treads wrapped around a
## blazing magma core (assets/models/robots/robot_ball.glb). It ROLLS — building
## to a fast charge, bouncing off cover, and slamming into you with its whole
## mass. STRIKER-9 pitcher units also bowl them down ramps as living ordnance:
## see EnemyBowler.launch — an orb arrives airborne at throw speed, crushes what
## it lands on, then gets up and hunts like any other orb.
## The magma core ruptures on death — stand clear of the wreck.

@export var crush_damage: float = 35.0   ## Impact damage while flying/bowled.
@export var core_burst_damage: float = 18.0
@export var core_burst_radius: float = 3.2

const ROLL_RADIUS := 0.9

var _thrown_air: bool = false  ## True while sailing after a bowler's throw.
var _thrown_t: float = 0.0
var _mesh: Node3D
var _spin: float = 0.0

func _ready() -> void:
	super._ready()
	max_health = 150.0
	bite_damage = 26.0
	move_speed = 10.5       # a rolling mass outruns you on the flat
	turn_speed = 6.0        # ...but corners in wide arcs — juke it
	attack_range = 3.0
	preferred_range = 1.2
	score_value = 200
	stagger_threshold = 60.0
	# The "pounce" inherited from the hound reads as a short BOUNCE here — the
	# orb compresses, then hops at you. Tuned flatter than the dog's spring.
	pounce_damage = 32.0
	pounce_windup = 0.45
	pounce_cooldown = 4.5
	pounce_min = 5.0
	pounce_max = 12.0
	pounce_h_speed = 15.0
	pounce_up = 4.0
	hp.max_health = max_health
	hp.current_health = max_health
	_mesh = get_node_or_null("Model/Mesh")

## Bowled by a STRIKER-9 (or scripted ramp trap): arrive as living ordnance.
func launch_throw(vel: Vector3) -> void:
	_thrown_air = true
	_thrown_t = 0.0
	velocity = vel
	set_state(State.CHASE)

func _physics_process(delta: float) -> void:
	if _thrown_air:
		_thrown_t += delta
		_apply_gravity(delta)
		move_and_slide()
		# Enemies don't hard-collide with the player (soft separation), so a
		# bowled orb crushes by proximity: sail close enough and it connects.
		var p := get_tree().get_first_node_in_group("player")
		if p is Node3D and (p as Node3D).global_position.distance_to(global_position) <= 1.8:
			var d = p.get_node_or_null("Damageable")
			if d:
				d.apply_damage(crush_damage, self)
			if "velocity" in p:
				var away: Vector3 = (p as Node3D).global_position - global_position
				away.y = 0.0
				p.velocity += away.normalized() * 10.0 + Vector3.UP * 4.0
			if p.has_method("shake"):
				p.shake(0.8)
			AudioBus.play_synth_at("impact_metal", global_position, -2.0, 0.7)
			_thrown_air = false
		# Touched down and bled off speed — resume hunting under its own power.
		if (is_on_floor() and _thrown_t > 0.3 \
				and Vector2(velocity.x, velocity.z).length() < 7.0) or _thrown_t > 4.0:
			_thrown_air = false
		_update_roll(delta)
		return
	super._physics_process(delta)
	_update_roll(delta)

## Spin the treaded sphere to match ground speed so it reads as ROLLING, not
## gliding. The body already yaws to face travel; the axle is the mesh's local X.
func _update_roll(delta: float) -> void:
	if _mesh == null or state == State.DEAD:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if _thrown_air:
		speed = maxf(speed, velocity.length())
	_spin += (speed / ROLL_RADIUS) * delta
	_mesh.rotation.x = -_spin

## The magma core ruptures — a hot little burst that punishes point-blank kills
## (and makes a bowled orb feel like ordnance to the end).
func _on_died(src: Node) -> void:
	var fx := EXPLOSION.instantiate()
	get_tree().current_scene.add_child(fx)
	(fx as Node3D).global_position = global_position + Vector3.UP * 0.6
	AudioBus.play_synth_at("explosion", global_position, -3.0, 1.2)
	var p := get_tree().get_first_node_in_group("player")
	if p is Node3D and (p as Node3D).global_position.distance_to(global_position) <= core_burst_radius:
		var d = p.get_node_or_null("Damageable")
		if d:
			d.apply_damage(core_burst_damage, self)
	super._on_died(src)
