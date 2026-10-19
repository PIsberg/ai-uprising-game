extends Node3D
## Windowed look check for NETWORK BREACH: a lit yard with a sentry turret dead
## ahead, an explosive barrel and a laser gate to the sides and a robot behind,
## photographed mid-scan (tint, marks, the picked target's label and cost, the
## bandwidth bar). Writes <out>/network_breach.png.
##   godot --path . res://tests/network_breach_shot.tscn -- --out=<dir>

var out := "user://"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.08, 0.1, 0.14)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.4, 0.45, 0.5)
	add_child(we)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	fl.mesh = pm
	add_child(fl)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 80)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	add_child(sb)
	GameState.set_state(GameState.State.PLAYING)
	var p: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector3(0, 0.1, 0)
	var turret := SentryTurret.new()
	add_child(turret)
	turret.global_position = Vector3(0.6, 0, -12)
	var barrel: Node3D = (load("res://scenes/props/barrel.tscn") as PackedScene).instantiate()
	add_child(barrel)
	barrel.global_position = Vector3(-5, 0, -10)
	var gate := LaserGate.new()
	add_child(gate)
	gate.global_position = Vector3(5, 0, -9)
	var bot: Node3D = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(bot)
	bot.global_position = Vector3(-2.5, 0, -20)
	await _frames(30)
	Input.action_press(NetworkBreach.ACTION)
	await _frames(20)
	get_viewport().get_texture().get_image().save_png(out.path_join("network_breach.png"))
	Input.action_release(NetworkBreach.ACTION)
	Engine.time_scale = 1.0
	print("RESULT PASS")
	get_tree().quit()
