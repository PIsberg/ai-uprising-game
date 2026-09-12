extends Node3D
## Regression probe for the player's soft enemy separation (player.gd
## _update_enemy_separation). The design comment promises a push "capped well
## below anything that could snap/launch the player" (separation_max_speed,
## 6 m/s). The implementation ADDED that value to velocity every physics
## frame, on top of whatever velocity friction had left, so a body pressing
## into the player was a 6 m/s-per-frame impulse (~360 m/s^2), not a cap.
## Measured on water_world: a fishbot brushing the idle player at the spawn
## island flung them 5.8 m in 0.5 s (11.6 m/s) straight into the flood.
##
## Parks an enemy-layer body inside the player's separation probe and asserts
## the player's horizontal speed never exceeds the documented cap and the
## displacement over one second stays in walking range.
##   godot --headless --path . --audio-driver Dummy res://tests/separation_push_probe.tscn

const FRAMES := 60             ## one second of physics at 60 Hz
const SPEED_TOL := 1.15        ## cap * this = allowed peak
const MAX_DISPLACEMENT := 4.0  ## metres in one second (walk speed territory)

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

## A dumb enemy-layer body (no script, no gravity): the separation probe only
## looks at the collider's layer and position.
func _build_presser(at: Vector3) -> Node3D:
	var b := StaticBody3D.new()
	b.collision_layer = 4 # enemy
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.4
	sh.height = 1.8
	cs.shape = sh
	b.add_child(cs)
	add_child(b)
	b.global_position = at
	return b

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3.ZERO
	for i in 10:
		await get_tree().physics_frame # settle on the floor
	var cap: float = float(player.get("separation_max_speed"))
	var start: Vector3 = player.global_position
	# Press from slightly behind: deep inside the 1.2 m probe, away = +Z.
	_build_presser(start + Vector3(0, 0.9, -0.3))

	var peak := 0.0
	for i in FRAMES:
		await get_tree().physics_frame
		var h := Vector2(player.velocity.x, player.velocity.z).length()
		peak = maxf(peak, h)
	var moved: float = Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	print("cap=%.1f m/s  peak horizontal speed=%.2f m/s  displacement in %d frames=%.2f m" % [cap, peak, FRAMES, moved])
	_check(peak <= cap * SPEED_TOL, "push never exceeds separation_max_speed (%.2f <= %.2f)" % [peak, cap * SPEED_TOL])
	_check(moved <= MAX_DISPLACEMENT, "one second of pressing moves the player at most %.1f m (%.2f)" % [MAX_DISPLACEMENT, moved])
	_check(moved > 0.2, "the push still separates them (%.2f m)" % moved)

	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
