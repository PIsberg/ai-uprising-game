extends Node3D
## Windowed look-check of the boss presence HUD over a live boss: the intro
## card at its peak (letterbox, header, name, epithet), the notched boss bar
## with a damage trail, and the PHASE II and FINAL PHASE banners.
## Headless gives black frames.
##   godot --path . res://tests/boss_presence_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://boss_presence_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/boss_presence_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _real_wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.06, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.45, 0.45)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 25, 0)
	add_child(key)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position.y = -0.5
	body.add_child(cs)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	fm.mesh = pm
	body.add_child(fm)
	add_child(body)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(3, 3.0, 4)
	cam.look_at(Vector3(0, 5.0, -20), Vector3.UP)
	cam.make_current()
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	add_child(hud)

	var sm: Node3D = (load("res://scenes/enemies/smasher.tscn") as PackedScene).instantiate()
	add_child(sm)
	sm.global_position = Vector3(0, 0.1, -20)
	sm.set_physics_process(false) # stand there: the shot is about the HUD
	await _real_wait(2.4) # the card's clock is clamped through the spawn hitch
	await _shot("card")
	await _real_wait(3.0)
	var hp: Node = sm.get_node("Damageable")
	hp.set("invulnerable", false)
	hp.set("armor", 0.0)
	var maxh: float = hp.get("max_health")
	hp.call("apply_damage", maxh * 0.2, null)
	await _real_wait(0.15)
	await _shot("trail")
	await _real_wait(1.5)
	hp.call("apply_damage", maxh * 0.2, null) # 80 % -> 60 %: phase II
	await _real_wait(0.45)
	await _shot("phase2")
	await _real_wait(2.5)
	hp.call("apply_damage", maxh * 0.3, null) # -> 30 %: final phase
	await _real_wait(0.45)
	await _shot("final")
	Engine.time_scale = 1.0
	get_tree().quit()
