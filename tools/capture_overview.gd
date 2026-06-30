extends Node3D
## Loads a level and renders a single high 3/4 overview frame to
## docs/screenshots/overview_<id>.png — for inspecting layout/verticality.
## Run: godot --path . tools/capture_overview.tscn   (set LEVEL_ID)

const LEVEL_ID := "gpt"
const OUT := "res://docs/screenshots"
# Look-at + camera offset (authored in pre-scale-ish world units; tweak per level).
const LOOK := Vector3(19.6, 4.5, -8.4)
const CAM := Vector3(36, 13, 8)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var lvl: Node = load("res://scenes/levels/level_%s.tscn" % LEVEL_ID).instantiate()
	add_child(lvl)
	var hud := lvl.get_node_or_null("HUD")
	if hud:
		hud.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.make_current()
	cam.global_position = CAM
	cam.look_at(LOOK, Vector3.UP)
	# Strong fill so the structure reads through the level's mood fog.
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-48), deg_to_rad(35), 0)
	key.light_energy = 2.6
	add_child(key)
	var spot := OmniLight3D.new()
	spot.global_position = LOOK + Vector3(0, 6, 0)
	spot.light_energy = 6.0
	spot.omni_range = 40.0
	add_child(spot)
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/overview_%s.png" % [OUT, LEVEL_ID])
	print("OVERVIEW SAVED ", LEVEL_ID)
	get_tree().quit()
