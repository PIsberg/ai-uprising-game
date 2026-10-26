extends Node3D
## Probe: the MENDER's eye rig (Enemy_EyeDrone: the chassis is an eye, a
## lidded lens on its Body bone). A SPIDER at half health 6 m off on the
## floor is its patient; the player starts 30 m away.
## (1) mending, the beam's root is on the lens: 0.65-0.95 m from the
##     sphere's centre along the eye's look, within 0.2 m of that point, and
##     0.3+ m from the old fixed node (0.36 m inside the sphere);
## (2) the eye pitches down onto the patient: _eye_pitch under -0.25 rad
##     within 0.15 of the true angle, and the Body bone's look (its swept
##     pose) drops below -0.2 in y;
## (3) the iris narrows: the Charging clip is the player's assigned clip
##     while the beam runs, and the patient's health rises;
## (4) the player closing to 5 m: within 0.5 s a back-flip is running (the
##     BackFlip clip, _flip_t > 0), the beam is dropped, the eye turns on the
##     player, and 0.6 s in it is fleeing past 1.2x move_speed;
## (5) the flip over and the player gone, the beam and the Charging hold are
##     back on the patient within 1.5 s;
## (6) the patient at full health: the beam drops, the hold is released
##     (clip not Charging within 0.6 s) and the eye levels (within 0.1 rad
##     after 1 s).
##   godot --headless --path . --audio-driver Dummy res://tests/mender_eye_probe.tscn

var ok := true
var _e: CharacterBody3D
var _ally: CharacterBody3D
var _player: CharacterBody3D

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _build_floor() -> void:
	var region := NavigationRegion3D.new()
	add_child(region)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	mi.mesh = pm
	region.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	region.add_child(body)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _ap() -> AnimationPlayer:
	return _e.find_child("AnimationPlayer", true, false) as AnimationPlayer

func _beam() -> MeshInstance3D:
	return _e.get("_beam")

## The beam box spans local -Z..+Z and looks at its target: its root is
## the +Z end.
func _beam_root() -> Vector3:
	var b := _beam()
	return b.global_position + b.global_transform.basis.z.normalized() * b.scale.z * 0.5

func _eye_look() -> Vector3:
	var sk := _e.find_child("Skeleton3D", true, false) as Skeleton3D
	var pose: Transform3D = (_e.get("_sweep") as Node).call("posed", "Body")
	return _e.global_transform.basis.inverse() * (sk.global_transform.basis * pose.basis).z.normalized()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 0.1, 30)
	_player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	var php: Node = _player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	_ally = (load("res://scenes/enemies/spider.tscn") as PackedScene).instantiate()
	add_child(_ally)
	_ally.global_position = Vector3(0, 0.1, -6)
	_ally.set("sight_range", 0.0)
	_ally.set("_leap_cd", 999.0)
	_e = (load("res://scenes/enemies/mender.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 3.3, 0)
	for i in 10:
		await get_tree().physics_frame
	var ahp: Node = _ally.get_node("Damageable")
	ahp.max_health = 400.0 # a long mend: 16/s would top a spider up in 1.5 s
	ahp.current_health = 100.0
	var have := _e.get("_sweep") != null and _e.get("muzzle") != null
	_check("eye rig set up: the Body sweep and a muzzle", have, "(sweep %s, muzzle %s)" % [_e.get("_sweep"), _e.get("muzzle")])
	if not have:
		print("RESULT FAIL")
		get_tree().quit()
		return
	await _wait(1.5)
	# (1) the beam root on the lens.
	var beaming: bool = _beam().visible
	var pitch: float = _e.get("_eye_pitch")
	var look_w := _e.global_transform.basis * (Quaternion(Vector3.RIGHT, pitch) * Vector3.FORWARD)
	var root := _beam_root()
	var r := root.distance_to(_e.global_position)
	var off := root.distance_to(_e.global_position + look_w * 0.8)
	var old := root.distance_to(_e.global_transform * Vector3(0, 0, -0.36))
	var muzzle_off := (_e.get("muzzle") as Node3D).global_position.distance_to(root)
	_check("mending, the beam leaves the lens, the muzzle with it", beaming and r > 0.65 and r < 0.95 and off < 0.2 and old > 0.3 and muzzle_off < 0.02, "(beam %s, root %.2f m from the centre, %.2f m off the lens, %.2f m from the old node, muzzle %.3f m off)" % [beaming, r, off, old, muzzle_off])
	# (2) the eye pitched onto the patient.
	var to: Vector3 = _ally.global_position + Vector3.UP * 0.6 - _e.global_position
	var true_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var look_b := _eye_look()
	_check("the eye pitches down onto the patient", pitch < -0.25 and absf(pitch - true_pitch) < 0.15 and look_b.y < -0.2, "(pitch %.2f, true %.2f, Body look %s)" % [pitch, true_pitch, look_b])
	# (3) the iris narrowed, the patient healing.
	var hp0: float = ahp.current_health
	await _wait(1.0)
	_check("the iris narrows into Charging while it mends, and the patient heals", _ap().assigned_animation == "Charging" and ahp.current_health > hp0 + 8.0, "(assigned %s, current %s, health %.1f -> %.1f)" % [_ap().assigned_animation, _ap().current_animation, hp0, ahp.current_health])
	# (4) the player closes in: a back-flip.
	_player.global_position = _e.global_position + Vector3(0, -3.2, 5.0)
	var frames := 0
	while frames < 30 and float(_e.get("_flip_t")) <= 0.0:
		await get_tree().physics_frame
		frames += 1
	var flipping: bool = float(_e.get("_flip_t")) > 0.0
	var clip := _ap().current_animation
	var beam_off: bool = not _beam().visible
	await _wait(0.6)
	var spd := Vector2(_e.velocity.x, _e.velocity.z).length()
	var pitch_flee: float = _e.get("_eye_pitch")
	_check("the player closing in: a back-flip away at a burst of speed, the beam dropped", flipping and clip == "BackFlip" and beam_off and spd > float(_e.get("move_speed")) * 1.2, "(flip %s after %d ticks, clip %s, beam off %s, %.1f m/s, eye pitch %.2f)" % [flipping, frames, clip, beam_off, spd, pitch_flee])
	# (5) the player gone, the flip over: back to mending.
	_player.global_position = Vector3(0, 0.1, 40)
	ahp.current_health = 100.0
	await _wait(1.5)
	_check("the flip over, the beam and the focus are back on the patient", _beam().visible and _ap().assigned_animation == "Charging" and float(_e.get("_flip_t")) <= 0.0, "(beam %s, assigned %s, flip left %.2f)" % [_beam().visible, _ap().assigned_animation, _e.get("_flip_t")])
	# (6) the patient whole: the beam drops, the hold is released, the eye levels.
	ahp.current_health = ahp.max_health
	await _wait(0.6)
	var released := _ap().assigned_animation != "Charging" and not _beam().visible
	await _wait(1.0)
	_check("the patient whole: beam off, iris open again, eye level", released and absf(float(_e.get("_eye_pitch"))) < 0.1, "(released %s, assigned %s, pitch %.2f)" % [released, _ap().assigned_animation, _e.get("_eye_pitch")])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
