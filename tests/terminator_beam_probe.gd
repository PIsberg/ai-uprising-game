extends Node3D
## Dev probe: let the TERMINATOR settle, then force its Optic Lance and confirm
## the green beam charges, fires, tracks, renders, and burns a player standing in
## it. Run windowed:
##   godot --path . res://tests/terminator_beam_probe.tscn

var _boss: Node3D
var _pdmg: Damageable

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0); sun.light_energy = 1.1
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.35, 0.38, 0.45)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.09)
	env.environment.glow_enabled = true
	add_child(env)
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(80, 1, 80)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0); sb.add_child(cs); add_child(sb)
	# A real-ish player: layer 2 + capsule so the beam raycast can hit it.
	var player := CharacterBody3D.new(); player.add_to_group("player"); player.collision_layer = 2
	var pcs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.4; cap.height = 1.7
	pcs.shape = cap; pcs.position = Vector3(0, 0.9, 0); player.add_child(pcs)
	_pdmg = Damageable.new(); _pdmg.name = "Damageable"; _pdmg.max_health = 400.0; player.add_child(_pdmg)
	add_child(player); player.global_position = Vector3(0, 1.0, 16)

	_boss = (load("res://scenes/enemies/terminator.tscn") as PackedScene).instantiate()
	_boss.position = Vector3(0, 0.5, 0)
	add_child(_boss)

	var cam := Camera3D.new(); add_child(cam)
	cam.look_at_from_position(Vector3(12, 5, 9), Vector3(0, 2.0, 8), Vector3.UP)
	cam.current = true

	# Let the eruption entrance finish and the AI engage.
	await get_tree().create_timer(2.2).timeout
	if _boss.get("_rising"):
		_boss.set("_rising", false)
		_boss.global_position = Vector3(0, 0.5, 0)
		if _boss.hp: _boss.hp.invulnerable = false
	await get_tree().create_timer(1.0).timeout
	# Force the lance now.
	_boss.set("_beam_cd", 0.0)
	await get_tree().create_timer(0.45).timeout
	_shoot(cam, "charge")
	var hp0: float = _pdmg.current_health
	await get_tree().create_timer(1.0).timeout
	_shoot(cam, "fire")
	var hp1: float = _pdmg.current_health
	print("BEAM hp_before=%.0f hp_after=%.0f burned=%s windup=%s time=%s" % [
		hp0, hp1, str(hp1 < hp0), str(_boss.get("_beam_windup")), str(_boss.get("_beam_time"))])
	await get_tree().create_timer(0.8).timeout
	_shoot(cam, "late")
	get_tree().quit()

func _shoot(cam: Camera3D, tag: String) -> void:
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/term_beam_" + tag + ".png")
	print("SAVED term_beam_", tag, ".png")
