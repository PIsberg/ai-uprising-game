extends Node
## Probe: the megacity skyline round every open-sky level (scripts/levels/skyline.gd).
## For every open-sky level's plan:
## (1) it is the same city every time the level loads (seeded by the level);
## (2) no tower, tier or spire stands within MARGIN of the floor;
## (3) the near ring rises over the perimeter wall and the far ring stands
##     tall behind it: NEAR_MIN_TALL near towers top 2.5x the wall, FAR_MIN
##     far towers stand past the near ring and top 40 m;
## (4) the hero landmark stays framed: no far tower inside LANDMARK_CLEAR of its
##     bearing and nothing near inside LANDMARK_FRAME taller than FRAME_H;
## (5) every aviation beacon sits on top of a spire or roof;
## (6) SIGN_COUNT billboards, past the floor, each facing the arena;
## and once built for real: interiors get no skyline; one tower draw holding
## every planned box, one beacon draw, one panel draw, a Label3D per sign, and
## nothing casts a shadow.
##   godot --headless --path . --audio-driver Dummy res://tests/skyline_probe.tscn

const MARGIN := 10.0
const NEAR_MIN_TALL := 6
const FAR_MIN := 20
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var open_ids: Array = []
	for id in LevelDefs._defs().keys():
		if LevelDefs.get_def(id).get("open_sky", false):
			open_ids.append(id)
	_check("open-sky levels found", open_ids.size() >= 10, str(open_ids.size()))
	for id in open_ids:
		_check_plan(id, LevelDefs.get_def(id))

	# Built for real.
	var interior_id := ""
	for id in LevelDefs._defs().keys():
		if not LevelDefs.get_def(id).get("open_sky", false):
			interior_id = id
			break
	var holder := Node3D.new()
	add_child(holder)
	_check("interior (%s): no skyline" % interior_id,
			Skyline.build_for(holder, LevelDefs.get_def(interior_id), Color.CYAN, false) == null)
	var def: Dictionary = LevelDefs.get_def(open_ids[0])
	var plan := Skyline.plan(def)
	var sk := Skyline.build_for(holder, def, Color.CYAN, false)
	_check("open sky: skyline built", sk != null and sk.get_parent() == holder)
	var mms := sk.find_children("*", "MultiMeshInstance3D", true, false)
	var counts: Array = []
	for m in mms:
		counts.append((m as MultiMeshInstance3D).multimesh.instance_count)
	_check("three batched draws (towers, beacons, sign panels)", mms.size() == 3, str(counts))
	_check("tower draw holds every planned box", plan["towers"].size() in counts, "%d in %s" % [plan["towers"].size(), counts])
	_check("beacon draw holds every beacon", plan["beacons"].size() in counts)
	_check("a Label3D per sign", sk.find_children("*", "Label3D", true, false).size() == Skyline.SIGN_COUNT)
	var casters := 0
	for g in sk.find_children("*", "GeometryInstance3D", true, false):
		if (g as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casters += 1
	_check("nothing casts a shadow", casters == 0, str(casters))

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _check_plan(id: String, def: Dictionary) -> void:
	var plan := Skyline.plan(def)
	var again := Skyline.plan(def)
	_check("%s: same city every load" % id, var_to_str(plan) == var_to_str(again))
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var base := maxf(fs.x, fs.y) * 0.5
	var towers: Array = plan["towers"]
	var inside := 0
	var near_tall := 0
	var far := 0
	var lm_bad := 0
	var has_lm := String(def.get("landmark", {}).get("kind", "")) != "none"
	var h := Landmark.heading_for(def)
	var lm_ang := atan2(h.x, h.z)
	for t in towers:
		var p: Vector3 = t["pos"]
		var s: Vector3 = t["size"]
		var r := maxf(s.x, s.z) * 0.71
		if absf(p.x) - r < fs.x * 0.5 + MARGIN and absf(p.z) - r < fs.y * 0.5 + MARGIN:
			inside += 1
		var top := p.y + s.y * 0.5
		var off := absf(angle_difference(atan2(p.x, p.z), lm_ang))
		if not t.get("far", false):
			if top > 2.5 * LevelBuilder.WALL_HEIGHT:
				near_tall += 1
			if has_lm and off < Skyline.LANDMARK_FRAME and top > Skyline.FRAME_H + 0.01:
				lm_bad += 1
		else:
			if t.get("base", false) and top > 40.0:
				far += 1
			if has_lm and off < Skyline.LANDMARK_CLEAR:
				lm_bad += 1
	_check("%s: nothing within %d m of the floor" % [id, MARGIN], inside == 0, str(inside))
	_check("%s: near ring rises over the wall" % id, near_tall >= NEAR_MIN_TALL, str(near_tall))
	_check("%s: far ring stands tall behind it" % id, far >= FAR_MIN, str(far))
	_check("%s: the landmark stays framed" % id, lm_bad == 0, str(lm_bad))
	var loose := 0
	for b in plan["beacons"]:
		var on_top := false
		for t in towers:
			var p: Vector3 = t["pos"]
			var s: Vector3 = t["size"]
			if Vector2(b.x - p.x, b.z - p.z).length() < maxf(s.x, s.z) * 0.71 \
					and absf(b.y - (p.y + s.y * 0.5)) < 0.6:
				on_top = true
				break
		if not on_top:
			loose += 1
	_check("%s: beacons on tops" % id, plan["beacons"].size() > 0 and loose == 0,
			"%d beacons, %d loose" % [plan["beacons"].size(), loose])
	var signs: Array = plan["signs"]
	var bad_signs := 0
	for sg in signs:
		var p: Vector3 = sg["pos"]
		var facing := Vector3(sin(sg["yaw"]), 0.0, cos(sg["yaw"]))
		var to_centre := Vector3(-p.x, 0.0, -p.z).normalized()
		if facing.dot(to_centre) < 0.9 or String(sg["text"]).is_empty() \
				or (absf(p.x) < fs.x * 0.5 + MARGIN and absf(p.z) < fs.y * 0.5 + MARGIN):
			bad_signs += 1
	_check("%s: %d signs, facing the arena" % [id, Skyline.SIGN_COUNT],
			signs.size() == Skyline.SIGN_COUNT and bad_signs == 0, "%d, %d bad" % [signs.size(), bad_signs])
