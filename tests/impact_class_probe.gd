extends Node3D
## Probe: a round marks the wall the way its gun would (Impact.set_damage_class,
## BulletMark.spawn's damage_class). Each hitscan gun fires at a concrete wall
## through its real Weapon._do_hitscan:
## (1) rail slugs (Longshot, Gauss) splash cyan sparks under a cyan light and
##     leave a hole that glows hot (emission on) and cools to dark within 2.5 s;
## (2) arc rounds (Arc Coil) throw blue-white crackle under a blue light and
##     scorch with a short blue glow;
## (3) ballistic rounds (M9, AR-7) keep the surface's own sparks and a cold hole;
## (4) a Breacher blast's nine pellets each throw a smaller burst than one rifle
##     round.
##   godot --headless --path . --audio-driver Dummy res://tests/impact_class_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GraphicsSettings.quality = GraphicsSettings.Quality.HIGH # marks are skipped on LOW
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 20, 1)
	cs.shape = bs
	wall.add_child(cs)
	add_child(wall)
	wall.global_position = Vector3(0, 0, -10)
	var shooter := Node3D.new()
	add_child(shooter)
	var rifle := await _shot("rifle", shooter)
	var pistol := await _shot("pistol", shooter)
	var sniper := await _shot("sniper", shooter)
	var gauss := await _shot("gauss", shooter)
	var arc := await _shot("arccoil", shooter)
	var shotgun := await _shot("shotgun", shooter)

	for r in [rifle, pistol]:
		_check("%s: surface sparks, cold hole" % r["id"], r["spark"].is_equal_approx(_concrete_sparks())
			and r["mark_glow"] <= 0.0, "%s glow %.2f" % [r["spark"], r["mark_glow"]])
	for r in [sniper, gauss]:
		_check("%s: cyan sparks" % r["id"], r["spark"].b > 0.85 and r["spark"].r < 0.75, str(r["spark"]))
		_check("%s: cyan light" % r["id"], r["light"].g > 0.9 and r["light"].r < 0.6, str(r["light"]))
		_check("%s: hole glows hot" % r["id"], r["mark_glow"] > 1.0, "%.2f" % r["mark_glow"])
		_check("%s: hole cools to dark" % r["id"], r["mark_glow_later"] <= 0.05, "%.2f" % r["mark_glow_later"])
	_check("arc coil: blue-white crackle", arc["spark"].b > 0.9 and arc["spark"].r < 0.75, str(arc["spark"]))
	_check("arc coil: blue light", arc["light"].b > 0.9 and arc["light"].r < 0.5, str(arc["light"]))
	_check("arc coil: scorch glows blue", arc["mark_glow"] > 0.5 and arc["mark_tint"].b > arc["mark_tint"].r,
		"%.2f %s" % [arc["mark_glow"], arc["mark_tint"]])
	for r in [sniper, gauss, arc]:
		_check("%s: the energy bolt's impact ring is a thin ring, not a disc" % r["id"], r["ring_ok"])
	_check("breacher pellets each throw a smaller burst than a rifle round", shotgun["amount"] < rifle["amount"],
		"%d vs %d" % [shotgun["amount"], rifle["amount"]])
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## One hitscan from `id` straight at the wall; what its impact and mark look like.
func _shot(id: String, shooter: Node3D) -> Dictionary:
	for n in get_tree().get_nodes_in_group(BulletMark.GROUP):
		n.queue_free()
	await get_tree().process_frame
	var w: Weapon = (load("res://scenes/weapons/%s.tscn" % id) as PackedScene).instantiate()
	add_child(w)
	w._active_shooter = shooter
	var before := get_children().size()
	var tori_before := _tori()
	w._do_hitscan(Vector3(randf_range(-5, 5), 0, 0), Vector3(0, 0, -1))
	var ring_ok := true
	for t in _tori():
		if t in tori_before:
			continue
		var tm := (t as MeshInstance3D).mesh as TorusMesh
		# A ring, not a disc: the tube is a thin band of the radius.
		ring_ok = ring_ok and (tm.outer_radius - tm.inner_radius) / tm.outer_radius <= 0.25
	var impact: Node3D = null
	for c in get_children().slice(before):
		if c.has_method("set_surface"):
			impact = c
	var marks := get_tree().get_nodes_in_group(BulletMark.GROUP)
	var mark: Decal = marks[marks.size() - 1] if not marks.is_empty() else null
	var out := {"ring_ok": ring_ok, "id": id, "spark": Color.BLACK, "light": Color.BLACK, "amount": 0, "mark_glow": -1.0,
		"mark_glow_later": -1.0, "mark_tint": Color.BLACK}
	if impact:
		out["spark"] = (impact.get_node("Sparks") as CPUParticles3D).color
		out["amount"] = (impact.get_node("Sparks") as CPUParticles3D).amount
		var l := impact.get_node_or_null("Light") as OmniLight3D
		out["light"] = l.light_color if l else Color.BLACK
	if mark:
		out["mark_glow"] = mark.emission_energy if mark.texture_emission else 0.0
		out["mark_tint"] = mark.modulate
		await get_tree().create_timer(2.5).timeout
		out["mark_glow_later"] = mark.emission_energy if is_instance_valid(mark) and mark.texture_emission else 0.0
	w.queue_free()
	return out

func _tori() -> Array:
	return get_tree().root.find_children("*", "MeshInstance3D", true, false).filter(
		func(n: Node) -> bool: return (n as MeshInstance3D).mesh is TorusMesh)

func _concrete_sparks() -> Color:
	return Color(0.92, 0.88, 0.8)
