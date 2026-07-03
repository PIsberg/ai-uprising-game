extends Node
## Headless functional check of the OPEN (enterable) building on level 1 at
## world centre (28, -, -2.8), size 8x12x8: interior is hollow, walls solid,
## the doorway is open, and the upper floor is baked walkable navmesh.
##   godot --headless --path . --audio-driver Dummy res://tests/open_house_check.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# Adding to /root inside _ready fails ("parent busy"); do it deferred.
	var lvl := (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(lvl)
	await get_tree().create_timer(2.5).timeout
	var space := lvl.get_world_3d().direct_space_state
	var solid := func(p: Vector3) -> bool:
		var q := PhysicsPointQueryParameters3D.new()
		q.position = p
		q.collision_mask = 1
		return not space.intersect_point(q, 1).is_empty()
	var ok := true
	# Interior ground hollow; back wall solid; doorway gap open; lintel solid.
	var checks := [
		["interior ground clear", Vector3(28, 1.5, -2.8), false],
		["upper floor headroom clear", Vector3(28, 8.0, -2.8), false],
		["back wall solid", Vector3(31.85, 3.0, -2.8), true],
		["side wall solid", Vector3(28, 3.0, -6.5), true],
		["doorway open at walk height", Vector3(24.2, 1.5, -2.8), false],
		["lintel above door solid", Vector3(24.2, 5.0, -2.8), true],
		["upper slab solid", Vector3(28, 6.0, -2.8), true],
		["roof solid", Vector3(28, 11.9, -2.8), true],
	]
	for c in checks:
		var got: bool = solid.call(c[1])
		var pass_c: bool = got == c[2]
		print("%-28s %s" % [c[0], "OK" if pass_c else "FAIL (solid=%s)" % got])
		if not pass_c:
			ok = false
	# Upper floor must be real navmesh (enemies/player can fight up there).
	var nav := NavigationServer3D.map_get_closest_point(lvl.get_world_3d().navigation_map, Vector3(28, 6.6, -2.8))
	var nav_ok := absf(nav.y - 6.15) < 0.5 and Vector2(nav.x - 28, nav.z + 2.8).length() < 1.5
	print("upper floor navmesh at %s -> %s" % [nav, "OK" if nav_ok else "FAIL"])
	if not nav_ok:
		ok = false
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
