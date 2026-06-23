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

func apply_damage(amount: float, source = null, crit: bool = false) -> void:
	# A stored shooter (a projectile/explosion's source) can be freed before its
	# hit lands. Passing a freed object to a typed `Node` param crashes Godot at
	# the call itself, so we take `source` untyped and null out a dead reference
	# here — this shields every caller and the source-typed signals below.
	if source != null and not is_instance_valid(source):
		source = null
	if invulnerable or current_health <= 0.0:
		var parent := get_parent()
		if parent and parent.has_method("notify_shield_hit"):
			parent.notify_shield_hit(source)
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
		GameState.report_player_hit(mitigated, pos, killed, crit)
		_spawn_damage_number(mitigated, pos, killed, crit)
	if killed:
		died.emit(source)


## Floating world-space damage number that drifts up and fades — anchored at the
## hit point in 3D so it tracks as you move. Heavier hits read bigger; headshots
## are a distinct gold "crit" (with a !) so precision is visibly rewarded. This
## is the single damage-number system (the HUD no longer spawns a second one).
func _spawn_damage_number(amount: float, pos: Vector3, killed: bool, crit: bool = false) -> void:
	if amount < 1.0:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var lbl := Label3D.new()
	lbl.text = (str(roundi(amount)) + "!") if crit else str(roundi(amount))
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.pixel_size = 0.0028
	lbl.outline_size = 12 if crit else 10
	# Heavier hits read bigger; gold crit > red kill > white->hot-orange by bite.
	var heavy := clampf(amount / 80.0, 0.0, 1.0)
	if crit:
		lbl.modulate = Color(1.0, 0.95, 0.35)
		lbl.font_size = 76
	elif killed:
		lbl.modulate = Color(1.0, 0.3, 0.2)
		lbl.font_size = 56 + int(heavy * 18.0)
	else:
		lbl.modulate = Color(1.0, 0.95, 0.9).lerp(Color(1.0, 0.55, 0.3), heavy)
		lbl.font_size = 40 + int(heavy * 22.0)
	scene.add_child(lbl)
	# Scatter so stacked hits don't overlap into an unreadable blob.
	lbl.global_position = pos + Vector3(randf_range(-0.3, 0.3), randf_range(-0.1, 0.2), randf_range(-0.3, 0.3))
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
