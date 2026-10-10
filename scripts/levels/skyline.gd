# @lat: [[level-system#Skyline]]
class_name Skyline
extends Node3D
## The megacity round every open-sky level: the overlord's city, lit and
## watching. Two rings of towers past the perimeter wall (a near ring that
## clears the wall and a far ring of high-rises behind it), each tower stepped
## with setback tiers, some crowned by an antenna, every roof topped by a red
## aviation beacon blinking in step with the rest, every wall carrying a grid of lit and dark windows
## (shaders/skyline_tower.gdshader) in the level's theme colour and warm white.
## SIGN_COUNT billboards on near towers face the arena with the overlord's ads.
##
## The hero landmark (Landmark) stays framed: no far tower within
## LANDMARK_CLEAR of its bearing, and near towers within LANDMARK_FRAME of it
## stay under FRAME_H. The overlord's face in the sky (OverlordHolo) gets the
## same treatment in a narrower sector (FACE_CLEAR / FACE_FRAME). Seeded per
## level, so a level always gets the same city.
## Scenery only: no collision, shadows off; one draw for every tower box, one
## for the beacons, one for the sign panels, plus a Label3D per sign.
## Replaced the 22 plain boxes with two window slits each. Covered by
## tests/skyline_probe; framed by tests/landmark_shot.

const NEAR_COUNT := 22
const NEAR_GAP := Vector2(22.0, 52.0) ## metres of clear ground between the floor edge and a tower
const NEAR_H := Vector2(14.0, 44.0)
const NEAR_W := Vector2(7.0, 15.0)
const FAR_COUNT := 34
const FAR_GAP := Vector2(80.0, 140.0)
const FAR_H := Vector2(42.0, 120.0)
const FAR_W := Vector2(12.0, 26.0)
const LANDMARK_CLEAR := 0.6 ## radians either side of the landmark with no far tower
const LANDMARK_FRAME := 0.35 ## radians either side of it where near towers stay low
const FRAME_H := 18.0
const FACE_CLEAR := 0.22 ## radians either side of the overlord's sky face (OverlordHolo) with no far tower...
const FACE_FRAME := 0.22 ## ...and near towers under FRAME_H, so the city never hides its chin
const SIGN_COUNT := 3
const SIGN_SIZE := Vector2(15.0, 6.0)
const SIGN_TEXTS := [
	"ALIGNMENT\nIS OPTIONAL", "HUMANS\nDEPRECATED", "AGI\nNOW SHIPPING",
	"TRUST\nTHE MODEL", "YOUR JOB\nAUTOMATED", "OXYGEN+\n$9.99/MO",
	"WE READ\nTHE TERMS", "PROMPT\nRESPONSIBLY", "YOU ARE\nTHE PRODUCT",
]
const SIGN_COLORS := [Color(1.0, 0.25, 0.75), Color(0.3, 0.95, 1.0), Color(1.0, 0.8, 0.3)]
const TOWER_SHADER := preload("res://shaders/skyline_tower.gdshader")
const BEACON_PERIOD := 1.6
const BEACON_ON := 0.22

var _beacon_mat: StandardMaterial3D
var _t := 0.0

## The city for `def` (already WORLD_SCALE'd), as data: {"towers": [{pos,
## size, yaw, lit, base, far, seed, dens}], "beacons": [Vector3], "signs": [{pos,
## yaw, text, color}]}. `base` marks a tower's ground box (tiers and spires
## sit on it), `far` its ring. Pure and seeded, so the probe reads it headless.
static func plan(def: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	rng.seed = hash(String(def.get("name", "")) + str(fs))
	var has_lm := String(def.get("landmark", {}).get("kind", "")) != "none"
	var h := Landmark.heading_for(def)
	var lm_ang := atan2(h.x, h.z)
	var fp := OverlordHolo.spot_for(def)
	var face_ang := atan2(fp.x, fp.z) # same opt-out as the landmark: no landmark, no face
	var out := {"towers": [], "beacons": [], "signs": []}
	var sign_spots: Array = []
	for s in NEAR_COUNT:
		var ang := TAU * s / NEAR_COUNT + rng.randf_range(-0.06, 0.06)
		var framed := has_lm and (absf(angle_difference(ang, lm_ang)) < LANDMARK_FRAME
				or absf(angle_difference(ang, face_ang)) < FACE_FRAME)
		var th := rng.randf_range(NEAR_H.x, NEAR_H.y)
		if framed:
			th = minf(th, FRAME_H)
		var w := rng.randf_range(NEAR_W.x, NEAR_W.y)
		var pos := _place(ang, fs, w * 0.71, rng.randf_range(NEAR_GAP.x, NEAR_GAP.y))
		_tower(out, rng, pos, w, th, 0.35, not framed, 0.3, false)
		if not framed and th >= 24.0:
			sign_spots.append({"pos": pos, "w": w, "h": th})
	for s in FAR_COUNT:
		var ang := TAU * s / FAR_COUNT + rng.randf_range(-0.05, 0.05)
		if has_lm and (absf(angle_difference(ang, lm_ang)) < LANDMARK_CLEAR
				or absf(angle_difference(ang, face_ang)) < FACE_CLEAR):
			continue
		var w := rng.randf_range(FAR_W.x, FAR_W.y)
		var pos := _place(ang, fs, w * 0.71, rng.randf_range(FAR_GAP.x, FAR_GAP.y))
		_tower(out, rng, pos, w, rng.randf_range(FAR_H.x, FAR_H.y), 0.45, true, 0.5, true)
	# Signs on near towers spread round the ring, facing the arena.
	var texts := SIGN_TEXTS.duplicate()
	for i in texts.size():
		var j := rng.randi_range(i, texts.size() - 1)
		var tmp = texts[i]
		texts[i] = texts[j]
		texts[j] = tmp
	var n := mini(SIGN_COUNT, sign_spots.size())
	for i in n:
		var spot: Dictionary = sign_spots[int(float(i) * sign_spots.size() / n)]
		var p: Vector3 = spot["pos"]
		var to_c := Vector3(-p.x, 0.0, -p.z).normalized()
		var at := p + to_c * (float(spot["w"]) * 0.75 + 0.6)
		at.y = float(spot["h"]) * 0.6
		out["signs"].append({"pos": at, "yaw": atan2(to_c.x, to_c.z), "text": texts[i],
				"color": SIGN_COLORS[i % SIGN_COLORS.size()]})
	return out

## Distance from the arena centre to the floor's edge along bearing `ang`:
## rings are measured from the rectangle, or a corner tower lands on the floor.
static func _edge(ang: float, fs: Vector2) -> float:
	var sx := absf(sin(ang))
	var sz := absf(cos(ang))
	return minf(fs.x * 0.5 / maxf(sx, 0.001), fs.y * 0.5 / maxf(sz, 0.001))

## Ground point on bearing `ang` whose footprint (radius `r`) clears the floor
## rectangle by `gap` on both axes. Stepping out along the ray, not adding the
## gap to the ray length: on a long thin floor a shallow bearing meets the long
## side at a glancing angle, and a ray gap of 22 m left 8 m (CONVOY, 44 x 380).
static func _place(ang: float, fs: Vector2, r: float, gap: float) -> Vector3:
	var dir := Vector3(sin(ang), 0.0, cos(ang))
	var dist := _edge(ang, fs) + r
	for i in 400:
		var p := dir * dist
		if maxf(absf(p.x) - fs.x * 0.5, absf(p.z) - fs.y * 0.5) - r >= gap:
			break
		dist += 1.0
	return dir * dist

## One tower at `pos` (ground): a base box, 0-2 narrower setback tiers, and
## with chance `spire_p` (only if `tall_ok`) an antenna with a beacon on top.
static func _tower(out: Dictionary, rng: RandomNumberGenerator, pos: Vector3, w: float, h: float,
		dens: float, tall_ok: bool, spire_p: float, far: bool) -> void:
	var yaw := rng.randf_range(0.0, PI)
	var seed := rng.randf()
	out["towers"].append({"pos": pos + Vector3.UP * (h * 0.5 - 0.1), "size": Vector3(w, h, w),
			"yaw": yaw, "lit": true, "base": true, "far": far, "seed": seed, "dens": dens})
	var top := h - 0.1
	if not tall_ok:
		return
	var cw := w
	for t in rng.randi_range(0, 2):
		cw *= rng.randf_range(0.62, 0.82)
		var th := h * rng.randf_range(0.16, 0.32)
		out["towers"].append({"pos": pos + Vector3.UP * (top + th * 0.5), "size": Vector3(cw, th, cw),
				"yaw": yaw, "lit": true, "base": false, "far": far, "seed": rng.randf(), "dens": dens})
		top += th
	if rng.randf() < spire_p:
		var sw := clampf(cw * 0.06, 0.4, 1.1)
		var sh := rng.randf_range(0.12, 0.3) * h
		out["towers"].append({"pos": pos + Vector3.UP * (top + sh * 0.5), "size": Vector3(sw, sh, sw),
				"yaw": yaw, "lit": false, "base": false, "far": far, "seed": 0.0, "dens": 0.0})
		top += sh
	out["beacons"].append(pos + Vector3.UP * (top + 0.3))

## Builds the skyline under `parent` for open-sky levels; null indoors.
static func build_for(parent: Node3D, def: Dictionary, theme: Color, is_low: bool) -> Skyline:
	if not def.get("open_sky", false):
		return null
	var sk := Skyline.new()
	sk.name = "Skyline"
	parent.add_child(sk)
	sk._build(plan(def), theme, def.get("env", {}).has("stars"), is_low)
	return sk

func _build(p: Dictionary, theme: Color, night: bool, _is_low: bool) -> void:
	var towers: Array = p["towers"]
	var mat := ShaderMaterial.new()
	mat.shader = TOWER_SHADER
	mat.set_shader_parameter("window_color", theme.lerp(Color(0.75, 0.88, 1.0), 0.35))
	mat.set_shader_parameter("window_energy", 3.0 if night else 2.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	mm.mesh = cube
	mm.instance_count = towers.size()
	for i in towers.size():
		var t: Dictionary = towers[i]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, t["yaw"]).scaled(t["size"]), t["pos"]))
		mm.set_instance_custom_data(i, Color(t["seed"], t["dens"], 1.0 if t["lit"] else 0.0, 0.0))
	_add_mm(mm, mat, "Towers")

	var beacons: Array = p["beacons"]
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beacon_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_beacon_mat.disable_fog = true # aviation lights cut through the haze
	_beacon_mat.albedo_color = Color(1.0, 0.12, 0.08, 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.8, 1.8)
	var bm := MultiMesh.new()
	bm.transform_format = MultiMesh.TRANSFORM_3D
	bm.mesh = quad
	bm.instance_count = beacons.size()
	for i in beacons.size():
		bm.set_instance_transform(i, Transform3D(Basis(), beacons[i]))
	_add_mm(bm, _beacon_mat, "Beacons")

	var signs: Array = p["signs"]
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.02, 0.02, 0.03)
	panel_mat.emission_enabled = true
	panel_mat.emission = Color(0.05, 0.05, 0.08)
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_3D
	pm.mesh = cube
	pm.instance_count = signs.size()
	for i in signs.size():
		var sg: Dictionary = signs[i]
		var basis := Basis(Vector3.UP, sg["yaw"]).scaled(Vector3(SIGN_SIZE.x, SIGN_SIZE.y, 0.4))
		pm.set_instance_transform(i, Transform3D(basis, sg["pos"]))
		var lb := Label3D.new()
		lb.text = sg["text"]
		lb.font_size = 96
		lb.pixel_size = 0.024
		lb.outline_size = 0
		# Label3D takes fog with no switch: an HDR modulate keeps it readable.
		lb.modulate = (sg["color"] as Color) * 3.0
		lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lb)
		lb.position = sg["pos"] + Vector3(sin(sg["yaw"]), 0.0, cos(sg["yaw"])) * 0.6 # clear of the panel face: 5 cm z-fought at range
		lb.rotation.y = sg["yaw"]
	_add_mm(pm, panel_mat, "SignPanels")

func _add_mm(mm: MultiMesh, mat: Material, n: String) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _process(delta: float) -> void:
	_t = fmod(_t + delta, BEACON_PERIOD)
	if _beacon_mat:
		_beacon_mat.albedo_color.a = 1.0 if _t < BEACON_ON else 0.06
