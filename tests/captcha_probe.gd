extends Node
## Probe: CAPTCHA gates (scripts/systems/captcha_gate.gd, a `gates` entry with
## `"captcha": true`).
## (1) GEMINI, GROK and MISTRAL each flag one gate; the real level builds the
##     CaptchaGate in that gap: clear floor through it, gate walls either side;
## (2) a ground robot stepping in is held for HOLD_TIME (inert, a challenge
##     over it, the gate counts it), then moves again verified;
## (3) a verified robot walks through a second time untouched;
## (4) a hijack-proof robot waves through as a VERIFIED ACCOUNT, not held;
## (5) a flyer passing over (origin above FLY_H) is not challenged;
## (6) the player walking through ticks the box, which clears after BOX_TIME.
##   godot --headless --path . --audio-driver Dummy res://tests/captcha_probe.tscn

const LEVELS := ["gemini", "grok", "mistral"]
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _robot(scene: String, pos: Vector3) -> EnemyBase:
	var e: EnemyBase = (load(scene) as PackedScene).instantiate()
	add_child(e)
	e.global_position = pos
	e.set_physics_process(false) # posed: we move it ourselves
	return e

func _run() -> void:
	# 1. Authored and built in the gap.
	for id in LEVELS:
		var flagged: Array = LevelDefs.get_def(id).get("gates", []).filter(func(g: Dictionary) -> bool:
			return g.get("captcha", false))
		_check("%s flags one CAPTCHA gate" % id, flagged.size() == 1, str(flagged.size()))
		var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		await _frames(3)
		var built := get_tree().get_nodes_in_group(CaptchaGate.GROUP)
		_check("%s builds it" % id, built.size() == 1, str(built.size()))
		if built.size() == 1 and flagged.size() == 1:
			var g: CaptchaGate = built[0]
			var space := (lvl as Node3D).get_world_3d().direct_space_state
			var p := g.global_position
			var across := g.global_transform.basis.x.normalized()
			var box := BoxShape3D.new()
			box.size = Vector3(g.width - 1.0, 2.0, 0.6)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = box
			q.collision_mask = 1
			q.transform = Transform3D(g.global_transform.basis.orthonormalized(), p + Vector3.UP * 1.2)
			_check("%s gate gap is clear" % id, space.intersect_shape(q, 1).is_empty())
			var walls := 0
			for s in [-1.0, 1.0]:
				var r := PhysicsRayQueryParameters3D.create(p + Vector3.UP, p + Vector3.UP + across * s * (g.width * 0.5 + 0.8), 1)
				if not space.intersect_ray(r).is_empty():
					walls += 1
			_check("%s gate walls either side" % id, walls == 2, str(walls))
		lvl.queue_free()
		await _frames(3)

	# 2-6. Mechanics in an empty room.
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(200, 1, 200)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var stage := Node3D.new()
	add_child(stage)
	var gate := CaptchaGate.build(stage, Vector3.ZERO, Vector3.RIGHT, 6.0, 4.4)
	var e := _robot("res://scenes/enemies/android.tscn", Vector3(0, 0, 6))
	await _frames(3)
	e.global_position = Vector3(0, 0, 0)
	await _frames(3)
	_check("a robot stepping in is held", e._emp_t > CaptchaGate.HOLD_TIME - 0.2 and gate.held == 1,
			"emp %.2f held %d" % [e._emp_t, gate.held])
	var prompt := e.get_node_or_null("CaptchaPrompt") as Label3D
	_check("a challenge over it", prompt != null and prompt.text.length() > 0, prompt.text if prompt else "")
	e.set_physics_process(true) # let the EMP clock run
	await _frames(int((CaptchaGate.HOLD_TIME + 0.3) * 60.0))
	_check("then it moves again", e._emp_t == 0.0 and e.has_meta(&"captcha_passed"))
	e.set_physics_process(false)
	e.global_position = Vector3(0, 0, 6)
	await _frames(3)
	e.global_position = Vector3(0, 0, 0)
	await _frames(3)
	_check("verified: a second pass is untouched", e._emp_t == 0.0 and gate.held == 1, str(gate.held))

	var big := _robot("res://scenes/enemies/android.tscn", Vector3(2, 0, 6))
	big._health_mult = EnemyBase.HIJACK_BOSS_HP / big.max_health + 1.0
	await _frames(3)
	big.global_position = Vector3(2, 0, 0)
	await _frames(3)
	_check("hijack-proof: waved through", big._emp_t == 0.0 and gate.held == 1 and big.has_meta(&"captcha_passed"))

	var flyer := _robot("res://scenes/enemies/drone.tscn", Vector3(-2, 4.5, 6))
	await _frames(3)
	flyer.global_position = Vector3(-2, CaptchaGate.SENSE_H + 1.0, 0)
	await _frames(3)
	_check("a flyer over the sensor is not challenged", not flyer.has_meta(&"captcha_passed") and gate.held == 1)

	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	pcs.shape = cap
	pcs.position.y = 1.0
	player.add_child(pcs)
	add_child(player)
	player.global_position = Vector3(0, 0, 8)
	await _frames(3)
	player.global_position = Vector3(0, 0, 0)
	await _frames(3)
	_check("the player ticks the box", gate.panel_text() == CaptchaGate.PANEL_TICKED, gate.panel_text())
	await _frames(int((CaptchaGate.BOX_TIME + 0.3) * 60.0))
	_check("the box clears after BOX_TIME", gate.panel_text() == CaptchaGate.PANEL_IDLE, gate.panel_text())

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
