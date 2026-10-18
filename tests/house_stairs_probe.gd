extends Node
## Probe: the real player walks up every enterable house's stairs (#290).
## An open building (def "buildings" entry with "open": true) has an interior
## ramp up its back wall to the upper floor (LevelBuilder._build_open_building,
## bodies named "HouseRamp"). The old stairwell left the ramp under the slab for
## its first 2.5 m, so in Maple Grove's 3.2 m storeys a walking player hit their
## head 1.25 m up, and level 01's 4.5 m and 6 m storeys made the short ramp
## 49 and 56 deg, past the player's slope limit. Neither could be climbed.
## For every level with open buildings: each HouseRamp is walked by the real
## Player (tests/ramp_walker.gd: walk, no jump, no sprint) to its top.
##   godot --headless --path . --audio-driver Dummy res://tests/house_stairs_probe.tscn

const Walker := preload("res://tests/ramp_walker.gd")
const IDS := ["01", "suburb", "suburb_boss"]

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var total := 0
	for id in IDS:
		var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		for i in 150: # build + navmesh bake
			await get_tree().physics_frame
		var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
		var hp = player.get("hp") if player else null
		if hp:
			hp.invulnerable = true
		for body in get_tree().get_nodes_in_group("ramp_surface"):
			if not String(body.name).begins_with("HouseRamp_"):
				continue
			total += 1
			var from: Vector3 = body.get_meta("ramp_from")
			var to: Vector3 = body.get_meta("ramp_to")
			var r: Dictionary = await Walker.walk(player, from, to)
			var slope := rad_to_deg(atan2(to.y - from.y, Vector2(to.x - from.x, to.z - from.z).length()))
			_check("%s: the player walks up the house stairs at %s" % [id, Vector3(from.x, 0, from.z)], r["ok"],
				"%.0f deg; got to y %.2f of %.2f, ended at %s" % [slope, r["best_y"], to.y, r["at"]])
		# The walker must have switched every robot off, or they shove, block and
		# knock back the walk (it once looked them up in a group nothing joins).
		var live := 0
		var robots := get_tree().get_nodes_in_group("enemy")
		for e in robots:
			if e.process_mode != Node.PROCESS_MODE_DISABLED or (e is CollisionObject3D and (e as CollisionObject3D).collision_layer != 0):
				live += 1
		_check("%s: every robot is switched off during the walks" % id, robots.size() > 0 and live == 0,
			"%d of %d still live" % [live, robots.size()])
		lvl.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	_check("found the open buildings' stairs", total >= 6, "%d" % total)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
