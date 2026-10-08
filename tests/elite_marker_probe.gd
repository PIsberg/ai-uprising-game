extends Node
## Elite affix markers must be told apart by SHAPE, not colour alone (#150):
## the spinning marker above an elite is the identity cue the first-encounter
## toast tells the player to rely on, and a colourblind player (or anyone in a
## busy, colour-graded level) cannot rely on hue. For every affix the probe
## spawns a real elite through Elite.apply (pre-add, the spawner path), waits
## for the marker, and reads what is actually there:
##   * every affix's marker has a different silhouette (the set of mesh types
##     and their rounded sizes under EliteMarker);
##   * every pair of marker colours is at least MIN_COLOR_GAP apart in RGB, so
##     the colour is still a useful second cue for normal vision.
##   godot --headless --path . --audio-driver Dummy res://tests/elite_marker_probe.tscn

const MIN_COLOR_GAP := 0.3

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

static func _signature(marker: Node) -> String:
	var parts: Array[String] = []
	for mi in marker.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var s := m.get_aabb().size * (mi as Node3D).scale
		parts.append("%s(%.2f,%.2f,%.2f)" % [m.get_class(), s.x, s.y, s.z])
	parts.sort()
	return ", ".join(parts)

func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	add_child(floor_body)

	var scene: PackedScene = load("res://scenes/enemies/android.tscn")
	var sigs := {}
	var x := -8.0
	for kind in Elite.KINDS:
		var e: Node3D = scene.instantiate()
		Elite.apply(e, kind)
		e.position = Vector3(x, 0.1, 0)
		x += 4.0
		add_child(e)
		e.set_physics_process(false)
		for i in 10:
			await get_tree().process_frame
		var marker := e.get_node_or_null("EliteMarker")
		_check(marker != null, "%s elite has a marker" % kind)
		if marker:
			sigs[kind] = _signature(marker)
			print("       %s: %s" % [kind, sigs[kind]])

	var kinds: Array = sigs.keys()
	for i in kinds.size():
		for j in range(i + 1, kinds.size()):
			_check(sigs[kinds[i]] != sigs[kinds[j]],
				"%s and %s markers differ in shape" % [kinds[i], kinds[j]])

	for i in Elite.KINDS.size():
		for j in range(i + 1, Elite.KINDS.size()):
			var a: Color = Elite.AFFIX_COLORS[Elite.KINDS[i]]
			var b: Color = Elite.AFFIX_COLORS[Elite.KINDS[j]]
			var d := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			_check(d >= MIN_COLOR_GAP, "%s vs %s marker colours %.2f apart (need %.2f)"
				% [Elite.KINDS[i], Elite.KINDS[j], d, MIN_COLOR_GAP])

	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit(0 if _fail.is_empty() else 1)
