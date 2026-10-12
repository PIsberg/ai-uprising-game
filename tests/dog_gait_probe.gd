extends Node3D
## Probe: the K-9 HUNTER (DOG) trots on its legs instead of sliding.
## robot_dog_v2.glb keeps upper legs, lower legs and paws as separate meshes,
## each holding the left and the right leg. Paws are measured off the model:
## every drawn mesh under the GLB's paw nodes (Sphere002 front, Sphere003
## rear), grouped by side, centroids in the body frame.
## (1) running after a target: every paw swings fore and aft at least 0.12 m;
## (2) a trot: diagonal paws move together (front-left with rear-right,
##     correlation > 0.6) and the two front paws in opposition (< -0.6);
## (3) standing still: every paw back within 0.03 m of where it rests.
##   godot --headless --path . --audio-driver Dummy res://tests/dog_gait_probe.tscn

const PAWS := {"front": "Sphere002", "rear": "Sphere003"}

var ok := true
var _e: CharacterBody3D

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
	pm.size = Vector2(120, 120)
	mi.mesh = pm
	region.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, 1, 160)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	region.add_child(body)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

## Body-frame paw centroids: {"FL": .., "FR": .., "RL": .., "RR": ..}. Left is -x.
func _paws() -> Dictionary:
	var inv := _e.global_transform.affine_inverse()
	var out := {}
	for end in PAWS:
		var node := _e.find_child(PAWS[end], true, false)
		var sums := {"L": Vector3.ZERO, "R": Vector3.ZERO}
		var cnt := {"L": 0, "R": 0}
		for m in node.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if not mi.is_visible_in_tree():
				continue
			for s in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
				for i in idx:
					var q: Vector3 = inv * mi.global_transform * v[i]
					var side := "L" if q.x < 0.0 else "R"
					sums[side] += q
					cnt[side] += 1
		for side in ["L", "R"]:
			out[("F" if end == "front" else "R") + side] = sums[side] / maxf(cnt[side], 1)
	return out

static func _corr(a: Array, b: Array) -> float:
	var n := a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / sqrt(maxf(saa * sbb, 1e-12))

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -30) # inside its 38 m sight
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0

	_e = (load("res://scenes/enemies/dog.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 0.1, 0)
	_e.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 4:
		await get_tree().physics_frame
	var rest := _paws()
	print("  rest paws %s" % rest)
	_e.process_mode = Node.PROCESS_MODE_INHERIT
	_e.set("target", player)
	_e.call("set_state", 3) # CHASE
	var track := {"FL": [], "FR": [], "RL": [], "RR": []}
	var speed := 0.0
	var t := 0.0
	while t < 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t < 0.5:
			continue # getting up to speed
		var p := _paws()
		for k in track:
			(track[k] as Array).append((p[k] as Vector3).z)
		speed = maxf(speed, Vector2(_e.velocity.x, _e.velocity.z).length())
	print("  ran at up to %.1f m/s" % speed)
	_check("dog actually ran", speed > 2.0, "(%.1f m/s)" % speed)
	for k in track:
		var a: Array = track[k]
		var span: float = a.max() - a.min()
		_check("%s paw swings fore and aft" % k, span >= 0.12, "(%.3f m)" % span)
	var diag := _corr(track["FL"], track["RR"])
	var front := _corr(track["FL"], track["FR"])
	_check("diagonal paws move together (trot)", diag > 0.6, "(r %.2f)" % diag)
	_check("front paws in opposition", front < -0.6, "(r %.2f)" % front)

	# Stop: legs settle back under it.
	_e.set("target", null)
	_e.call("set_state", 0) # IDLE
	_e.set("move_speed", 0.0)
	_e.velocity = Vector3.ZERO
	t = 0.0
	while t < 1.2:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var still := _paws()
	var worst := 0.0
	for k in still:
		worst = maxf(worst, (still[k] as Vector3).distance_to(rest[k]))
	_check("paws back under it when it stops", worst < 0.03, "(%.3f m)" % worst)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
