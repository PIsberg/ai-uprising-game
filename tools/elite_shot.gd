extends Node3D
## Verifies the on-body elite marker (scripts/systems/elite.gd): spawns 3
## androids, force-applies a distinct affix to each BEFORE add_child (mirrors
## how enemy_spawner.gd calls Elite.maybe_apply pre-add), screenshots the
## lineup so the three marker colours are visible, then kills one and checks
## the marker fades out with it.
##   godot --path . --quit-after 1200 res://tools/elite_shot.tscn

const SHOT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/df4a3e78-e161-445d-96b9-6124bf321864/scratchpad"
const ANDROID := preload("res://scenes/enemies/android.tscn")
const KINDS := ["shielded", "volatile", "swift"]

var _elites: Array[EnemyBase] = []

func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	body.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.35, 0.37, 0.42)
	pm.material = fmat
	fl.mesh = pm
	add_child(fl)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.12, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 0.8
	we.environment = env
	add_child(we)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.position = Vector3(0, 1, 40)
	add_child(player)

	for i in KINDS.size():
		var e := ANDROID.instantiate() as EnemyBase
		# Force-apply the affix pre-add — same entry point enemy_spawner.gd uses
		# via Elite.maybe_apply, just skipping the random roll for a deterministic probe.
		Elite.apply(e, KINDS[i])
		e.position = Vector3((i - 1) * 3.0, 0.6, 0)
		e.rotation.y = PI
		add_child(e)
		if e.has_method("set_process"):
			e.set_process(false)
		_elites.append(e)

	await get_tree().create_timer(1.5).timeout # let the marker attach + settle

	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.6, 8), Vector3(0, 1.6, 0), Vector3.UP)
	cam.make_current()
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + "/elites.png")
	print("SAVED elites.png")

	# Kill check: the marker must stop spinning and fade out with the enemy.
	var target := _elites[0]
	var marker := target.get_node_or_null("EliteMarker")
	if marker == null:
		print("FAIL: no EliteMarker found on the shielded elite before the kill")
		get_tree().quit()
		return
	target.hp.apply_damage(99999.0)
	await get_tree().create_timer(0.8).timeout
	if not is_instance_valid(marker):
		print("PASS: marker freed after kill")
	else:
		var mat: StandardMaterial3D = null
		if marker.get_child_count() > 0:
			mat = (marker.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
		var a := mat.albedo_color.a if mat else -1.0
		if mat and a <= 0.05:
			print("PASS: marker alpha faded to %.3f after kill" % a)
		else:
			print("FAIL: marker alpha still %.3f after kill (expected ~0)" % a)
	get_tree().quit()
