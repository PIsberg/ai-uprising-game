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
@export var menace_glow: float = 1.0 ## Scales the red damage-blink flare (0 disables).
@export var menace_color: Color = Color(1.0, 0.16, 0.1)
@export var anim_idle: String = "Idle"
@export var anim_walk: String = "Walk" ## Empty for hovering enemies with no gait.
@export var anim_attack: String = "" ## Played as a one-shot on each weapon discharge.
@export var anim_stagger: String = "" ## Hit-reaction clip while the parent is staggered.
@export var walk_speed_scale: float = 1.4 ## Walk clip speed at full ground speed.
@export var lean_max: float = 0.14 ## Max forward/back lean (radians) from movement.
@export var bank_max: float = 0.22 ## Max roll into lateral movement (radians). Flyers auto-bank harder.

var _anim: AnimationPlayer
var _parent: EnemyBase
var _prev_recoil: float = 0.0
var _menace_light: OmniLight3D
var _glow_mats: Array[Material] = []
var _blink_tween: Tween
# Velocity-driven lean/bank applied to the imported mesh (composed under its
# base flip/scale so it never fights EnemyBase's flinch on the Model node).
var _mesh: Node3D
var _mesh_base: Transform3D
var _lean_pitch: float = 0.0
var _lean_roll: float = 0.0

func _ready() -> void:
	add_to_group("robot_models")
	_parent = get_parent() as EnemyBase
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_apply_materials()
	_build_menace_glow()
	# The imported model node we lean/bank (the direct child holding the rig).
	for c in get_children():
		if c is Node3D and not (c is AnimationPlayer):
			_mesh = c
			_mesh_base = (c as Node3D).transform
			break
	# Flyers (no walk gait) bank like aircraft; walkers just lean a little.
	if anim_walk == "":
		bank_max *= 2.6
		lean_max *= 1.5
	if _anim == null:
		if _mesh == null:
			set_physics_process(false) # nothing to drive
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

func update_advanced_materials() -> void:
	_glow_mats.clear()
	for mi in _collect_meshes(self):
		mi.material_override = null
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, null)
	_apply_materials()

func _apply_materials() -> void:
	var use_triplanar := bool(GraphicsSettings.get("robot_triplanar_enabled"))
	if texture == null and tint == Color.WHITE and menace_glow <= 0.0 and not use_triplanar:
		return
	
	for mi in _collect_meshes(self):
		if texture != null:
			if use_triplanar:
				var sm := ShaderMaterial.new()
				sm.shader = preload("res://shaders/damaged_robot.gdshader")
				sm.set_shader_parameter("albedo_color", tint)
				sm.set_shader_parameter("albedo_tex", texture)
				sm.set_shader_parameter("metallic", 0.25)
				sm.set_shader_parameter("roughness", 0.65)
				sm.set_shader_parameter("menace_color", menace_color)
				sm.set_shader_parameter("menace_blink", 0.0)
				_glow_mats.append(sm)
				mi.material_override = sm
			else:
				var mat := StandardMaterial3D.new()
				mat.albedo_texture = texture
				mat.albedo_color = tint
				mat.metallic = 0.25
				mat.roughness = 0.65
				_add_menace_emission(mat, texture)
				mi.material_override = mat
		elif mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m is BaseMaterial3D:
					if use_triplanar:
						var sm := ShaderMaterial.new()
						sm.shader = preload("res://shaders/damaged_robot.gdshader")
						sm.set_shader_parameter("albedo_color", m.albedo_color * tint)
						sm.set_shader_parameter("albedo_tex", m.albedo_texture)
						sm.set_shader_parameter("metallic", m.metallic)
						sm.set_shader_parameter("roughness", m.roughness)
						if m.normal_enabled:
							sm.set_shader_parameter("normal_tex", m.normal_texture)
							sm.set_shader_parameter("normal_scale", m.normal_scale)
						sm.set_shader_parameter("menace_color", menace_color)
						sm.set_shader_parameter("menace_blink", 0.0)
						_glow_mats.append(sm)
						mi.set_surface_override_material(s, sm)
					else:
						var dup := m.duplicate() as BaseMaterial3D
						dup.albedo_color = dup.albedo_color * tint
						_add_menace_emission(dup, dup.albedo_texture)
						mi.set_surface_override_material(s, dup)

## Robots read as neutral machines until hit: the red emission channel is
## prepared on every material here but stays dark — `damage_blink()` flares it.
## The albedo doubles as the emission mask, so panel highlights flare while
## recesses stay dark instead of the whole body glowing like a toy.
func _add_menace_emission(mat: BaseMaterial3D, mask: Texture2D) -> void:
	if menace_glow <= 0.0:
		return
	mat.emission_enabled = true
	mat.emission = menace_color
	mat.emission_texture = mask # null is fine: a flat, fainter flare tint
	mat.emission_energy_multiplier = 0.0
	_glow_mats.append(mat)

## A core light for the damage flare — dark until hit, sized off the model's
## silhouette so it sits mid-torso on any chassis.
func _build_menace_glow() -> void:
	if menace_glow <= 0.0:
		return
	var top := 0.0
	for mi in _collect_meshes(self):
		if mi.mesh:
			var aabb: AABB = (mi.global_transform * mi.mesh.get_aabb())
			top = maxf(top, aabb.end.y - global_position.y)
	_menace_light = OmniLight3D.new()
	_menace_light.light_color = menace_color
	_menace_light.light_energy = 0.0
	_menace_light.omni_range = 6.0
	_menace_light.shadow_enabled = false
	_menace_light.position = Vector3(0, clampf(top * 0.55, 0.8, 3.2), 0)
	add_child(_menace_light)

## Red damage blink: the ember sheen and core light flare up on a hit and die
## back down — pain you can read at a glance, without a constant red tint.
func damage_blink() -> void:
	if menace_glow <= 0.0:
		return
	if _blink_tween and _blink_tween.is_valid():
		_blink_tween.kill()
	
	for m in _glow_mats:
		if m is ShaderMaterial:
			m.set_shader_parameter("menace_blink", 2.4 * menace_glow)
		else:
			m.emission_energy_multiplier = 2.4 * menace_glow
			
	if _menace_light:
		_menace_light.light_energy = 3.0 * menace_glow
		
	_blink_tween = create_tween().set_parallel(true)
	for m in _glow_mats:
		if m is ShaderMaterial:
			_blink_tween.tween_method(
				func(v: float): m.set_shader_parameter("menace_blink", v),
				2.4 * menace_glow, 0.0, 0.28)
		else:
			_blink_tween.tween_property(m, "emission_energy_multiplier", 0.0, 0.28)
			
	if _menace_light:
		_blink_tween.tween_property(_menace_light, "light_energy", 0.0, 0.28)

## Power-down on death: the core light dies and the ember sheen drains so the
## topple reads as a dark wreck, not a still-live machine.
func _extinguish() -> void:
	if _menace_light:
		create_tween().tween_property(_menace_light, "light_energy", 0.0, 0.7)
	for m in _glow_mats:
		if m is ShaderMaterial:
			create_tween().tween_method(
				func(v: float): m.set_shader_parameter("menace_blink", v),
				float(m.get_shader_parameter("menace_blink")), 0.0, 0.9)
		else:
			create_tween().tween_property(m, "emission_energy_multiplier", 0.0, 0.9)

## Bank/lean the chassis into its movement: tilt forward when advancing, roll
## into lateral motion. Flyers bank hard (aircraft), walkers lean subtly — sells
## momentum and makes the whole roster read as alive instead of sliding.
func _apply_lean(delta: float) -> void:
	if _mesh == null or _parent == null:
		return
	var lv := _parent.global_transform.basis.inverse() * _parent.velocity
	var spd := maxf(_parent.move_speed, 1.0)
	var fwd := clampf(-lv.z / spd, -1.0, 1.0) # +1 advancing (forward is -Z)
	var lat := clampf(lv.x / spd, -1.0, 1.0)  # +1 strafing right
	var t := clampf(8.0 * delta, 0.0, 1.0)
	_lean_pitch = lerpf(_lean_pitch, fwd * lean_max, t)
	_lean_roll = lerpf(_lean_roll, -lat * bank_max, t)
	_mesh.transform = Transform3D(
		_mesh_base.basis * Basis.from_euler(Vector3(_lean_pitch, 0.0, _lean_roll)),
		_mesh_base.origin)

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
	if _parent.hp:
		var hr := clampf(_parent.hp.current_health / maxf(_parent.hp.max_health, 1.0), 0.0, 1.0)
		for m in _glow_mats:
			if m is ShaderMaterial:
				m.set_shader_parameter("health_ratio", hr)
				
	if _parent.state == EnemyBase.State.DEAD:
		if _anim:
			_anim.pause()
		_extinguish()
		set_physics_process(false)
		return
	_apply_lean(delta)
	if _anim == null:
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
