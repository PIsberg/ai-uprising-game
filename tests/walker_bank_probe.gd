extends Node3D
## Probe: grounded robots lean like walkers, flyers bank like aircraft (#276).
## RobotModel used to treat every model without a walk clip as a flyer and
## bank it 2.6x (lean 1.5x) for good, so static-mesh ground robots (DOG, RONIN,
## HOWITZER, SERVER, ...) heeled over like planes when they strafed. Each robot
## stands on a floor, is frozen, and is fed a full-speed sideways (then
## forward) velocity; its model's settled roll (pitch) must stay within the
## walker bound for a grounded robot and reach the aircraft bound for a flyer.
##   godot --headless --path . --audio-driver Dummy res://tests/walker_bank_probe.tscn

const GROUNDED := ["dog", "ronin", "howitzer", "server", "roller", "warbot", "gunslinger", "enforcer", "optic"]
const FLYERS := ["drone", "raptor", "quantizer"]
const WALKER_ROLL := 0.24  ## rad: RobotModel's walker bank_max (0.22) + rounding
const WALKER_PITCH := 0.15 ## rad: walker lean_max (0.14) + rounding
const FLYER_ROLL := 0.45   ## rad: an aircraft bank clears this

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

## Settled [roll, pitch] of `e`'s model under a velocity (body frame `local_v`).
func _settle(e: CharacterBody3D, local_v: Vector3) -> Vector2:
	var model := e.get_node("Model")
	e.velocity = e.global_transform.basis * local_v
	for i in 30:
		model.call("_apply_lean", 0.2)
	return Vector2(float(model.get("_lean_roll")), float(model.get("_lean_pitch")))

func _run() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var x := -60.0
	for id in GROUNDED + FLYERS:
		var e: CharacterBody3D = (load("res://scenes/enemies/%s.tscn" % id) as PackedScene).instantiate()
		add_child(e)
		e.global_position = Vector3(x, 0.2 if id in GROUNDED else 3.0, 0)
		x += 12.0
		for i in 20:
			await get_tree().physics_frame # settle onto the floor (flyers hover)
		var grounded := e.is_on_floor()
		e.process_mode = Node.PROCESS_MODE_DISABLED
		var spd: float = maxf(float(e.get("move_speed")), 1.0)
		var side := _settle(e, Vector3(spd, 0, 0))
		var fwd := _settle(e, Vector3(0, 0, -spd))
		print("  %-10s on floor %s, roll %.3f rad, pitch %.3f rad" % [id, grounded, absf(side.x), absf(fwd.y)])
		if id in GROUNDED:
			_check("%s stands on the floor" % id, grounded)
			_check("%s strafes like a walker" % id, absf(side.x) <= WALKER_ROLL, "(roll %.2f)" % side.x)
			_check("%s advances like a walker" % id, absf(fwd.y) <= WALKER_PITCH, "(pitch %.2f)" % fwd.y)
		else:
			_check("%s off the floor" % id, not grounded)
			_check("%s banks like an aircraft" % id, absf(side.x) >= FLYER_ROLL, "(roll %.2f)" % side.x)
		e.queue_free()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
