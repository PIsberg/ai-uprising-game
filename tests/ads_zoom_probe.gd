extends Node3D
## Live physics probe: holding "aim" (RMB) must actually zoom the camera —
## fov converges near the equipped weapon's ads_fov instead of being reset by
## a competing writer — and releasing must return it to the base fov.
## Run: godot --headless --path . --audio-driver Dummy res://tests/ads_zoom_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

func _ready() -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var floor_body := StaticBody3D.new(); floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new(); var fbs := BoxShape3D.new(); fbs.size = Vector3(60, 1, 60)
	fcs.shape = fbs; fcs.position = Vector3(0, -0.5, 0); floor_body.add_child(fcs)
	nav.add_child(floor_body)
	add_child(DirectionalLight3D.new())

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	var cam := player.get_node("Head/Camera3D") as Camera3D
	var wm := player.get_node("Head/Camera3D/WeaponHolder")
	await get_tree().create_timer(0.5).timeout

	var base_fov := cam.fov
	Input.action_press("aim")
	for i in 90: # 1.5s: plenty for the 10/s ads lerp + fov blend to converge
		await get_tree().physics_frame
	var aimed_fov := cam.fov
	var target: float = wm.ads_target_fov()
	Input.action_release("aim")
	for i in 90:
		await get_tree().physics_frame
	var released_fov := cam.fov

	print("ADS base=%.1f aimed=%.1f (weapon target %.1f) released=%.1f" % [
		base_fov, aimed_fov, target, released_fov])
	var zoomed := aimed_fov < base_fov - 8.0 and absf(aimed_fov - target) < 4.0
	var returned := absf(released_fov - base_fov) < 4.0
	print("RESULT %s" % ("PASS" if zoomed and returned else "FAIL"))
	get_tree().quit()
