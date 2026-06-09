class_name Damageable
extends Node

signal health_changed(current: float, max: float)
signal damaged(amount: float, source: Node)
signal died(source: Node)

@export var max_health: float = 100.0
@export var armor: float = 0.0
@export var invulnerable: bool = false

var current_health: float

func _ready() -> void:
	current_health = max_health

func apply_damage(amount: float, source: Node = null) -> void:
	if invulnerable or current_health <= 0.0:
		return
	# Owners can intercept/scale incoming damage (e.g. a brute's frontal shield).
	var parent := get_parent()
	if parent and parent.has_method("modify_incoming_damage"):
		amount = parent.modify_incoming_damage(amount, source)
		if amount <= 0.0:
			return
	var mitigated := maxf(0.0, amount - armor)
	current_health = maxf(0.0, current_health - mitigated)
	var killed := current_health <= 0.0
	damaged.emit(mitigated, source)
	health_changed.emit(current_health, max_health)
	# Combat feedback: report player-dealt hits (hit markers + damage numbers).
	var owner_node := get_parent()
	if source and source.is_in_group("player") and owner_node is Node3D \
			and not owner_node.is_in_group("player"):
		var pos: Vector3 = (owner_node as Node3D).global_position + Vector3.UP * 1.5
		GameState.report_player_hit(mitigated, pos, killed)
		_spawn_damage_number(mitigated, pos, killed)
	if killed:
		died.emit(source)


## Floating world-space damage number that drifts up and fades.
func _spawn_damage_number(amount: float, pos: Vector3, killed: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var lbl := Label3D.new()
	lbl.text = str(roundi(amount))
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.pixel_size = 0.0028
	lbl.outline_size = 10
	lbl.modulate = Color(1.0, 0.3, 0.2) if killed else Color(1.0, 0.88, 0.4)
	lbl.font_size = 64 if killed else 44
	scene.add_child(lbl)
	lbl.global_position = pos + Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y + 0.9, 0.65).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.65).set_delay(0.15)
	tw.tween_callback(lbl.queue_free)

func heal(amount: float) -> void:
	if current_health <= 0.0:
		return
	current_health = minf(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

func is_alive() -> bool:
	return current_health > 0.0
