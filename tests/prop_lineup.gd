extends Node3D
## Dev probe: lines up the prop scenes so model swaps can be eyeballed;
## saves user://prop_lineup.png and quits. Run windowed:
##   godot --path . res://tests/prop_lineup.tscn

const PROPS := [
	"res://scenes/props/crate.tscn",
	"res://scenes/props/barrel.tscn",
	"res://scenes/props/gas_canister.tscn",
	"res://scenes/props/locker.tscn",
	"res://scenes/props/shelves.tscn",
	"res://scenes/props/desk.tscn",
	"res://scenes/props/satellite_dish.tscn",
	"res://scenes/props/car.tscn",
	"res://scenes/props/fence.tscn",
	"res://scenes/props/tree.tscn",
]

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.5, 0.55)
	add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 10)
	floor_mesh.mesh = pm
	add_child(floor_mesh)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.2, 9.0)
	cam.rotation_degrees = Vector3(-8, 0, 0)
	add_child(cam)
	for i in PROPS.size():
		var p: Node3D = (load(PROPS[i]) as PackedScene).instantiate()
		add_child(p)
		p.global_position = Vector3((float(i) - (PROPS.size() - 1) * 0.5) * 3.0, 0, 0)
	await get_tree().create_timer(0.6).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/prop_lineup.png")
	print("SAVED prop_lineup.png")
	get_tree().quit()
