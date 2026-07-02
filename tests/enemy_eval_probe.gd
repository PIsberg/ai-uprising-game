extends Node3D
## Objective enemy balance eval: spawn each enemy 1v1 vs a stationary high-HP
## player at mid range and measure, over a fixed window, the REAL package —
## damage landed (DPS, accounting for accuracy/projectile travel/pathing),
## whether it closes (min distance), and how much it strafes (lateral spread).
## Headless: godot --headless --path . --quit-after 4000 res://tests/enemy_eval_probe.tscn

const TYPES := [
	"drone", "android", "spider", "mech", "skitter", "vacuum", "hunter",
	"reaper", "strider", "sniper", "seeker", "brute", "gunner", "raptor",
	"mender", "sentinel", "mauler", "ravager", "warmech", "alien", "dog", "server",
	"fishbot", "shark",
	"warbot", "enforcer", "ripper", "whirlwind", "optic", "roller", "gunslinger", "breaker",
]
const SPAWN_DIST := 14.0
const WINDOW := 6.0

var _nav: NavigationRegion3D
var _player: CharacterBody3D
var _pdmg: Damageable

func _ready() -> void:
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); add_child(sun)
	_nav = NavigationRegion3D.new(); add_child(_nav)
	var fmi := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(120, 120); fmi.mesh = pm
	_nav.add_child(fmi)
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(120, 1, 120)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0); sb.add_child(cs); _nav.add_child(sb)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5; nm.cell_size = 0.25
	_nav.navigation_mesh = nm; _nav.bake_navigation_mesh()
	await get_tree().create_timer(0.3).timeout

	_player = CharacterBody3D.new()
	_player.add_to_group("player")
	_player.collision_layer = 2; _player.collision_mask = 1
	var pcs := CollisionShape3D.new(); var pcap := CapsuleShape3D.new()
	pcap.radius = 0.4; pcap.height = 1.7; pcs.shape = pcap; pcs.position = Vector3(0, 0.9, 0)
	_player.add_child(pcs)
	_pdmg = Damageable.new(); _pdmg.name = "Damageable"; _pdmg.max_health = 1.0e9
	_player.add_child(_pdmg)
	# Stand-in shake() so attacks that call it don't error.
	add_child(_player)
	_player.global_position = Vector3(0, 1.0, 0)

	print("ENEMY EVAL  (window=%.0fs, spawn=%.0fm, player stationary, NORMAL diff)" % [WINDOW, SPAWN_DIST])
	print("%-10s %7s %8s %8s %8s  %s" % ["type", "dmg", "dps", "minDist", "strafe", "note"])
	for t in TYPES:
		await _eval(t)
	print("ENEMY_EVAL_DONE")
	get_tree().quit()

func _eval(t: String) -> void:
	var e := EnemyCodex.get_entry(t)
	var path: String = e.get("scene", "res://scenes/enemies/%s.tscn" % t)
	var enemy: Node3D = (load(path) as PackedScene).instantiate()
	if "preview" in enemy:
		enemy.preview = false
	_nav.add_child(enemy)
	# Spawn each enemy in its INTENDED engagement band so ranged units fire instead
	# of spending the window repositioning (melee clamp low; they close in 6s).
	var pref: float = (enemy.preferred_range if enemy is EnemyBase else 12.0)
	var dist: float = clampf(pref * 1.15, 8.0, 26.0)
	enemy.global_position = Vector3(0, 0.6, -dist)
	enemy.rotation.y = PI # face the player (+Z)
	var hp0: float = _pdmg.current_health
	await get_tree().physics_frame
	# Wake it up immediately so we measure engagement, not the spot-the-player delay.
	if enemy is EnemyBase:
		enemy.target = _player
		if enemy.has_method("set_state"):
			enemy.set_state(EnemyBase.State.CHASE)
	if enemy.has_method("_begin_rise"): # vacuum starts folded
		enemy._begin_rise()
	var min_d := dist
	var max_x := 0.0
	var elapsed := 0.0
	while elapsed < WINDOW and is_instance_valid(enemy):
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if is_instance_valid(enemy):
			var d := enemy.global_position.distance_to(_player.global_position)
			min_d = minf(min_d, d)
			max_x = maxf(max_x, absf(enemy.global_position.x))
	var dealt: float = hp0 - _pdmg.current_health
	var note := ""
	if not is_instance_valid(enemy):
		note = "self-destructed"
	print("%-10s %7.0f %8.1f %8.1f %8.1f  %s" % [t, dealt, dealt / WINDOW, min_d, max_x, note])
	if is_instance_valid(enemy):
		enemy.queue_free()
	await get_tree().physics_frame
