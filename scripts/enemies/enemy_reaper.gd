class_name EnemyReaper
extends EnemyBase
## Fast, fragile shock trooper. Its model (reaper_droid.glb, built by
## tools/blender/build_reaper.py) is a gaunt, hooded battle droid carrying a
## heavy rifle at its right hip, no blades: it closes at a sprint firing short
## bursts from that rifle without slowing (marching fire), and up close it
## lunges and drives the rifle into you, a strike that shoves you back. It
## RUNS on its legs: the model is built as `Body`, `Rifle`, `LegL` and `LegR`,
## and a `BipedGait` swings each leg about its hip (the top of its bounds), the
## two in opposition, on a sprinter's stride. tests/biped_gait_probe.

@export var slash_damage: float = 20.0  ## the rifle strike at the end of the lunge
@export var shot_damage: float = 4.0    ## per round of the marching-fire burst

const LEGS := ["LegL", "LegR"]
var _gait := BipedGait.new(1.8, 0.55) ## 1.8 m a stride, 0.55 rad each side: a sprint
var _gait_tried := false

const TRACER := preload("res://scenes/fx/tracer_red.tscn")
## 2 cm ahead of the rifle's muzzle brake, in the body's frame. build_reaper.py
## prints the brake's front face: (0.199, 1.002, -0.59).
const RIFLE_TIP := Vector3(0.2, 1.0, -0.61)
const BURST_ROUNDS := 3
const BURST_GAP := 0.09     ## s between rounds
const BURST_EVERY := 1.7    ## s from one burst to the next
const FIRE_MIN := 5.0       ## inside this the lunge takes over
const FIRE_MAX := 24.0
const SPREAD_DEG := 3.5
const STRIKE_SHOVE := 7.0   ## m/s the rifle strike drives the target back

var _burst_left: int = 0
var _burst_t: float = 0.0
var _burst_cd: float = 0.6


func _ready() -> void:
	max_health = 62.0
	move_speed = 8.6
	turn_speed = 9.0
	sight_range = 34.0
	sight_angle_deg = 200.0
	attack_range = 3.0
	preferred_range = 1.5
	attack_cooldown = 1.1
	attack_lunge_speed = 12.0
	score_value = 130
	stagger_threshold = 40.0
	super._ready()
	if muzzle:
		muzzle.position = RIFLE_TIP


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state != State.DEAD:
		_tick_gait(delta)

## Find the leg parts once RobotModel's fit has landed; each hip is the top
## of its leg's bounds on the leg's own centre line.
func _setup_gait() -> void:
	var parts: Array = []
	for n in LEGS:
		var mi := find_child(n, true, false) as MeshInstance3D
		if mi == null:
			return # a model without the cut parts (a stale import) keeps still, quietly
		parts.append(mi)
	if not (parts[0] as MeshInstance3D).is_visible_in_tree():
		return
	_gait_tried = true
	for side in 2:
		var mi: MeshInstance3D = parts[side]
		var box: AABB = rig_frame().affine_inverse() * (mi.global_transform * mi.mesh.get_aabb())
		var c := box.get_center()
		_gait.add_leg([PartRig.entry(self, mi)], Vector3(c.x, box.end.y - 0.02, c.z), side)

func _tick_gait(delta: float) -> void:
	if not _gait_tried:
		_setup_gait()
		return
	_gait.tick(delta, Vector2(velocity.x, velocity.z).length(), move_speed)


## Marching fire: bursts start and run from here, on top of whatever the state
## machine is doing, so it never stops to shoot. EMP, hijack and death skip
## _run_state, and with it the gun.
func _run_state(delta: float) -> void:
	super._run_state(delta)
	_burst_cd = maxf(0.0, _burst_cd - delta)
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_burst_left -= 1
			_burst_t = BURST_GAP
			_fire_round()
		return
	if _burst_cd > 0.0 or target == null or not is_instance_valid(target) \
			or state not in [State.CHASE, State.ATTACK] or GameState.attack_grace_active():
		return
	var dist := global_position.distance_to(target.global_position)
	if dist < FIRE_MIN or dist > FIRE_MAX or not _can_see(target):
		return
	_burst_left = BURST_ROUNDS
	_burst_t = 0.0
	_burst_cd = BURST_EVERY
	_bark_attack()


func _fire_round() -> void:
	if target == null or not is_instance_valid(target) or muzzle == null:
		return
	recoil = 0.6
	_muzzle_flash()
	var origin := muzzle.global_position
	AudioBus.play_synth_at("drone_shot", origin, -5.0, randf_range(0.9, 1.0))
	var dir := scatter_aim((target.global_position + Vector3.UP * 0.9 - origin).normalized(), SPREAD_DEG)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0)
	q.collision_mask = 0b0000011 # world + player
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end_point := origin + dir * 60.0
	if not hit.is_empty():
		end_point = hit.position
		var d: Node = (hit.collider as Node).get_node_or_null("Damageable") if hit.collider else null
		if d:
			d.apply_damage(shot_damage, self)
	var t := TRACER.instantiate()
	get_tree().current_scene.add_child(t)
	if t.has_method("setup"):
		t.setup(origin, end_point)


## The lunge ends in the rifle: a strike that lands and shoves the target back.
func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slash_damage, self)
		if "velocity" in target:
			var away: Vector3 = target.global_position - global_position
			away.y = 0.0
			away = away.normalized() if away.length() > 0.05 else -global_transform.basis.z
			target.velocity += away * STRIKE_SHOVE + Vector3.UP * 2.0
		AudioBus.play_synth_at("impact_metal", global_position, -6.0, 1.2)
	_attack_lunge()
