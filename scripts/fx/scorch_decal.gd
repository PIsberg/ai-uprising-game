class_name ScorchDecal
extends Decal
## Persistent blast scar: a dark radial burn projected onto whatever the
## explosion happened over, with an ember-hot rim that cools off in the first
## seconds, then a slow fade-out. Capped hard — the oldest mark is recycled so
## long firefights can't pile up hundreds of projected boxes.
##
## Usage from any FX/level script:
##   ScorchDecal.spawn(get_tree().current_scene, pos, radius)
## A decal projects along its local -Y. With no `normal` that is straight down,
## right for a blast on or over a floor. A round that goes off on a wall passes
## the wall's normal (`struck_normal` finds it): projected down, its burn and
## ember ring smeared down the wall as two vertical stripes.

const MAX_MARKS := 24
const LIFETIME := 22.0
const EMBER_TIME := 2.6

static var _marks: Array = []
static var _burn_tex: GradientTexture2D = null
static var _ember_tex: GradientTexture2D = null

static func spawn(world: Node, pos: Vector3, radius: float = 2.2, normal: Vector3 = Vector3.UP) -> void:
	if world == null or not world.is_inside_tree():
		return
	# Ambient-detail tier gate: LOW strips decorative FX entirely.
	if GraphicsSettings.detail_scale() <= 0.0:
		return
	while _marks.size() >= MAX_MARKS:
		var old = _marks.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var d := ScorchDecal.new()
	d.size = Vector3(radius * 2.0, 2.4, radius * 2.0)
	d.texture_albedo = _burn_texture()
	d.texture_emission = _ember_texture()
	d.emission_energy = 3.4
	d.albedo_mix = 1.0
	d.cull_mask = 1 # project onto world geometry only, not robots walking over
	d.position = pos
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	if n.dot(Vector3.UP) > 0.999:
		d.rotation.y = randf() * TAU
	else:
		# Local Y out of the struck face, spun at random about it.
		var x := n.cross(Vector3.UP if absf(n.y) < 0.99 else Vector3.RIGHT).normalized()
		d.basis = Basis(x, n, x.cross(n)).rotated(n, randf() * TAU)
	world.add_child(d)
	_marks.append(d)
	d._play_life()

## The normal of the world face a round flying along `dir` struck at `pos`
## (a world-only ray through the blast point), or UP when it burst on a robot
## or in the air.
static func struck_normal(from: Node3D, pos: Vector3, dir: Vector3) -> Vector3:
	if from == null or not from.is_inside_tree() or dir.length() < 0.01:
		return Vector3.UP
	var d := dir.normalized()
	var q := PhysicsRayQueryParameters3D.create(pos - d * 0.6, pos + d * 0.9)
	q.collision_mask = 1
	var hit := from.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or (hit.normal as Vector3).length() < 0.5:
		return Vector3.UP
	return (hit.normal as Vector3).normalized()

func _play_life() -> void:
	var tw := create_tween()
	# Ember rim cools first, then the char slowly weathers away.
	tw.tween_property(self, "emission_energy", 0.0, EMBER_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(LIFETIME - EMBER_TIME - 6.0)
	tw.tween_property(self, "modulate", Color(1, 1, 1, 0), 6.0)
	tw.tween_callback(_expire)

func _expire() -> void:
	_marks.erase(self)
	queue_free()

## Radial char: near-black core easing through charcoal to a transparent edge.
static func _burn_texture() -> GradientTexture2D:
	if _burn_tex != null:
		return _burn_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 0.8, 1.0])
	g.colors = PackedColorArray([
		Color(0.008, 0.008, 0.008, 1.0),
		Color(0.02, 0.018, 0.015, 0.92),
		Color(0.05, 0.04, 0.035, 0.5),
		Color(0.08, 0.07, 0.06, 0.0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 128
	t.height = 128
	_burn_tex = t
	return t

## Ember ring: transparent core, molten-orange band, transparent edge — the
## still-glowing rim of the blast that _play_life cools to nothing.
static func _ember_texture() -> GradientTexture2D:
	if _ember_tex != null:
		return _ember_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 0.68, 0.85, 1.0])
	g.colors = PackedColorArray([
		Color(0, 0, 0, 0),
		Color(0.4, 0.06, 0.0, 0.0),
		Color(1.0, 0.32, 0.06, 0.9),
		Color(0.7, 0.12, 0.02, 0.4),
		Color(0, 0, 0, 0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 128
	t.height = 128
	_ember_tex = t
	return t
