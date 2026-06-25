class_name VolumetricTree
extends RefCounted
## Builds the geometry + 3D texture that the volumetric-billboard tree shader
## (shaders/volumetric_tree.gdshader) needs. The shader slices a stack of
## camera-facing quads through a 3D texture; we supply:
##   - mesh():   SLICES stacked unit quads (the shader reads VERTEX_ID/4 as the
##               slice index, so vertices must be grouped 4-per-quad in order).
##   - volume(): a procedurally voxelised tree (brown trunk + clumpy green crown
##               with ragged, gappy foliage) baked into an ImageTexture3D.
## Both are built once and cached (one process-wide tree asset, many instances).

const SLICES := 34
const VOL := 40   ## 3D-texture resolution per axis.

static var _mesh: ArrayMesh = null
static var _tex: ImageTexture3D = null
static var _shader: Shader = preload("res://shaders/volumetric_tree.gdshader")

## SLICES stacked quads. Positions are placeholders (the shader rewrites VERTEX
## from UV + VERTEX_ID); UVs and the 4-per-quad vertex order are what matter.
static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for s in SLICES:
		var z := float(s) / float(SLICES) - 0.5
		for c in corners:
			verts.append(Vector3(c.x - 0.5, c.y - 0.5, z))
			uvs.append(c)
		var b := s * 4
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh = m
	return m

static func volume() -> ImageTexture3D:
	if _tex != null:
		return _tex
	var imgs: Array[Image] = []
	for z in VOL:
		var img := Image.create(VOL, VOL, false, Image.FORMAT_RGBA8)
		for y in VOL:
			for x in VOL:
				var p := Vector3((x + 0.5) / VOL, (y + 0.5) / VOL, (z + 0.5) / VOL)
				img.set_pixel(x, y, _voxel(p))
		imgs.append(img)
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_RGBA8, VOL, VOL, VOL, false, imgs)
	_tex = t
	return t

## Density/colour at a normalised volume coordinate (0..1 on each axis).
static func _voxel(p: Vector3) -> Color:
	var trunk_r := Vector2(p.x - 0.5, p.z - 0.5).length()
	# Trunk: a tapered bark column up the centre of the lower half.
	if p.y < 0.5 and trunk_r < 0.05 + (0.5 - p.y) * 0.05:
		var bn := _fbm(p * 16.0)
		return Color(0.34 + 0.12 * bn, 0.2 + 0.06 * bn, 0.1, 1.0)
	# Crown: a slightly squashed sphere with ragged, gappy foliage.
	var d := p - Vector3(0.5, 0.66, 0.5)
	d.y *= 1.15
	var r := d.length()
	var n := _fbm(p * 5.0)
	var edge := 0.33 + 0.10 * n
	if r < edge:
		var clump := _fbm(p * 9.0 + Vector3(7, 3, 11))
		var a := smoothstep(edge, edge - 0.13, r) * (0.45 + 0.85 * clump)
		if clump < 0.33:
			a *= 0.18  # punch holes so the canopy reads as leaves, not a ball
		var g := 0.28 + 0.3 * clump
		return Color(0.1 + 0.14 * n, g, 0.05 + 0.08 * n, clamp(a, 0.0, 1.0))
	return Color(0, 0, 0, 0)

static var _shadow_tex: Texture2D = null

## A soft round dark texture for a ground-contact shadow blob (grounds the
## billboard trees, which cast no real shadow). Built once.
static func ground_shadow_tex() -> Texture2D:
	if _shadow_tex != null:
		return _shadow_tex
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := Vector2(sz * 0.5, sz * 0.5)
	for y in sz:
		for x in sz:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c) / (sz * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 1.8) * 0.55  # soft falloff, max ~55% darken
			img.set_pixel(x, y, Color(0, 0, 0, a))
	_shadow_tex = ImageTexture.create_from_image(img)
	return _shadow_tex

## A flat ground-shadow quad to sit just under a tree of the given size.
static func ground_shadow(particle_size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var r := particle_size * 0.7
	pm.size = Vector2(r, r)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 1)
	mat.albedo_texture = ground_shadow_tex()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.material = mat
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## A ShaderMaterial wired to the shared volume, sized for one tree.
static func material(particle_size: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("alpha_tex", volume())
	mat.set_shader_parameter("particle_size", particle_size)
	mat.set_shader_parameter("quads_num_x2", float(SLICES * 2))
	return mat

## A ready-to-place tree instance. The volume is centred on the node origin, so
## the caller should lift the node by ~half the tree height to sit it on ground.
static func make(particle_size: float = 4.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh()
	mi.material_override = material(particle_size)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-particle_size, -particle_size, -particle_size),
		Vector3(particle_size * 2.0, particle_size * 2.0, particle_size * 2.0))
	return mi

# ---- value-noise helpers (deterministic, for the voxel bake) ----

static func _hash(p: Vector3) -> float:
	var s := sin(p.x * 127.1 + p.y * 311.7 + p.z * 74.7) * 43758.5453
	return s - floor(s)

static func _vnoise(p: Vector3) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector3(3, 3, 3) - 2.0 * f)
	var c000 := _hash(i + Vector3(0, 0, 0))
	var c100 := _hash(i + Vector3(1, 0, 0))
	var c010 := _hash(i + Vector3(0, 1, 0))
	var c110 := _hash(i + Vector3(1, 1, 0))
	var c001 := _hash(i + Vector3(0, 0, 1))
	var c101 := _hash(i + Vector3(1, 0, 1))
	var c011 := _hash(i + Vector3(0, 1, 1))
	var c111 := _hash(i + Vector3(1, 1, 1))
	var x00 := lerpf(c000, c100, f.x)
	var x10 := lerpf(c010, c110, f.x)
	var x01 := lerpf(c001, c101, f.x)
	var x11 := lerpf(c011, c111, f.x)
	return lerpf(lerpf(x00, x10, f.y), lerpf(x01, x11, f.y), f.z)

static func _fbm(p: Vector3) -> float:
	return 0.6 * _vnoise(p) + 0.3 * _vnoise(p * 2.0) + 0.1 * _vnoise(p * 4.0)
