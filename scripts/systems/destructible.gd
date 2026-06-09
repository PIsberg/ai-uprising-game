class_name Destructible
extends StaticBody3D
## A shootable world prop with a Damageable. Cars `explode` (FX + AoE that hurts
## nearby enemies/player and shakes the camera — and can chain-react into other
## explosives), fences just `_shatter` into sparks. Lives on collision layer 1,
## so both hitscan weapons and explosive splash already find its Damageable.

@export var explode: bool = false
@export var splash_radius: float = 5.5
@export var splash_damage: float = 55.0
@export var shake_radius: float = 16.0
@export var debris_color: Color = Color(0.55, 0.55, 0.6) ## Tint of the chunks it bursts into.
@export var debris_count: int = 10

const EXPLOSION := preload("res://scenes/fx/enemy_explosion.tscn")
const IMPACT := preload("res://scenes/fx/impact.tscn")

@onready var hp: Damageable = $Damageable
var _dead: bool = false

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("destructible")
	if hp:
		hp.died.connect(_on_destroyed)

func _on_destroyed(_source: Node) -> void:
	if _dead:
		return
	_dead = true
	if explode:
		_explode()
	else:
		_shatter()
	queue_free()

func _explode() -> void:
	var fx := EXPLOSION.instantiate()
	get_parent().add_child(fx)
	(fx as Node3D).global_position = global_position + Vector3.UP * 0.8
	AudioBus.play_synth_at("explosion", global_position, 4.0, randf_range(0.6, 0.75))
	_burst_debris(debris_count + 6, 5.0)
	# Area-of-effect: hurt every Damageable in radius (enemies, player, other props).
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = splash_radius
	q.shape = s
	q.transform = Transform3D(Basis(), global_position)
	q.collision_mask = 0b0000111 # world + player + enemy
	var seen := {}
	for h in space.intersect_shape(q, 24):
		var col: Node = h.get("collider")
		if col == null:
			continue
		var d = col.get_node_or_null("Damageable")
		if d == null or d == hp or seen.has(d):
			continue
		seen[d] = true
		var dist := (col as Node3D).global_position.distance_to(global_position)
		var falloff := clampf(1.0 - dist / splash_radius, 0.0, 1.0)
		d.apply_damage(splash_damage * falloff, self)
	# Camera punch if the player is close to the blast.
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		var pd := (p as Node3D).global_position.distance_to(global_position)
		if pd < shake_radius:
			p.shake(clampf(1.0 - pd / shake_radius, 0.0, 1.0))

func _shatter() -> void:
	AudioBus.play_synth_at("impact_metal", global_position, 2.0, randf_range(0.8, 1.0))
	for i in 4:
		var fx := IMPACT.instantiate()
		get_parent().add_child(fx)
		(fx as Node3D).global_position = global_position + Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.6), randf_range(-1.0, 1.0))
	_burst_debris(debris_count, 3.5)

## A one-shot burst of tumbling chunks in the prop's colour — the satisfying
## "it broke apart" payoff. Lives on the scene (the prop frees itself) and is
## cleaned up by a short timer.
func _burst_debris(count: int, speed: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, count)
	p.lifetime = 1.1
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.18, 0.18, 0.18)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = debris_color
	mat.metallic = 0.3
	mat.roughness = 0.7
	mesh.material = mat
	p.mesh = mesh
	parent.add_child(p)
	p.global_position = global_position + Vector3.UP * 0.6
	var tree := p.get_tree()
	if tree:
		var t := tree.create_timer(1.6)
		t.timeout.connect(p.queue_free)
