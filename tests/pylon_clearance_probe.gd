extends Node
## Probe: no outdoor light mast stands inside walkable geometry (#290). An
## outdoor light gets a floodlight mast from the ground up to it
## (LevelBuilder group "light_pylon"), and it was placed before any ramp, bridge
## or platform existed: titan's centre light put a 9 m pole through the
## SkyBridge deck at its midpoint, where it stopped a walking player dead.
## For every builder level: each mast's column (its radius, from 0.3 m up to
## just under the light) overlaps no world body but itself, and open-sky levels
## still get masts (the guard skips a mast, it must not skip them all).
##   godot --headless --path . --audio-driver Dummy res://tests/pylon_clearance_probe.tscn

const IDS := [
	"01", "gpt", "gemini", "claude", "grok", "suburb", "suburb_boss", "mistral",
	"overseer", "alien", "uplink", "assembly", "titan", "archon", "range",
	"horde", "sublevel", "crucible", "frostbreak", "neon", "lava_world",
	"water_world", "desert", "convoy", "guardrails", "hivemind",
]

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var masts := 0
	for id in IDS:
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			continue
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		for i in 3:
			await get_tree().physics_frame
		var space := get_viewport().world_3d.direct_space_state
		var bad: Array[String] = []
		var n := 0
		for p in get_tree().get_nodes_in_group("light_pylon"):
			var body := p as StaticBody3D
			var cyl := (body.get_child(0) as CollisionShape3D).shape as CylinderShape3D
			var top := body.global_position.y + cyl.height * 0.5
			var probe := CylinderShape3D.new()
			probe.radius = cyl.radius
			probe.height = top - 0.6
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = probe
			q.transform = Transform3D(Basis(), Vector3(body.global_position.x, 0.3 + probe.height * 0.5, body.global_position.z))
			q.collision_mask = 1
			q.exclude = [body.get_rid()]
			n += 1
			for hit in space.intersect_shape(q, 4):
				bad.append("mast at %s through %s" % [Vector3(body.global_position.x, top, body.global_position.z),
					(hit["collider"] as Node).get_path()])
		masts += n
		_check("%s: no light mast stands inside geometry" % id, bad.is_empty(), "%d masts; %s" % [n, "; ".join(bad)])
		lvl.queue_free()
		for i in 2:
			await get_tree().process_frame
	_check("outdoor levels still get light masts", masts >= 20, "%d in all" % masts)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
