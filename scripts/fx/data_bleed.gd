# @lat: [[weapons#Data Bleed]]
class_name DataBleed
extends RefCounted
## Robots bleed data. Every bullet that lands on a robot spills a spray of
## glowing binary, 0s and 1s tumbling out of the wound and fading as they
## drift down, on top of the sparks and scrap; a crit spills more. When a robot
## dies, whatever killed it, its weights pour out: a BURST_AMOUNT fountain of
## glyphs rising off the chassis.
##
## One CPUParticles3D per spill, a two-frame glyph sheet ("0" | "1", drawn here
## from 5x7 bitmaps) picked per particle with anim_offset. No lights, no
## shadows, unshaded HDR green so it reads in the dark and through fog. Shotgun
## pellets each call spill, so one frame may start at most FRAME_BUDGET
## emitters; the rest are dropped. LOW halves every amount.
## Hooks: Weapon._enemy_hit_pop (hitscan hits) and EnemyBase (hp.died, so the
## subclasses that override _on_died without super still burst).
## Covered by tests/data_bleed_probe.

const GROUP := "data_bleed"
const HIT_MIN := 4
const HIT_MAX := 14
const CRIT_BONUS := 6
const BURST_AMOUNT := 48
const FRAME_BUDGET := 6
const COLOR := Color(0.2, 1.0, 0.42)
const GLYPH_PX := 16
const GLYPHS := [
	["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
]

static var _tex: ImageTexture = null
static var _mat: StandardMaterial3D = null
static var _mesh: QuadMesh = null
static var _frame := -1
static var _spent := 0

## Glyphs for a hit of `dmg` damage.
static func hit_amount(dmg: float, crit: bool) -> int:
	var n := clampi(HIT_MIN + int(dmg * 0.2), HIT_MIN, HIT_MAX)
	return n + (CRIT_BONUS if crit else 0)

## Glyphs a spill node was started with (the probe reads it).
static func amount_of(n: Node) -> int:
	return int(n.get_meta("glyphs", 0))

## Sprays `amount` glyphs at `at`, thrown along `dir`. Returns the emitter, or
## null when this frame's budget is spent.
static func spill(parent: Node, at: Vector3, dir: Vector3, amount: int) -> CPUParticles3D:
	return _emit(parent, at, dir, amount, 55.0, Vector2(1.2, 3.2), Vector3(0, -4.0, 0), 0.75, 0.14, false)

## The death fountain: BURST_AMOUNT glyphs rising off a body centred at `at`.
static func burst(parent: Node, at: Vector3) -> CPUParticles3D:
	return _emit(parent, at, Vector3.UP, BURST_AMOUNT, 70.0, Vector2(1.5, 4.0), Vector3(0, -1.5, 0), 1.3, 0.2, true)

static func _emit(parent: Node, at: Vector3, dir: Vector3, amount: int, spread: float, vel: Vector2,
		grav: Vector3, life: float, size: float, always: bool) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var f := Engine.get_physics_frames()
	if f != _frame:
		_frame = f
		_spent = 0
	if _spent >= FRAME_BUDGET and not always:
		return null
	_spent += 1
	var p := CPUParticles3D.new()
	p.name = "DataBleed"
	p.add_to_group(GROUP)
	p.set_meta("glyphs", amount)
	var low := false
	var gs := parent.get_node_or_null("/root/GraphicsSettings")
	if gs and gs.has_method("is_low"):
		low = gs.is_low()
	p.amount = maxi(2, amount / 2 if low else amount)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.gravity = grav
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0 # picks the 0 or the 1 per glyph
	var ramp := Gradient.new()
	ramp.set_color(0, Color(COLOR.r * 1.5, COLOR.g * 1.5, COLOR.b * 1.5, 1.0)) # more saturates to white
	ramp.add_point(0.5, Color(COLOR.r * 1.15, COLOR.g * 1.15, COLOR.b * 1.15, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(COLOR.r, COLOR.g, COLOR.b, 0.0))
	p.color_ramp = ramp
	p.mesh = _quad(size)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p

static func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _material()
	return q

static func _material() -> StandardMaterial3D:
	if _mat:
		return _mat
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mat.particles_anim_h_frames = 2
	_mat.particles_anim_v_frames = 1
	_mat.particles_anim_loop = false
	_mat.vertex_color_use_as_albedo = true
	_mat.albedo_texture = glyph_texture()
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat.disable_fog = true
	return _mat

## The two-frame sheet: "0" left, "1" right, white on clear, GLYPH_PX square.
static func glyph_texture() -> ImageTexture:
	if _tex:
		return _tex
	var img := Image.create(GLYPH_PX * 2, GLYPH_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cell := 2 # each bitmap pixel is 2x2: 5x7 -> 10x14 inside 16x16
	for g in GLYPHS.size():
		var rows: Array = GLYPHS[g]
		for r in rows.size():
			var row: String = rows[r]
			for c in row.length():
				if row[c] != "1":
					continue
				for dy in cell:
					for dx in cell:
						img.set_pixel(g * GLYPH_PX + 3 + c * cell + dx, 1 + r * cell + dy, Color.WHITE)
	_tex = ImageTexture.create_from_image(img)
	return _tex
