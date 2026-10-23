class_name BlastPush
extends RefCounted
## Explosions throw robots. A grenade or splash round the PLAYER set off tosses
## every plain grounded robot in its radius outward and up (the robot's launch(),
## so its own movement pauses until it lands), full strength at the centre and
## EDGE of it at the rim. Bosses are too heavy to move, flyers are already in
## the air, and a robot's own rockets never scatter its squad. A throw that
## ends in a LavaHazard bed is a MELTDOWN (lava_hazard.gd).
##
## The robot is duck-typed (group "enemy", launch(), score_value, hover_height),
## never named: naming EnemyBase from a class the weapons load closes a script
## load cycle that leaves pickup.gd unloadable (the same trap Salvage documents).

const PUSH := 7.5   ## m/s outward at the blast centre
const LIFT := 6.0   ## m/s upward at the blast centre (project gravity is 24: about 0.5 s in the air)
const EDGE := 0.35  ## fraction of both kept at the rim of the splash
const BOSS_SCORE := 1000 ## a robot's score_value from which it is a boss

## Speed of a throw at `falloff` (1 at the centre, 0 at the rim), in m/s.
static func throw_speed(falloff: float) -> float:
	return PUSH * lerpf(EDGE, 1.0, clampf(falloff, 0.0, 1.0))

## Throw `body` away from `centre`. Returns whether it flew.
static func throw(body: Node, centre: Vector3, falloff: float, shooter: Node) -> bool:
	if not (body is Node3D and body.is_in_group("enemy") and body.has_method("launch")):
		return false
	if not (is_instance_valid(shooter) and shooter.is_in_group("player")):
		return false
	if "hover_height" in body or int(body.get("score_value")) >= BOSS_SCORE:
		return false
	var hp := body.get_node_or_null("Damageable")
	if hp == null or not hp.is_alive():
		return false
	var k := lerpf(EDGE, 1.0, clampf(falloff, 0.0, 1.0))
	var dir: Vector3 = (body as Node3D).global_position - centre
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	if dir.length() < 0.05:
		dir = Vector3.FORWARD
	body.call("launch", dir.normalized() * PUSH * k + Vector3.UP * LIFT * k, 1.0)
	return true
