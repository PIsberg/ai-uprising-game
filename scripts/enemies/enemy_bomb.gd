class_name EnemyBomb
extends Node3D
## A lobbed ballistic bomb: arcs to the target, blinks faster as the fuse runs
## down, then detonates in a readable AoE that hurts the player. Code-built.

var velocity: Vector3 = Vector3.ZERO
var damage: float = 26.0
var blast_radius: float = 4.0
var fuse: float = 1.6
var _t: float = 0.0
var _shell_mat: StandardMaterial3D

## Lob with a solved arc so the bomb lands ON the target point in `flight` s.
static func lob_at(scene: Node, from: Vector3, to: Vector3, flight: float, dmg: float) -> void:
	var b := EnemyBomb.new()
	b.damage = dmg
	b.fuse = flight + 0.35 # a beat after landing — the window to step off it
	scene.add_child(b)
	b.global_position = from
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var delta := to - from
	b.velocity = Vector3(delta.x / flight, delta.y / flight + 0.5 * g * flight, delta.z / flight)

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.albedo_color = Color(0.15, 0.16, 0.18)
	_shell_mat.metallic = 0.7
	_shell_mat.emission_enabled = true
	_shell_mat.emission = Color(1.0, 0.2, 0.12)
	_shell_mat.emission_energy_multiplier = 1.0
	sm.material = _shell_mat
	mi.mesh = sm
	add_child(mi)

func _physics_process(delta: float) -> void:
	_t += delta
	velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	global_position += velocity * delta
	# Rest on the ground once it lands (cheap: stop at y<=0.2 going down).
	if velocity.y < 0.0 and global_position.y <= 0.2:
		global_position.y = 0.2
		velocity = velocity.move_toward(Vector3.ZERO, 12.0 * delta)
	# Blink ramps up as the fuse runs out — the "get away from it" tell.
	_shell_mat.emission_energy_multiplier = 1.0 + 4.0 * absf(sin(_t * (4.0 + _t * 10.0)))
	if _t >= fuse:
		_detonate()

func _detonate() -> void:
	set_physics_process(false)
	AudioBus.play_synth_at("explosion", global_position, 0.0, 1.1)
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D and (player as Node3D).global_position.distance_to(global_position) <= blast_radius:
		var d = player.get_node_or_null("Damageable")
		if d:
			d.apply_damage(damage, self)
		if player.has_method("shake"):
			player.shake(0.5)
	# Expanding blast ring so the radius reads.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.4
	torus.outer_radius = 0.55
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.45, 0.2, 0.9)
	torus.material = mat
	ring.mesh = torus
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(ring)
		ring.global_position = global_position + Vector3(0, 0.15, 0)
		var tw := ring.create_tween().set_parallel(true)
		tw.tween_property(ring, "scale", Vector3.ONE * blast_radius * 1.8, 0.35)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
		tw.chain().tween_callback(ring.queue_free)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.2)
	light.light_energy = 6.0
	light.omni_range = blast_radius * 2.0
	if scene:
		scene.add_child(light)
		light.global_position = global_position + Vector3.UP
		var lt := light.create_tween()
		lt.tween_property(light, "light_energy", 0.0, 0.3)
		lt.tween_callback(light.queue_free)
	queue_free()
