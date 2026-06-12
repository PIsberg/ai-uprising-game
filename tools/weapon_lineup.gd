# Dev probe: renders every player weapon scene (real models applied by
# weapon.gd) in a grid and saves user://weapon_lineup.png, then quits. Run:
#   godot --path . --resolution 1280x720 --script tools/weapon_lineup.gd
extends SceneTree

const WEAPONS := ["pistol", "smg", "rifle", "shotgun", "plasma",
	"gauss", "tesla", "arccoil", "twinrail", "devastator"]

func _init() -> void:
	var root_node := Node3D.new()
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.2, 2.6)
	root_node.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	root_node.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.22, 0.26)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 1.0
	env.environment = e
	root_node.add_child(env)
	for i in WEAPONS.size():
		var ps: PackedScene = load("res://scenes/weapons/%s.tscn" % WEAPONS[i])
		if ps == null:
			continue
		var inst := ps.instantiate() as Node3D
		inst.position = Vector3((i % 5) * 1.25 - 2.5, 0.7 - floorf(i / 5.0) * 1.0, 0)
		inst.rotation.y = PI * 0.5 # muzzle (-Z) to screen-left
		root_node.add_child(inst)
		var lbl := Label3D.new()
		lbl.text = WEAPONS[i]
		lbl.font_size = 48
		lbl.position = inst.position + Vector3(0, 0.4, 0)
		root_node.add_child(lbl)
	get_root().add_child(root_node)
	_capture()

func _capture() -> void:
	for i in 12:
		await process_frame
	var img := get_root().get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/weapon_lineup.png")
	print("SAVED ", OS.get_user_data_dir() + "/weapon_lineup.png")
	quit()
