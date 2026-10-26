extends Node3D
## Probe: the AR-7 Pulse Rifle has a firing signature of its own (PulseRifleFx,
## scripts/weapons/fx/pulse_rifle_fx.gd) through Weapon's SignatureFx hooks:
##   - every third tracer is the long bright one (3.2 m, hotter colour) and the
##     two between are short dim beads (0.8 m), in that rhythm from the first round;
##   - with a cold barrel there is no heat shimmer over the muzzle; four quick
##     shots heat it past HAZE_HEAT and the shimmer shows, its strength up with
##     the heat; cooled, it hides again;
##   - every shot leaves one smoke streamer at the muzzle and no shared puff,
##     and a hot barrel's streamer is denser than a cold one's;
##   - a round into a robot throws spall whose spray runs along the plating
##     (across the struck face, not back along the round);
##   - an unsigned gun (the M9's scene with its signature cleared) has none of it.
##   godot --headless --path . --audio-driver Dummy res://tests/rifle_fx_probe.tscn

const RIFLE_FX := "res://scripts/weapons/fx/pulse_rifle_fx.gd"

var ok := true
var cam: Camera3D

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(0, 1.6, 0.4), Vector3(0, 1.0, -30), Vector3.UP)
	var robot := _robot(Vector3(0, 1.5, -5))
	var w: Weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
	add_child(w)
	w.global_position = Vector3(0.2, 1.4, 0)
	var ctl: Weapon = (load("res://scenes/weapons/pistol.tscn") as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	ctl.global_position = Vector3(-0.2, 1.4, 0)
	await get_tree().process_frame
	await get_tree().physics_frame

	_check("the AR-7 carries the pulse rifle signature",
			w._sig != null and w._sig.get_script() != null and w._sig.get_script().resource_path == RIFLE_FX)
	_check("an unsigned gun carries the silent default signature",
			ctl._sig != null and ctl._sig.get_script().resource_path.ends_with("signature_fx.gd"))

	# The belt rhythm: short, short, LONG, short, short, LONG.
	var from := Vector3(0.3, 1.4, 0)
	var to := Vector3(0.0, 1.0, -30.0)
	var lengths: Array[float] = []
	var tints: Array[Color] = []
	for i in 6:
		var t := _spawned(func() -> void: w._spawn_tracer(from, to), "")
		if t.size() == 1:
			lengths.append(t[0].bolt_length)
			tints.append(t[0]._mat.get_shader_parameter("tint"))
			t[0].queue_free()
	_check("six rounds draw six tracers", lengths.size() == 6, str(lengths.size()))
	if lengths.size() == 6:
		var rhythm := lengths.map(func(l: float) -> String: return "L" if l > 2.0 else "s")
		_check("every third round is the long tracer, the rest short beads (ssLssL)",
				"".join(rhythm) == "ssLssL", "".join(rhythm) + " " + str(lengths))
		var long_sum := tints[2].r + tints[2].g + tints[2].b
		var short_sum := tints[0].r + tints[0].g + tints[0].b
		_check("the long tracer burns hotter than the beads", long_sum > short_sum + 0.2,
				"%.2f vs %.2f" % [long_sum, short_sum])
		_check("the beads keep the gun's own colour", tints[0].is_equal_approx(w.shot_color()))
	var ct := _spawned(func() -> void: ctl._spawn_tracer(from, to), "")
	_check("an unsigned gun's tracer is the stock bolt (2.2 m at 150 m/s)",
			ct.size() == 1 and is_equal_approx(ct[0].bolt_length, 2.2) and is_equal_approx(ct[0].bolt_speed, 150.0))
	for n in ct:
		n.queue_free()

	# Heat shimmer: cold, none; hot, a curtain over the muzzle.
	w._active_camera = cam
	w._active_shooter = null
	w._heat = 0.0
	await get_tree().process_frame
	_check("a cold barrel has no shimmer", _haze(w) == null or not _haze(w).visible)
	w.mag = maxi(w.mag, 6)
	var streamers: Array = []
	var smoke := 0
	for i in 4:
		var shot := _spawned(func() -> void: w._do_shot(), "")
		streamers.append_array(shot.filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "pulse_streamer"))
		smoke += shot.filter(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "muzzle_smoke").size()
	var heat: float = w._heat
	_check("four quick shots heat the barrel past HAZE_HEAT", heat >= PulseRifleFx.HAZE_HEAT, "%.2f" % heat)
	await get_tree().process_frame
	var hz := _haze(w)
	_check("a hot barrel shows the shimmer over the muzzle", hz != null and hz.visible and hz.get_parent() == w.muzzle)
	if hz:
		var s1: float = hz.material_override.get_shader_parameter("strength")
		_check("the shimmer sits above the bore", hz.position.y > 0.05, str(hz.position))
		w._heat = 1.0
		w._sig.on_process(0.0)
		var s2: float = hz.material_override.get_shader_parameter("strength")
		_check("the shimmer strengthens with the heat", s2 > s1, "%.4f -> %.4f" % [s1, s2])
		w._heat = 0.0
		w._sig.on_process(0.0)
		_check("a cooled barrel hides the shimmer", not hz.visible)
	_check("every shot leaves one streamer", streamers.size() == 4, str(streamers.size()))
	_check("the AR-7 throws no shared muzzle smoke", smoke == 0, str(smoke))
	if streamers.size() == 4:
		var a0: int = streamers[0].amount
		var a3: int = streamers[3].amount
		_check("a hot barrel's streamer is denser than a cold one's", a3 > a0, "%d -> %d" % [a0, a3])
		_check("the streamer leaves the muzzle",
				streamers[0].global_position.distance_to(w.muzzle.global_position) < 0.15)

	# Spall along the plating.
	await get_tree().process_frame
	var origin := Vector3(2.0, 1.5, 0)
	var rdir := (Vector3(0, 1.5, -5 + 0.4) - origin).normalized()
	var hp0: float = robot.get_node("Damageable").current_health
	var hits := _spawned(func() -> void: w._do_hitscan(origin, rdir), "")
	var spall := hits.filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "spall")
	_check("the round hit the robot", robot.get_node("Damageable").current_health < hp0)
	_check("a round into a robot throws one spall spray", spall.size() == 1, str(spall.size()))
	if spall.size() == 1:
		var p: CPUParticles3D = spall[0]
		var normal := Vector3(0, 0, 1)
		_check("the spall runs along the plating, not back along the round",
				absf(p.direction.dot(normal)) < 0.2 and p.direction.x < -0.8, str(p.direction))
		_check("the spall starts at the hit", p.global_position.distance_to(Vector3(0, 1.5, -4.6)) < 0.3, str(p.global_position))
	var chits := _spawned(func() -> void: ctl._do_hitscan(origin, rdir), "")
	_check("an unsigned gun throws no spall",
			chits.filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "spall").is_empty())
	ctl._active_camera = cam
	ctl.mag = maxi(ctl.mag, 3)
	var cshot := _spawned(func() -> void: ctl._do_shot(), "")
	_check("an unsigned gun keeps the shared muzzle smoke and no streamer",
			cshot.any(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "muzzle_smoke")
			and not cshot.any(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "pulse_streamer"))
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _haze(w: Weapon) -> MeshInstance3D:
	for c in w.muzzle.get_children():
		if c.get_meta("sig_fx", "") == "heat_haze":
			return c
	return null

## Run `action` and return the nodes it added under this scene, optionally only
## those tagged with the given sig_fx meta.
func _spawned(action: Callable, tag: String) -> Array:
	var before := get_children()
	action.call()
	var out: Array = []
	for n in get_children():
		if n in before:
			continue
		if tag == "" or n.get_meta("sig_fx", "") == tag:
			out.append(n)
	return out

## A robot stand-in: a body on the enemy layer with a Damageable, its +Z face at z + 0.4.
func _robot(at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 4
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 1.8, 0.8)
	cs.shape = box
	sb.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1.0e6
	sb.add_child(hp)
	add_child(sb)
	sb.global_position = at
	return sb
