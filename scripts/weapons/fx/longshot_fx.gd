class_name LongshotFx
extends SignatureFx
## The MK-VII Longshot's signature: a round that breaks the air. A train of
## shock rings punches out down the first SHOCK_REACH metres of the shot line,
## each a beat after the one before, so the crack visibly runs away from you;
## a headshot (or weak-point crit) throws a four-point star flash with a ring
## at the hit, the payoff for the hardest shot in the game; and the bolt throws
## a big glowing case that trails smoke as it tumbles, instead of the shared
## brass. Covered by tests/longshot_fx_probe.

const SHOCK_RINGS := 4
const SHOCK_REACH := 12.0 ## metres down the line the last ring forms
const SHOCK_STAGGER := 0.03 ## seconds between rings
const SHOCK_TIME := 0.22
const STAR_SIZE := 1.6 ## metres across the star's long arms
const STAR_TIME := 0.18
const CASE_DELAY := 0.35 ## seconds after the shot the bolt is worked

func owns_brass() -> bool:
	return true

func on_fire() -> void:
	_shock_train()
	_case_later()

func on_enemy_hit(pos: Vector3, _normal: Vector3, _dir: Vector3, _dmg: float, crit: bool) -> void:
	if crit:
		_star(pos)

func _shot_line() -> Array:
	var muzzle: Node3D = weapon.get("muzzle")
	var cam: Camera3D = weapon.get("_active_camera")
	var from: Vector3 = muzzle.global_position if muzzle else weapon.global_position
	var fwd: Vector3 = -cam.global_basis.z if cam else (-muzzle.global_basis.z if muzzle else -weapon.global_basis.z)
	return [from, fwd.normalized()]

## Rings at even steps down the line, each spawned SHOCK_STAGGER after the last.
func _shock_train() -> void:
	var root := scene()
	if root == null:
		return
	var line := _shot_line()
	var from: Vector3 = line[0]
	var fwd: Vector3 = line[1]
	var col: Color = weapon.call("shot_color") if weapon.has_method("shot_color") else Color(0.6, 0.85, 1.0)
	var tree := weapon.get_tree()
	for i in SHOCK_RINGS:
		var at := from + fwd * (SHOCK_REACH * float(i + 1) / SHOCK_RINGS)
		var grow := 1.5 + i * 0.8
		if i == 0:
			_ring(root, at, fwd, col, grow, i)
		else:
			tree.create_timer(SHOCK_STAGGER * i).timeout.connect(func() -> void:
				if is_instance_valid(root):
					_ring(root, at, fwd, col, grow, i))

func _ring(root: Node, at: Vector3, fwd: Vector3, col: Color, grow: float, index: int) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.09
	tm.outer_radius = 0.11
	tm.rings = 28
	tm.ring_segments = 5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(col.lerp(Color.WHITE, 0.5), 0.55)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.5
	tm.material = mat
	var mi := MeshInstance3D.new()
	mi.set_meta("sig_fx", "shock_ring")
	mi.set_meta("index", index)
	mi.mesh = tm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var up := Vector3.UP if absf(fwd.y) < 0.99 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(fwd, up) * Basis(Vector3.RIGHT, -PI * 0.5), at)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * grow, SHOCK_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, SHOCK_TIME)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, SHOCK_TIME)
	tw.chain().tween_callback(mi.queue_free)

## A four-point star (two long crossed bars, two short diagonal ones) and a
## ring, camera-facing, snapping out and gone in STAR_TIME.
func _star(pos: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	var node := Node3D.new()
	node.set_meta("sig_fx", "crit_star")
	var mats: Array[StandardMaterial3D] = []
	var arms := [Vector2(STAR_SIZE, STAR_SIZE * 0.05), Vector2(STAR_SIZE * 0.05, STAR_SIZE),
			Vector2(STAR_SIZE * 0.45, STAR_SIZE * 0.035), Vector2(STAR_SIZE * 0.45, STAR_SIZE * 0.035)]
	for i in arms.size():
		var q := QuadMesh.new()
		q.size = arms[i]
		var mat := _flare_mat(Color(1.0, 0.97, 0.9))
		q.material = mat
		mats.append(mat)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i >= 2:
			# The short arms on the diagonals; billboard mode keeps the roll.
			mat.billboard_keep_scale = true
			mi.rotation.z = PI * 0.25 * (1.0 if i == 2 else -1.0)
		node.add_child(mi)
	root.add_child(node)
	node.global_position = pos
	node.scale = Vector3.ONE * 0.3
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "scale", Vector3.ONE, STAR_TIME * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for m in mats:
		tw.tween_property(m, "albedo_color:a", 0.0, STAR_TIME).set_delay(STAR_TIME * 0.2)
	tw.chain().tween_callback(node.queue_free)
	AudioBus.play_synth_at("headshot", pos, 2.0, 1.25)

func _flare_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 10.0
	return mat

func _case_later() -> void:
	var w := weapon
	w.get_tree().create_timer(CASE_DELAY).timeout.connect(func() -> void:
		if is_instance_valid(w) and w.is_inside_tree():
			_hot_case())

## A big glowing case thrown out the right, trailing a thread of smoke.
func _hot_case() -> void:
	var root := scene()
	if root == null:
		return
	var right := weapon.global_basis.x
	var up := weapon.global_basis.y
	var node := Node3D.new()
	node.set_meta("sig_fx", "hot_case")
	root.add_child(node)
	node.global_position = weapon.global_position + right * 0.12 + up * 0.04
	var p := CPUParticles3D.new()
	p.name = "Case"
	p.one_shot = true
	p.emitting = true
	p.amount = 1
	p.lifetime = 1.2
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = (right + up * 0.8).normalized()
	p.spread = 10.0
	p.initial_velocity_min = 1.8
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -9.0, 0)
	p.angular_velocity_min = -600.0
	p.angular_velocity_max = 600.0
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.009
	cyl.bottom_radius = 0.012
	cyl.height = 0.075
	cyl.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.62, 0.25)
	mat.metallic = 0.85
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.12)
	mat.emission_energy_multiplier = 2.5
	cyl.material = mat
	p.mesh = cyl
	node.add_child(p)
	# The smoke thread, emitted along the same throw so it trails the case.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	grad.colors = PackedColorArray([Color(0.7, 0.7, 0.72, 0.0), Color(0.7, 0.7, 0.72, 0.3), Color(0.6, 0.6, 0.62, 0.0)])
	var sm := SphereMesh.new()
	sm.radius = 0.015
	sm.height = 0.03
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	sm.material = smat
	var s := CPUParticles3D.new()
	s.name = "Smoke"
	s.one_shot = true
	s.emitting = true
	s.amount = 14
	s.lifetime = 0.8
	s.explosiveness = 0.0
	s.local_coords = false
	s.direction = p.direction
	s.spread = 12.0
	s.initial_velocity_min = 1.2
	s.initial_velocity_max = 2.2
	s.gravity = Vector3(0, -3.0, 0)
	s.mesh = sm
	s.color_ramp = grad
	node.add_child(s)
	weapon.get_tree().create_timer(1.8).timeout.connect(node.queue_free)
	var land := node.global_position - Vector3(0, 1.2, 0) + right * 0.5
	weapon.get_tree().create_timer(0.75).timeout.connect(
		func() -> void: AudioBus.play_synth_at("brass_tink", land, -14.0, 0.7))
