class_name ThrownCleaver
extends Area3D
## A spinning thrown blade (the MAITRE-D's serving-tray cleaver). Flies flat
## with a whirling blur, bites the player on contact. Code-built visuals.

var velocity: Vector3 = Vector3.ZERO
var damage: float = 18.0
var _life: float = 3.0

static func throw_at(scene: Node, from: Vector3, to: Vector3, speed: float, dmg: float) -> void:
	var c := ThrownCleaver.new()
	c.damage = dmg
	scene.add_child(c)
	c.global_position = from
	c.velocity = (to - from).normalized() * speed

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # the player
	monitoring = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.45
	cs.shape = sh
	add_child(cs)
	# Blade: a flat bright square with a glowing edge; handle stub for the read.
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.02, 0.55)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.78, 0.82)
	mat.metallic = 0.9
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.2)
	mat.emission_energy_multiplier = 1.4
	bm.material = mat
	blade.mesh = bm
	add_child(blade)
	body_entered.connect(_on_hit)

func _physics_process(delta: float) -> void:
	velocity.y -= 3.5 * delta # a light arc — thrown steel, not a bullet
	global_position += velocity * delta
	rotation.y += 18.0 * delta # the whirling-blade read
	_life -= delta
	if _life <= 0.0:
		queue_free()

func _on_hit(body: Node3D) -> void:
	if body.is_in_group("player"):
		var d = body.get_node_or_null("Damageable")
		if d:
			d.apply_damage(damage, self)
		if body.has_method("shake"):
			body.shake(0.3)
		AudioBus.play_synth_at("impact_metal", global_position, -4.0, 1.4)
	queue_free()
