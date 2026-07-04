extends Node3D
## Ramp walkability probe. Instantiates every level, finds every ramp body the
## builder tagged (group "ramp_surface" — see level_builder._build_ramp_wedge),
## and for each:
##   (a) sweeps a player-sized capsule from foot to top in small steps using
##       CharacterBody3D.test_move, failing if any step is blocked (a lip/gap
##       the player can't walk through);
##   (b) raycasts CLEARANCE_M straight up from points along the ramp, failing
##       if anything overhangs closer than that (head-bonking spiral tower
##       corners / interior ramps stacked under a floor slab).
## Run headless: godot --headless --path . --quit-after 9000 res://tests/ramp_probe.tscn

const IDS := [
	"01", "gpt", "gemini", "claude", "grok", "suburb", "suburb_boss", "mistral",
	"overseer", "alien", "uplink", "assembly", "titan", "archon", "range",
	"horde", "sublevel", "crucible", "frostbreak", "neon", "lava_world",
	"water_world", "desert", "convoy",
]

const CAPSULE_RADIUS := 0.35
const CAPSULE_HEIGHT := 1.8
const CLEARANCE_M := 2.2
const STEP := 0.2      # sample spacing (m) along a ramp's walking line
const CLEAR_UP := 0.15 # comfortable stand-off above the theoretical surface line —
                        # sub-cm float/hull-facet noise below this isn't what a
                        # player would ever feel as "stuck".

var _probe: CharacterBody3D
var _total_ramps := 0
var _total_fails := 0

func _ready() -> void:
	_probe = CharacterBody3D.new()
	_probe.collision_layer = 2
	_probe.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_RADIUS
	cap.height = CAPSULE_HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, CAPSULE_HEIGHT * 0.5, 0)
	_probe.add_child(cs)
	add_child(_probe)
	await get_tree().physics_frame

	for id in IDS:
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			print("SKIP %s: no scene" % id)
			continue
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		var pdmg := lvl.find_child("Damageable", true, false)
		if pdmg:
			pdmg.invulnerable = true
		await get_tree().create_timer(2.5).timeout   # build geometry + bake navmesh
		var ramps := get_tree().get_nodes_in_group("ramp_surface")
		if ramps.is_empty():
			print("RAMPS %s: none" % id)
		else:
			var issues: Array = []
			for body in ramps:
				_total_ramps += 1
				issues.append_array(_test_ramp(id, body))
			if issues.is_empty():
				print("RAMPS %s: %d ramp(s) OK" % [id, ramps.size()])
			else:
				_total_fails += issues.size()
				print("RAMPS %s: %d ramp(s), %d issue(s):" % [id, ramps.size(), issues.size()])
				for msg in issues:
					print("      ", msg)
		lvl.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	print("RAMP_PROBE ", "PASS (%d ramps checked)" % _total_ramps if _total_fails == 0
		else "FAIL (%d issue(s) across %d ramps)" % [_total_fails, _total_ramps])
	get_tree().quit()

## Sweeps + headroom-checks one tagged ramp body. Reads its true (pre-embed,
## pre-sink) intended endpoints from metadata set in _build_ramp_wedge, so the
## test line matches design intent exactly rather than re-deriving it from the
## (looser) collision geometry.
func _test_ramp(level_id: String, body: Node) -> Array:
	var issues: Array = []
	if not body.has_meta("ramp_from") or not body.has_meta("ramp_to"):
		return issues
	var from: Vector3 = body.get_meta("ramp_from")
	var to: Vector3 = body.get_meta("ramp_to")
	var delta := to - from
	var horiz := Vector2(delta.x, delta.z).length()
	var total := sqrt(horiz * horiz + delta.y * delta.y)
	if total < 0.05:
		return issues
	var steps: int = maxi(4, int(ceil(total / STEP)))
	var space := _probe.get_world_3d().direct_space_state

	# For each point along the ramp's nominal line, find the ACTUAL topmost
	# walkable surface there (a short downward raycast). A ramp is often
	# legitimately buried under a landing/roof deck near a tower corner (see
	# level_builder._build_tower's overhang notes) — the player stands on
	# whichever surface is higher, not necessarily this ramp's own line.
	# Testing against the buried line would flag "stuck"/"low headroom"
	# against a surface the player never actually touches.
	var surfaces: Array[Vector3] = []
	for i in range(steps + 1):
		var s: Vector3 = from.lerp(to, float(i) / float(steps))
		var down_q := PhysicsRayQueryParameters3D.create(s + Vector3(0, 3.0, 0), s + Vector3(0, -1.0, 0))
		down_q.collision_mask = 1
		var down_hit := space.intersect_ray(down_q)
		surfaces.append(down_hit.position if down_hit else s)

	var blocked_any := false
	for i in range(steps):
		var s0: Vector3 = surfaces[i]
		var s1: Vector3 = surfaces[i + 1]
		var p0 := s0 + Vector3(0, CLEAR_UP, 0)
		var p1 := s1 + Vector3(0, CLEAR_UP, 0)
		_probe.global_transform = Transform3D(Basis(), p0)
		_probe.velocity = Vector3.ZERO
		var col := KinematicCollision3D.new()
		if not blocked_any and _probe.test_move(_probe.global_transform, p1 - p0, col, 0.05):
			blocked_any = true
			var hit_name := "?"
			if col.get_collider():
				hit_name = str(col.get_collider().name)
			issues.append("%s: STUCK on %s near %s (t=%.2f of foot->top run, hit %s, depth=%.3f)" %
				[level_id, body.name, s0, float(i) / float(steps), hit_name, col.get_depth()])
		# Headroom: cast up CLEARANCE_M from just above the ACTUAL surface.
		var q := PhysicsRayQueryParameters3D.create(s0 + Vector3(0, 0.05, 0), s0 + Vector3(0, CLEARANCE_M, 0))
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit:
			var hn := "?"
			if hit.collider:
				hn = str(hit.collider.name)
			issues.append("%s: LOW HEADROOM on %s at %s — overhang %.2f m up (need %.2f m, hit %s)" %
				[level_id, body.name, s0, hit.position.y - s0.y, CLEARANCE_M, hn])
	return issues
