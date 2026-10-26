class_name GaussFx
extends SignatureFx
## The ARC-9 Gauss Lance's signature: a railgun that shows the rails. Two
## magnetic rails run along the barrel behind the muzzle; holding the charge
## (alt fire) lights them from cold to white-hot with the charge, and at full
## charge arcs jump between them. Every robot the lance punches through gets a
## punch-through ring, a disc of light round the shot line where it passed; and
## a round into a wall leaves a slag spot, a molten fleck that cools from white
## through orange to dark. Covered by tests/gauss_fx_probe.

const RAIL_LEN := 0.32 ## metres the rails run back from the muzzle
const RAIL_GAP := 0.035 ## metres either side of the bore
const RAIL_COLD := 0.25 ## rail emission uncharged
const RAIL_HOT := 9.0 ## rail emission at full charge
const SPARK_AT := 0.95 ## charge past which arcs jump between the rails
const PIERCE_RING_TIME := 0.25
const SLAG_LIFE := 2.0
const SLAG_RADIUS := 0.09

var rails: Array[MeshInstance3D] = []
var _rail_mats: Array[StandardMaterial3D] = []
var spark: ArcBolt = null

func on_process(_delta: float) -> void:
	_build_rails()
	if _rail_mats.is_empty():
		return
	var c := charge()
	var col := _color()
	for m in _rail_mats:
		m.emission = col.lerp(Color.WHITE, c * 0.7)
		m.emission_energy_multiplier = lerpf(RAIL_COLD, RAIL_HOT, c)
	if spark:
		spark.visible = c >= SPARK_AT
		if spark.visible:
			# Between the rails, somewhere along their run behind the tip.
			var muzzle := rails[0].get_parent() as Node3D
			var z := 0.04 + RAIL_LEN * randf_range(0.1, 0.9)
			spark.zap(muzzle.to_global(Vector3(-RAIL_GAP, 0, z)),
					muzzle.to_global(Vector3(RAIL_GAP, 0, z + randf_range(-0.04, 0.04))), 0.015)

## The alt charge right now, 0..1.
func charge() -> float:
	var c = weapon.get("_alt_charge")
	return float(c) if c != null else 0.0

func rail_energy() -> float:
	return _rail_mats[0].emission_energy_multiplier if not _rail_mats.is_empty() else 0.0

func on_enemy_hit(pos: Vector3, _normal: Vector3, dir: Vector3, _dmg: float, _crit: bool) -> void:
	_pierce_ring(pos, dir)

func on_world_hit(pos: Vector3, normal: Vector3, _dir: Vector3, _surface: String) -> void:
	_slag(pos, normal)

func _color() -> Color:
	var data: WeaponData = weapon.get("data")
	return data.tracer_color if data else Color(0.6, 0.9, 1.0)

func _build_rails() -> void:
	if not rails.is_empty():
		return
	var muzzle: Node3D = weapon.get("muzzle")
	if muzzle == null:
		return
	for side in [-1.0, 1.0]:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.008, 0.012, RAIL_LEN)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = _color().darkened(0.4)
		m.emission_enabled = true
		m.emission = _color()
		m.emission_energy_multiplier = RAIL_COLD
		bm.material = m
		var mi := MeshInstance3D.new()
		mi.set_meta("sig_fx", "gauss_rail")
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Behind the tip (+Z is back toward the stock), either side of the bore.
		mi.position = Vector3(side * RAIL_GAP, 0.0, RAIL_LEN * 0.5 + 0.02)
		muzzle.add_child(mi)
		rails.append(mi)
		_rail_mats.append(m)
	spark = ArcBolt.make(4, 0.006, _color())
	spark.set_meta("sig_fx", "rail_spark")
	spark.visible = false
	muzzle.add_child(spark)

## A thin disc of light round the shot line where it passed through a robot.
func _pierce_ring(pos: Vector3, dir: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	var d := dir.normalized()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.2
	tm.rings = 32
	tm.ring_segments = 5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(_color().lerp(Color.WHITE, 0.4), 0.9)
	mat.emission_enabled = true
	mat.emission = _color()
	mat.emission_energy_multiplier = 7.0
	tm.material = mat
	var mi := MeshInstance3D.new()
	mi.set_meta("sig_fx", "pierce_ring")
	mi.mesh = tm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(d, up) * Basis(Vector3.RIGHT, -PI * 0.5), pos)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(3.0, 1.0, 3.0), PIERCE_RING_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, PIERCE_RING_TIME)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, PIERCE_RING_TIME)
	tw.chain().tween_callback(mi.queue_free)

## A molten fleck on the wall that cools from white through orange to dark.
func _slag(pos: Vector3, normal: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	var n := normal.normalized()
	var slag := Slag.new()
	slag.name = "GaussSlag"
	slag.set_meta("sig_fx", "slag")
	root.add_child(slag)
	var up := Vector3.UP if absf(n.y) < 0.99 else Vector3.RIGHT
	# Local +Y on the normal: the disc lies flat on the wall.
	slag.global_transform = Transform3D(Basis.looking_at(n, up) * Basis(Vector3.RIGHT, -PI * 0.5), pos + n * 0.01)

class Slag extends Node3D:
	var mat: StandardMaterial3D
	var age := 0.0

	func _ready() -> void:
		var cm := CylinderMesh.new()
		cm.top_radius = GaussFx.SLAG_RADIUS
		cm.bottom_radius = GaussFx.SLAG_RADIUS
		cm.height = 0.004
		cm.radial_segments = 14
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		cm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_tick(0.0)

	func heat() -> float:
		return clampf(1.0 - age / GaussFx.SLAG_LIFE, 0.0, 1.0)

	func _process(delta: float) -> void:
		_tick(delta)
		if age >= GaussFx.SLAG_LIFE:
			queue_free()

	func _tick(delta: float) -> void:
		age += delta
		var k := heat()
		var col := Color.WHITE.lerp(Color(1.0, 0.45, 0.1), clampf((1.0 - k) * 2.0, 0.0, 1.0))
		col = col.lerp(Color(0.12, 0.05, 0.03), clampf((0.5 - k) * 2.0, 0.0, 1.0))
		mat.albedo_color = Color(col, clampf(k * 2.0, 0.0, 1.0))
		mat.emission = col
		mat.emission_energy_multiplier = 8.0 * k * k
