class_name EnemyRipper
extends EnemyAndroid
## RIPPER — a walking minigun platform (robot_minigun.glb: a rotary barrel that
## was pure dressing while this fired like any android with a longer burst).
## Now it fights like the model looks:
##  - SPIN-UP: the barrel audibly winds for a beat before the saw starts — the
##    cue to get moving (the android fires instantly; this one telegraphs).
##  - WALKING SAW: the stream aims at a point that TRAILS the player and only
##    slowly catches up, so the line of tracers visibly walks onto you —
##    strafing out of it is real counter-play, not a dice roll.
##  - GRINDING ADVANCE: it never plants while sawing — it closes at a slow,
##    implacable walk, denying the "trade from one piece of cover" stalemate.

var _saw_aim: Vector3 = Vector3.ZERO
var _spinning: bool = false

func _ready() -> void:
	super._ready()
	max_health = 170.0
	move_speed = 3.6
	turn_speed = 6.0
	attack_range = 28.0
	preferred_range = 15.0
	hitscan_damage = 5.0
	burst_count = 12      # a long minigun saw
	score_value = 230
	hp.max_health = max_health
	hp.current_health = max_health

func _state_attack(delta: float) -> void:
	super._state_attack(delta)
	# Grinding advance: while the saw runs, keep walking at the target.
	if _burst_remaining > 0 and target and is_instance_valid(target):
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length() > 3.0:
			var d := to.normalized()
			velocity.x = d.x * chase_speed() * 0.45
			velocity.z = d.z * chase_speed() * 0.45

## Spin-up gate in front of the android's instant burst.
func _start_burst() -> void:
	if _spinning:
		return
	_spinning = true
	AudioBus.play_synth_at("charge", global_position, -4.0, 0.7)
	recoil = 1.0 # the wind-up jolt fires the attack clip early
	if target and is_instance_valid(target):
		_saw_aim = target.global_position + Vector3.UP * 0.6 # saw starts where you WERE
	get_tree().create_timer(0.45).timeout.connect(func() -> void:
		if not is_instance_valid(self) or state == State.DEAD:
			return
		_spinning = false
		_burst_remaining = burst_count
		_burst_timer = 0.0
		_bark_attack())

## The walking saw: each shot chases a lagging aim point instead of the
## android's per-shot perfect tracking.
func _fire_one_shot() -> void:
	if target == null or muzzle == null:
		return
	_saw_aim = _saw_aim.lerp(target.global_position + Vector3.UP * 0.6, 0.22)
	recoil = 1.0
	if muzzle_flash_scene:
		muzzle.add_child(muzzle_flash_scene.instantiate())
	AudioBus.play_synth_at("drone_shot", muzzle.global_position, -5.0, randf_range(1.25, 1.35))
	var origin := muzzle.global_position
	var dir := scatter_aim((_saw_aim - origin).normalized(), burst_spread_deg)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 80.0)
	q.collision_mask = 0b0000011 # world + player
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var end_point := origin + dir * 80.0
	if not hit.is_empty():
		end_point = hit.position
		var col: Node = hit.collider
		var d: Node = col.get_node_or_null("Damageable") if col else null
		if d:
			d.apply_damage(hitscan_damage, self)
	if tracer_scene:
		var t := tracer_scene.instantiate()
		get_tree().current_scene.add_child(t)
		if t.has_method("setup"):
			t.setup(origin, end_point)
