extends Node3D
## Stages each boss's entrance on a dark arena and captures a timed frame sequence
## so every arrival can be eyeballed for "cool / effectful / unique". Windowed only
## (headless renders black). Saves to OUT/<boss>_<n>.png.
##   godot --path . --resolution 1280x720 res://tests/boss_entrance_all.tscn

const OUT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/0fc2ad91-24b1-454b-a19d-915b39dd00b0/scratchpad/bosses"

# boss id -> {scene, cam_pos, look_at, fov, shot times}
const BOSSES := [
	{"id": "titan",   "scene": "res://scenes/enemies/titan.tscn",
		"cam": Vector3(7, 5, 20), "look": Vector3(0, 4, 0), "fov": 70.0,
		"shots": [0.25, 0.5, 0.6, 0.6, 0.7]},
	{"id": "smasher", "scene": "res://scenes/enemies/smasher.tscn",
		"cam": Vector3(7, 5, 18), "look": Vector3(0, 3.5, 0), "fov": 68.0,
		"shots": [0.25, 0.4, 0.6, 0.7, 0.7]},
	{"id": "manus",   "scene": "res://scenes/enemies/manus.tscn",
		"cam": Vector3(7, 4.5, 17), "look": Vector3(0, 2.5, 0), "fov": 68.0,
		"shots": [0.3, 0.4, 0.6, 0.7, 0.8]},
]

var _cam: Camera3D
var _player: Node3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, 40, 0); key.light_energy = 0.7
	add_child(key)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.025, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.12, 0.14, 0.18); e.ambient_light_energy = 0.5
	e.glow_enabled = true; e.glow_intensity = 0.7; e.glow_bloom = 0.15
	e.glow_hdr_threshold = 1.05; e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e; add_child(env)
	var body := StaticBody3D.new(); body.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new()
	bs.size = Vector3(120, 1, 120); cs.shape = bs; cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	var fm := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(120, 120)
	var fmat := StandardMaterial3D.new(); fmat.albedo_color = Color(0.07, 0.08, 0.09); fmat.roughness = 0.6
	pm.material = fmat; fm.mesh = pm; body.add_child(fm); add_child(body)
	_cam = Camera3D.new(); add_child(_cam)
	_player = Node3D.new(); _player.add_to_group("player")
	_player.global_position = Vector3(6, 1.6, 18); add_child(_player)

	for b in BOSSES:
		await _stage(b)
	print("BOSS_ENTRANCE_ALL_DONE")
	get_tree().quit()

func _stage(b: Dictionary) -> void:
	_cam.position = b["cam"]; _cam.look_at(b["look"], Vector3.UP); _cam.fov = b["fov"]
	var boss := (load(b["scene"]) as PackedScene).instantiate() as Node3D
	boss.position = Vector3(0, 0.5, 0)   # set BEFORE add_child (EnemySpawner convention)
	add_child(boss)
	var i := 0
	for t in b["shots"]:
		await get_tree().create_timer(t, true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [OUT, b["id"], i])
		i += 1
	print("STAGED ", b["id"])
	boss.queue_free()
	# Free any entrance FX that parented to the scene (a BossPortal rift whose
	# close() never fired because we freed the boss mid-cinematic) so it can't
	# bleed into the next boss's shot.
	for c in get_children():
		if c is BossPortal:
			c.queue_free()
	await get_tree().create_timer(0.3, true, false, true).timeout
