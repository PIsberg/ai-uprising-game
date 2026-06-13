extends Node3D
## Bullet impact: spark burst + smoke (CPUParticles), a brief flash light, and a
## scorch Decal that lingers and fades so hits visibly mark the world.

@export var lifetime: float = 2.5
var _age: float = 0.0
@onready var _decal: Decal = $Decal
@onready var _light: OmniLight3D = $Light
@onready var _sparks: CPUParticles3D = $Sparks
@onready var _smoke: CPUParticles3D = $Smoke

# Shared, generated bullet-hole texture: a dark punched centre, a cratered rim,
# and radial cracks — reads as a hole rather than a soft smudge.
static var _hole_tex: Texture2D = null

func _ready() -> void:
	if _decal:
		_decal.texture_albedo = _bullet_hole_texture()

static func _bullet_hole_texture() -> Texture2D:
	if _hole_tex != null:
		return _hole_tex
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s * 0.5, s * 0.5)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var d: float = p.distance_to(c) / (s * 0.5)
			var ang := (p - c).angle()
			var a := 0.0
			var shade := 0.05
			if d < 0.32:
				a = 1.0 # punched hole — near black, solid
				shade = 0.02
			elif d < 0.62:
				var crack := 0.5 + 0.5 * sin(ang * 9.0)
				a = clampf(1.0 - (d - 0.32) / 0.3, 0.0, 1.0) * (0.45 + 0.45 * crack)
				shade = 0.12
			img.set_pixel(x, y, Color(shade, shade, shade * 1.1, a))
	_hole_tex = ImageTexture.create_from_image(img)
	return _hole_tex

## Tint + scale the burst to the surface hit: metal throws bright sparks, dirt
## just coughs dust, concrete is in between. Also chips off physical-looking
## debris fragments so the hit reads as the surface breaking, not just a flash.
func set_surface(kind: String) -> void:
	if _sparks:
		match kind:
			"metal":
				_sparks.color = Color(1.0, 0.92, 0.65); _sparks.amount = 30
			"dirt":
				_sparks.color = Color(0.85, 0.6, 0.35); _sparks.amount = 7
			_:
				_sparks.color = Color(0.92, 0.88, 0.8); _sparks.amount = 14
	if _smoke:
		match kind:
			"metal": _smoke.color = Color(0.62, 0.62, 0.66)
			"dirt": _smoke.color = Color(0.52, 0.42, 0.3)
			_: _smoke.color = Color(0.72, 0.72, 0.72)
	_spawn_debris(kind)

## A short spray of chunky fragments blasted off the surface along the hit
## normal — metal sheds bright hot shards, concrete grey chips, dirt brown clods.
func _spawn_debris(kind: String) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.local_coords = false
	p.lifetime = 0.5
	p.explosiveness = 1.0
	# Parent (-Z via orient/look_at) points along the surface normal.
	p.direction = Vector3(0, 0, -1)
	p.spread = 55.0
	p.gravity = Vector3(0, -18.0, 0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	var frag := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.3
	mat.roughness = 0.7
	match kind:
		"metal":
			p.amount = 9; p.initial_velocity_min = 4.0; p.initial_velocity_max = 9.0
			frag.size = Vector3(0.05, 0.05, 0.05)
			mat.albedo_color = Color(0.35, 0.36, 0.4)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.6, 0.25)
			mat.emission_energy_multiplier = 2.5
		"dirt":
			p.amount = 7; p.initial_velocity_min = 2.0; p.initial_velocity_max = 5.0
			frag.size = Vector3(0.06, 0.06, 0.06)
			mat.albedo_color = Color(0.32, 0.24, 0.16)
		_:
			p.amount = 8; p.initial_velocity_min = 3.0; p.initial_velocity_max = 6.5
			frag.size = Vector3(0.055, 0.055, 0.055)
			mat.albedo_color = Color(0.4, 0.4, 0.42)
	frag.material = mat
	p.mesh = frag
	add_child(p)

func orient(normal: Vector3) -> void:
	if normal.length_squared() < 0.001:
		return
	# Parent faces along the normal (drives the spark/smoke spray direction).
	look_at(global_position + normal, Vector3.UP if absf(normal.y) < 0.99 else Vector3.RIGHT)
	# A Decal projects down its local -Y, so aim +Y along the surface normal and
	# give it a random spin around that axis for variety.
	if _decal:
		var up := normal.normalized()
		var ref := Vector3.RIGHT if absf(up.dot(Vector3.UP)) > 0.95 else Vector3.UP
		var right := ref.cross(up).normalized()
		var fwd := up.cross(right).normalized()
		var basis := Basis(right, up, fwd).rotated(up, randf() * TAU)
		_decal.global_transform = Transform3D(basis, global_position)

func _process(delta: float) -> void:
	_age += delta
	# Spark flash light snaps out fast.
	if _light:
		_light.light_energy = maxf(0.0, 3.0 * (1.0 - _age / 0.12))
	# Scorch holds, then fades over the back half of its life.
	if _decal:
		_decal.modulate.a = clampf((1.0 - _age / lifetime) / 0.5, 0.0, 1.0)
	if _age > lifetime:
		queue_free()
