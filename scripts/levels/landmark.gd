# @lat: [[level-system#Landmarks]]
class_name Landmark
extends Node3D
## A level's hero landmark: one colossal AI megastructure past the skyline,
## placed on the spawn-to-exit heading so it stands ahead of the player for the
## whole level and gives every open-sky map a silhouette of its own.
##
## Def key `landmark`: {"kind": ..., "sign": "GEMINI", "color": Color, "bearing": deg}
##   kind  "spire"    stepped datacenter arcology, light bands, antenna crown
##         "twin"     two spires joined by a lit sky-bridge
##         "dish"     a relay array: three giant dishes on lattice masts, uplink beam
##         "stacks"   reactor cooling towers with glowing rims and steam
##         "monolith" a black slab with a burning seam, ringed by a slow halo
##   sign   holographic name over the crown ("" for none). Not "label": every
##          "label" in level_defs.gd is translated HUD text (check_strings_csv.py),
##          and these are proper names.
##   bearing  degrees clockwise from the spawn-to-exit heading (default 0)
## Open-sky levels without the key get a plain spire in the theme colour.
## Interior levels get the "core" instead (see _build_core): the AI itself,
## hanging under the ceiling over the room's centre, a lattice sphere with
## counter-rotating rings around an eye that turns to follow you. `"kind":
## "none"` opts a level out.
##
## Visual only: no collision, shadows off. Bodies take the level's fog (they
## read as distant), the light bands ignore it so they cut through the haze.
## LOW skips the animated extras (searchlight, steam, halo spin).
## Covered by tests/landmark_probe; framed by tests/landmark_shot.

const DIST_PAST_FLOOR := 115.0 ## metres beyond the floor's half-extent
## Built at 1x and scaled up whole: at eye level behind a perimeter wall a 1x
## spire showed only its crown (judged in tests/landmark_shot).
const SCALE := 1.5

var kind := "spire"
var accent := Color(0.6, 0.8, 1.0)
var label_text := ""
var low := false
var _body_mat: StandardMaterial3D
var _band_mat: StandardMaterial3D
var _row_mat: StandardMaterial3D ## dimmer, warmer lit-floor rows between bands
var _beacon_mat: StandardMaterial3D

## Builds the landmark for `def` (already WORLD_SCALE'd) under `parent`: past the
## skyline on open sky, the AI core indoors (null when it has no room). Returns it.
static func build_for(parent: Node3D, def: Dictionary, theme: Color, is_low: bool) -> Landmark:
	var spec: Dictionary = def.get("landmark", {})
	if String(spec.get("kind", "")) == "none":
		return null
	if not def.get("open_sky", false):
		return _build_core(parent, def, spec, theme, is_low)
	var lm := Landmark.new()
	lm.name = "Landmark"
	lm.kind = String(spec.get("kind", "spire"))
	lm.accent = spec.get("color", theme)
	lm.label_text = String(spec.get("sign", ""))
	lm.low = is_low
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
	var exit: Vector3 = def.get("exit", Vector3(0, 0, -1))
	var heading := exit - spawn
	heading.y = 0.0
	if heading.length() < 1.0:
		heading = Vector3(0, 0, -1)
	heading = heading.normalized().rotated(Vector3.UP, -deg_to_rad(float(spec.get("bearing", 0.0))))
	var dist := maxf(fs.x, fs.y) * 0.5 + DIST_PAST_FLOOR
	parent.add_child(lm)
	lm.position = heading * dist
	lm.rotation.y = atan2(heading.x, heading.z) # local +Z faces away from the arena
	lm.scale = Vector3.ONE * SCALE
	lm._build()
	return lm

func _build() -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.06, 0.065, 0.08)
	_body_mat.metallic = 0.6
	_body_mat.roughness = 0.55
	# A faint inner glow, so the silhouette still reads against a black night sky.
	_body_mat.emission_enabled = true
	_body_mat.emission = accent.darkened(0.6)
	_body_mat.emission_energy_multiplier = 0.25
	_band_mat = _glow(accent, 3.2)
	_row_mat = _glow(accent.lerp(Color(1.0, 0.85, 0.6), 0.35), 1.4)
	_beacon_mat = _glow(Color(1.0, 0.12, 0.08), 6.0)
	match kind:
		"twin":
			_spire(Vector3(-26, 0, 0), 0.85)
			_spire(Vector3(26, 0, 0), 1.0)
			var bridge_y := 150.0 * 0.62
			_box(Vector3(0, bridge_y, 0), Vector3(36, 4.0, 7.0), _body_mat)
			_box(Vector3(0, bridge_y - 2.2, -3.6), Vector3(36, 0.8, 0.4), _band_mat)
			_box(Vector3(0, bridge_y + 2.2, -3.6), Vector3(36, 0.8, 0.4), _band_mat)
			_name_tag(Vector3(0, 175.0, 0))
		"dish":
			for i in 3:
				var x := (float(i) - 1.0) * 46.0
				_dish(Vector3(x, 0, absf(x) * 0.35), 1.0 - absf(float(i) - 1.0) * 0.2, deg_to_rad(-25.0 + i * 25.0))
			_beam(Vector3(0, 0, 0), 420.0, 2.2)
			_name_tag(Vector3(0, 120.0, 0))
		"stacks":
			for i in 4:
				var x := (float(i) - 1.5) * 44.0
				_stack(Vector3(x, 0, (i % 2) * 22.0), 1.0 - (i % 2) * 0.15)
			_name_tag(Vector3(0, 125.0, 0))
		"monolith":
			_monolith()
			_name_tag(Vector3(0, 205.0, 0))
		_:
			_spire(Vector3.ZERO, 1.0)
			_name_tag(Vector3(0, 175.0, 0))

# ---------- interior core ----------

const CORE_REACH := 5.0 ## metres around the core's spot whose walkable tops it must clear
const CORE_HEADROOM := 3.5 ## clear air kept over the highest walkable top: above a jump, out of the eye-level firefight
const CORE_MIN_R := 1.1
const CORE_MAX_R := 3.2
## Mirrors of LevelBuilder.WALL_HEIGHT / PLAYER_CLEARANCE_M (LevelBuilder already
## references this class; naming it back would close a load cycle).
## tests/landmark_probe fails if they drift.
const ROOM_BASE_H := 6.0
const ROOM_CLEARANCE_M := 2.2

var core_radius := 0.0
var _eye: Node3D = null

## Highest walkable top (authored walls, platforms, towers) within CORE_REACH
## of `at` (floor x/z), from the scaled def: deterministic, no physics query.
static func _floor_top_near(def: Dictionary, at: Vector2) -> float:
	var top := 0.0
	for key in ["walls", "platforms"]:
		for w in def.get(key, []):
			var p: Vector3 = w.get("pos", Vector3.ZERO)
			var s: Vector3 = w.get("size", Vector3.ONE)
			if Vector2(p.x, p.z).distance_to(at) - Vector2(s.x, s.z).length() * 0.5 < CORE_REACH:
				top = maxf(top, p.y + s.y * 0.5)
	for t in def.get("towers", []):
		var p: Vector3 = t.get("pos", Vector3.ZERO)
		if Vector2(p.x, p.z).distance_to(at) - float(t.get("radius", 3.0)) < CORE_REACH:
			top = maxf(top, float(t.get("height", 8.0)))
	return top

## The spot for the core: the centre, or the candidate around it (two rings at
## 15% and 30% of the floor's short side) with the most clear air, nearer the
## centre on a tie. Returns Vector3(x, z, floor_top).
static func _core_spot(def: Dictionary) -> Vector3:
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var short := minf(fs.x, fs.y)
	var cands: Array[Vector2] = [Vector2.ZERO]
	for ring in [0.15, 0.3]:
		for k in 8:
			cands.append(Vector2.from_angle(TAU * k / 8.0) * short * ring)
	var best := Vector3.INF
	for c in cands:
		if _near_gate(def, c):
			continue
		var top := _floor_top_near(def, c)
		if best == Vector3.INF or top < best.z - 0.5:
			best = Vector3(c.x, c.y, top)
	return best

## A route gate is a full-height wall across the arena (def "gates"); a core
## hung across one would sit half inside it.
static func _near_gate(def: Dictionary, c: Vector2) -> bool:
	for g in def.get("gates", []):
		var at := float(g.get("at", 0.0))
		var d := absf(c.y - at) if String(g.get("axis", "z")) == "z" else absf(c.x - at)
		if d < CORE_MAX_R * 1.35 + 1.0:
			return true
	return false

## The room's ceiling height, mirroring LevelBuilder._build_room (raised to
## clear the tallest tower).
static func _room_height(def: Dictionary) -> float:
	var h := ROOM_BASE_H
	for t in def.get("towers", []):
		h = maxf(h, float((t as Dictionary).get("height", 8.0)) + ROOM_CLEARANCE_M + 0.3)
	return h

static func _build_core(parent: Node3D, def: Dictionary, spec: Dictionary, theme: Color, is_low: bool) -> Landmark:
	var ceiling := _room_height(def) - 0.4
	var spot := _core_spot(def)
	if spot == Vector3.INF:
		return null
	var span := ceiling - (spot.z + CORE_HEADROOM)
	# The rings reach 1.35 r: the whole core must fit the clear air.
	var r := minf(CORE_MAX_R, span / 2.7)
	if r < CORE_MIN_R:
		return null
	var lm := Landmark.new()
	lm.name = "Landmark"
	lm.kind = "core"
	lm.accent = spec.get("color", theme)
	lm.low = is_low
	lm.core_radius = r
	parent.add_child(lm)
	lm.position = Vector3(spot.x, ceiling - r * 1.35, spot.y)
	lm._build_core_parts(r)
	return lm

func _build_core_parts(r: float) -> void:
	_band_mat = _glow(accent, 2.6)
	_band_mat.disable_fog = false
	# Lattice: the 30 edges of an icosahedron.
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = []
	for v in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append((v as Vector3).normalized() * r)
	var edge_len := verts[0].distance_to(verts[1])
	# One MultiMesh draw for all 30 struts (as 30 MeshInstances the core cost
	# ~30 extra draw calls per interior in tools/perf_measure).
	var strut := CylinderMesh.new()
	strut.top_radius = r * 0.025
	strut.bottom_radius = r * 0.025
	strut.height = edge_len
	strut.radial_segments = 4
	strut.rings = 1
	strut.material = _band_mat
	var xforms: Array[Transform3D] = []
	for i in verts.size():
		for j in range(i + 1, verts.size()):
			if absf(verts[i].distance_to(verts[j]) - edge_len) < 0.01:
				xforms.append(_strut_xform(verts[i], verts[j]))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = strut
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var lattice := MultiMeshInstance3D.new()
	lattice.name = "Lattice"
	lattice.multimesh = mm
	_quiet(lattice)
	add_child(lattice)
	if not low:
		var lt := lattice.create_tween().set_loops()
		lt.tween_property(lattice, "rotation:y", TAU, 40.0).as_relative()
	# A faint shell so the lattice reads as a volume, not a wireframe.
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r * 0.97
	sm.height = r * 1.94
	shell.mesh = sm
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shm.albedo_color = Color(accent, 0.07)
	shell.material_override = shm
	_quiet(shell)
	add_child(shell)
	# Two data rings on crossed axes, counter-rotating.
	for k in 2:
		var pivot := Node3D.new()
		pivot.rotation = Vector3(deg_to_rad(70.0 if k == 0 else -20.0), 0, deg_to_rad(20.0 if k == 0 else 65.0))
		add_child(pivot)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r * 1.3
		tm.outer_radius = r * 1.35
		tm.rings = 64
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = _band_mat
		_quiet(ring)
		pivot.add_child(ring)
		if not low:
			var rt := pivot.create_tween().set_loops()
			rt.tween_property(pivot, "rotation:y", TAU * (1.0 if k == 0 else -1.0), 18.0 + k * 7.0).as_relative()
	# It lights the hall around it: the AI is the room's lamp. Not in the
	# "level_light" group, so a blackout leaves it burning.
	var glow := OmniLight3D.new()
	glow.light_color = accent
	glow.light_energy = 1.8
	glow.omni_range = r * 6.0 + 6.0
	glow.shadow_enabled = false
	add_child(glow)
	# The eye: a white-hot iris in the accent colour with a dark pupil, turned
	# toward the player every frame.
	_eye = Node3D.new()
	_eye.name = "Eye"
	add_child(_eye)
	var iris := MeshInstance3D.new()
	var im := SphereMesh.new()
	im.radius = r * 0.3
	im.height = r * 0.6
	iris.mesh = im
	iris.material_override = _glow(accent.lerp(Color.WHITE, 0.35), 4.0)
	_quiet(iris)
	_eye.add_child(iris)
	var pupil := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = r * 0.12
	pm.bottom_radius = r * 0.12
	pm.height = r * 0.04
	pupil.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(0.02, 0.0, 0.0)
	pupil.material_override = pmat
	pupil.rotation.x = PI * 0.5 # disc faces local -Z, the eye's forward
	pupil.position.z = -r * 0.29
	_quiet(pupil)
	_eye.add_child(pupil)
	set_process(true)

## A cylinder's (local +Y) transform spanning a -> b.
static func _strut_xform(a: Vector3, b: Vector3) -> Transform3D:
	var up := (b - a).normalized()
	var side := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := side.cross(up).normalized()
	return Transform3D(Basis(x, up, x.cross(up).normalized()), (a + b) * 0.5)

func _ready() -> void:
	set_process(kind == "core")

func _process(delta: float) -> void:
	if _eye == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to := cam.global_position - _eye.global_position
	if to.length() < 0.5:
		return
	var want := Basis.looking_at(to.normalized(), Vector3.UP if absf(to.normalized().y) < 0.98 else Vector3.FORWARD)
	_eye.global_basis = _eye.global_basis.slerp(want, clampf(4.0 * delta, 0.0, 1.0)).orthonormalized()

## Where the eye is looking (its -Z), for tests/landmark_probe.
func eye_forward() -> Vector3:
	return -_eye.global_basis.z if _eye else Vector3.ZERO

# ---------- parts ----------

## Stepped arcology: five tapering tiers, a light band at every setback,
## vertical light seams, an antenna mast with a red beacon and a sweeping
## searchlight on the crown.
func _spire(at: Vector3, s: float) -> void:
	var y := 0.0
	var w := 30.0 * s
	var tiers := 5
	for t in tiers:
		var h := (34.0 - t * 3.0) * s
		_box(at + Vector3(0, y + h * 0.5, 0), Vector3(w, h, w), _body_mat)
		# A setback band, three rows of lit floors, two vertical seams per face.
		_box(at + Vector3(0, y + h, 0), Vector3(w + 0.6, 0.9, w + 0.6), _band_mat)
		for r in 3:
			_box(at + Vector3(0, y + h * (0.25 + r * 0.22), 0), Vector3(w + 0.3, 0.35, w + 0.3), _row_mat)
		for f in [-1.0, 1.0]:
			_box(at + Vector3(w * 0.22 * f, y + h * 0.5, -w * 0.5 - 0.15), Vector3(0.5, h * 0.8, 0.3), _band_mat)
		y += h
		w *= 0.78
	var mast_h := 32.0 * s
	_box(at + Vector3(0, y + mast_h * 0.5, 0), Vector3(1.4, mast_h, 1.4), _body_mat)
	_beacon(at + Vector3(0, y + mast_h + 1.0, 0), 2.2, 0.0)
	_beacon(at + Vector3(w * 0.45, y + 1.0, w * 0.45), 1.4, 0.5)
	_beacon(at + Vector3(-w * 0.45, y + 1.0, -w * 0.45), 1.4, 0.25)
	if not low:
		_searchlight(at + Vector3(0, y + 2.0, 0))

## A relay dish on a lattice mast, tilted toward the sky.
func _dish(at: Vector3, s: float, yaw: float) -> void:
	var mast_h := 52.0 * s
	for c in 4:
		var a := TAU * c / 4.0 + PI / 4.0
		_box(at + Vector3(cos(a) * 4.0, mast_h * 0.5, sin(a) * 4.0), Vector3(0.9, mast_h, 0.9), _body_mat)
		_box(at + Vector3(cos(a) * 4.5, mast_h * 0.5, sin(a) * 4.5), Vector3(0.25, mast_h, 0.25), _row_mat)
	for k in 5:
		_box(at + Vector3(0, mast_h * (0.2 + k * 0.18), 0), Vector3(9.0, 0.6, 9.0), _body_mat)
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = at + Vector3(0, mast_h + 4.0, 0)
	pivot.rotation = Vector3(deg_to_rad(-55.0), yaw, 0)
	var dish := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 26.0 * s
	cm.bottom_radius = 8.0 * s
	cm.height = 9.0 * s
	cm.radial_segments = 32
	cm.cap_top = false
	dish.mesh = cm
	# Open bowl: seen from the arena you look INTO it, at faces that back-face
	# culling would drop (the first frames showed bare floating rims).
	var bowl := _body_mat.duplicate() as StandardMaterial3D
	bowl.cull_mode = BaseMaterial3D.CULL_DISABLED
	dish.material_override = bowl
	_quiet(dish)
	pivot.add_child(dish)
	# Feed horn: a lit strut out of the bowl with a hot tip.
	var feed := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.6, 16.0 * s, 0.6)
	feed.mesh = fb
	feed.material_override = _row_mat
	feed.position.y = 8.0 * s
	_quiet(feed)
	pivot.add_child(feed)
	var tip := MeshInstance3D.new()
	var ts := SphereMesh.new()
	ts.radius = 1.4 * s
	ts.height = 2.8 * s
	tip.mesh = ts
	tip.material_override = _band_mat
	tip.position.y = 16.0 * s
	_quiet(tip)
	pivot.add_child(tip)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 25.4 * s
	tm.outer_radius = 26.6 * s
	tm.rings = 48
	rim.mesh = tm
	rim.material_override = _band_mat
	rim.position.y = 4.5 * s
	_quiet(rim)
	pivot.add_child(rim)
	_beacon(at + Vector3(0, mast_h + 0.5, 0), 1.6, randf())

## A cooling tower faked as two mirrored cones (a pinched hyperboloid), glowing
## at the rim, venting steam.
func _stack(at: Vector3, s: float) -> void:
	var h := 90.0 * s
	for half in 2:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = (24.0 if half == 0 else 13.0) * s
		cm.top_radius = (13.0 if half == 0 else 17.0) * s
		cm.height = (h * 0.62) if half == 0 else (h * 0.38)
		cm.radial_segments = 40
		cm.cap_top = false
		cm.cap_bottom = false
		cone.mesh = cm
		cone.material_override = _body_mat
		cone.position = at + Vector3(0, (h * 0.31) if half == 0 else (h * 0.62 + h * 0.19), 0)
		_quiet(cone)
		add_child(cone)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 16.4 * s
	tm.outer_radius = 17.6 * s
	tm.rings = 48
	rim.mesh = tm
	rim.material_override = _band_mat
	rim.position = at + Vector3(0, h, 0)
	_quiet(rim)
	add_child(rim)
	_beacon(at + Vector3(17.0 * s, h + 0.8, 0), 1.6, randf())
	if not low:
		_steam(at + Vector3(0, h + 4.0, 0), 15.0 * s)

## The black slab with a burning seam, ringed by a slow halo.
func _monolith() -> void:
	_box(Vector3(0, 95.0, 0), Vector3(54.0, 190.0, 16.0), _body_mat)
	_box(Vector3(0, 95.0, -8.2), Vector3(2.2, 182.0, 0.4), _band_mat)
	for y in [40.0, 95.0, 150.0]:
		_box(Vector3(0, y, -8.2), Vector3(54.4, 0.7, 0.4), _band_mat)
	_beacon(Vector3(0, 191.5, 0), 2.6, 0.0)
	var halo := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 58.0
	tm.outer_radius = 61.0
	tm.rings = 96
	tm.ring_segments = 8
	halo.mesh = tm
	halo.material_override = _band_mat
	halo.position = Vector3(0, 120.0, 0)
	halo.rotation = Vector3(deg_to_rad(72.0), 0, deg_to_rad(12.0))
	_quiet(halo)
	add_child(halo)
	if not low:
		var tw := halo.create_tween().set_loops()
		tw.tween_property(halo, "rotation:y", TAU, 90.0).as_relative()

# ---------- pieces ----------

func _box(at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	_quiet(mi)
	add_child(mi)
	return mi

func _quiet(mi: GeometryInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

static func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.disable_fog = true
	return m

## An aviation beacon: a red light that blinks once every 1.6 s, `phase` (0..1)
## offsetting it so a skyline of them never blinks in lockstep.
func _beacon(at: Vector3, r: float, phase: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _beacon_mat
	mi.position = at
	mi.visible = false
	_quiet(mi)
	add_child(mi)
	mi.add_to_group("landmark_beacon")
	var blink := func() -> void:
		var tw := mi.create_tween().set_loops()
		tw.tween_callback(mi.show)
		tw.tween_interval(0.35)
		tw.tween_callback(mi.hide)
		tw.tween_interval(1.25)
	var start := mi.create_tween()
	start.tween_interval(1.6 * phase + 0.01)
	start.tween_callback(blink)

## A pale searchlight cone sweeping the sky from the crown.
func _searchlight(at: Vector3) -> void:
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = at
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 16.0
	cm.bottom_radius = 0.6
	cm.height = 260.0
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(accent.lerp(Color.WHITE, 0.6), 0.07)
	m.disable_fog = true
	cone.material_override = m
	cone.position = Vector3(0, 130.0, 0)
	_quiet(cone)
	var tilt := Node3D.new()
	tilt.rotation.x = deg_to_rad(38.0)
	pivot.add_child(tilt)
	tilt.add_child(cone)
	var tw := pivot.create_tween().set_loops()
	tw.tween_property(pivot, "rotation:y", TAU, 14.0).as_relative()

## A tall faint uplink beam (the dish array is talking to something).
func _beam(at: Vector3, h: float, r: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 12
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(accent.lerp(Color.WHITE, 0.4), 0.35)
	m.disable_fog = true
	mi.material_override = m
	mi.position = at + Vector3(0, h * 0.5, 0)
	_quiet(mi)
	add_child(mi)

func _steam(at: Vector3, r: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = r
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(1.2, 0.4, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(0.75, 0.75, 0.78, 0.0))
	grad.add_point(0.15, Color(0.75, 0.75, 0.78, 0.35))
	grad.set_color(grad.get_point_count() - 1, Color(0.6, 0.6, 0.65, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(26, 26)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff_texture()
	q.material = m
	p.mesh = q
	p.position = at
	_quiet(p)
	add_child(p)

static var _puff: Texture2D = null
static func _puff_texture() -> Texture2D:
	if _puff:
		return _puff
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	_puff = gt
	return _puff

## The AI's name as a hologram over the crown, always facing the arena.
func _name_tag(at: Vector3) -> void:
	if label_text == "":
		return
	var l := Label3D.new()
	l.name = "NameTag"
	l.text = label_text
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.font_size = 256
	l.pixel_size = 0.09
	l.outline_size = 0
	# Overbright on purpose: a Label3D takes the level's fog and has no switch for
	# it, so at 200 m a 1.0 colour reads as a dim smudge; HDR lets glow carry it.
	var c := accent.lerp(Color.WHITE, 0.5) * 2.2
	l.modulate = Color(c.r, c.g, c.b, 1.0)
	l.shaded = false
	l.double_sided = true
	l.no_depth_test = false
	l.fixed_size = false
	l.position = at
	add_child(l)
	if not low:
		var tw := l.create_tween().set_loops()
		tw.tween_property(l, "modulate:a", 0.7, 1.8).set_trans(Tween.TRANS_SINE)
		tw.tween_property(l, "modulate:a", 1.0, 1.8).set_trans(Tween.TRANS_SINE)
