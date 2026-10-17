extends Node
## Report tool (#290): does the REAL player walk up every ramp? ramp_probe
## sweeps a bare capsule with test_move and a copy of the step-up assist; this
## drives the actual Player scene instead (its own floor snapping, step-up,
## slope limit and collision, tests/ramp_walker.gd), so a ramp ramp_probe flags
## can be told apart from one a player is really stopped on.
## Every ramp body the builder tags ("ramp_surface", ramp_from/ramp_to meta) is
## walked once per run. Builder decor is random, so run it twice and compare
## before calling a stop real. Physics time only: run with --fixed-fps so a slow
## machine does not change results.
##   godot --headless --path . --audio-driver Dummy --fixed-fps 60 res://tests/ramp_walk_triage.tscn -- levels=01,gpt
## Prints one WALK line per ramp (OK, or STOPPED with where it ended, how high
## it got and what stands in front of it) and a per-level and total summary.
## Known non-defects it reports as STOPPED: a ramp whose top lands in a zipline
## station (titan's SkyBridge: the cable carries the player away) and a walk
## that crosses a jump pad or a low-gravity field.

const Walker := preload("res://tests/ramp_walker.gd")
const IDS := [
	"01", "gpt", "gemini", "claude", "grok", "suburb", "suburb_boss", "mistral",
	"overseer", "alien", "uplink", "assembly", "titan", "archon", "range",
	"horde", "sublevel", "crucible", "frostbreak", "neon", "lava_world",
	"water_world", "desert", "convoy",
]

var _total := 0
var _stopped := 0

func _ready() -> void:
	_run.call_deferred()

func _ids() -> Array:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("levels="):
			return Array(a.substr(7).split(",", false))
	return IDS

func _run() -> void:
	for id in _ids():
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			continue
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		for i in 150: # build + navmesh bake, on the physics clock
			await get_tree().physics_frame
		var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
		if player == null:
			print("WALK %s: no player" % id)
			lvl.queue_free()
			await get_tree().process_frame
			continue
		var hp = player.get("hp")
		if hp:
			hp.invulnerable = true
		var n := 0
		var bad := 0
		for body in get_tree().get_nodes_in_group("ramp_surface"):
			if not (body.has_meta("ramp_from") and body.has_meta("ramp_to")):
				continue
			n += 1
			var from: Vector3 = body.get_meta("ramp_from")
			var to: Vector3 = body.get_meta("ramp_to")
			var r: Dictionary = await Walker.walk(player, from, to)
			if r["ok"]:
				print("WALK %s OK %s [%s -> %s]" % [id, body.name, from, to])
				continue
			bad += 1
			var p: Vector3 = r["at"]
			print("WALK %s STOPPED %s [%s -> %s] at %s (got to y %.2f of %.2f, %.1f m short; ahead: %s)" % [
				id, body.name, from, to, p, float(r["best_y"]), to.y, Vector2(p.x - to.x, p.z - to.z).length(), _ahead(player, to)])
		_total += n
		_stopped += bad
		print("WALKS %s: %d ramp(s), %d stopped" % [id, n, bad])
		lvl.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("RAMP_WALK %d ramp(s), %d stopped" % [_total, _stopped])
	get_tree().quit()

## What stands in front of the player at ankle, knee and chest height toward
## `to`: the collider's path, and its shape's world bounds.
func _ahead(player: CharacterBody3D, to: Vector3) -> String:
	var d := Vector3(to.x - player.global_position.x, 0, to.z - player.global_position.z).normalized()
	var out: Array[String] = []
	for h in [0.1, 0.45, 1.2]:
		var o: Vector3 = player.global_position + Vector3.UP * h
		var q := PhysicsRayQueryParameters3D.create(o, o + d * 1.0, 1)
		q.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			var c: Node = hit.collider
			var shape := ""
			for cs in c.get_children():
				if cs is CollisionShape3D and (cs as CollisionShape3D).shape:
					var s := (cs as CollisionShape3D).shape
					var ab: AABB = (cs as Node3D).global_transform * s.get_debug_mesh().get_aabb()
					shape = " %s spanning %s..%s" % [s.get_class(), ab.position, ab.end]
					break
			out.append("%.2fm %s%s" % [h, str(c.get_path()) if c.is_inside_tree() else str(c.name), shape])
	return ", ".join(out) if not out.is_empty() else "nothing within 1 m"
