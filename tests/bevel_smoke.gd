extends Node3D
## Headless smoke test: BeveledBoxMesh must instance from a .tscn sub_resource
## and from code, and produce non-empty geometry.

func _ready() -> void:
	var from_scene := $MI.mesh as Mesh
	var n_scene := 0
	if from_scene and from_scene.get_surface_count() > 0:
		n_scene = from_scene.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var from_code := BeveledBoxMesh.new()
	from_code.size = Vector3(2, 1, 0.5)
	from_code.bevel = 0.04
	var n_code := 0
	if from_code.get_surface_count() > 0:
		n_code = from_code.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	print("BEVEL_SMOKE scene_verts=%d code_verts=%d" % [n_scene, n_code])
	get_tree().quit(0 if (n_scene == 96 and n_code == 96) else 1)
