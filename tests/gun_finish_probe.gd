extends Node3D
## Probe: the guns' worn-gunmetal skin (Weapon._gunmetal_material) has no
## mirror-smooth patches. Its roughness used to swing over 0..0.5 with a noise
## map, so the smooth spots mirrored the level (bright green in the foundry)
## next to matte ones and every gun read as camouflage (tests/viewmodel_shot).
## For every gun in GameState.WEAPON_ORDER and Salvage.TABLE, on every gunmetal
## surface of its model: the effective roughness (material roughness x the
## generated noise map's red channel) stays within MIN_ROUGH..MAX_ROUGH and
## varies by at most MAX_SPREAD, i.e. brushed wear, not blotches.
##   godot --headless --path . --audio-driver Dummy res://tests/gun_finish_probe.tscn

const MIN_ROUGH := 0.25
const MAX_ROUGH := 0.65
const MAX_SPREAD := 0.2

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var guns: Array = GameState.WEAPON_ORDER.duplicate()
	for k in Salvage.TABLE:
		guns.append(String(Salvage.TABLE[k]["scene"]))
	var checked := 0
	for p: String in guns:
		var id := p.get_file().get_basename()
		var w: Weapon = (load(p) as PackedScene).instantiate()
		add_child(w)
		await get_tree().process_frame
		var mats := _gunmetal(w)
		_check("%s has a gunmetal skin" % id, not mats.is_empty())
		var lo := INF
		var hi := -INF
		for m: StandardMaterial3D in mats:
			var r := await _red_range(m.roughness_texture as NoiseTexture2D)
			lo = minf(lo, m.roughness * r.x)
			hi = maxf(hi, m.roughness * r.y)
		if not mats.is_empty():
			checked += 1
			_check("%s skin has no mirror patches (roughness >= %.2f)" % [id, MIN_ROUGH], lo >= MIN_ROUGH, "%.2f" % lo)
			_check("%s skin is not glossy-matte camo (spread <= %.2f, max <= %.2f)" % [id, MAX_SPREAD, MAX_ROUGH],
					hi - lo <= MAX_SPREAD + 0.001 and hi <= MAX_ROUGH, "%.2f..%.2f" % [lo, hi])
		w.queue_free()
		await get_tree().process_frame
	_check("every gun was checked", checked == guns.size(), "%d of %d" % [checked, guns.size()])
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## The model's surface materials that are gunmetal (roughness-mapped, not the
## emissive accents).
func _gunmetal(w: Weapon) -> Array:
	var out: Array = []
	for n in w.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i) as StandardMaterial3D
			if m and m.roughness_texture is NoiseTexture2D and not m in out:
				out.append(m)
	return out

## Lowest and highest red value of a generated noise texture (0..1).
func _red_range(tex: NoiseTexture2D) -> Vector2:
	var img := tex.get_image()
	var t0 := Time.get_ticks_msec()
	while img == null and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
		img = tex.get_image()
	if img == null:
		return Vector2(0, 1)
	var lo := 1.0
	var hi := 0.0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var r := img.get_pixel(x, y).r
			lo = minf(lo, r)
			hi = maxf(hi, r)
	return Vector2(lo, hi)
