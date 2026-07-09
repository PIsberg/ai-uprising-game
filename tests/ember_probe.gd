extends Node3D
## Do lava beds build ember emitters, with a visibility_aabb big enough that
## they don't get frustum-culled the moment you look away? (The classic
## GPUParticles3D default-AABB bug.) Also: water/coolant beds must NOT spark.

var _ok := true
func _check(n: String, c: bool, d: String = "") -> void:
	print("%s %s %s" % ["ok  " if c else "BAD ", n, d])
	if not c: _ok = false

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	var beds := get_tree().get_nodes_in_group("hazard")
	_check("gpt has lava beds", beds.size() == 2, str(beds.size()))
	var lit := 0
	for b in beds:
		var lights := (b as Node).find_children("*", "OmniLight3D", false, false)
		lit += lights.size()
		var ps := (b as Node).find_children("*", "GPUParticles3D", false, false)
		_check("bed sparks", ps.size() == 1, "%d emitters" % ps.size())
		if ps.size() == 1:
			var p := ps[0] as GPUParticles3D
			_check("  emitting", p.emitting)
			_check("  amount scales with bed", p.amount >= 12, str(p.amount))
			var a := p.visibility_aabb
			_check("  aabb spans the bed", a.size.x > 5.0 and a.size.y > 2.0, str(a.size))
	# A line of lamps, not one blob (HIGH tier default -> up to 5 per long bed).
	_check("lava lit as a channel", lit >= 6, "%d lamps across %d beds" % [lit, beds.size()])

	# Water pools must not throw embers.
	var w := LavaHazard.new()
	w.water = true
	w.size = Vector2(8, 8)
	add_child(w)
	await get_tree().process_frame
	_check("water pool does not spark",
		w.find_children("*", "GPUParticles3D", false, false).is_empty())
	print("RESULT ", "PASS" if _ok else "FAIL")
	get_tree().quit()
