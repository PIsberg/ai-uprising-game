extends Node
## Probe: the Enemy Codex puts robots built on the same model on one page.
## (1) ground truth from the art: every codex entry's model file is read out of
##     its enemy scene (the first .glb/.gltf/.fbx it references), Blender forks
##     are folded onto their base model (FORK_SUFFIXES), and two non-boss entries
##     must share a page exactly when they share a base model; procedural robots
##     (no model file) and the bosses each get a page of their own;
##     A family id is never also a robot type (family_of would pull that robot in);
## (2) EnemyCodex.pages() keeps roster order, a page sits where its first
##     member does, and only discovered members are listed;
## (3) the Encyclopedia shows one page per family: a page with two discovered
##     variants gets a two-button variant bar, picking the second shows that
##     robot's dossier, Next moves to the next family (no bar on a one-robot
##     page), and the page count reads pages, not robots.
##   godot --headless --path . --audio-driver Dummy res://tests/codex_family_probe.tscn

const FORK_SUFFIXES := ["_armed", "_bladed", "_siege", "_fierce", "_strike"]
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# 1. Ground truth.
	var base := {}
	for t in EnemyCodex.ORDER:
		base[t] = _base_model(String(EnemyCodex.get_entry(t).get("scene", "")))
	var bad := 0
	var families := 0
	var seen := {}
	for i in EnemyCodex.ORDER.size():
		var a: String = EnemyCodex.ORDER[i]
		for j in range(i + 1, EnemyCodex.ORDER.size()):
			var b: String = EnemyCodex.ORDER[j]
			var same_model: bool = base[a] != "" and base[a] == base[b] \
					and not DamageMatrix.BOSSES.has(a) and not DamageMatrix.BOSSES.has(b)
			var same_page := EnemyCodex.family_of(a) == EnemyCodex.family_of(b)
			if same_model != same_page:
				bad += 1
				print("  %s (%s) / %s (%s): same model %s, same page %s" % [a, base[a], b, base[b], same_model, same_page])
		if not seen.has(EnemyCodex.family_of(a)):
			seen[EnemyCodex.family_of(a)] = true
			families += 1
	_check("pages follow the shared models", bad == 0, "%d mismatched pairs" % bad)
	_check("fewer pages than robots", families < EnemyCodex.ORDER.size(), "%d pages for %d robots" % [families, EnemyCodex.ORDER.size()])
	_check("drone and mender share a page", EnemyCodex.family_of("drone") == EnemyCodex.family_of("mender"))
	_check("the OVERSEER keeps its own page", EnemyCodex.family_of("overseer") == "overseer")
	_check("no family id is also a robot type", EnemyCodex.FAMILIES.keys().all(
			func(k) -> bool: return not EnemyCodex.ORDER.has(k)))
	_check("every family page has a title", EnemyCodex.FAMILIES.keys().all(
			func(k) -> bool: return String(EnemyCodex.FAMILIES[k].get("name", "")) != ""))

	# 2. pages().
	var all_pages: Array = EnemyCodex.pages(EnemyCodex.ORDER)
	_check("every robot on exactly one page", _flat(all_pages).size() == EnemyCodex.ORDER.size())
	_check("page count matches the families", all_pages.size() == families, "%d vs %d" % [all_pages.size(), families])
	var order_ok := true
	var last := -1
	for p in all_pages:
		var first := EnemyCodex.ORDER.find(p[0])
		if first < last:
			order_ok = false
		last = first
		for k in range(1, p.size()):
			if EnemyCodex.ORDER.find(p[k]) < EnemyCodex.ORDER.find(p[k - 1]):
				order_ok = false
	_check("pages and variants in roster order", order_ok)
	var some: Array = EnemyCodex.pages(["mender", "spider", "drone"])
	_check("only discovered members listed", some == [["drone", "mender"], ["spider"]], str(some))
	_check("nothing discovered, no pages", EnemyCodex.pages([]).is_empty())

	# 3. The Encyclopedia.
	GameState.discovered_enemies.clear()
	for t in ["drone", "mender", "spider"]:
		GameState.discovered_enemies[t] = true
	var enc: Node = (load("res://scenes/ui/encyclopedia.tscn") as PackedScene).instantiate()
	add_child(enc)
	await get_tree().process_frame
	_check("two pages for three robots", enc._pages.size() == 2, str(enc._pages))
	_check("variant bar shown with two variants", enc._variant_bar.visible and _buttons(enc).size() == 2)
	_check("first variant is the drone", enc._name_lbl.text == String(EnemyCodex.get_entry("drone")["name"]), enc._name_lbl.text)
	_check("page count reads pages", enc._count_lbl.text.begins_with("1 / 2"), enc._count_lbl.text)
	(_buttons(enc)[1] as Button).pressed.emit()
	await get_tree().process_frame
	_check("picking the second variant shows the mender", enc._name_lbl.text == String(EnemyCodex.get_entry("mender")["name"]), enc._name_lbl.text)
	enc._on_next()
	await get_tree().process_frame
	_check("next page is the spider", enc._name_lbl.text == String(EnemyCodex.get_entry("spider")["name"]), enc._name_lbl.text)
	_check("no variant bar on a one-robot page", not enc._variant_bar.visible)
	enc.queue_free()
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _buttons(enc: Node) -> Array:
	return enc._variant_bar.get_children().filter(func(c) -> bool: return c is Button and c.visible)

func _flat(pages: Array) -> Array:
	var out: Array = []
	for p in pages:
		out.append_array(p)
	return out

## The model file an enemy scene is built from, folded onto its base model.
func _base_model(scene: String) -> String:
	if scene == "" or not FileAccess.file_exists(scene):
		return ""
	var txt := FileAccess.get_file_as_string(scene)
	var rx := RegEx.new()
	rx.compile('path="(res://[^"]+\\.(glb|gltf|fbx))"')
	var m := rx.search(txt)
	if m == null:
		return ""
	var name := m.get_string(1).get_file().get_basename()
	for s in FORK_SUFFIXES:
		if name.ends_with(s):
			name = name.substr(0, name.length() - String(s).length())
	return name
