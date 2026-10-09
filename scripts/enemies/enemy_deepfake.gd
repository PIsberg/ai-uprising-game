class_name EnemyDeepfake
extends EnemyAndroid
## DEEPFAKE - generative-adversarial infiltrator. A burst rifleman (the android's
## kit) that, once it is in a fight, projects two copies of itself to either
## side (DeepfakeDecoy). The copies mirror its moves and fire with it, so three
## guns light up and only one hurts. About half the time it also swaps places
## with one of its projections as they appear: the shell game.
##
## Reading it: the copies glitch (a sideways tear and a magenta flash about once
## a second), cast no shadow, and do not show on radar; one hit pops a copy.
## When the real one dies, its projections die with it.
## Covered by tests/deepfake_probe.

const DECOY_COUNT := 2
const PROJECT_COOLDOWN := 9.0 ## seconds after its last copy is gone
const DECOY_LIFE := 14.0
const SPREAD := 3.6 ## metres either side of it the copies appear
const SWAP_CHANCE := 0.5

var decoys: Array[DeepfakeDecoy] = []
var _project_cd := 1.2

func _ready() -> void:
	super._ready()
	max_health = 150.0
	move_speed = 5.4
	sight_range = 34.0
	attack_range = 26.0
	preferred_range = 13.0
	attack_cooldown = 1.8
	hitscan_damage = 8.0
	score_value = 260
	hp.max_health = max_health
	hp.current_health = max_health
	# Override-proof: subclasses' _on_died can skip super; the signal can't.
	hp.died.connect(func(_s: Node) -> void: collapse_decoys())

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if hp == null or not hp.is_alive() or state == State.DEAD:
		return
	_prune()
	if (state == State.ATTACK or state == State.CHASE) and is_instance_valid(target) \
			and decoys.is_empty() and _emp_t <= 0.0 and not hijacked:
		_project_cd -= delta
		if _project_cd <= 0.0:
			project()

func _prune() -> void:
	var live: Array[DeepfakeDecoy] = []
	for d in decoys:
		if is_instance_valid(d) and not d.is_queued_for_deletion():
			live.append(d)
	decoys = live

## Projects the copies. Returns how many landed (a spot is skipped when a wall
## stands between it and the robot or there is no floor under it).
func project() -> int:
	_project_cd = PROJECT_COOLDOWN
	var parent := get_parent()
	if parent == null:
		return 0
	var side := Vector3.RIGHT
	if is_instance_valid(target):
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length() > 0.1:
			side = to.normalized().cross(Vector3.UP)
	var spots: Array[Vector3] = []
	for s in [-1.0, 1.0]:
		var spot := _clear_spot(global_position + side * SPREAD * s)
		if spot != Vector3.INF:
			spots.append(spot)
	if spots.is_empty():
		return 0
	var here := global_position
	if randf() < SWAP_CHANCE:
		var pick := randi() % spots.size()
		global_position = spots[pick]
		spots[pick] = here
		_glitch_flash(here)
	var vis := _visual_root
	for spot in spots:
		var d := DeepfakeDecoy.new()
		d.setup(self, vis, muzzle.position if muzzle else Vector3(0, 1.4, -0.8),
				tracer_scene, muzzle_flash_scene)
		d.life = DECOY_LIFE
		parent.add_child(d)
		d.global_position = spot
		d.rotation.y = rotation.y
		d.set_target(target)
		decoys.append(d)
		_glitch_flash(spot)
	AudioBus.play_synth_at("overlord_glitch", here, -2.0, 1.25)
	return decoys.size()

## The spot `want` if the robot can see it at chest height and there is floor
## under it, else Vector3.INF.
func _clear_spot(want: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var chest := Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(global_position + chest, want + chest)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	if not space.intersect_ray(q).is_empty():
		return Vector3.INF
	var down := PhysicsRayQueryParameters3D.create(want + Vector3.UP * 1.5, want + Vector3.DOWN * 2.5)
	down.collision_mask = 1
	var floor_hit := space.intersect_ray(down)
	if floor_hit.is_empty():
		return Vector3.INF
	return floor_hit.position

func _glitch_flash(at: Vector3) -> void:
	var parent := get_parent()
	if parent:
		DeepfakeDecoy._burst(parent, at + Vector3.UP * 1.0)

## Every copy fires with the real one.
func _start_burst() -> void:
	super._start_burst()
	for d in decoys:
		if is_instance_valid(d):
			d.fake_burst(burst_count)

func collapse_decoys() -> void:
	for d in decoys:
		if is_instance_valid(d):
			d.shatter(false)
	decoys.clear()
