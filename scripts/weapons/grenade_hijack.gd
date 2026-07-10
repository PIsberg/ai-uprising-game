class_name GrenadeHijack
extends RigidBody3D
## HIJACK CHARGE — the rarest special: a firmware-injection spike that arcs and
## lands like a grenade, then STEALS the nearest robot in range. The converted
## unit fights for you (hunting its former squadmates, drawing their fire) until
## its loyalty firmware reasserts itself and the chassis burns out. Bosses
## resist — on them the spike only manages a short EMP stun (see EnemyBase.hijack).

@export var fuse: float = 0.95           ## Flight/arming time before it fires the spike.
@export var burst_radius: float = 6.0    ## The nearest robot inside gets converted.
@export var hijack_time: float = 12.0    ## Seconds the stolen unit fights for you before burnout.

var _shooter: Node
var _t: float = 0.0
var _done: bool = false
var _core_mat: StandardMaterial3D
var _pulse: float = 0.0

func _ready() -> void:
	add_to_group("grenade") # enemies scan this group to scramble clear of the burst
	var core := get_node_or_null("Core") as MeshInstance3D
	if core and core.mesh and core.mesh.material is StandardMaterial3D:
		_core_mat = core.mesh.material.duplicate()
		core.set_surface_override_material(0, _core_mat)

func throw_grenade(initial_velocity: Vector3, shooter: Node) -> void:
	_shooter = shooter
	linear_velocity = initial_velocity
	angular_velocity = Vector3(randf_range(-2, 2), randf_range(8, 14), randf_range(-2, 2))

func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	# Arming: the core blinks an accelerating viral green as the injection primes.
	var urgency := clampf(_t / maxf(fuse, 0.01), 0.0, 1.0)
	_pulse += delta * TAU * lerpf(5.0, 20.0, urgency)
	var beat := 0.5 + 0.5 * sin(_pulse)
	if _core_mat:
		_core_mat.emission_energy_multiplier = lerpf(1.4, 3.8, beat) + urgency * 2.0
	var light := get_node_or_null("Light") as OmniLight3D
	if light:
		light.light_energy = lerpf(0.6, 2.2, beat)
	if _t >= fuse:
		_burst()

func _burst() -> void:
	_done = true
	var pos := global_position
	# Find the NEAREST convertible robot in range — one spike, one convert.
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = burst_radius
	q.shape = sphere
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = 0b0000100  # enemies only
	var best: Node = null
	var best_d := INF
	var seen := {}
	for h in space.intersect_shape(q, 48):
		var node: Node = h.get("collider")
		while node:
			if node.has_method("hijack"):
				break
			node = node.get_parent()
		if node == null or seen.has(node):
			continue
		seen[node] = true
		var d: float = pos.distance_to((node as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = node
	if best:
		best.hijack(hijack_time, _shooter)
	_spawn_burst_fx(pos)
	AudioBus.play_synth_at("overlord_glitch", pos, 1.0, 1.2) # firmware-injection scramble
	AudioBus.play_synth_at("broadcast_blip", pos, -4.0, 0.7)
	queue_free()

## A green ring-shockwave + flash — same read as the EMP burst, friendly color.
func _spawn_burst_fx(pos: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.5
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rmat.albedo_color = Color(0.4, 1.0, 0.55, 0.7)
	rmat.emission_enabled = true
	rmat.emission = Color(0.4, 1.0, 0.55)
	rmat.emission_energy_multiplier = 5.0
	torus.material = rmat
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.5
	var grow := burst_radius / 0.5
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * grow, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(rmat, "albedo_color:a", 0.0, 0.4)
	ring.create_tween().tween_callback(ring.queue_free).set_delay(0.45)
	# A quick green flash.
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.45, 1.0, 0.55)
	flash.light_energy = 9.0
	flash.omni_range = burst_radius * 2.0
	parent.add_child(flash)
	flash.global_position = pos
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 0.35)
	ft.tween_callback(flash.queue_free)
