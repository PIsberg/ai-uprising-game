extends Node3D
## Probe: the ramp walker tells a walked ramp from a stopped one (#339).
## tests/ramp_walker.gd is the verdict of the CI ramp walk (ramp_walk_triage,
## every ramp of every level) and of house_stairs_probe. That walk now reports
## zero stops, so a walker that could no longer see a stop would pass for ever.
## Four ramps on a bare floor, 8 m long and 2 m up onto a deck, the real Player
## walking each (no jump, no sprint):
##   - a clean ramp is walked;
##   - a ramp with a knee-high wall across it is a stop, and the walker got no
##     higher than the wall;
##   - a ramp whose top holds a zipline station is walked, and says it rode
##     (titan's SkyBridge: the cable used to carry the walker 47 m away, which
##     read as the last repeatable stop);
##   - a ramp with a station half way up is a stop: a cable that takes the
##     player off before the top has not delivered them to it.
## Physics time only.
##   godot --headless --path . --audio-driver Dummy res://tests/ramp_walker_probe.tscn

const Walker := preload("res://tests/ramp_walker.gd")
const RUN := 8.0 ## metres of ramp along -Z
const RISE := 2.0
const WIDTH := 2.4

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _box(size: Vector3, xf: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.global_transform = xf
	return body

## A ramp from (x, 0, 0) up to (x, RISE, -RUN) with a deck behind its top.
## Returns [from, to].
func _ramp(x: float) -> Array:
	var from := Vector3(x, 0.0, 0.0)
	var to := Vector3(x, RISE, -RUN)
	var along := (to - from).normalized()
	var side := Vector3.RIGHT
	var up := side.cross(along).normalized() * -1.0
	if up.y < 0.0:
		up = -up
	# The slab's top face lies on the walking line.
	_box(Vector3(WIDTH, 0.2, (to - from).length()), Transform3D(Basis(side, up, side.cross(up)), (from + to) * 0.5 - up * 0.1))
	_box(Vector3(WIDTH, 0.2, 6.0), Transform3D(Basis.IDENTITY, Vector3(x, RISE - 0.1, -RUN - 3.0)))
	return [from, to]

func _zip(at: Vector3, far: Vector3) -> void:
	var z := ZipLine.new()
	z.a = at
	z.b = far
	add_child(z)

func _run() -> void:
	GameState.reset_run()
	GameState.set_state(GameState.State.PLAYING)
	_box(Vector3(120, 1, 120), Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0)))
	var clean := _ramp(-18.0)
	var walled := _ramp(-6.0)
	var station_top := _ramp(6.0)
	var station_mid := _ramp(18.0)
	# Knee high (0.6 m over the ramp where it stands): over the 0.3 m step-up.
	var wall_at: Vector3 = (walled[0] as Vector3).lerp(walled[1], 0.5)
	_box(Vector3(WIDTH, 0.6, 0.2), Transform3D(Basis.IDENTITY, wall_at + Vector3.UP * 0.3))
	# A station 1.6 m before the top, as on titan, and one half way up. Both
	# cables run off to the floor far to the side.
	var up_dir := ((station_top[1] as Vector3) - (station_top[0] as Vector3)).normalized()
	_zip((station_top[1] as Vector3) - up_dir * 1.6, Vector3(6.0, 0.0, 40.0))
	_zip((station_mid[0] as Vector3).lerp(station_mid[1], 0.5), Vector3(18.0, 0.0, 40.0))
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.2, 20)
	player.set("_god", true)
	for i in 30:
		await get_tree().physics_frame

	var r: Dictionary = await Walker.walk(player, clean[0], clean[1])
	_check("a clean ramp is walked", r["ok"] and not r["rode"], "got to y %.2f of %.2f" % [r["best_y"], RISE])

	r = await Walker.walk(player, walled[0], walled[1])
	_check("a ramp with a knee-high wall across it is a stop", not r["ok"] and float(r["best_y"]) < RISE * 0.5 + 0.7,
		"ok %s, got to y %.2f, wall at y %.2f" % [r["ok"], r["best_y"], wall_at.y])

	r = await Walker.walk(player, station_top[0], station_top[1])
	_check("a zipline station at the top takes the walker: walked", r["ok"] and r["rode"],
		"ok %s rode %s, taken at %s" % [r["ok"], r["rode"], r["at"]])

	r = await Walker.walk(player, station_mid[0], station_mid[1])
	_check("a zipline station half way up is a stop", not r["ok"] and r["rode"],
		"ok %s rode %s, taken at %s" % [r["ok"], r["rode"], r["at"]])

	# The walker lets go of the last cable, so the next walk starts on its feet.
	r = await Walker.walk(player, clean[0], clean[1])
	_check("after a ride the next ramp is walked from its foot", r["ok"] and not r["rode"], "got to y %.2f" % r["best_y"])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
