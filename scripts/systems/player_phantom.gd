class_name PlayerPhantom
extends StaticBody3D
## A hallucinated human: the MODEL HALLUCINATION skirmish event's decoy. The
## robots' vision model glitches and sees extra copies of the player; a robot
## closer to a phantom than to the player turns on it (EnemyBase._perceive, the
## "player_phantom" group, same rule as the hijacked-traitor priority).
##
## It sits on the PLAYER's layer (2) so the robots' hitscans and line-of-sight
## rays, which mask world + player, find it. It is NOT in the "player" group,
## and every pickup, task zone, firewall and hazard bonus keys on that group,
## so a phantom can soak fire but never holds an objective or grabs loot. The
## player's own fire masks world + enemy, so it passes straight through.
## Pops when shot to pieces or when the hallucination ends.
## Covered by tests/hallucination_probe.

signal popped

const LIFE := 12.0
const HEALTH := 60.0
const COLOR := Color(0.35, 0.95, 1.0)

var life := LIFE
var _mat: ShaderMaterial
var _tag: Label3D
var _gone := false

func _ready() -> void:
	add_to_group("player_phantom")
	collision_layer = 2
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = HEALTH
	add_child(hp)
	hp.died.connect(func(_s: Node) -> void: pop())
	hp.damaged.connect(func(_a: float, _s: Node) -> void: _flicker(0.9))
	# A hologram of a person: body, head, a scanline shimmer.
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/hologram.gdshader")
	_mat.set_shader_parameter("holo_color", COLOR)
	_mat.set_shader_parameter("alpha", 0.55)
	_mat.set_shader_parameter("scan_count", 60.0)
	# A person in primitives: torso, legs, arms angled off the shoulders, head.
	_limb(0.2, 0.75, Vector3(0, 1.18, 0), 0.0)
	for s in [-1.0, 1.0]:
		_limb(0.09, 0.9, Vector3(0.11 * s, 0.45, 0), 0.0)
		_limb(0.07, 0.7, Vector3(0.3 * s, 1.15, 0), deg_to_rad(12.0) * s)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.13
	hm.height = 0.26
	head.mesh = hm
	head.position.y = 1.68
	head.material_override = _mat
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)
	_tag = Label3D.new()
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.text = "HUMAN? p=%.2f" % randf_range(0.48, 0.61)
	_tag.font_size = 40
	_tag.pixel_size = 0.004
	_tag.outline_size = 8
	_tag.modulate = COLOR
	_tag.position.y = 2.2
	add_child(_tag)

func _limb(r: float, h: float, at: Vector3, roll: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	mi.mesh = cm
	mi.position = at
	mi.rotation.z = roll
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _physics_process(delta: float) -> void:
	if _gone:
		return
	life -= delta
	if life <= 0.0:
		pop(false)
		return
	# A glitch every so often, so it reads as a projection.
	if randf() < delta * 1.5:
		_flicker(0.4)

func _flicker(strength: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("alpha", 0.55 * (1.0 - strength * randf()))
	var tw := create_tween()
	tw.tween_interval(0.06)
	tw.tween_callback(func() -> void:
			if _mat:
				_mat.set_shader_parameter("alpha", 0.55))

## Breaks the hallucination for this copy. `shot`: the robots destroyed it
## (a louder pop); false when the event ends.
func pop(shot: bool = true) -> void:
	if _gone:
		return
	_gone = true
	collision_layer = 0
	remove_from_group("player_phantom")
	popped.emit()
	var parent := get_parent()
	if parent:
		DeepfakeDecoy._burst(parent, global_position + Vector3.UP * 1.0)
	AudioBus.play_synth_at("overlord_glitch", global_position, -6.0 if shot else -12.0, 1.9)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.6, 0.05, 1.6), 0.12).set_trans(Tween.TRANS_EXPO)
	tw.tween_callback(queue_free)
