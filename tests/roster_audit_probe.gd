extends Node3D
## Spawns every enemy on a lit floor in labelled groups and screenshots each
## group close-up, so model LOOK can be compared against stats (hp/speed/attack).
##   godot --path . tests/roster_audit_probe.tscn
## Saves user://roster_<n>.png

# Grouped so each shot holds a readable number of models. Order roughly by role.
const GROUPS := [
	["skitter", "spider", "seeker", "drone", "reaper", "dog"],           # small/fast
	["hunter", "raptor", "fishbot", "vacuum", "gunslinger", "optic"],    # light skirmishers
	["strider", "sniper", "gunner", "sentinel", "warbot", "enforcer"],   # ranged troopers
	["orb", "roller", "breaker", "whirlwind", "mauler", "ravager"],      # melee/rush
	["brute", "server", "ripper", "android", "mech", "mender"],          # mid bruisers/support
	["ronin", "howitzer", "bowler", "shark", "terminator"],              # heavies/special
	["colossus", "titan", "smasher", "manus", "overseer", "archon"],     # bosses
]

var _shot := 0

func _ready() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	body.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.32, 0.34, 0.4)
	pm.material = fmat
	fl.mesh = pm
	add_child(fl)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.12, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	we.environment = env
	add_child(we)
	# A far-away fake player so enemies orient forward but don't path far.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.position = Vector3(0, 1, 400)
	add_child(player)

	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.make_current()

	for g in GROUPS:
		var nodes: Array = []
		for i in g.size():
			var n := _spawn(g[i], Vector3((i - (g.size() - 1) * 0.5) * 4.0, 0.6, 0))
			nodes.append(n)
		await get_tree().create_timer(1.2).timeout # settle + let _ready scale run
		# Freeze so they stop moving/attacking for the shot.
		for n in nodes:
			if is_instance_valid(n):
				n.set_process(false)
				n.set_physics_process(false)
		var span: float = g.size() * 4.0
		cam.look_at_from_position(Vector3(0, 2.2, span * 0.62 + 6.0), Vector3(0, 1.2, 0), Vector3.UP)
		for i in 12:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/roster_%d.png" % _shot)
		print("SAVED roster_%d : %s" % [_shot, ", ".join(g)])
		_shot += 1
		for n in nodes:
			if is_instance_valid(n):
				n.queue_free()
		await get_tree().process_frame
	print("DONE")
	get_tree().quit()

func _spawn(id: String, pos: Vector3) -> Node3D:
	var b: Node3D = (load("res://scenes/enemies/%s.tscn" % id) as PackedScene).instantiate()
	add_child(b)
	b.global_position = pos
	b.rotation.y = PI
	# Disable damageable death etc. by just leaving them; add a name tag.
	var lbl := Label3D.new()
	lbl.text = id.to_upper()
	lbl.font_size = 96
	lbl.pixel_size = 0.006
	lbl.position = Vector3(0, 3.4, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate = Color(1, 1, 0.6)
	lbl.outline_size = 24
	b.add_child(lbl)
	return b
