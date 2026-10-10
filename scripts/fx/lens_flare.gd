class_name LensFlare
extends ColorRect
## The camera's lens flare: when the player looks toward the sun (or, on a
## night_sky level, the moon) with nothing in the way, a flare blooms across
## the screen (shaders/lens_flare.gdshader): a hot core, aperture spikes, an
## anamorphic streak, tinted ghosts along the lens axis and dirt on the glass
## lighting up round it. Lives under the player's PostFX layer, before the post
## overlay, so it takes the grade, grain and vignette.
##
## Occlusion is a fan of RAYS physics rays round the light (world + robots), so
## the flare dims as the sun slips behind a pillar instead of popping, and is
## eased either way (fade rates FADE_IN / FADE_OUT). Scenery with no collision (the Skyline's MultiMesh towers)
## publishes boxes through the "flare_occluder" group and `flare_boxes()`; each
## ray is also tested against the ones whose bounding cone holds the light.
## Off with the Advanced Post-Process FX setting (the Performance and Balanced
## presets turn it off).

const SHADER := preload("res://shaders/lens_flare.gdshader")
const MASK := 1 | 4 ## World and robots hide the sun.
const RAY_LEN := 600.0
## Ray directions round the light, as (right, up) offsets in radians: the
## centre plus a ring about a sun-disc wide, so partial cover reads partial.
const RAYS := [Vector2.ZERO, Vector2(0.012, 0), Vector2(-0.012, 0), Vector2(0, 0.012), Vector2(0, -0.012)]
const FADE_IN := 9.0 ## 1/s
const FADE_OUT := 14.0 ## 1/s: a pillar cuts it a little faster than it returns.
const NIGHT_POWER := 0.35 ## The moon flares softly.
## Fraction of the screen half-size beyond the edge where the light still
## flares (the streak and ghosts reach in before the disc does).
const EDGE_REACH := 0.35

var camera: Camera3D
var source_root: Node ## Where to look for the sky and sun; the current scene if null.
var strength := 0.0 ## Eased, occlusion-faded flare strength fed to the shader.
var light_uv := Vector2(0.5, 0.5)
var _src: Dictionary = {}
var _src_checked := false
var _boxes: Array = [] ## Visual-only occluders (Skyline.flare_boxes).
var _occluders_seen := -1 ## Size of the flare_occluder group when _boxes was read.
static var _dirt: ImageTexture

## Dirt on the lens: soft smudges and fine specks in a small greyscale texture,
## baked once (a few ms, at load) and shared. Computing it per pixel in the
## shader cost 3.4 ms a frame at 3840x2400 on an Arc A370M.
static func dirt_texture() -> ImageTexture:
	if _dirt:
		return _dirt
	const W := 320
	const H := 200
	var acc := PackedFloat32Array()
	acc.resize(W * H)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	for i in 70:
		_stamp(acc, W, H, Vector2(rng.randf() * W, rng.randf() * H), rng.randf_range(5.0, 15.0),
			rng.randf_range(0.25, 0.6))
	for i in 160:
		_stamp(acc, W, H, Vector2(rng.randf() * W, rng.randf() * H), rng.randf_range(0.8, 2.2),
			rng.randf_range(0.5, 1.0))
	var img := Image.create(W, H, false, Image.FORMAT_L8)
	for y in H:
		for x in W:
			var v := clampf(acc[y * W + x], 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	_dirt = ImageTexture.create_from_image(img)
	return _dirt

static func _stamp(acc: PackedFloat32Array, w: int, h: int, c: Vector2, r: float, a: float) -> void:
	for y in range(maxi(0, int(c.y - r)), mini(h, int(c.y + r) + 1)):
		for x in range(maxi(0, int(c.x - r)), mini(w, int(c.x + r) + 1)):
			var d := Vector2(x, y).distance_to(c) / r
			if d < 1.0:
				acc[y * w + x] += a * (1.0 - d * d) * (1.0 - d * d)

## The light to flare off in `root`'s level: {"dir": unit Vector3 toward the
## light, "color": Color, "power": float}, or {} when there is none to see:
## interiors (WorldEnvironment meta open_sky false), HDRI skies (their sun is
## painted into the photo, not at the light), no sun.
static func source_for(root: Node) -> Dictionary:
	if root == null:
		return {}
	var wes := root.find_children("*", "WorldEnvironment", true, false)
	if wes.is_empty():
		return {}
	var we := wes[0] as WorldEnvironment
	if not bool(we.get_meta("open_sky", false)) or we.environment == null:
		return {}
	var sky := we.environment.sky
	var mat: Material = sky.sky_material if sky else null
	if mat == null or mat is PanoramaSkyMaterial:
		return {}
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		if sm.shader == null or not sm.shader.resource_path.ends_with("night_sky.gdshader"):
			return {}
		var md: Vector3 = sm.get_shader_parameter("moon_dir") if sm.get_shader_parameter("moon_dir") != null \
			else Vector3(0.45, 0.55, -0.7) # the shader's default
		var mc = sm.get_shader_parameter("moon_color")
		return {"dir": md.normalized(), "color": mc if mc is Color else Color(0.85, 0.9, 1.0),
			"power": NIGHT_POWER}
	# Procedural / physical sky: the sun disc sits where the key light points from.
	var best: DirectionalLight3D = null
	for n in root.find_children("*", "DirectionalLight3D", true, false):
		var l := n as DirectionalLight3D
		if l.visible and (best == null or l.light_energy > best.light_energy):
			best = l
	if best == null:
		return {}
	var dir := best.global_transform.basis.z.normalized()
	if dir.y < -0.02:
		return {} # below the horizon
	return {"dir": dir, "color": best.light_color, "power": clampf(best.light_energy, 0.3, 1.0)}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0, 0, 0, 0)
	var sm := ShaderMaterial.new()
	sm.shader = SHADER
	sm.set_shader_parameter("dirt_tex", dirt_texture())
	material = sm
	visible = false

func _process(delta: float) -> void:
	if not _src_checked:
		# Deferred to the first frame: the level builds its sky after the player.
		_src = source_for(source_root if source_root else get_tree().current_scene)
		_src_checked = true
	_sync_occluders()
	var want := 0.0
	var cam := camera if is_instance_valid(camera) else get_viewport().get_camera_3d()
	var gs := get_node_or_null("/root/GraphicsSettings")
	var allowed: bool = gs == null or bool(gs.get("advanced_post_process_enabled"))
	if allowed and not _src.is_empty() and cam and cam.is_inside_tree():
		want = _target_strength(cam)
	var rate := FADE_IN if want > strength else FADE_OUT
	strength = lerpf(strength, want, 1.0 - exp(-rate * delta))
	if strength < 0.01 and want == 0.0:
		strength = 0.0
	visible = strength > 0.0
	if visible:
		var sm := material as ShaderMaterial
		var vs := get_viewport_rect().size
		sm.set_shader_parameter("light_uv", light_uv)
		sm.set_shader_parameter("strength", strength)
		sm.set_shader_parameter("tint", _src["color"])
		sm.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
		sm.set_shader_parameter("spin", cam.global_rotation.y * 0.6)

## How strong the flare should be from `cam` this frame: power x on-screen
## falloff x visible fraction of the ray fan.
func _target_strength(cam: Camera3D) -> float:
	var dir: Vector3 = _src["dir"]
	var fwd := -cam.global_transform.basis.z
	if fwd.dot(dir) < 0.2:
		return 0.0 # well behind or beside the view: skip the rays
	var origin := cam.global_position
	var far := origin + dir * 1000.0
	if cam.is_position_behind(far):
		return 0.0
	var vs := get_viewport_rect().size
	var sp := cam.unproject_position(far)
	light_uv = sp / vs
	# 1 inside the frame, falling to 0 EDGE_REACH beyond the edge.
	var off := (light_uv - Vector2(0.5, 0.5)).abs() * 2.0 - Vector2.ONE
	var edge := 1.0 - clampf(maxf(off.x, off.y) / EDGE_REACH, 0.0, 1.0)
	if edge <= 0.0:
		return 0.0
	return float(_src["power"]) * edge * _visible_fraction(cam, dir)

## Re-read the occluder boxes whenever the flare_occluder group grows or shrinks
## (a skyline built after the flare, or torn down with its level). Static
## scenery: the boxes themselves are not re-read while the group holds steady.
func _sync_occluders() -> void:
	var nodes := get_tree().get_nodes_in_group("flare_occluder")
	if nodes.size() == _occluders_seen:
		return
	_occluders_seen = nodes.size()
	_boxes.clear()
	for n in nodes:
		if is_instance_valid(n) and not n.is_queued_for_deletion() and n.has_method("flare_boxes"):
			_boxes.append_array(n.flare_boxes())

## True when the ray from `from` along unit `dir` passes through the box (slab test
## in the box's own frame).
static func ray_hits_box(box: Dictionary, from: Vector3, dir: Vector3) -> bool:
	var inv: Transform3D = box["to_local"]
	var o := inv * from
	var d := inv.basis * dir
	var half: Vector3 = box["half"]
	var t0 := 0.0
	var t1 := INF
	for a in 3:
		if absf(d[a]) < 1e-6:
			if absf(o[a]) > half[a]:
				return false
			continue
		var ta := (-half[a] - o[a]) / d[a]
		var tb := (half[a] - o[a]) / d[a]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true

## The occluder boxes that could cover the light from `origin`: the light's
## direction falls inside the box's bounding cone.
func _boxes_toward(origin: Vector3, dir: Vector3) -> Array:
	var out: Array = []
	for b in _boxes:
		var to: Vector3 = (b["centre"] as Vector3) - origin
		var dist := to.length()
		if dist < 0.01:
			continue
		var cone := asin(clampf(float(b["radius"]) / dist, 0.0, 1.0)) + 0.03
		if to.dot(dir) > 0.0 and (to / dist).angle_to(dir) < cone:
			out.append(b)
	return out

func _visible_fraction(cam: Camera3D, dir: Vector3) -> float:
	var space := cam.get_world_3d().direct_space_state
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 1e-4:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	var origin := cam.global_position
	var exclude: Array[RID] = []
	var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
	if player:
		exclude.append(player.get_rid())
	var near_boxes := _boxes_toward(origin, dir)
	var clear := 0
	for o in RAYS:
		var d := (dir + right * (o as Vector2).x + up * (o as Vector2).y).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * RAY_LEN, MASK)
		q.exclude = exclude
		if not space.intersect_ray(q).is_empty():
			continue
		var hidden := false
		for b in near_boxes:
			if ray_hits_box(b, origin, d):
				hidden = true
				break
		if not hidden:
			clear += 1
	return float(clear) / float(RAYS.size())
