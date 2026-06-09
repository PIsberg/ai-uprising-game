class_name HoldConsole
extends Area3D
## An interaction point the player must stand at and hold for a few seconds —
## "hacking a terminal" or "planting a charge". Progress accrues while the
## player is in the zone and ebbs slowly if they step away (so it pressures them
## to hold ground under fire). Completes the task at `hold_seconds`; if
## `detonate` is set (sabotage), it blows up on completion.

@export var task_id: String = "hack"
@export var hold_seconds: float = 3.0
@export var detonate: bool = false
@export var accent: Color = Color(0.3, 0.9, 1.0)

const EXPLOSION := preload("res://scenes/fx/grenade_explosion.tscn")

var _done: bool = false
var _inside: int = 0
var _t: float = 0.0
var _panel_mat: StandardMaterial3D
var _light: OmniLight3D

func _ready() -> void:
	collision_layer = 64
	collision_mask = 2 # player
	add_to_group("objective")
	add_to_group("console")
	body_entered.connect(func(b): if b.is_in_group("player"): _inside += 1)
	body_exited.connect(func(b): if b.is_in_group("player"): _inside = maxi(0, _inside - 1))
	_build_visual()

func _build_visual() -> void:
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 1.1, 0.6)
	base.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.13, 0.14, 0.17)
	bmat.metallic = 0.6
	bmat.roughness = 0.4
	base.material_override = bmat
	base.position = Vector3(0, 0.55, 0)
	add_child(base)

	# Angled glowing screen.
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.9, 0.6, 0.06)
	panel.mesh = pm
	_panel_mat = StandardMaterial3D.new()
	_panel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_panel_mat.albedo_color = accent
	_panel_mat.emission_enabled = true
	_panel_mat.emission = accent
	_panel_mat.emission_energy_multiplier = 2.5
	panel.material_override = _panel_mat
	panel.position = Vector3(0, 1.15, 0.0)
	panel.rotation_degrees = Vector3(-30, 0, 0)
	add_child(panel)

	# Trigger zone (a slab the player stands in/at).
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 2.0, 2.4)
	cs.shape = bs
	cs.position = Vector3(0, 1.0, 0)
	add_child(cs)

	_light = OmniLight3D.new()
	_light.light_color = accent
	_light.light_energy = 2.0
	_light.omni_range = 5.0
	_light.position = Vector3(0, 1.2, 0)
	add_child(_light)

func _process(delta: float) -> void:
	_t += delta
	var prog := _task_progress()
	if not _done:
		if _inside > 0:
			GameState.advance_task(task_id, delta)
			if GameState.is_task_done(task_id):
				_on_complete()
		elif prog > 0.0:
			GameState.set_task_progress(task_id, maxf(0.0, prog - delta * 0.5))
	# Faster pulse while actively being worked.
	var rate := 9.0 if _inside > 0 and not _done else 3.0
	if _panel_mat:
		_panel_mat.emission_energy_multiplier = 2.5 + sin(_t * rate) * 1.2
	if _light:
		_light.light_energy = 2.0 + sin(_t * rate) * 0.8

## Current progress value of our task (0 if missing).
func _task_progress() -> float:
	for t in GameState.level_tasks:
		if t["id"] == task_id:
			return t["progress"]
	return 0.0

func _on_complete() -> void:
	_done = true
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("pickup_health", global_position, -1.0, 0.9)
	if detonate:
		var fx := EXPLOSION.instantiate()
		get_parent().add_child(fx)
		(fx as Node3D).global_position = global_position + Vector3.UP * 1.0
		(fx as Node3D).scale = Vector3.ONE * 1.5
		var p := get_tree().get_first_node_in_group("player")
		if p and p.has_method("shake"):
			p.shake(0.6)
		queue_free()
	else:
		# Hacked terminal goes dim/green and inert.
		if _panel_mat:
			_panel_mat.emission = Color(0.3, 1.0, 0.4)
