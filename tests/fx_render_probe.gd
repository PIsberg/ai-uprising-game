extends Node3D
## Render the energy-bolt flash (gauss) + new impact shock-ring to verify the
## later-weapon FX upgrade.
##   godot --path . res://tests/fx_render_probe.tscn

const OUT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/fx_bolt.png"

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.05, 0.08)
	e.glow_enabled = true
	e.glow_intensity = 0.8
	env.environment = e
	add_child(env)
	# A wall to catch the bolt so the ring sits on a surface.
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(4, 4, 0.2)
	wall.mesh = bm
	var wmat := StandardMaterial3D.new(); wmat.albedo_color = Color(0.2, 0.22, 0.26)
	wall.material_override = wmat
	wall.position = Vector3(3, 0, 0)
	add_child(wall)
	var cam := Camera3D.new()
	cam.position = Vector3(1.4, 0.7, 2.8)
	cam.look_at_from_position(cam.position, Vector3(1.6, 0, 0), Vector3.UP)
	add_child(cam)
	var w: Node3D = load("res://scenes/weapons/gauss.tscn").instantiate()
	add_child(w)
	_run.call_deferred(w)

func _run(w) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	w._energy_beam_flash(Vector3(0, 0, 0), Vector3(2.9, 0, 0))
	await get_tree().create_timer(0.09).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("SAVED ", OUT)
	get_tree().quit()
