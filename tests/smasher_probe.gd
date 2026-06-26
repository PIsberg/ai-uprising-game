extends Node3D
## Spawns BEHEMOTH-X in a small arena with a player stand-in and lets the real AI
## run, so we can SEE the poster mech (steel + pauldrons + fists + red reactor/
## visor) and confirm it wakes, charges, and smashes. Captures shots to user://.
## Run windowed: godot --path . --quit-after 700 res://tests/smasher_probe.tscn

var _player: CharacterBody3D
var _boss: Node
var _cam: Camera3D
var _smashes := 0

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44, 35, 0); sun.light_energy = 1.5
	add_child(sun)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.4, 0.45, 0.55)
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.08, 0.09, 0.13)
	add_child(we)
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(80, 80); floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new(); fmat.albedo_color = Color(0.16, 0.17, 0.2)
	floor_mi.material_override = fmat
	nav.add_child(floor_mi)
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(80, 1, 80)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0); sb.add_child(cs); nav.add_child(sb)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 2.4; nm.cell_size = 0.3
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh()
	await get_tree().create_timer(0.4).timeout

	_player = CharacterBody3D.new()
	_player.add_to_group("player")
	_player.collision_layer = 2; _player.collision_mask = 1
	var pcs := CollisionShape3D.new(); var pcap := CapsuleShape3D.new()
	pcap.radius = 0.4; pcap.height = 1.7; pcs.shape = pcap; pcs.position = Vector3(0, 0.9, 0)
	_player.add_child(pcs)
	var pdmg := Damageable.new(); pdmg.name = "Damageable"; pdmg.max_health = 2000.0
	_player.add_child(pdmg)
	add_child(_player)
	_player.global_position = Vector3(0, 1.0, 16)

	_boss = (load("res://scenes/enemies/smasher.tscn") as PackedScene).instantiate()
	add_child(_boss)
	_boss.global_position = Vector3(0, 0.5, -8)

	_cam = Camera3D.new(); add_child(_cam)
	_cam.global_position = Vector3(16, 11, 20)
	_cam.look_at(Vector3(0, 6, -2), Vector3.UP)

	var shots := [1.6, 3.2, 5.0, 7.0, 9.0]
	var elapsed := 0.0
	var si := 0
	while elapsed < 9.5:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if si < shots.size() and elapsed >= shots[si]:
			await _grab("sm_%d" % si)
			si += 1
	var dmg: float = 2000.0 - (_player.get_node("Damageable") as Damageable).current_health
	print("SMASHER boss_alive=%s player_dmg=%.0f" % [is_instance_valid(_boss), dmg])
	print("SMASHER ", "OK" if dmg > 0.0 else "PARTIAL (no hit landed yet)")
	get_tree().quit()

func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/" + name + ".png")
	print("  shot ", name)
