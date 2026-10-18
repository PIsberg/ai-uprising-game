class_name BulletMark
extends RefCounted
## Small dark bullet-impact decal punched into world geometry (never enemies —
## callers only reach this once a hit is known to be non-Damageable). Shared by
## BOTH hitscan (weapons/weapon.gd) and projectile (weapons/projectile.gd)
## impacts so every source of gunfire draws from ONE capped pool instead of
## each keeping its own — a mag dump or a hail of rockets can't grow the scene
## without bound. Oldest mark is recycled first once the cap is hit. Skipped
## below MEDIUM detail (a purely cosmetic mark isn't worth the draw call on the
## low tier) — see GraphicsSettings.detail_scale(), the same gate level_builder
## uses for its optional detail passes.

const MAX_MARKS := 40
const GROUP := "bullet_hole"
const HOLD := 8.0
const FADE := 2.0

## A rail slug's hole glows molten and cools; an arc round's scorch glows blue
## for a beat (`damage_class`, WeaponData.DamageClass). Seconds to cool.
const RAIL_COOL := 1.6
const ARC_COOL := 0.5
static var _glow_tex: Texture2D = null

## Punch a mark into `scene` at `pos`, oriented flush to the surface along
## `normal`, styled by the round's `damage_class`. No-op on LOW detail or if
## `scene` isn't valid.
static func spawn(scene: Node, pos: Vector3, normal: Vector3, damage_class: int = 0) -> void:
	if scene == null or not is_instance_valid(scene):
		return
	if GraphicsSettings.detail_scale() <= 0.0:
		return
	var tree := scene.get_tree()
	var marks := tree.get_nodes_in_group(GROUP)
	if marks.size() >= MAX_MARKS:
		marks[0].queue_free()
	var d := Decal.new()
	d.add_to_group(GROUP)
	# The impact FX's punched-hole texture (dark centre, cratered rim, radial
	# cracks) — reads as a bullet hole, where a plain scorch reads as a smudge.
	d.texture_albedo = preload("res://scripts/fx/impact.gd")._bullet_hole_texture()
	var s := randf_range(0.12, 0.2)
	var cool := 0.0
	var glow := 0.0
	match damage_class:
		WeaponData.DamageClass.RAIL:
			s *= 1.4 # a slug punches a wider hole
			d.modulate = Color(1.0, 0.55, 0.22)
			glow = 6.0
			cool = RAIL_COOL
		WeaponData.DamageClass.ARC:
			d.modulate = Color(0.55, 0.75, 1.0)
			glow = 3.0
			cool = ARC_COOL
	if glow > 0.0:
		d.texture_emission = _glow_texture()
		d.emission_energy = glow
	d.size = Vector3(s, 0.35, s)
	d.cull_mask = 1
	scene.add_child(d)
	# Project along the surface normal (Decal boxes project down local -Y).
	var up := normal.normalized()
	var x := up.cross(Vector3.FORWARD)
	if x.length_squared() < 0.01:
		x = up.cross(Vector3.RIGHT)
	x = x.normalized()
	d.global_transform = Transform3D(Basis(x, up, x.cross(up)).rotated(up, randf() * TAU), pos + up * 0.02)
	if glow > 0.0:
		# Hot metal cooling: the glow dies and the tint goes back to a dark hole.
		var cool_tw := d.create_tween().set_parallel(true)
		cool_tw.tween_property(d, "emission_energy", 0.0, cool).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		cool_tw.tween_property(d, "modulate", Color.WHITE, cool)
	var tw := d.create_tween()
	tw.tween_interval(HOLD)
	tw.tween_property(d, "modulate:a", 0.0, FADE)
	tw.tween_callback(d.queue_free)

## The hot rim of a fresh hole: a bright ring around a dark core, so the glow
## sits where the metal was melted, not over the punched-through centre.
static func _glow_texture() -> Texture2D:
	if _glow_tex != null:
		return _glow_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n * 0.5, n * 0.5)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (n * 0.5)
			var v := clampf(1.0 - absf(d - 0.36) / 0.2, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, v))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex
