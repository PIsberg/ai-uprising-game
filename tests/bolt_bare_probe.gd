extends Node3D
## Bare-scene isolation: the exact bolt material on tall columns at 30/60/90 m
## with NO level, NO environment. Determines whether distant transparent
## unshaded surfaces are being culled by the engine or by level setup.

const SHOT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/95a1d0e0-6d29-460c-8157-97f2f1fe8e7d/scratchpad/bolt_bare.png"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 5, 0)
	cam.look_at(Vector3(0, 20, -60), Vector3.UP)
	cam.current = true
	for d in [30.0, 60.0, 90.0]:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.disable_fog = true
		mat.albedo_color = Color(0.85, 0.9, 1.0, 0.95)
		mat.emission_enabled = true
		mat.emission = Color(0.75, 0.85, 1.0)
		mat.emission_energy_multiplier = 6.0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2, 40, 2)
		bm.material = mat
		mi.mesh = bm
		add_child(mi)
		mi.global_position = Vector3((d - 60.0) * 0.7, 20, -d)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(SHOT)
	print("SAVED ", SHOT)
	get_tree().quit()
