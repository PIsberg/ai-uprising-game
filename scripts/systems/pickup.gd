class_name Pickup
extends Area3D

enum Kind { HEALTH, AMMO, WEAPON }

@export var kind: Kind = Kind.HEALTH
@export var amount: int = 25
@export var weapon_scene: PackedScene ## Used when kind == WEAPON.

var _taken: bool = false
var _bob_phase: float = 0.0
@onready var _mesh: Node3D = get_node_or_null("Mesh")
@onready var _light: OmniLight3D = get_node_or_null("Light")
var _mesh_home_y: float = 0.0
var _light_base: float = 0.0

func _ready() -> void:
	collision_layer = 32
	collision_mask = 2
	add_to_group("pickup")
	body_entered.connect(_on_body_entered)
	_bob_phase = randf() * TAU
	if _mesh:
		_mesh_home_y = _mesh.position.y
	if _light:
		_light_base = _light.light_energy

func _process(delta: float) -> void:
	rotate_y(delta * 1.2)
	_bob_phase += delta * 2.0
	if _mesh:
		_mesh.position.y = _mesh_home_y + sin(_bob_phase) * 0.12
	if _light:
		_light.light_energy = _light_base + sin(_bob_phase * 1.5) * _light_base * 0.3

func _on_body_entered(body: Node) -> void:
	if _taken or not body.is_in_group("player"):
		return
	match kind:
		Kind.HEALTH:
			var d := body.get_node_or_null("Damageable")
			if d == null or d.current_health >= d.max_health:
				return # don't waste a full-health pickup
			d.heal(amount)
			if body.has_method("notify_pickup"):
				body.notify_pickup("+%d HEALTH" % amount)
			AudioBus.play_synth_at("pickup_health", global_position, -2.0)
		Kind.AMMO:
			var wm := body.get_node_or_null("Head/Camera3D/WeaponHolder")
			if wm:
				# Top up every weapon's reserve, not just the equipped one.
				for w in wm.weapons:
					if w and w.has_method("add_ammo"):
						w.add_ammo(amount)
			var got_grenade := false
			if body.has_method("add_grenade"):
				body.add_grenade(1)
				got_grenade = true
			if body.has_method("notify_pickup"):
				body.notify_pickup("+%d AMMO" % amount + (" · +1 GRENADE" if got_grenade else ""))
			AudioBus.play_synth_at("pickup_ammo", global_position, -2.0)
		Kind.WEAPON:
			if weapon_scene == null:
				return
			var wm := body.get_node_or_null("Head/Camera3D/WeaponHolder")
			if wm and wm.has_method("add_weapon"):
				wm.add_weapon(weapon_scene, true) # equip the shiny new gun
				GameState.unlock_weapon(weapon_scene.resource_path)
			AudioBus.play_synth_at("pickup_health", global_position, 0.0, 0.7)
	_taken = true
	queue_free()
