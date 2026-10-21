extends Node3D
## An android that keeps flanking keeps shooting (#414). In ATTACK the android
## sometimes runs for a flank point beside its target and holds fire until it
## gets there; with the point far off, or re-picked every 3 s before it
## arrives, it went quiet for as long as it ran. Two rewritten robots flanking
## each other could trade no shots for 5 s (the reward_rewrite_probe flake).
## Here an android that always flanks (flank_chance 1) toward points 40 m out
## (preferred_range 40) fights a still player for 14 s. Shots are counted by the
## tracers it spawns, so a miss still counts:
##   - it fires (control);
##   - the longest gap between two shots stays under MAX_GAP: a flank gives up
##     after EnemyAndroid.FLANK_MAX and the android shoots from where it stands;
##   - it still flanks (it travels at least 6 m from where it started).
##   godot --headless --path . --audio-driver Dummy res://tests/android_flank_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ANDROID := preload("res://scenes/enemies/android.tscn")
const MAX_GAP := 4.5

var _fail: Array[String] = []
var _shots: Array[float] = []
var _t := 0.0
var _tracer_path := ""

func _check(cond: bool, label: String, detail: String = "") -> void:
	print(("  ok   " if cond else "  FAIL ") + label + ("  (" + detail + ")" if detail != "" else ""))
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _physics_process(delta: float) -> void:
	_t += delta

func _run() -> void:
	await _nav_floor(200.0)
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	(player.get_node("Damageable") as Damageable).invulnerable = true
	var bot: EnemyBase = ANDROID.instantiate()
	add_child(bot)
	bot.global_position = Vector3(0, 0.1, -12)
	await get_tree().physics_frame
	bot.set("flank_chance", 1.0)
	bot.preferred_range = 40.0
	var start := bot.global_position
	_tracer_path = (bot.get("tracer_scene") as PackedScene).resource_path if bot.get("tracer_scene") else ""
	_check(_tracer_path != "", "the android has a tracer to count shots by")
	get_tree().node_added.connect(_on_node_added)
	var far := 0.0
	_t = 0.0
	while _t < 14.0:
		await get_tree().physics_frame
		if is_instance_valid(bot):
			far = maxf(far, Vector2(bot.global_position.x - start.x, bot.global_position.z - start.z).length())
	get_tree().node_added.disconnect(_on_node_added)
	_check(_shots.size() >= 5, "it fires", "%d shots" % _shots.size())
	var gap := 0.0
	for i in range(1, _shots.size()):
		gap = maxf(gap, _shots[i] - _shots[i - 1])
	if not _shots.is_empty():
		gap = maxf(gap, 14.0 - _shots[-1]) # a silent tail counts too
	_check(gap < MAX_GAP, "it never holds fire longer than %.1f s while flanking" % MAX_GAP, "longest gap %.2f s" % gap)
	_check(far >= 6.0, "it still flanks", "travelled %.1f m" % far)
	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	get_tree().quit(0 if _fail.is_empty() else 1)

## A baked navmesh floor, so the flank runs on real paths.
func _nav_floor(size: float) -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	fmi.mesh = pm
	nav.add_child(fmi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size, 1, size)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	nav.add_child(sb)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5
	nm.cell_size = 0.25
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)
	for i in 3:
		await get_tree().physics_frame

func _on_node_added(n: Node) -> void:
	if n.scene_file_path == _tracer_path:
		_shots.append(_t)
