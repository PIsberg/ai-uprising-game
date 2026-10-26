class_name ArcCoilFx
extends SignatureFx
## The CL-3 Arc Coil's signature: a capacitor gun you can read. Three amber
## coil rings round the barrel behind the muzzle hold the burst: each round
## drains one (it goes dark), and through the burst cooldown they recharge one
## by one, so the gun shows whether the next burst is ready. A round into a wall
## discharges across it, amber arcs skittering out along the surface; a round
## into a robot throws a cosmetic arc on to the nearest other robot within
## JUMP_RANGE, the charge looking for ground. Covered by tests/arccoil_fx_probe.

const RING_COUNT := 3
const RING_RADIUS := 0.045 ## metres round the bore
const RING_GAP := 0.035 ## metres between rings along the barrel
const RING_LIT := 6.0 ## emission of a charged ring
const RECHARGE := 0.18 ## seconds per ring once the burst is done
const RECHARGE_DELAY := 0.12 ## seconds after the last round before the first ring refills
const SURFACE_ARCS := 3
const SURFACE_REACH := Vector2(0.35, 0.65)
const JUMP_RANGE := 6.0
const ARC_TIME := 0.16

var rings: Array[MeshInstance3D] = []
var _ring_mats: Array[StandardMaterial3D] = []
var charge := float(RING_COUNT) ## rings charged, fractional while refilling
var _since_shot := 999.0

func on_fire() -> void:
	_build_rings()
	charge = maxf(0.0, floorf(charge - 0.001))
	_since_shot = 0.0
	_paint()

func on_process(delta: float) -> void:
	_build_rings()
	_since_shot += delta
	if _since_shot > RECHARGE_DELAY and charge < RING_COUNT:
		charge = minf(float(RING_COUNT), charge + delta / RECHARGE)
		_paint()

func on_world_hit(pos: Vector3, normal: Vector3, _dir: Vector3, _surface: String) -> void:
	_discharge(pos, normal)

func on_enemy_hit(pos: Vector3, _normal: Vector3, _dir: Vector3, _dmg: float, _crit: bool) -> void:
	_jump(pos)

## Rings lit right now (a ring counts once it is fully refilled).
func lit_rings() -> int:
	return int(floorf(charge + 0.001))

func _color() -> Color:
	var data: WeaponData = weapon.get("data")
	return data.tracer_color if data else Color(1.0, 0.7, 0.25)

func _build_rings() -> void:
	if not rings.is_empty():
		return
	var muzzle: Node3D = weapon.get("muzzle")
	if muzzle == null:
		return
	var col := _color()
	for i in RING_COUNT:
		var tm := TorusMesh.new()
		tm.inner_radius = RING_RADIUS * 0.78
		tm.outer_radius = RING_RADIUS
		tm.rings = 20
		tm.ring_segments = 6
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = RING_LIT
		tm.material = mat
		var mi := MeshInstance3D.new()
		mi.name = "CoilRing%d" % i
		mi.set_meta("sig_fx", "coil_ring")
		mi.mesh = tm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Torus axis +Y laid along the bore (local Z), rings stepping back from the tip.
		mi.rotation_degrees = Vector3(90, 0, 0)
		mi.position = Vector3(0, 0, 0.05 + i * RING_GAP)
		muzzle.add_child(mi)
		rings.append(mi)
		_ring_mats.append(mat)

## Light the charged rings, the refilling one part way, the rest dark. The ring
## nearest the muzzle drains first and refills last.
func _paint() -> void:
	for i in _ring_mats.size():
		var idx := RING_COUNT - 1 - i # back ring = first to refill
		var k := clampf(charge - float(idx), 0.0, 1.0)
		var m := _ring_mats[i]
		m.emission_energy_multiplier = lerpf(0.15, RING_LIT, k)
		m.albedo_color = _color().darkened(0.75 * (1.0 - k))

## Amber arcs skittering out across the struck surface from the hit.
func _discharge(pos: Vector3, normal: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	var n := normal.normalized()
	var t1 := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := n.cross(t1).normalized()
	var start := pos + n * 0.02
	for i in SURFACE_ARCS:
		var ang := TAU * (float(i) + randf_range(-0.3, 0.3)) / SURFACE_ARCS
		var out := (t1 * cos(ang) + t2 * sin(ang)) * randf_range(SURFACE_REACH.x, SURFACE_REACH.y)
		_arc(root, start, start + out, 0.06, "surface_arc")

## A cosmetic arc from the struck robot on to the nearest other robot within
## JUMP_RANGE: the robot hit is the one nearest the hit point.
func _jump(pos: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	var nearest: Node3D = null
	var nearest_d := INF
	var second: Node3D = null
	var second_d := INF
	for e in weapon.get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not is_instance_valid(e):
			continue
		var d := (e as Node3D).global_position.distance_to(pos)
		if d < nearest_d:
			second = nearest
			second_d = nearest_d
			nearest = e
			nearest_d = d
		elif d < second_d:
			second = e
			second_d = d
	if second == null or second.global_position.distance_to(pos) > JUMP_RANGE:
		return
	var to := second.global_position + Vector3.UP * 1.0
	_arc(root, pos, to, 0.25, "arc_jump")

func _arc(root: Node, a: Vector3, b: Vector3, amp: float, tag: String) -> void:
	var bolt := ArcBolt.make(5, 0.016, _color())
	bolt.set_meta("sig_fx", tag)
	root.add_child(bolt)
	bolt.global_position = a
	bolt.zap(a, b, amp)
	var tw := bolt.create_tween()
	tw.tween_method(bolt.set_alpha, 1.0, 0.0, ARC_TIME)
	tw.tween_callback(bolt.queue_free)
