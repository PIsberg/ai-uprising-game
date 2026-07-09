extends Node3D
## The viewmodel kick is a spring integrated with plain Euler using the RAW frame
## delta. Euler's damping term diverges once delta > 2/KICK_DAMPING (~0.09 s,
## i.e. any frame slower than ~11 fps). A shot fired across a hitch — the first
## shot compiles the muzzle-flash shader — sends _kick_pos to infinity and then
## to NaN, and NOTHING ever resets it. The WeaponHolder's position is NaN, so
## EVERY weapon in it disappears, permanently, for the rest of the level.
##
## Reproduces it, then asserts the guarded integrator stays bounded.
##   godot --headless --path . res://tests/kick_stability_probe.tscn

var _ok := true
func _check(n: String, c: bool, d: String = "") -> void:
	print("%s %s %s" % ["ok  " if c else "BAD ", n, d])
	if not c:
		_ok = false

func _ready() -> void:
	_run.call_deferred()

func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _run() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	for i in 60:
		await get_tree().physics_frame
	GameState.set_state(GameState.State.PLAYING)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var wm: Node = player.get_node_or_null("Head/Camera3D/WeaponHolder")
	await get_tree().physics_frame

	# One shot's worth of kick, then a burst of hitching frames (a shader-compile
	# stall on the first shot), then normal frames.
	wm._on_fired(wm.current)
	for i in 30:
		wm._process(0.10)   # a shader-compile stall: 10 fps
		if i % 6 == 0:
			print("   hitch frame %2d: |kick| = %.4f" % [i, (wm._kick_pos as Vector3).length()])
	var kick: Vector3 = wm._kick_pos
	print("   after 30 frames @10fps: |kick| = %.4f  finite=%s" % [kick.length(), _finite(kick)])
	for i in 120:
		wm._process(1.0 / 60.0)
	var pos: Vector3 = wm.position
	var kick2: Vector3 = wm._kick_pos

	# The holder's rest position is its authored hip offset, not the origin —
	# measure DISPLACEMENT from the hip, which is what "the gun is gone" means.
	var hip: Vector3 = wm._hip_position
	var off: float = (pos - hip).length()
	print("   after 120 recovery frames @60fps: |kick| = %.4f  displacement from hip = %.4f m" % [
		kick2.length(), off])
	_check("kick stays finite", _finite(kick2), str(kick2))
	_check("holder position stays finite", _finite(pos), str(pos))
	_check("holder settles back to the hip (<5 cm)", off < 0.05, "offset=%.4f m" % off)
	# And the ordinary 60 fps kick must still feel like a kick: a real punch that
	# settles quickly. A "fix" that flattens the recoil is not a fix.
	wm._kick_pos = Vector3.ZERO
	wm._kick_pos_vel = Vector3.ZERO
	wm._on_fired(wm.current)
	var peak := 0.0
	for i in 12:
		wm._process(1.0 / 60.0)
		peak = maxf(peak, (wm._kick_pos as Vector3).length())
	var after := (wm._kick_pos as Vector3).length()
	for i in 40:
		wm._process(1.0 / 60.0)
	var rest := (wm._kick_pos as Vector3).length()
	print("   60fps single shot: peak |kick| = %.4f  settles to %.5f" % [peak, rest])
	_check("60fps kick still punches", peak > 0.005, "peak=%.4f" % peak)
	_check("60fps kick settles back", rest < 0.002, "rest=%.5f" % rest)

	print("RESULT ", "PASS" if _ok else "FAIL")
	get_tree().quit()
