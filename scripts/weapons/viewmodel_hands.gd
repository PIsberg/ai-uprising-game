class_name ViewmodelHands
extends Node3D
## The player's gloved hands and sleeved forearms, holding the viewmodel gun.
## Built once per gun from primitives (no rig, no asset) and parented under the
## Viewmodel, so every kick, sway, sprint pose and reload moves hands and gun
## together. `fit` reads where to hold each gun off its own mesh: the trigger
## hand closes on the lowest vertices in the rear half (the grip), and a long gun
## gets a support hand cupping the underside of its fore-end. The Blaster Kit
## guns are toy-chunky, so the hands scale with the gun's height (`hand_scale`)
## rather than staying human-sized and reading as doll's hands. The forearms run
## back from the wrists to an elbow point beside and below the eye, out of the
## camera's view at hip and at ADS, so no arm ever ends in mid-air on screen.
## Covered by tests/viewmodel_hands_probe.

## Fitted gun length (metres) from which the gun is held with two hands.
const TWO_HAND_LEN := 0.5
## Elbows in viewmodel space. The WeaponHolder sits at (0.25, -0.22, -0.45) from
## the eye, so these are low, beside and ahead of the camera: well outside the
## frustum, and the forearm never crosses the near plane. The left elbow is
## flared out wide so that forearm crosses the view side-on and its hand shows,
## instead of pointing at the eye and hiding the hand behind its own sleeve.
const ELBOW_RIGHT := Vector3(0.2, -0.48, 0.3)
const ELBOW_LEFT := Vector3(-0.74, -0.5, 0.12)
## The grip's rake: a hand closes round it tilted top-forward.
const GRIP_RAKE := -0.2
## How far ahead of the viewmodel origin (z, metres) Weapon parks a gun's grip:
## about 0.55 m from the eye, where the trigger hand is inside the bottom of the
## frame instead of under it, without shrinking a pistol to a toy.
const GRIP_Z := -0.1

var trigger_hand: Node3D = null
var support_hand: Node3D = null
var _ends: Array[Node3D] = []

static var _glove_mat: StandardMaterial3D
static var _plate_mat: StandardMaterial3D
static var _sleeve_mat: StandardMaterial3D

## Build the hands for a fitted gun under `viewmodel`: `pts` from grip_points,
## `box` the gun's fitted AABB in viewmodel space, `accent` its energy colour
## (the sleeve's status band and the knuckle LEDs take it).
static func fit(viewmodel: Node3D, pts: Dictionary, box: AABB, accent: Color) -> ViewmodelHands:
	var h := ViewmodelHands.new()
	h.name = "Hands"
	viewmodel.add_child(h)
	var k := hand_scale(box)
	h._build_trigger_hand(pts["grip"], pts["grip_w"], k, accent)
	if box.size.z >= TWO_HAND_LEN:
		h._build_support_hand(pts["fore"], pts["fore_w"], k, accent)
	return h

## Hand size for a gun `box`: 1 is a real hand (a gun 0.2 m tall), growing with
## the gun's height up to 1.5x for the chunkiest.
static func hand_scale(box: AABB) -> float:
	return clampf(box.size.y / 0.2, 1.0, 1.5)

## The far end of every forearm (one per hand), for the off-screen check.
func forearm_ends() -> Array[Node3D]:
	return _ends

## Where the hands close, from the gun's vertices in viewmodel space:
##   grip   the trigger hand: centred on the grip (vertices in the rear half
##          and the lower 45% of the gun), between its bottom and the receiver;
##   grip_w the grip's width across x;
##   fore   the support palm's top: a third of the way back from the muzzle but
##          at least 0.22 lengths ahead of the grip, on the underside of the
##          body there (the lowest vertex above the grip band, so a magazine
##          hanging below is not mistaken for the fore-end);
##   fore_w the fore-end's width there.
## Falls back to fixed fractions of `box` when a band holds no vertices.
static func grip_points(verts: PackedVector3Array, box: AABB) -> Dictionary:
	var length := box.size.z
	var y_band := box.position.y + box.size.y * 0.45
	var mid_z := box.position.z + length * 0.5
	var zs: Array[float] = []
	var y_min := INF
	var x_lo := INF
	var x_hi := -INF
	for v in verts:
		if v.z > mid_z and v.y < y_band:
			zs.append(v.z)
			y_min = minf(y_min, v.y)
			x_lo = minf(x_lo, v.x)
			x_hi = maxf(x_hi, v.x)
	var cx := box.position.x + box.size.x * 0.5
	var grip := Vector3(cx, box.position.y + box.size.y * 0.3, box.end.z - length * 0.3)
	var grip_w := 0.035
	if zs.size() >= 3:
		zs.sort()
		grip = Vector3(cx, lerpf(y_min, y_band, 0.6), zs[int(zs.size() * 0.5)])
		grip_w = clampf(x_hi - x_lo, 0.025, 0.06)
	var fz := minf(box.position.z + length * 0.33, grip.z - length * 0.22)
	var fy := INF
	var fy_any := INF
	var fx_lo := INF
	var fx_hi := -INF
	for v in verts:
		if absf(v.z - fz) < 0.03:
			fy_any = minf(fy_any, v.y)
			if v.y > y_band:
				fy = minf(fy, v.y)
			fx_lo = minf(fx_lo, v.x)
			fx_hi = maxf(fx_hi, v.x)
	if fy == INF:
		fy = fy_any
	var fore := Vector3(cx, box.position.y + box.size.y * 0.55, fz)
	var fore_w := 0.045
	if fy < INF:
		fore.y = fy
		fore_w = clampf(fx_hi - fx_lo, 0.03, 0.08)
	return {"grip": grip, "grip_w": grip_w, "fore": fore, "fore_w": fore_w}

## Every vertex of `model`'s meshes, in `viewmodel` space.
static func vertices(viewmodel: Node3D, model: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var inv := viewmodel.global_transform.affine_inverse()
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			if arr.is_empty():
				continue
			for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
				out.append(xf * v)
	return out

# ---------- the trigger hand ----------
## Right hand round the grip: palm on the far (right) side, three fingers
## wrapping the front strap and across the near side, the index finger laid
## forward through the trigger guard, the thumb along the near side above them.
func _build_trigger_hand(grip: Vector3, grip_w: float, k: float, accent: Color) -> void:
	# Built at real-hand size round a grip shrunk by 1/k, then scaled by k.
	var hw := grip_w * 0.5 / k
	var gd := clampf(grip_w * 1.15 / k, 0.035, 0.06) # front-to-back depth of the grip
	var hand := Node3D.new()
	hand.name = "TriggerHand"
	hand.position = grip
	hand.rotation.x = GRIP_RAKE
	hand.scale = Vector3.ONE * k
	add_child(hand)
	trigger_hand = hand
	_box(hand, Vector3(0.026, 0.085, gd + 0.035), Vector3(hw + 0.013, -0.006, 0.006), _glove())
	var front := -gd * 0.5 - 0.008
	for fy: float in [0.012, -0.012, -0.035]:
		# Across the front strap, then back along the near side.
		_capsule(hand, Vector3(hw + 0.006, fy, front), Vector3(-hw - 0.004, fy, front), 0.0105, _glove())
		_capsule(hand, Vector3(-hw - 0.009, fy, front), Vector3(-hw - 0.009, fy, front + 0.04), 0.0105, _glove())
	# Index on the trigger, thumb above it on the near side.
	_capsule(hand, Vector3(-hw - 0.006, 0.034, -0.004), Vector3(-hw - 0.004, 0.03, front - 0.03), 0.0095, _glove())
	_capsule(hand, Vector3(-hw - 0.012, 0.05, 0.02), Vector3(-hw - 0.01, 0.058, -0.03), 0.0105, _glove())
	# Armoured knuckle plate on the near side, with a status LED in the gun's colour.
	_box(hand, Vector3(0.008, 0.07, 0.03), Vector3(-hw - 0.021, -0.012, front + 0.018), _plate())
	_led(hand, Vector3(-hw - 0.026, 0.016, front + 0.018), accent)
	_forearm(hand.transform * Vector3(hw * 0.5 + 0.01, -0.04, 0.045), ELBOW_RIGHT, k, accent)

# ---------- the support hand ----------
## Left hand cupping the fore-end from below: palm under the gun, fingers up the
## near side spread along the barrel, thumb along the far side.
func _build_support_hand(fore: Vector3, fore_w: float, k: float, accent: Color) -> void:
	var hw := fore_w * 0.5 / k
	var hand := Node3D.new()
	hand.name = "SupportHand"
	hand.position = fore
	hand.scale = Vector3.ONE * k
	add_child(hand)
	support_hand = hand
	_box(hand, Vector3(hw * 2.0 + 0.024, 0.024, 0.09), Vector3(0.0, -0.012, 0.0), _glove())
	for fz: float in [-0.033, -0.011, 0.011, 0.033]:
		_capsule(hand, Vector3(-hw - 0.008, -0.012, fz), Vector3(-hw - 0.01, 0.03, fz - 0.004), 0.0095, _glove())
	_capsule(hand, Vector3(hw + 0.008, -0.01, 0.03), Vector3(hw + 0.01, 0.018, -0.03), 0.0105, _glove())
	_box(hand, Vector3(0.008, 0.026, 0.085), Vector3(-hw - 0.02, 0.0, 0.0), _plate())
	_led(hand, Vector3(-hw - 0.025, 0.004, -0.03), accent)
	_forearm(hand.transform * Vector3(-0.01, -0.03, 0.05), ELBOW_LEFT, k, accent)

## Glove cuff, then a sleeve that thickens toward the elbow: an alloy vambrace
## over the forearm with a thin status band in the gun's colour at its wrist
## end, and two fabric rucks further up so the sleeve reads as cloth, not pipe.
func _forearm(wrist: Vector3, elbow: Vector3, k: float, accent: Color) -> void:
	var dir := (elbow - wrist).normalized()
	var at := func(d: float) -> Vector3: return wrist + dir * d * k
	_tube(self, at.call(-0.02), at.call(0.05), 0.031 * k, 0.034 * k, _glove())
	_tube(self, at.call(0.04), elbow + dir * 0.08, 0.038 * k, 0.052 * k, _sleeve())
	_tube(self, at.call(0.075), at.call(0.2), 0.042 * k, 0.046 * k, _plate())
	var band := StandardMaterial3D.new()
	band.albedo_color = accent * 0.3
	band.emission_enabled = true
	band.emission = accent
	band.emission_energy_multiplier = 0.8
	_tube(self, at.call(0.085), at.call(0.093), 0.0435 * k, 0.0437 * k, band)
	for d: float in [0.25, 0.31]:
		_tube(self, at.call(d), at.call(d + 0.022), 0.048 * k, 0.05 * k, _sleeve())
	var end := Node3D.new()
	end.name = "Elbow"
	end.position = elbow
	add_child(end)
	_ends.append(end)

# ---------- primitives ----------
func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := BeveledBoxMesh.new()
	m.size = size
	m.bevel = minf(0.006, size[size.min_axis_index()] * 0.3)
	m.material = mat
	_add(parent, m, Transform3D(Basis(), pos))

func _capsule(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(a.distance_to(b) + r * 2.0, r * 2.0 + 0.001)
	m.radial_segments = 10
	m.rings = 3
	m.material = mat
	_add(parent, m, Transform3D(_basis_y(b - a), (a + b) * 0.5))

func _tube(parent: Node3D, a: Vector3, b: Vector3, r_a: float, r_b: float, mat: Material) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_b # CylinderMesh's top is +Y, which _basis_y points at b
	m.bottom_radius = r_a
	m.height = a.distance_to(b)
	m.radial_segments = 14
	m.rings = 1
	m.material = mat
	_add(parent, m, Transform3D(_basis_y(b - a), (a + b) * 0.5))

func _led(parent: Node3D, pos: Vector3, col: Color) -> void:
	var m := SphereMesh.new()
	m.radius = 0.004
	m.height = 0.008
	m.radial_segments = 8
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	m.material = mat
	_add(parent, m, Transform3D(Basis(), pos))

func _add(parent: Node3D, mesh: Mesh, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

## A basis whose +Y runs along `dir`.
static func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.BACK if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))

# ---------- shared materials ----------
## Synthetic tactical glove: near-black, soft sheen, a faint rim so the fingers
## still read against a dark level.
static func _glove() -> StandardMaterial3D:
	if _glove_mat == null:
		_glove_mat = StandardMaterial3D.new()
		_glove_mat.albedo_color = Color(0.1, 0.1, 0.11)
		_glove_mat.roughness = 0.62
		_glove_mat.rim_enabled = true
		_glove_mat.rim = 0.25
		_glove_mat.rim_tint = 0.3
	return _glove_mat

## Knuckle armour: brushed dark alloy.
static func _plate() -> StandardMaterial3D:
	if _plate_mat == null:
		_plate_mat = StandardMaterial3D.new()
		_plate_mat.albedo_color = Color(0.26, 0.27, 0.29)
		_plate_mat.metallic = 0.75
		_plate_mat.roughness = 0.36
	return _plate_mat

## Resistance fatigues: worn olive drab, matte.
static func _sleeve() -> StandardMaterial3D:
	if _sleeve_mat == null:
		_sleeve_mat = StandardMaterial3D.new()
		_sleeve_mat.albedo_color = Color(0.17, 0.18, 0.14)
		_sleeve_mat.roughness = 0.94
		_sleeve_mat.rim_enabled = true
		_sleeve_mat.rim = 0.15
		_sleeve_mat.rim_tint = 0.5
	return _sleeve_mat
