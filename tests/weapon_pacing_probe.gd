extends Node
## Campaign weapon pacing: the level at which a weapon is FIRST offered should
## track its power rank in GameState.WEAPON_ORDER. Finding a weaker gun later
## than a stronger one is an anticlimax, and it happened a lot: the rank-9 Gauss
## Lance was handed out on level 3, the rank-12 Devastator on level 8, while the
## rank-4 Maelstrom waited until level 13 and the rank-7 Longshot until 14.
##
## Re-finds don't count — only the first level a weapon appears on.
##   godot --headless --path . res://tests/weapon_pacing_probe.tscn

## Known, accepted exception: the TPX-9 Tempest Coil (rank 11) is authored as a
## TITAN-level reward and so lands after the Devastator (rank 12).
const ALLOWED := ["tempest"]

func _ready() -> void:
	var order: Array = GameState.WEAPON_ORDER
	var rank := {}
	for i in order.size():
		rank[String(order[i]).get_file().get_basename()] = i + 1

	var campaign: Array[String] = []
	for ch in LevelDefs.CHAPTERS:
		for id in ch["ids"]:
			campaign.append(String(id))

	var first := {}
	for i in campaign.size():
		var def: Dictionary = LevelDefs.get_def(campaign[i])
		var scenes: Array[String] = []
		var w: Dictionary = def.get("weapon", {})
		if w.has("scene"):
			scenes.append(String(w["scene"]))
		for x in def.get("extra_weapons", []):
			scenes.append(String((x as Dictionary).get("scene", "")))
		for sc in scenes:
			var n := sc.get_file().get_basename()
			if n != "" and not first.has(n):
				first[n] = i + 1

	var seen: Array = []
	for n in first:
		seen.append([int(first[n]), int(rank.get(n, 99)), n])
	seen.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	print("%-4s %-13s %-5s" % ["lvl", "weapon", "rank"])
	for e in seen:
		print("%-4d %-13s %-5d" % [e[0], e[2], e[1]])

	# Rank must not fall as the campaign advances (ties within a level are fine).
	var bad := 0
	var peak := 0
	for e in seen:
		var lvl: int = e[0]
		var r: int = e[1]
		var n: String = e[2]
		if r < peak and not ALLOWED.has(n):
			bad += 1
			print("BAD  %s (rank %d) first offered on level %d, after a rank-%d weapon" % [n, r, lvl, peak])
		peak = maxi(peak, r)
	print("\ninversions=", bad)
	print("RESULT ", "PASS" if bad == 0 else "FAIL")
	get_tree().quit()
