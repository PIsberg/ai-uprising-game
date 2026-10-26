class_name SidearmFx
extends SignatureFx
## The M9 Sidearm's signature: a crack, not a boom. Its round is a short, fast
## white-hot streak; a round that stops on a hard surface whistles off it as a
## ricochet, a streak leaving along the bounce with a falling whine; a round
## that lands on a robot pings a crisp cross glint off the plating; and instead
## of the shared cloud off the muzzle, a thin wisp curls up out of the ejection
## port with the casing. Covered by tests/sidearm_fx_probe.

## A shorter, faster bolt than the stock 2.2 m at 150 m/s: a pistol round cracks.
const BOLT := {"bolt_speed": 240.0, "bolt_length": 1.1, "bolt_width": 1.1}
## Chance a round ricochets off each surface kind; soft ones swallow it.
const RICOCHET_CHANCE := {"metal": 1.0, "concrete": 0.7, "stone": 0.7}
const RICOCHET_JITTER_DEG := 14.0 ## scatter about the perfect bounce
const RICOCHET_SPEED := 26.0 ## m/s the streak flies off at
const RICOCHET_REACH := Vector2(3.0, 6.0) ## metres it flies before it is gone
const RICOCHET_COLOR := Color(1.0, 0.95, 0.8)
const GLINT_TIME := 0.09
const GLINT_SIZE := 0.42 ## metres across the cross at a plain hit
const WISP_COLOR := Color(0.72, 0.72, 0.75)

func tracer_style() -> Dictionary:
	return BOLT

func owns_muzzle_smoke() -> bool:
	return true

func on_fire() -> void:
	_breech_wisp()

func on_world_hit(pos: Vector3, normal: Vector3, dir: Vector3, surface: String) -> void:
	var chance: float = RICOCHET_CHANCE.get(surface, 0.0)
	if chance <= 0.0 or randf() > chance:
		return
	_ricochet(pos, normal, dir)

func on_enemy_hit(pos: Vector3, _normal: Vector3, _dir: Vector3, _dmg: float, crit: bool) -> void:
	_glint(pos, crit)

## The round leaves the wall along its bounce, scattered a little, always away
## from the surface: the shared tracer scene in bolt mode, white-hot, with the
## ricochet whine falling off the hit.
func _ricochet(pos: Vector3, normal: Vector3, dir: Vector3) -> void:
	var root := scene()
	var data: WeaponData = weapon.get("data")
	if root == null or data == null or data.tracer_scene == null:
		return
	var n := normal.normalized()
	var out := dir.normalized().bounce(n)
	var axis := out.cross(Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT).normalized()
	out = out.rotated(axis.rotated(out, randf() * TAU), deg_to_rad(randf_range(0.0, RICOCHET_JITTER_DEG)))
	if out.dot(n) < 0.05:
		out = (out + n * (0.05 - out.dot(n))).normalized() # never back into the wall
	var t: Node3D = data.tracer_scene.instantiate()
	t.set_meta("sig_fx", "ricochet")
	if "bolt" in t:
		t.bolt = true
		t.bolt_speed = RICOCHET_SPEED
		t.bolt_length = 0.9
		t.bolt_width = 0.8
	root.add_child(t)
	var start := pos + n * 0.03
	if t.has_method("setup"):
		t.setup(start, start + out * randf_range(RICOCHET_REACH.x, RICOCHET_REACH.y), RICOCHET_COLOR)
	AudioBus.play_synth_at("ricochet", pos, -10.0, randf_range(0.85, 1.2))

## A crisp cross of light off the plating where the round landed: two thin
## billboard bars that snap out and fade in GLINT_TIME. A crit glints bigger and whiter.
func _glint(pos: Vector3, crit: bool) -> void:
	var root := scene()
	if root == null:
		return
	var node := Node3D.new()
	node.set_meta("sig_fx", "glint")
	var col := Color(1.0, 0.98, 0.92) if crit else Color(1.0, 0.92, 0.7)
	var size := GLINT_SIZE * (1.5 if crit else 1.0)
	var mats: Array[StandardMaterial3D] = []
	for i in 2:
		var q := QuadMesh.new()
		q.size = Vector2(size, size * 0.07) if i == 0 else Vector2(size * 0.07, size)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 8.0
		mat.no_depth_test = true
		q.material = mat
		mats.append(mat)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	root.add_child(node)
	node.global_position = pos
	node.scale = Vector3.ONE * 0.4
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "scale", Vector3.ONE, GLINT_TIME).set_ease(Tween.EASE_OUT)
	for m in mats:
		tw.tween_property(m, "albedo_color:a", 0.0, GLINT_TIME)
	tw.chain().tween_callback(node.queue_free)

## A thin wisp rising out of the ejection port (right of the slide, over the
## grip) and drifting with it, in place of the shared cloud off the muzzle.
func _breech_wisp() -> void:
	var root := scene()
	if root == null:
		return
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	grad.colors = PackedColorArray([Color(WISP_COLOR, 0.0), Color(WISP_COLOR, 0.28), Color(WISP_COLOR, 0.0)])
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(1.0, 1.0))
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	smat.albedo_color = Color.WHITE
	sm.material = smat
	var right := weapon.global_basis.x
	var up := weapon.global_basis.y
	var amount := 4 if not GraphicsSettings.gpu_particles_enabled else 10
	var p := GraphicsSettings.create_particles(amount, 0.7, 0.9, (up + right * 0.35).normalized(), 18.0,
			Vector3(0, 0.5, 0), 0.25, 0.55, 0.8, 1.0, sm, grad, curve)
	p.set_meta("sig_fx", "breech_wisp")
	root.add_child(p)
	p.global_position = weapon.global_position + right * 0.04 + up * 0.05
	weapon.get_tree().create_timer(1.0).timeout.connect(p.queue_free)
