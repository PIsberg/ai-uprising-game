class_name WreckBody
extends RigidBody3D
## The physics half of a robot's death: a box the size of the chassis that
## takes the killing shot as an impulse and tumbles, and drags the dead robot
## (and its wreck fire) along with it. A robot shot at the edge of a catwalk
## goes over it, one killed on a staircase slides down it, a flyer killed in
## the air drops instead of toppling where it hung.
##
## Not a per-bone ragdoll: the skinned rigs sit under skeletons scaled 41-270x,
## and PhysicalBone3D bodies there lose that scale and fly apart (tried on the
## HUNTER and STILT MECH, #259). One rigid box works for all 52
## chassis, rigid models included.
##
## The robot stays where it is in the tree (level code watches it); this body
## is its sibling and writes the robot's transform each physics tick until it
## settles, then hands back for the sink (`settled`).

signal settled

const SETTLE_TIME := 2.2 ## Tumble this long (or until asleep) before the sink.
const MIN_TIME := 1.0    ## Never settle sooner, even if it lands asleep.
const PUSH := 3.4        ## m/s along the shot.
const LIFT := 1.2        ## m/s up, so it clears a lip instead of scraping.
const SPIN := 1.2        ## rad/s of random tumble about the vertical.
const TIP := 3.0         ## rad/s (for a 1 m chassis) tipping it over along the shot.

var follower: Node3D
var _scale := Vector3.ONE
var _top := 1.0
var _t := 0.0
var _carried: Array = [] ## [Node3D, Vector3 offset in this body's frame]

## Hand `robot` to a new wreck body under `parent` and throw it along `dir`
## (flat, away from the shooter). `top` is the chassis height.
static func launch(robot: Node3D, parent: Node, dir: Vector3, top: float) -> WreckBody:
	var wb := WreckBody.new()
	wb.name = "WreckBody"
	wb.follower = robot
	wb._scale = robot.global_transform.basis.get_scale()
	wb._top = clampf(top, 0.4, 6.0)
	wb.collision_layer = 0 # nothing collides with the wreck: it never blocks the player
	wb.collision_mask = 1  # it lands on the world
	wb.mass = 60.0
	wb.continuous_cd = true # a fast flyer must not tunnel through a catwalk
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.12
	wb.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var w := clampf(wb._top * 0.42, 0.45, 2.2)
	box.size = Vector3(w, wb._top, w * 0.8)
	cs.shape = box
	cs.position = Vector3(0, wb._top * 0.5, 0)
	wb.add_child(cs)
	wb.add_to_group("wreck_bodies")
	parent.add_child(wb)
	wb.global_transform = Transform3D(robot.global_transform.basis.orthonormalized(), robot.global_position)
	# Velocities, not an impulse: on its first tick the body's mass is not in
	# the physics server yet, so mass * push flung it 370 m.
	wb.linear_velocity = dir * PUSH + Vector3.UP * LIFT
	# Tip the top over along `dir` (w = up x dir moves the top along dir),
	# faster for a short chassis, plus a little random spin.
	wb.angular_velocity = Vector3.UP.cross(dir) * TIP / sqrt(wb._top) \
		+ Vector3.UP * randf_range(-SPIN, SPIN)
	return wb

## Keep `node` at `local` (this body's frame) as it tumbles, without turning
## it: a ground fire stays upright on the fallen torso.
func carry(node: Node3D, local: Vector3) -> void:
	_carried.append([node, local])

## A point on the chassis' centre line, `frac` of the way up, in world space.
func torso_point(frac: float = 0.5) -> Vector3:
	return global_transform * Vector3(0, _top * frac, 0)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(follower):
		queue_free()
		return
	_t += delta
	follower.global_transform = Transform3D(global_transform.basis.orthonormalized() * Basis.from_scale(_scale), global_position)
	for c in _carried:
		if is_instance_valid(c[0]):
			(c[0] as Node3D).global_position = global_transform * (c[1] as Vector3)
	if global_position.y < -60.0: # fell out of the world
		follower.queue_free()
		queue_free()
		return
	if _t >= SETTLE_TIME or (_t >= MIN_TIME and sleeping):
		set_physics_process(false)
		freeze = true
		settled.emit()
		# The robot sinks and frees itself; this body goes with it.
		follower.tree_exiting.connect(queue_free)
