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

## Punch a mark into `scene` at `pos`, oriented flush to the surface along
## `normal`. No-op on LOW detail or if `scene` isn't valid.
static func spawn(scene: Node, pos: Vector3, normal: Vector3) -> void:
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
	var tw := d.create_tween()
	tw.tween_interval(HOLD)
	tw.tween_property(d, "modulate:a", 0.0, FADE)
	tw.tween_callback(d.queue_free)
