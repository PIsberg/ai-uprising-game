class_name EnemyForkbomb
extends EnemySpider
## FORK BOMB - a process that replicates when you kill it. The spider's
## dart-and-pounce melee on an acid-green chassis; killed, it forks into two
## smaller, faster copies, and those fork once more: 1 -> 2 -> 4, seven kills
## in all, spilling around you at once (the multi-kill callouts were already
## named for it).
##
## The counter: disintegrate it (gauss, Longshot, plasma, OMEGA) and the
## process is deleted before it can fork. Splash and chain weapons clear the
## swarm it leaves.
##
## The fork rides hp.died (override-proof) and reads the kill style during the
## emission, while the killing weapon's KillFx tag is still on. The children
## spawn deferred, which the portal's kill_all two-tick confirm already allows
## for. Covered by tests/forkbomb_probe.

const SCENE_PATH := "res://scenes/enemies/forkbomb.tscn"
const MAX_GEN := 2
const GEN_SCALE := [1.25, 0.9, 0.62]
const GEN_HEALTH := [90.0, 40.0, 18.0]
const GEN_SPEED := [10.0, 12.5, 14.5]
const GEN_SCORE := [150, 60, 25]
const GEN_BITE := [20.0, 12.0, 7.0]

@export var generation: int = 0

func _ready() -> void:
	super._ready()
	var g := clampi(generation, 0, MAX_GEN)
	max_health = GEN_HEALTH[g]
	move_speed = GEN_SPEED[g]
	score_value = GEN_SCORE[g]
	bite_damage = GEN_BITE[g]
	hp.max_health = max_health
	hp.current_health = max_health
	scale = Vector3.ONE * GEN_SCALE[g]
	hp.died.connect(_on_fork_died)

func _on_fork_died(_source: Node) -> void:
	if generation >= MAX_GEN:
		return
	if hp.kill_fx == KillFx.DISINTEGRATE:
		_tag("kill -9", Color(0.45, 0.9, 1.0))
		return
	var at := global_position
	var side := Vector3.RIGHT
	if is_instance_valid(target):
		var to := target.global_position - at
		to.y = 0.0
		if to.length() > 0.1:
			side = to.normalized().cross(Vector3.UP)
	_fork.call_deferred(at, side, target)
	_tag("fork()", Color(0.4, 1.0, 0.45))

## Spawns the two children either side of where it died, already hunting.
func _fork(at: Vector3, side: Vector3, hunt: Node3D) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var scene := load(SCENE_PATH) as PackedScene
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	for s in [-1.0, 1.0]:
		var spot: Vector3 = at + side * 0.9 * s
		# Never fork into a wall: fall back to the death spot.
		if space:
			var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, spot + Vector3.UP * 0.4)
			q.collision_mask = 1
			if not space.intersect_ray(q).is_empty():
				spot = at
		var child := scene.instantiate() as EnemyForkbomb
		child.generation = generation + 1
		parent.add_child(child)
		child.global_position = spot
		child.velocity = side * 6.0 * s + Vector3.UP * 3.0
		if is_instance_valid(hunt):
			child.target = hunt
			child.set_state(State.CHASE)
	DeepfakeDecoy._burst(parent, at + Vector3.UP * 0.6)
	AudioBus.play_synth_at("overlord_glitch", at, -4.0, 2.2)

func _tag(text: String, col: Color) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64
	l.outline_size = 10
	l.pixel_size = 0.005
	l.modulate = col
	parent.add_child(l)
	l.global_position = global_position + Vector3.UP * 1.4
	var tw := l.create_tween()
	tw.tween_property(l, "global_position:y", l.global_position.y + 0.9, 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.tween_callback(l.queue_free)
