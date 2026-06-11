class_name RobotModel
extends Node3D
## Drives an imported (glTF/FBX) animated robot model for an EnemyBase parent.
## Sits on the "Model" wrapper node (so EnemyBase's flinch/stagger nudges still
## work) with the imported scene instanced underneath. Reads the parent's state,
## velocity and recoil each tick, so enemy scripts don't have to drive
## animations themselves:
##   - blends Idle <-> Walk by ground speed (walk anim speed scales with it)
##   - fires the attack clip on the recoil spike every weapon discharge causes
##   - plays the hit-reaction clip while the parent is staggered
##   - freezes the pose on death so the topple reads as a dead wreck
## Quaternius FBX mechs import with no texture; `texture` rebuilds their
## material. `tint` recolors textured glTF models (e.g. the red seeker).

@export var texture: Texture2D ## Albedo for FBX imports that lose their texture.
@export var tint: Color = Color.WHITE ## Multiplies the model's albedo (variant recolor).
@export var anim_idle: String = "Idle"
@export var anim_walk: String = "Walk" ## Empty for hovering enemies with no gait.
@export var anim_attack: String = "" ## Played as a one-shot on each weapon discharge.
@export var anim_stagger: String = "" ## Hit-reaction clip while the parent is staggered.
@export var walk_speed_scale: float = 1.4 ## Walk clip speed at full ground speed.

var _anim: AnimationPlayer
var _parent: EnemyBase
var _prev_recoil: float = 0.0

func _ready() -> void:
	_parent = get_parent() as EnemyBase
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_apply_materials()
	if _anim == null:
		set_physics_process(false)
		return
	for n in [anim_idle, anim_walk]:
		if n != "" and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if _anim.has_animation(anim_idle):
		_anim.play(anim_idle)

## Manual override hook for enemy specials (e.g. the sniper's charge-up).
func play_named(anim_name: String, blend: float = 0.2) -> void:
	if _anim and _anim.has_animation(anim_name):
		_anim.play(anim_name, blend)

func _apply_materials() -> void:
	if texture == null and tint == Color.WHITE:
		return
	for mi in _collect_meshes(self):
		if texture != null:
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = texture
			mat.albedo_color = tint
			mat.metallic = 0.25
			mat.roughness = 0.65
			mi.material_override = mat
		elif mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m is BaseMaterial3D:
					var dup := m.duplicate() as BaseMaterial3D
					dup.albedo_color = dup.albedo_color * tint
					mi.set_surface_override_material(s, dup)

func _collect_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_collect_meshes(c))
	return out

func _physics_process(delta: float) -> void:
	if _parent == null:
		return
	if _parent.state == EnemyBase.State.DEAD:
		_anim.pause()
		set_physics_process(false)
		return
	# Weapon discharge -> attack one-shot (recoil spikes to 1 on every shot).
	if anim_attack != "" and _parent.recoil > 0.9 and _prev_recoil <= 0.9 \
			and _anim.has_animation(anim_attack):
		_anim.play(anim_attack, 0.12)
	_prev_recoil = _parent.recoil
	# Staggered -> hit-reaction clip.
	if anim_stagger != "" and _parent.state == EnemyBase.State.STAGGER \
			and _anim.current_animation != anim_stagger and _anim.has_animation(anim_stagger):
		_anim.play(anim_stagger, 0.1)
	# Let one-shots (attack/stagger) finish before locomotion takes back over.
	if _anim.is_playing() and (_anim.current_animation == anim_attack
			or _anim.current_animation == anim_stagger):
		return
	# Locomotion: idle <-> walk by ground speed.
	var speed := Vector2(_parent.velocity.x, _parent.velocity.z).length()
	var norm := clampf(speed / maxf(_parent.move_speed, 0.01), 0.0, 1.0)
	if norm > 0.15 and anim_walk != "" and _anim.has_animation(anim_walk):
		if _anim.current_animation != anim_walk:
			_anim.play(anim_walk, 0.25)
		_anim.speed_scale = lerpf(0.8, walk_speed_scale, norm)
	elif _anim.has_animation(anim_idle):
		if _anim.current_animation != anim_idle:
			_anim.play(anim_idle, 0.3)
		_anim.speed_scale = 1.0
