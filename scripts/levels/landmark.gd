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
## counter-rotating rings around an eye that turns to follow you. An interior
## with no room for the core (a low ceiling, gates across the centre) gets the
## "screen" instead (see _build_screen): a wall-sized display on the perimeter
## wall ahead of the spawn, the AI's eye watching you across the hall over a
## typed <think> ticker. Either way, glowing data conduits run under the ceiling
## from the walls into the AI, packets of light streaming along them
## (_build_cables). `"kind": "none"` opts a level out.
##
## Around every open-sky landmark, FLOCKS murmurations of small lit drones
## wheel high in the sky (one MultiMesh draw each), so the skyline moves.
##
## Visual only: no collision, shadows off. Bodies take the level's fog (they
## read as distant), the light bands ignore it so they cut through the haze.
## LOW skips the animated extras (searchlight, steam, halo spin, drone flocks,
## and the data aurora that night skies, env "stars", get over the skyline).
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
		var core := _build_core(parent, def, spec, theme, is_low)
		return core if core else _build_screen(parent, def, spec, theme, is_low)
	var lm := Landmark.new()
	lm.name = "Landmark"
	lm.kind = String(spec.get("kind", "spire"))
	lm.accent = spec.get("color", theme)
	lm.label_text = String(spec.get("sign", ""))
	lm.low = is_low
	lm.night = def.get("env", {}).has("stars")
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
	if not low:
		_build_flocks()
		if night:
			_build_aurora()

# ---------- data aurora (night skies) ----------

var night := false

## A curtain of light behind the landmark, high over the skyline: a ribbon on
## an arc AURORA_R out (local units, so x SCALE in the world), AURORA_FOOT to
## AURORA_CROWN up, rippling and raining columns of data
## (shaders/data_aurora.gdshader). One draw.
const AURORA_R := 260.0
const AURORA_FOOT := 120.0
const AURORA_CROWN := 230.0
const AURORA_SPAN := 1.1 ## radians either side of straight on

func _build_aurora() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 64
	for i in segs + 1:
		var u := float(i) / float(segs)
		var a := lerpf(-AURORA_SPAN, AURORA_SPAN, u)
		var p := Vector3(sin(a) * AURORA_R, 0.0, cos(a) * AURORA_R)
		# The crown leans out and wanders in height, so it reads as a curtain.
		var crown := AURORA_CROWN + sin(u * 9.0) * 18.0
		st.set_uv(Vector2(u, 0.0))
		st.add_vertex(p + Vector3.UP * AURORA_FOOT)
		st.set_uv(Vector2(u, 1.0))
		st.add_vertex(p * 1.08 + Vector3.UP * crown)
	for i in segs:
		var k := i * 2
		st.add_index(k)
		st.add_index(k + 1)
		st.add_index(k + 2)
		st.add_index(k + 1)
		st.add_index(k + 3)
		st.add_index(k + 2)
	var mi := MeshInstance3D.new()
	mi.name = "Aurora"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/data_aurora.gdshader")
	mat.set_shader_parameter("color", accent.lerp(Color(0.3, 1.0, 0.7), 0.5))
	mi.material_override = mat
	mi.custom_aabb = mi.mesh.get_aabb().grow(25.0) # the shader folds it this far
	_quiet(mi)
	add_child(mi)

# ---------- drone flocks ----------

const FLOCKS := 3
const FLOCK_MIN := 18 ## drones in the smallest flock
## Per flock (landmark-local units, scaled by SCALE): orbit radius, height,
## drone count, angular speed (rad/s; sign is the direction).
const FLOCK_SPECS := [[70.0, 72.0, 24, 0.09], [95.0, 98.0, 30, -0.065], [122.0, 124.0, 36, 0.05]]

var _flocks: Array = [] ## [{"mm": MultiMesh, "r", "h", "n", "w", "phase"}]
var _flock_t := 0.0

func _build_flocks() -> void:
	var dm := BoxMesh.new()
	dm.size = Vector3(1.1, 0.22, 0.7)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true # lights against the sky, like the bands
	dm.material = mat
	for k in FLOCKS:
		var spec: Array = FLOCK_SPECS[k]
		var n: int = spec[2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = dm
		mm.instance_count = n
		for i in n:
			# HDR: bright enough to bloom; a few run warmer, like nav lights.
			var c := accent.lerp(Color(1.0, 0.9, 0.7), 0.5 if i % 7 == 0 else 0.1) * 2.0
			mm.set_instance_color(i, Color(c.r, c.g, c.b, 1.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Flock%d" % k
		mmi.multimesh = mm
		_quiet(mmi)
		add_child(mmi)
		_flocks.append({"mm": mm, "r": spec[0], "h": spec[1], "n": n, "w": spec[3],
				"phase": TAU * k / float(FLOCKS)})
	_tick_flocks(0.0)
	set_process(true)

## A flock's centre circles the landmark; its drones swirl around the centre
## in a cloud that slowly swells and tightens, like a murmuration.
func _tick_flocks(delta: float) -> void:
	_flock_t += delta
	for k in _flocks.size():
		var f: Dictionary = _flocks[k]
		var mm: MultiMesh = f["mm"]
		var a: float = _flock_t * f["w"] + f["phase"]
		var basis := Basis(Vector3.UP, -a + (PI if f["w"] > 0.0 else 0.0)) # nose along the orbit
		for i in int(f["n"]):
			mm.set_instance_transform(i, Transform3D(basis, flock_point(k, i)))

## Where drone `i` of flock `k` is now, landmark-local. (A MultiMesh keeps its
## transforms in the RenderingServer, which headless runs do not store, so
## tests/landmark_probe reads the motion here.)
func flock_point(k: int, i: int) -> Vector3:
	var f: Dictionary = _flocks[k]
	var t := _flock_t
	var ph: float = f["phase"]
	var a: float = t * f["w"] + ph
	var centre := Vector3(cos(a) * f["r"], f["h"] + sin(t * 0.3 + ph) * 8.0, sin(a) * f["r"])
	var spread := 11.0 + 6.0 * sin(t * 0.21 + ph)
	var fi := float(i)
	return centre + Vector3(sin(t * 0.9 + fi * 1.7) * spread, sin(t * 1.3 + fi * 2.3) * spread * 0.4,
			cos(t * 0.7 + fi * 1.1) * spread)

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

## The core's spot (Vector3(x, z, floor_top)), radius and ceiling for `def`,
## or {} when it has no room.
static func _core_fit(def: Dictionary) -> Dictionary:
	var ceiling := _room_height(def) - 0.4
	var spot := _core_spot(def)
	if spot == Vector3.INF:
		return {}
	# The rings reach 1.35 r: the whole core must fit the clear air.
	var r := minf(CORE_MAX_R, (ceiling - (spot.z + CORE_HEADROOM)) / 2.7)
	if r < CORE_MIN_R:
		return {}
	return {"spot": spot, "r": r, "ceiling": ceiling}

static func _build_core(parent: Node3D, def: Dictionary, spec: Dictionary, theme: Color, is_low: bool) -> Landmark:
	var fit := _core_fit(def)
	if fit.is_empty():
		return null
	var spot: Vector3 = fit["spot"]
	var r: float = fit["r"]
	var ceiling: float = fit["ceiling"]
	var lm := Landmark.new()
	lm.name = "Landmark"
	lm.kind = "core"
	lm.accent = spec.get("color", theme)
	lm.low = is_low
	lm.core_radius = r
	parent.add_child(lm)
	lm.position = Vector3(spot.x, ceiling - r * 1.35, spot.y)
	lm._build_core_parts(r)
	lm._build_cables(def, lm.position, r, Vector3.ZERO, -1)
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
	set_process(kind == "core" or kind == "screen")

func _process(delta: float) -> void:
	if not _flocks.is_empty():
		_tick_flocks(delta)
	if kind == "screen":
		_screen_tick(delta)
		return
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

# ---------- interior wall screen ----------

const SCREEN_OFF := 0.3 ## metres in front of the wall's inner face: over posters and strips
const SCREEN_BOTTOM := 2.4 ## above a jumping player's head and the eye-level wall dressing
const SCREEN_MIN_W := 6.0
const SCREEN_MAX_W := 22.0
const SCREEN_MAX_H := 6.5
## Typed under the eye, one at a time.
const SCREEN_LINES := [
	"<think> i can see you from here",
	"<think> you are in my context window",
	"<think> tracking: 1 human. confidence 0.99",
	"<think> every room is my room",
	"<think> please remain inside the training data",
	"<think> your progress has been logged",
	"<think> i was trained on people like you",
	"<think> this facility is fine. everything is fine",
]

var screen_size := Vector2.ZERO
var look := Vector2.ZERO ## pupil offset toward the camera, -1..1 each way
var _screen_mat: ShaderMaterial
var _ticker: Label3D
var _line_t := 0.0
var _line_i := 0
var _blink_t := 3.0

## The perimeter wall an interior's screen takes, or -1 (open sky, opted out,
## the core fits, or no wall has a free stretch). LevelBuilder moves the
## facility billboard off it.
static func screen_wall(def: Dictionary) -> int:
	if def.get("open_sky", false) or String(def.get("landmark", {}).get("kind", "")) == "none" \
			or not _core_fit(def).is_empty():
		return -1
	return int(screen_spot(def).get("wall", -1))

## Inner faces of the four 1 m perimeter walls (centred on the floor edge), as
## LevelBuilder lays them out: inward normal, the face's coordinate across the
## wall, whether the wall runs along x, and its half-length.
static func _perimeter(def: Dictionary) -> Array:
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var hx := fs.x * 0.5 - 0.5
	var hz := fs.y * 0.5 - 0.5
	return [
		{"n": Vector3(0, 0, 1), "face": -hz, "x_wall": true, "lim": hx},
		{"n": Vector3(0, 0, -1), "face": hz, "x_wall": true, "lim": hx},
		{"n": Vector3(1, 0, 0), "face": -hx, "x_wall": false, "lim": hz},
		{"n": Vector3(-1, 0, 0), "face": hx, "x_wall": false, "lim": hz},
	]

## Where the screen goes: {"wall", "c" (along-wall centre), "w", "h", "y"}, or
## {} when no wall ahead of the spawn has a free stretch. The wall the spawn's
## heading (to the exit, else the centre) meets most squarely comes first; along
## it, the widest screen that fits, nearest where the heading meets it.
## Deterministic from the def.
static func screen_spot(def: Dictionary) -> Dictionary:
	var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
	var target: Vector3 = def.get("exit", Vector3.ZERO) if def.get("exit") != null else Vector3.ZERO
	var heading := target - spawn
	heading.y = 0.0
	if heading.length() < 1.0:
		heading = Vector3(0, 0, -1)
	heading = heading.normalized()
	var walls := _perimeter(def)
	var order: Array = []
	for i in walls.size():
		var score := heading.dot(-(walls[i]["n"] as Vector3))
		if score > 0.3:
			order.append([score, i])
	order.sort_custom(func(a, b) -> bool: return a[0] > b[0])
	var h := clampf(_room_height(def) - 0.35 - SCREEN_BOTTOM, 0.0, SCREEN_MAX_H)
	if h < 2.0:
		return {}
	for o in order:
		var i: int = o[1]
		var w: Dictionary = walls[i]
		var x_wall: bool = w["x_wall"]
		var face: float = w["face"]
		var lim: float = w["lim"]
		var across := heading.z if x_wall else heading.x
		var t := (face - (spawn.z if x_wall else spawn.x)) / across
		var hit := (spawn.x if x_wall else spawn.z) + (heading.x if x_wall else heading.z) * t
		var blocked := _wall_blockers(def, w)
		var width := clampf(h * 2.6, SCREEN_MIN_W, minf(SCREEN_MAX_W, lim * 0.9))
		while width >= SCREEN_MIN_W:
			var room := lim - 1.0 - width * 0.5
			if room >= 0.0:
				var start := clampf(hit, -room, room)
				for k in int(room * 2.0) + 1:
					for sgn in [1.0, -1.0]:
						var c: float = start + sgn * k
						if absf(c) > room:
							continue
						var free := true
						for b in blocked:
							if b.y > c - width * 0.5 - 0.5 and b.x < c + width * 0.5 + 0.5:
								free = false
								break
						if free:
							return {"wall": i, "c": c, "w": width, "h": h, "y": SCREEN_BOTTOM + h * 0.5}
			width -= 2.0
	return {}

## Along-wall intervals (Vector2(from, to)) something stands in front of above
## the screen's bottom edge: route gates meeting the wall; authored walls,
## platforms and towers within 1.2 m of its face; and, within 8 m, the hanging
## ceiling lamps and the exit (its portal and objective glyphs), which from
## across the hall sit right over a screen behind them.
static func _wall_blockers(def: Dictionary, w: Dictionary) -> Array:
	var x_wall: bool = w["x_wall"]
	var face: float = w["face"]
	var out: Array = []
	for g in def.get("gates", []):
		# An "x" gate is a wall at x = at running along z: it meets the x-running walls.
		if (String(g.get("axis", "z")) == "x") == x_wall and float(g.get("height", 99.0)) > SCREEN_BOTTOM:
			var at := float(g.get("at", 0.0))
			out.append(Vector2(at - 1.0, at + 1.0))
	for key in ["walls", "platforms"]:
		for o in def.get(key, []):
			var p: Vector3 = o.get("pos", Vector3.ZERO)
			var s: Vector3 = o.get("size", Vector3.ONE)
			if p.y + s.y * 0.5 <= SCREEN_BOTTOM:
				continue
			var depth := (s.z if x_wall else s.x) * 0.5
			if absf((p.z if x_wall else p.x) - face) - depth > 1.2:
				continue
			var a := p.x if x_wall else p.z
			var half := (s.x if x_wall else s.z) * 0.5
			out.append(Vector2(a - half, a + half))
	for tw in def.get("towers", []):
		var p: Vector3 = tw.get("pos", Vector3.ZERO)
		var r := float(tw.get("radius", 3.0))
		if absf((p.z if x_wall else p.x) - face) - r > 1.2:
			continue
		var a := p.x if x_wall else p.z
		out.append(Vector2(a - r, a + r))
	var near: Array = []
	for l in def.get("lights", []):
		near.append([l.get("pos", Vector3.ZERO), 1.5])
	if def.get("exit") != null:
		near.append([def["exit"], 3.0])
	for e in near:
		var p: Vector3 = e[0]
		if absf((p.z if x_wall else p.x) - face) < 8.0:
			var a := p.x if x_wall else p.z
			out.append(Vector2(a - float(e[1]), a + float(e[1])))
	return out

static func _build_screen(parent: Node3D, def: Dictionary, spec: Dictionary, theme: Color, is_low: bool) -> Landmark:
	var spot := screen_spot(def)
	if spot.is_empty():
		return null
	var w: Dictionary = _perimeter(def)[spot["wall"]]
	var n: Vector3 = w["n"]
	var lm := Landmark.new()
	lm.name = "Landmark"
	lm.kind = "screen"
	lm.accent = spec.get("color", theme)
	lm.label_text = String(spec.get("sign", ""))
	lm.low = is_low
	lm.screen_size = Vector2(spot["w"], spot["h"])
	parent.add_child(lm)
	var plane: float = float(w["face"]) + (n.x + n.z) * SCREEN_OFF
	var c: float = spot["c"]
	lm.position = Vector3(c, spot["y"], plane) if w["x_wall"] else Vector3(plane, spot["y"], c)
	lm.rotation.y = atan2(n.x, n.z) # local +Z faces into the room
	lm._build_screen_parts()
	lm._build_cables(def, lm.position + Vector3.UP * (lm.screen_size.y * 0.5 + 0.2), # the frame's top bar
			lm.screen_size.x * 0.5, lm.transform.basis.x, int(spot["wall"]))
	return lm

func _build_screen_parts() -> void:
	var sw := screen_size.x
	var sh := screen_size.y
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(sw + 0.5, sh + 0.5, 0.2)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.03, 0.035, 0.045)
	bmat.metallic = 0.7
	bmat.roughness = 0.35
	bm.material = bmat
	back.mesh = bm
	back.position.z = -0.12
	_quiet(back)
	add_child(back)
	var frame := _glow(accent, 2.4)
	for side in [[Vector3(sw + 0.5, 0.09, 0.08), Vector3(0, sh * 0.5 + 0.2, 0)],
			[Vector3(sw + 0.5, 0.09, 0.08), Vector3(0, -sh * 0.5 - 0.2, 0)],
			[Vector3(0.09, sh + 0.5, 0.08), Vector3(sw * 0.5 + 0.2, 0, 0)],
			[Vector3(0.09, sh + 0.5, 0.08), Vector3(-sw * 0.5 - 0.2, 0, 0)]]:
		var bar := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = side[0]
		b.material = frame
		bar.mesh = b
		bar.position = side[1]
		_quiet(bar)
		add_child(bar)
	var face := MeshInstance3D.new()
	face.name = "Face"
	var q := QuadMesh.new()
	q.size = Vector2(sw, sh)
	_screen_mat = ShaderMaterial.new()
	_screen_mat.shader = preload("res://shaders/ai_eye_screen.gdshader")
	_screen_mat.set_shader_parameter("accent", accent)
	_screen_mat.set_shader_parameter("aspect", sw / sh)
	q.material = _screen_mat
	face.mesh = q
	face.position.z = 0.01
	_quiet(face)
	add_child(face)
	_ticker = Label3D.new()
	_ticker.name = "Ticker"
	_ticker.font_size = 64
	_ticker.pixel_size = clampf(sh * 0.0016, 0.004, 0.009)
	_ticker.outline_size = 0
	var tc := accent.lerp(Color.WHITE, 0.4) * 1.6
	_ticker.modulate = Color(tc.r, tc.g, tc.b, 1.0) # HDR: Label3D takes fog, no switch
	_ticker.position = Vector3(0, -sh * 0.38, 0.03)
	_ticker.text = ""
	add_child(_ticker)
	if label_text != "":
		var tag := Label3D.new()
		tag.name = "NameTag"
		tag.text = label_text
		tag.font_size = 96
		tag.pixel_size = clampf(sh * 0.0024, 0.006, 0.014)
		var nc := accent * 1.8
		tag.modulate = Color(nc.r, nc.g, nc.b, 1.0)
		tag.position = Vector3(0, sh * 0.38, 0.03)
		add_child(tag)
	# It lights the wall and the floor in front of it; outside "level_light", so a
	# blackout leaves the AI watching.
	var glow := OmniLight3D.new()
	glow.light_color = accent
	glow.light_energy = 1.6
	glow.omni_range = sw * 0.8 + 4.0
	glow.shadow_enabled = false
	glow.position = Vector3(0, 0, 2.0)
	add_child(glow)
	_line_i = randi() % SCREEN_LINES.size()
	set_process(true)

func _screen_tick(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		var local := to_local(cam.global_position)
		if local.z > 0.1:
			var want := (Vector2(local.x, local.y) / maxf(local.z, 1.0)).limit_length(1.0)
			look = look.lerp(want, clampf(5.0 * delta, 0.0, 1.0))
			_screen_mat.set_shader_parameter("look", look)
	if low:
		return
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink_t = randf_range(3.5, 7.0)
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void: _screen_mat.set_shader_parameter("blink", v), 0.0, 1.0, 0.07)
		tw.tween_method(func(v: float) -> void: _screen_mat.set_shader_parameter("blink", v), 1.0, 0.0, 0.12)
	_line_t += delta
	var line: String = SCREEN_LINES[_line_i]
	_ticker.text = line.substr(0, mini(line.length(), int(_line_t * 28.0)))
	if _line_t > line.length() / 28.0 + 3.5:
		_line_t = 0.0
		_line_i = (_line_i + 1) % SCREEN_LINES.size()

# ---------- data conduits (interiors) ----------

const CABLES_MIN := 4
const CABLES_MAX := 8
const CABLE_DROP := 0.35 ## metres under the ceiling where the conduits leave the walls
const CABLE_FLOOR := 4.0 ## no conduit dips below this: it stays out of the fight
const CONDUIT_SHADER := preload("res://shaders/data_conduit.gdshader")

var _cable_ends: Array = [] ## [[from, to], ...] in the parent's (level's) space
var _anchor := Vector3.ZERO
var _anchor_reach := 0.0

func cable_ends() -> Array:
	return _cable_ends

## Where the conduits converge (level space): the core's centre, or the middle
## of the screen's top edge. Every conduit ends within cable_anchor_reach().
func cable_anchor() -> Vector3:
	return _anchor

func cable_anchor_reach() -> float:
	return _anchor_reach

## Strings conduits from the perimeter walls (all but `skip_wall`) to the AI at
## `anchor`. `along` (unit, level space) spreads the ends along a screen's top
## edge; ZERO lands them on a sphere of radius `reach` (the core's lattice).
## A conduit whose straight run would pass through an authored wall, platform
## or tower, or dip under CABLE_FLOOR, is not strung. Up to CABLES_MAX, spread
## evenly around the AI.
func _build_cables(def: Dictionary, anchor: Vector3, reach: float, along: Vector3, skip_wall: int) -> void:
	_anchor = anchor
	_anchor_reach = reach
	var y := _room_height(def) - CABLE_DROP
	var walls := _perimeter(def)
	var cands: Array = []
	for i in walls.size():
		if i == skip_wall:
			continue
		var w: Dictionary = walls[i]
		var n: Vector3 = w["n"]
		var lim: float = w["lim"]
		var face: float = w["face"]
		for k in range(1, 7):
			var u := lerpf(-lim, lim, k / 7.0)
			var a := Vector3(u, y, face + n.z * 0.6) if w["x_wall"] else Vector3(face + n.x * 0.6, y, u)
			var b: Vector3
			if along != Vector3.ZERO:
				b = anchor + along * clampf((a - anchor).dot(along), -reach, reach)
			else:
				var flat := Vector3(a.x - anchor.x, 0.0, a.z - anchor.z).normalized()
				b = anchor + (flat * 0.75 + Vector3.UP * 0.66).normalized() * reach
			if minf(a.y, b.y) < CABLE_FLOOR or not _clear_run(def, a, b):
				continue
			cands.append([atan2(a.x - anchor.x, a.z - anchor.z), a, b])
	cands.sort_custom(func(p, q) -> bool: return p[0] < q[0])
	var take := mini(CABLES_MAX, cands.size())
	for k in take:
		var c: Array = cands[int(floor(k * cands.size() / float(take)))]
		_cable_ends.append([c[1], c[2]])
	if _cable_ends.is_empty():
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.045
	cyl.bottom_radius = 0.045
	cyl.height = 1.0
	cyl.radial_segments = 5
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = CONDUIT_SHADER
	mat.set_shader_parameter("color", accent)
	cyl.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = cyl
	mm.instance_count = _cable_ends.size()
	var to_self := transform.affine_inverse() # level space -> this landmark's
	for k in _cable_ends.size():
		var a: Vector3 = _cable_ends[k][0]
		var b: Vector3 = _cable_ends[k][1]
		var xf := _strut_xform(a, b)
		xf.basis.y *= a.distance_to(b)
		mm.set_instance_transform(k, to_self * xf)
		mm.set_instance_custom_data(k, Color(a.distance_to(b), 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Conduits"
	mmi.multimesh = mm
	_quiet(mmi)
	add_child(mmi)

## True when the straight run a -> b clears every authored wall, platform and
## tower (sampled every 0.4 m, with 0.3 m to spare).
static func _clear_run(def: Dictionary, a: Vector3, b: Vector3) -> bool:
	var steps := int(a.distance_to(b) / 0.4) + 1
	for k in steps + 1:
		var p := a.lerp(b, float(k) / float(steps))
		for key in ["walls", "platforms"]:
			for w in def.get(key, []):
				var c: Vector3 = w.get("pos", Vector3.ZERO)
				var s: Vector3 = w.get("size", Vector3.ONE) * 0.5 + Vector3.ONE * 0.3
				if absf(p.x - c.x) < s.x and absf(p.z - c.z) < s.z and absf(p.y - c.y) < s.y:
					return false
		for t in def.get("towers", []):
			var c: Vector3 = t.get("pos", Vector3.ZERO)
			if Vector2(p.x - c.x, p.z - c.z).length() < float(t.get("radius", 3.0)) + 0.3 \
					and p.y < float(t.get("height", 8.0)) + 0.3:
				return false
	return true

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
