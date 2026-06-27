class_name EnemySeeker
extends EnemyBase
## A fast, fragile kamikaze flyer. It doesn't shoot — it locks on, screams in at
## the player's height, and detonates on contact (or when shot down). A blinking
## core pulses faster the closer it gets, telegraphing the blast so you can pop
## it or dodge in time.

@export var intercept_height: float = 1.0 ## Flies toward the player's chest height.
@export var detonate_radius: float = 2.2
@export var blast_radius: float = 4.2
@export var blast_damage: float = 48.0

const BIG_BLAST := preload("res://scenes/fx/grenade_explosion.tscn")

var _detonated: bool = false
var _pulse: float = 0.0
var _band_mat: StandardMaterial3D

## Visuals are a small red-tinted EyeDrone ($Model in the scene). The blinking
## eye lamp is the blast telegraph.
@onready var _eye_light: OmniLight3D = $EyeLight

func _ready() -> void:
	max_health = 28.0
	move_speed = 9.5
	turn_speed = 10.0
	sight_range = 40.0
	sight_angle_deg = 200.0
	attack_range = 30.0
	preferred_range = 0.5
	attack_cooldown = 1.0
	score_value = 90
	stagger_threshold = 99999.0 # too fast/fragile to bother staggering
	super._ready()
	_build_warhead_dressing()

## The seeker shares the EyeDrone model with the recon drone — dress it as the
## flying bomb it is so the two flyers read apart at a glance: four dark tail
## fins (missile silhouette) and an amber warning band that pulses with the
## blast telegraph.
func _build_warhead_dressing() -> void:
	# Centre the dressing on the hull, measured from the actual meshes (the
	# model is offset and scaled in the scene, so don't guess).
	var center := Vector3(0, 1.0, 0)
	var mdl := get_node_or_null("Model")
	if mdl:
		var inv := global_transform.affine_inverse()
		var first := true
		var merged := AABB()
		for mi in mdl.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh:
				var ab: AABB = (inv * m.global_transform) * m.mesh.get_aabb()
				merged = ab if first else merged.merge(ab)
				first = false
		if not first:
			center = merged.get_center()
	var hub := Node3D.new()
	hub.position = center
	add_child(hub)
	var fin_mat := StandardMaterial3D.new()
	fin_mat.albedo_color = Color(0.15, 0.15, 0.18)
	fin_mat.metallic = 0.7
	fin_mat.roughness = 0.4
	for i in 4:
		var fin := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.36, 0.26)
		bm.material = fin_mat
		fin.mesh = bm
		var a := TAU * float(i) / 4.0 + TAU / 8.0 # X pattern, clear of the eye
		fin.position = Vector3(sin(a) * 0.36, 0.0, cos(a) * 0.36)
		fin.rotation.y = a
		hub.add_child(fin)
	var band := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.07
	_band_mat = StandardMaterial3D.new()
	_band_mat.albedo_color = Color(1.0, 0.6, 0.1)
	_band_mat.emission_enabled = true
	_band_mat.emission = Color(1.0, 0.55, 0.1)
	_band_mat.emission_energy_multiplier = 2.0
	cm.material = _band_mat
	band.mesh = cm
	band.position.y = -0.16 # under the visor, not across it
	hub.add_child(band)

func _apply_gravity(_delta: float) -> void:
	pass # it flies

# Rush straight at the target instead of holding at a range.
func _state_chase(delta: float) -> void:
	if target == null:
		set_state(State.IDLE)
		return
	_move_toward(target.global_position, delta)

func _state_attack(delta: float) -> void:
	_state_chase(delta)

func _move_toward(dest: Vector3, delta: float) -> void:
	var ty: float = (target.global_position.y if target else dest.y) + intercept_height
	var to := Vector3(dest.x, ty, dest.z) - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var spd := chase_speed()
	if flat.length() > 0.05:
		var d := flat.normalized()
		velocity.x = move_toward(velocity.x, d.x * spd, 16.0 * delta)
		velocity.z = move_toward(velocity.z, d.z * spd, 16.0 * delta)
		_face_dir(d, delta)
	velocity.y = move_toward(velocity.y, (ty - global_position.y) * 5.0, 30.0 * delta)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	super._physics_process(delta)
	# Blink faster as it closes in — the telegraph to pop it or dodge.
	if target and _eye_light:
		var dist := global_position.distance_to(target.global_position)
		_pulse += delta * clampf(14.0 - dist, 3.0, 22.0)
		var b := 0.6 + 0.4 * sin(_pulse)
		_eye_light.light_energy = (2.0 + 4.0 * (1.0 - clampf(dist / 8.0, 0.0, 1.0))) * b
		if _band_mat:
			_band_mat.emission_energy_multiplier = 1.0 + 4.5 * b
	_check_detonate()

func _check_detonate() -> void:
	if _detonated or target == null:
		return
	if global_position.distance_to(target.global_position) <= detonate_radius:
		_detonate(true)

## Boom. `hit_player` true on a kamikaze run (full damage); false when shot down.
func _detonate(hit_player: bool) -> void:
	if _detonated:
		return
	_detonated = true
	# A clean kamikaze hit lands the full payload; shooting it down first earns a
	# weaker blast — so destroying it at close range is rewarded, not still a full
	# point-blank punish (the intended counter-play).
	var radius := blast_radius if hit_player else blast_radius * 0.6
	var damage := blast_damage if hit_player else blast_damage * 0.45
	var scene := get_tree().current_scene
	if scene:
		var fx := BIG_BLAST.instantiate()
		scene.add_child(fx)
		(fx as Node3D).global_position = global_position
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("explosion", global_position, 5.0, 0.7)
	# AoE: hurt the player + any nearby machines.
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = radius
	q.shape = sh
	q.transform = Transform3D(Basis(), global_position)
	q.collision_mask = 0b0000111 # world + player + enemy
	var seen := {}
	for h in space.intersect_shape(q, 16):
		var col: Node = h.get("collider")
		if col == null or col == self:
			continue
		var d = col.get_node_or_null("Damageable")
		if d == null or seen.has(d):
			continue
		seen[d] = true
		var dist: float = (col as Node3D).global_position.distance_to(global_position) if col is Node3D else 0.0
		var falloff := clampf(1.0 - dist / radius, 0.0, 1.0)
		d.apply_damage(damage * falloff, self)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		var pd: float = (p as Node3D).global_position.distance_to(global_position)
		if pd < radius * 2.0:
			p.shake(clampf(1.0 - pd / (radius * 2.0), 0.0, 1.0))
	queue_free()

# Shot down before it reaches you -> it still goes off (smaller, no free kill at point-blank).
func _on_died(source: Node) -> void:
	if _detonated:
		return
	GameState.add_kill(score_value, _kill_label())
	state = State.DEAD
	set_physics_process(false)
	_detonate(false)
