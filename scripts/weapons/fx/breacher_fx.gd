class_name BreacherFx
extends SignatureFx
## The SG-12 Breacher's signature: a blast, not a shot. Its nine pellets are
## stubby fast beads (the slug alt is one fat bolt); the muzzle belches a wide
## short bloom of fire and the shot cup (the wad) tumbles out glowing behind the
## pellets; a thick cloud rolls forward off the muzzle and hangs there in place
## of the shared puff; the spent hull is thrown out red on the pump stroke, not
## a brass case on the shot; and the pellets that land on a robot pepper it in
## one burst per blast, not nine hit pops. Covered by tests/shotgun_fx_probe.

const PELLET := {"bolt_speed": 200.0, "bolt_length": 0.55, "bolt_width": 0.8}
const SLUG := {"bolt_speed": 170.0, "bolt_length": 2.6, "bolt_width": 2.4}
const BLOOM_LEN := 0.45 ## metres the fire bloom reaches down the bore
const BLOOM_MOUTH := 0.3 ## metres across at its mouth
const WAD_SPEED := Vector2(13.0, 17.0) ## m/s the shot cup leaves at
const HULL_DELAY := 0.13 ## seconds after the shot the pump throws the hull (Weapon's pump beat)
const HULL_COLOR := Color(0.75, 0.12, 0.1)
const SMOKE_COLOR := Color(0.6, 0.6, 0.62)
const PEPPER_WINDOW_MS := 20 ## pellets landing this close together are one blast

var _last_pepper_ms := -100000

func tracer_style() -> Dictionary:
	return SLUG if weapon.get("_alt_slug") else PELLET

func owns_muzzle_smoke() -> bool:
	return true

func owns_brass() -> bool:
	return true

func on_fire() -> void:
	_bloom()
	_wad()
	_rolling_smoke()
	_hull_later()

func on_enemy_hit(pos: Vector3, normal: Vector3, _dir: Vector3, _dmg: float, _crit: bool) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_pepper_ms < PEPPER_WINDOW_MS:
		return
	_last_pepper_ms = now
	_pepper(pos, normal)

func _muzzle() -> Node3D:
	return weapon.get("muzzle")

## A wide short cone of fire down the bore that flares and collapses in a beat.
func _bloom() -> void:
	var muzzle := _muzzle()
	if muzzle == null:
		return
	var flame := MeshInstance3D.new()
	flame.set_meta("sig_fx", "blast_bloom")
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = BLOOM_MOUTH * 0.5
	cm.height = BLOOM_LEN
	cm.radial_segments = 12
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.7, 0.3, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.2)
	mat.emission_energy_multiplier = 9.0
	cm.material = mat
	flame.mesh = cm
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.rotation_degrees = Vector3(-90, 0, 0)
	flame.position = Vector3(0, 0, -BLOOM_LEN * 0.5)
	muzzle.add_child(flame)
	var tw := flame.create_tween().set_parallel(true)
	tw.tween_property(flame, "scale", Vector3(1.5, 1.0, 1.5), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.11)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.11)
	tw.chain().tween_callback(flame.queue_free)

## The shot cup: a glowing disc tumbling out behind the pellets and falling.
func _wad() -> void:
	var root := scene()
	var muzzle := _muzzle()
	if root == null or muzzle == null:
		return
	var p := CPUParticles3D.new()
	p.set_meta("sig_fx", "wad")
	p.one_shot = true
	p.emitting = true
	p.amount = 1
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = -muzzle.global_basis.z
	p.spread = 4.0
	p.initial_velocity_min = WAD_SPEED.x
	p.initial_velocity_max = WAD_SPEED.y
	p.gravity = Vector3(0, -9.0, 0)
	p.angular_velocity_min = -1400.0
	p.angular_velocity_max = 1400.0
	var disc := CylinderMesh.new()
	disc.top_radius = 0.028
	disc.bottom_radius = 0.028
	disc.height = 0.012
	disc.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.5, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.15)
	mat.emission_energy_multiplier = 3.0
	disc.material = mat
	p.mesh = disc
	root.add_child(p)
	p.global_position = muzzle.global_position + p.direction * 0.1
	weapon.get_tree().create_timer(1.2).timeout.connect(p.queue_free)

## A thick cloud rolling forward off the muzzle, swelling as it slows, hanging.
func _rolling_smoke() -> void:
	var root := scene()
	var muzzle := _muzzle()
	if root == null or muzzle == null:
		return
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	grad.colors = PackedColorArray([Color(SMOKE_COLOR, 0.0), Color(SMOKE_COLOR, 0.42), Color(SMOKE_COLOR, 0.0)])
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(1.0, 1.0))
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	smat.albedo_color = Color.WHITE
	sm.material = smat
	var amount := 10 if not GraphicsSettings.gpu_particles_enabled else 28
	var fwd := -muzzle.global_basis.z
	var p := GraphicsSettings.create_particles(amount, 1.6, 0.85, fwd, 22.0, Vector3(0, 0.35, 0),
			2.0, 4.0, 0.6, 1.2, sm, grad, curve)
	p.set_meta("sig_fx", "blast_smoke")
	root.add_child(p)
	p.global_position = muzzle.global_position + fwd * 0.15
	weapon.get_tree().create_timer(2.0).timeout.connect(p.queue_free)

## The spent hull leaves on the pump stroke, a beat after the shot: a red tube
## with a brass base thrown out to the right and tumbling.
func _hull_later() -> void:
	var w := weapon
	w.get_tree().create_timer(HULL_DELAY).timeout.connect(func() -> void:
		if is_instance_valid(w) and w.is_inside_tree():
			_hull())

func _hull() -> void:
	var root := scene()
	if root == null:
		return
	var right := weapon.global_basis.x
	var up := weapon.global_basis.y
	var p := CPUParticles3D.new()
	p.set_meta("sig_fx", "hull")
	p.one_shot = true
	p.emitting = true
	p.amount = 1
	p.lifetime = 1.2
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = (right + up * 0.9).normalized()
	p.spread = 12.0
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -9.0, 0)
	p.angular_velocity_min = -700.0
	p.angular_velocity_max = 700.0
	var tube := CylinderMesh.new()
	tube.top_radius = 0.009
	tube.bottom_radius = 0.009
	tube.height = 0.055
	tube.radial_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = HULL_COLOR
	mat.roughness = 0.6
	tube.material = mat
	p.mesh = tube
	root.add_child(p)
	p.global_position = weapon.global_position + right * 0.1 + up * 0.03
	weapon.get_tree().create_timer(1.6).timeout.connect(p.queue_free)
	var land := p.global_position - Vector3(0, 1.2, 0) + right * randf_range(0.3, 0.6)
	weapon.get_tree().create_timer(randf_range(0.6, 0.85)).timeout.connect(
		func() -> void: AudioBus.play_synth_at("brass_tink", land, -18.0, randf_range(0.6, 0.8)))

## One burst per blast where the pellets land: a spray of hot dents off the
## plating and a flat orange splash that snaps out and fades.
func _pepper(pos: Vector3, normal: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	var n := normal.normalized()
	var node := Node3D.new()
	node.set_meta("sig_fx", "pepper")
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.local_coords = false
	p.amount = 14
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.direction = n
	p.spread = 70.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -14.0, 0)
	var dent := BoxMesh.new()
	dent.size = Vector3(0.02, 0.02, 0.02)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(1.0, 0.6, 0.25)
	dmat.emission_enabled = true
	dmat.emission = Color(1.0, 0.55, 0.2)
	dmat.emission_energy_multiplier = 5.0
	dent.material = dmat
	p.mesh = dent
	node.add_child(p)
	var splash := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smat.albedo_color = Color(1.0, 0.6, 0.25, 0.6)
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.5, 0.2)
	smat.emission_energy_multiplier = 5.0
	q.material = smat
	splash.mesh = q
	splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(splash)
	root.add_child(node)
	node.global_position = pos + n * 0.03
	# The quad faces +Z; lay it flat on the struck face.
	var up := Vector3.UP if absf(n.y) < 0.99 else Vector3.RIGHT
	splash.global_transform = Transform3D(Basis.looking_at(-n, up), node.global_position)
	splash.scale = Vector3.ONE * 0.3
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(splash, "scale", Vector3.ONE, 0.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(smat, "albedo_color:a", 0.0, 0.14)
	tw.tween_property(smat, "emission_energy_multiplier", 0.0, 0.14)
	tw.chain().tween_interval(0.5)
	tw.chain().tween_callback(node.queue_free)
