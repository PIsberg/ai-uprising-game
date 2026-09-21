extends Node3D
## RAPTOR's model and its fight agree: the Blender fork (quaternius_flyergun_strike.glb,
## tools/blender/cfg_flyergun_strike.json) gives the hovering ball wings, engines, a V tail,
## a belly gun and talons, and the strafing run is flown like a bird of prey's stoop: it
## dives along the committed line raking belly-gun bolts ahead of it, drags its talons
## through the low point, then climbs out. Asserts the fork is wired + still animates, the
## pass really dips and recovers, the nose follows the flight path, the talons hit a target
## standing on the line exactly once and miss one that sidestepped, the guns stop once it
## has passed, and the thrusters vector from hover (down) to run (aft).

const RAPTOR := preload("res://scenes/enemies/raptor.tscn")
const ARMED := preload("res://assets/models/robots/quaternius_flyergun_armed.glb")

var _fails := 0
var _player: StaticBody3D
var _php: Damageable

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1

func _mesh_depth(root: Node) -> float:
	var lo := 1e9
	var hi := -1e9
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			lo = minf(lo, m.mesh.get_aabb().position.z)
			hi = maxf(hi, m.mesh.get_aabb().end.z)
	return hi - lo

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Fly one committed pass and report what happened on it. `sidestep` moves the player
## 5 m off the line the moment the run commits.
func _fly_pass(sidestep: bool) -> Dictionary:
	_player.global_position = Vector3(0, 1, 0)
	_php.current_health = _php.max_health
	var r := RAPTOR.instantiate() as Node3D
	add_child(r)
	r.global_position = Vector3(0, 5.2, 18)
	await _frames(30)
	var hover_thrust: Vector3 = r.call("thrust_dir") if r.has_method("thrust_dir") else Vector3.ZERO
	r.set("_run_cd", 0.0)
	var out := {"committed": false, "min_alt": 99.0, "start_alt": 0.0, "end_alt": 0.0,
		"min_pitch": 0.0, "max_pitch": 0.0, "rakes": 0, "shots_after_pass": 0,
		"hover_thrust": hover_thrust, "run_thrust": Vector3.ZERO, "hp_lost": 0.0}
	var model := r.get_node("Model") as Node3D
	var passed := false
	var shots_at_pass := 0
	for i in 60 * 8:
		await get_tree().physics_frame
		if not is_instance_valid(r):
			break
		var running := float(r.get("_run_t")) > 0.0
		if running and not out.committed:
			out.committed = true
			out.start_alt = r.global_position.y - _player.global_position.y
			if sidestep:
				var line: Vector3 = r.get("_run_dir")
				_player.global_position += line.cross(Vector3.UP).normalized() * 5.0
		if out.committed and running:
			var alt: float = r.global_position.y - 1.0 # the line's ground reference, not the dodger
			out.min_alt = minf(out.min_alt, alt)
			out.min_pitch = minf(out.min_pitch, model.rotation.x)
			out.max_pitch = maxf(out.max_pitch, model.rotation.x)
			if r.has_method("thrust_dir") and not passed:
				out.run_thrust = r.call("thrust_dir")
			var line2: Vector3 = r.get("_run_dir")
			var ahead: float = (Vector3(0, 0, 0) - r.global_position).dot(line2)
			if not passed and ahead < -1.0:
				passed = true
				shots_at_pass = int(r.get("_run_shots")) if "_run_shots" in r else -1
		if out.committed and not running:
			out.end_alt = r.global_position.y - 1.0
			break
	if is_instance_valid(r):
		out.rakes = int(r.get("_rake_hits")) if "_rake_hits" in r else -1
		var shots_end := int(r.get("_run_shots")) if "_run_shots" in r else -1
		out.shots_after_pass = shots_end - shots_at_pass if shots_at_pass >= 0 else -1
		r.queue_free()
	out.hp_lost = _php.max_health - _php.current_health
	await _frames(90) # let the bolts in flight land before the next pass resets health
	return out

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)

	_player = StaticBody3D.new()
	_player.add_to_group("player")
	_player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	pcs.shape = cap
	_player.add_child(pcs)
	_php = Damageable.new()
	_php.name = "Damageable"
	_php.max_health = 1000.0
	_player.add_child(_php)
	add_child(_player)
	_player.global_position = Vector3(0, 1, 0)

	# 1) The scene uses the strike fork (engines + tail reach further aft than the armed
	#    ball it replaced), clips intact.
	var probe_r := RAPTOR.instantiate() as Node3D
	var model := probe_r.get_node("Model/Mesh")
	var armed := ARMED.instantiate()
	var d_strike := _mesh_depth(model)
	var d_armed := _mesh_depth(armed)
	armed.free()
	_check(d_strike > d_armed + 0.1, "strike model carries engines + tail (depth %.2f > armed %.2f + 0.1)" % [d_strike, d_armed])
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_check(ap != null, "fork kept its AnimationPlayer")
	for clip in ["CharacterArmature|Idle", "CharacterArmature|Shoot", "CharacterArmature|Attack"]:
		_check(ap != null and ap.has_animation(clip), "fork kept clip %s" % clip)
	probe_r.free()

	# 2) A pass at a target that stays on the line.
	var hit: Dictionary = await _fly_pass(false)
	print("on-line pass: %s" % hit)
	_check(hit.committed, "raptor committed a run")
	_check(hit.start_alt > 3.4, "run starts from hover altitude (%.2f m)" % hit.start_alt)
	_check(hit.min_alt < 2.2, "the pass dives to talon height (lowest %.2f m)" % hit.min_alt)
	_check(hit.end_alt > 3.0, "and climbs back out (%.2f m at run end)" % hit.end_alt)
	_check(hit.min_pitch < -0.12, "nose drops in the dive (%.2f rad)" % hit.min_pitch)
	_check(hit.max_pitch > 0.12, "nose lifts in the climb-out (%.2f rad)" % hit.max_pitch)
	_check(hit.rakes == 1, "talons rake a target on the line exactly once (%d)" % hit.rakes)
	_check(hit.shots_after_pass == 0, "guns go quiet once it has passed (%d bolts after)" % hit.shots_after_pass)
	var ht: Vector3 = hit.hover_thrust
	var rt: Vector3 = hit.run_thrust
	_check(ht.y < -0.8, "hover: thrust points down (%s)" % ht)
	_check(rt.z > 0.7, "run: thrust swings aft (%s)" % rt)

	# 3) The counter-play: step off the committed line and the talons find nothing.
	var miss: Dictionary = await _fly_pass(true)
	print("sidestep pass: %s" % miss)
	_check(miss.committed, "second raptor committed a run")
	_check(miss.rakes == 0, "sidestepping the line dodges the talons (%d)" % miss.rakes)

	print("RESULT PASS" if _fails == 0 else "RESULT FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
