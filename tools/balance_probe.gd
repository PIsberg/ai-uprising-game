extends Node
## Headless balance probe. Loads each campaign level, lets enemies spawn/settle,
## and reports the combat budget per level: enemy population (peak + settled),
## total HP-to-clear, composition by type, and in-level supply pickups. Combined
## with weapon DPS this gives the real difficulty curve. Run headless:
##   godot --headless --path . tools/balance_probe.tscn

# Campaign-ish order (refined from level_defs); range/custom/sublevel are test maps.
const LEVELS := [
	"suburb", "01", "gpt", "claude", "gemini", "grok", "mistral",
	"neon", "titan", "alien", "assembly", "uplink", "crucible",
	"frostbreak", "lava_world", "water_world", "horde", "overseer",
	"archon", "suburb_boss",
]
const SETTLE_FRAMES := 90   # ~1.5s at 60fps for waves/spawners to populate
const SAMPLE_FRAMES := 240  # keep watching to catch wave spawns / peak

var _i := 0


func _ready() -> void:
	await _run()
	get_tree().quit()


func _run() -> void:
	print("=== BALANCE PROBE ===")
	print("level          | enemies(peak) | totalHP | health_pk | ammo_pk | top types")
	for id in LEVELS:
		var holder := Node3D.new()
		add_child(holder)
		var lvl: Node = _load_level(id)
		if lvl == null:
			print("%-14s | LOAD FAILED" % id)
			holder.free()
			continue
		holder.add_child(lvl)
		var peak := 0
		var peak_hp := 0.0
		var settled := 0
		for f in (SETTLE_FRAMES + SAMPLE_FRAMES):
			await get_tree().process_frame
			if f % 10 == 0:
				var n := get_tree().get_nodes_in_group("enemy").size()
				if n > peak:
					peak = n
					peak_hp = _total_enemy_hp()
				if f >= SETTLE_FRAMES:
					settled = maxi(settled, n)
		var comp := _composition()
		var hpacks := _count_group_scene("health") + _count_pickups("HealthPack")
		var ammo := _count_pickups("AmmoBox")
		print("%-14s | %4d (settled %3d) | %7.0f | %4d | %4d | %s" % [
			id, peak, settled, peak_hp, hpacks, ammo, comp])
		holder.free()
		# EnemySpawner (wave/AI-director spawns) parents new enemies to
		# get_tree().current_scene, not to whatever node loaded the level. In real
		# play that's correct since the level IS the current scene, but here the
		# probe's own root stays current_scene for the whole run, so wave-spawned
		# enemies were never under holder at all — holder.free() didn't touch them
		# and they piled up forever (peak counts + composition kept growing level
		# after level). Free every "enemy"-tagged node explicitly, regardless of
		# who parented it, so each level starts from an empty roster.
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e):
				e.free()
		await get_tree().process_frame
	print("=== PROBE DONE ===")


func _load_level(id: String) -> Node:
	var path := "res://scenes/levels/level_%s.tscn" % id
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	return ps.instantiate() if ps else null


func _total_enemy_hp() -> float:
	var sum := 0.0
	for e in get_tree().get_nodes_in_group("enemy"):
		var d = e.get_node_or_null("Damageable")
		if d:
			sum += d.max_health
	return sum


## Count enemies by class label, return a compact "android×6 drone×4 ..." string.
func _composition() -> String:
	var tally := {}
	for e in get_tree().get_nodes_in_group("enemy"):
		var s: Script = e.get_script()
		var nm := String(s.get_global_name()).replace("Enemy", "") if s else "?"
		tally[nm] = int(tally.get(nm, 0)) + 1
	var keys := tally.keys()
	keys.sort_custom(func(a, b): return tally[a] > tally[b])
	var parts := []
	for k in keys:
		parts.append("%s×%d" % [k, tally[k]])
	return " ".join(parts)


## Count nodes whose name contains a needle anywhere in the tree (pickups vary by
## level: placed AmmoBox/HealthPack scenes).
func _count_pickups(needle: String) -> int:
	return _count_named(get_tree().current_scene if get_tree().current_scene else self, needle)


func _count_named(root: Node, needle: String) -> int:
	if root == null:
		return 0
	var c := 0
	for n in root.get_children():
		if needle.to_lower() in n.name.to_lower():
			c += 1
		c += _count_named(n, needle)
	return c


func _count_group_scene(grp: String) -> int:
	return get_tree().get_nodes_in_group(grp).size()
