extends Node3D
## Full-chain probe for the Tesla beam IN PLAY: real player scene (weapon
## manager drives try_fire from the "fire" action) with the tesla equipped,
## trigger held. Reports the live ElectricBeam state and saves a screenshot
## to user://tesla_ingame.png when run windowed.
##   godot --path . res://tests/tesla_ingame_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const TESLA := preload("res://scenes/weapons/tesla.tscn")

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	add_child(DirectionalLight3D.new())
	var floor_body := StaticBody3D.new(); floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new(); var fbs := BoxShape3D.new(); fbs.size = Vector3(60, 1, 60)
	fcs.shape = fbs; fcs.position = Vector3(0, -0.5, 0); floor_body.add_child(fcs)
	var fmi := MeshInstance3D.new(); var fpm := PlaneMesh.new(); fpm.size = Vector2(60, 60)
	fmi.mesh = fpm; floor_body.add_child(fmi)
	add_child(floor_body)
	# A wall ahead so the beam has something to strike.
	var wall := StaticBody3D.new(); wall.collision_layer = 1
	var wcs := CollisionShape3D.new(); var wbs := BoxShape3D.new(); wbs.size = Vector3(10, 6, 1)
	wcs.shape = wbs; wall.add_child(wcs)
	var wmi := MeshInstance3D.new(); var wbm := BoxMesh.new(); wbm.size = Vector3(10, 6, 1)
	# Mid-grey like real level geometry, so the shot judges beam readability
	# against a normal background instead of a white-clipped one.
	var wmat := StandardMaterial3D.new(); wmat.albedo_color = Color(0.38, 0.4, 0.44)
	wbm.material = wmat
	wmi.mesh = wbm; wall.add_child(wmi)
	wall.position = Vector3(0, 3, -8)
	add_child(wall)
	_run.call_deferred()

func _run() -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	await get_tree().create_timer(0.4).timeout
	var wm = player.get_node("Head/Camera3D/WeaponHolder")
	wm.add_weapon(TESLA, true)
	await get_tree().create_timer(0.6).timeout # past the equip draw delay
	Input.action_press("fire")
	for i in 40:
		await get_tree().process_frame
	var w = wm.current
	var beam = w.get("_beam")
	var core_vis := false
	var arcs_vis := 0
	if beam:
		if beam.get("_core"):
			core_vis = beam.get("_core").visible
		for seg in beam.get("_arcs"):
			if seg.visible:
				arcs_vis += 1
	print("weapon=", w.name, " mode=", w.data.fire_mode, " mag=", w.mag,
		" beam_wanted=", w.get("_beam_wanted"))
	print("beam_exists=", beam != null, " core_visible=", core_vis, " arcs_visible=", arcs_vis)
	if beam:
		var muz = w.get("muzzle")
		print("muzzle_global=", muz.global_position if muz else null)
		print("cam_global=", player.get_node("Head/Camera3D").global_position)
		var core = beam.get("_core")
		print("core_origin=", core.global_transform.origin,
			" core_scale=", core.global_transform.basis.get_scale())
		print("core_layers=", core.layers, " beam_parent=", beam.get_parent().name)
	if not DisplayServer.get_name() == "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/tesla_ingame.png")
		print("SAVED tesla_ingame.png")
		# Instance diff: park a MANUAL ElectricBeam beside the weapon's beam at
		# offset endpoints, then dump both instances' state. If the manual one
		# renders and the weapon's doesn't, the difference must be printable.
		var manual := ElectricBeam.new()
		add_child(manual)
		for i in 10:
			manual.update_beam(Vector3(-0.25, 1.40, -0.81), Vector3(-1.5, 1.53, -7.5), false)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/tesla_pair.png")
		print("SAVED tesla_pair.png")
		var bc = beam.get("_core")
		var mc = manual.get("_core")
		print("WEAPON beam: node_vis=", beam.visible, " top=", beam.top_level,
			" node_xf=", beam.global_transform)
		print("MANUAL beam: node_vis=", manual.visible, " top=", manual.top_level,
			" node_xf=", manual.global_transform)
		print("W core: vis=", bc.visible, " layers=", bc.layers, " xf=", bc.global_transform)
		print("M core: vis=", mc.visible, " layers=", mc.layers, " xf=", mc.global_transform)
		var bmat = bc.mesh.material
		var mmat = mc.mesh.material
		print("W core mat: blend=", bmat.blend_mode, " alb=", bmat.albedo_color,
			" em=", bmat.emission, " emx=", bmat.emission_energy_multiplier, " same_mat=", bmat == mmat)
		print("M core mat: blend=", mmat.blend_mode, " alb=", mmat.albedo_color,
			" em=", mmat.emission, " emx=", mmat.emission_energy_multiplier)
		manual.queue_free()
		# Side view: watch the same live beam from a detached camera so we can
		# see WHERE the geometry actually is, not just down the barrel.
		var side := Camera3D.new()
		add_child(side)
		side.global_position = Vector3(6, 2.0, -4)
		side.look_at(Vector3(0, 1.5, -4), Vector3.UP)
		side.current = true
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/tesla_side.png")
		print("SAVED tesla_side.png")
		# Bisect: with fire STILL HELD (so the weapon keeps its own beam live),
		# park a FRESH ElectricBeam across the view plus an opaque reference box.
		# Shows whether ElectricBeam is renderable at all from the player camera.
		player.get_node("Head/Camera3D").current = true
		var fresh := ElectricBeam.new()
		add_child(fresh)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(1.0, 0.3, 0.3)
		box.mesh = bm
		box.position = Vector3(-1.5, 2.4, -5.0)
		add_child(box)
		for i in 15:
			fresh.update_beam(Vector3(-2.5, 1.2, -5.0), Vector3(2.5, 2.0, -5.0), true)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/tesla_cross.png")
		print("SAVED tesla_cross.png fresh_core_vis=", fresh.get("_core").visible,
			" fresh_core_xf=", fresh.get("_core").global_transform)
		# Camera bisect: drop the player camera's CameraAttributes (auto-exposure)
		# and re-shoot the identical scene.
		var pcam := player.get_node("Head/Camera3D") as Camera3D
		pcam.attributes = null
		for i in 10:
			fresh.update_beam(Vector3(-2.5, 1.2, -5.0), Vector3(2.5, 2.0, -5.0), true)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/tesla_noattr.png")
		print("SAVED tesla_noattr.png")
		# Void test: face open blackness (no wall, no impact bloom) while firing.
		# If the beam shows here, rendering is fine and the impact/muzzle blow-out
		# is what makes it unreadable in play.
		fresh.queue_free()
		box.queue_free()
		player.rotation.y = PI * 0.5
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/tesla_void.png")
		print("SAVED tesla_void.png")
		# Detached camera at the EXACT player-camera pose, refilled mag. If the
		# beam vanishes here too, the axial viewpoint itself is the problem; if
		# it shows, something about the player camera node is.
		w.mag = 200
		player.rotation.y = 0.0
		var clone := Camera3D.new()
		add_child(clone)
		await get_tree().process_frame
		clone.fov = pcam.fov
		clone.global_transform = pcam.global_transform
		clone.current = true
		for i in 15:
			await get_tree().process_frame
		print("clone_pose beam_wanted=", w.get("_beam_wanted"), " mag=", w.mag,
			" core_vis=", beam.get("_core").visible)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/tesla_clonecam.png")
		print("SAVED tesla_clonecam.png")
	Input.action_release("fire")
	var ok := beam != null and core_vis and arcs_vis > 0
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
