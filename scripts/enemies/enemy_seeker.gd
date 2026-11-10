class_name EnemySeeker
extends EnemyBase
## A fast, fragile kamikaze flyer. It doesn't shoot: it closes at the player's
## height, stops short to arm, then dives down one straight line and detonates
## on contact (or when shot down). A blinking core pulses faster the closer it
## gets; armed, the core and band burn steady white. Step off the line after it
## commits and it flies past and hangs spent (see DIVE_LOCK).

@export var intercept_height: float = 1.0 ## Flies toward the player's chest height.
@export var detonate_radius: float = 2.2
@export var blast_radius: float = 4.2
@export var blast_damage: float = 40.0

const BIG_BLAST := preload("res://scenes/fx/grenade_explosion.tscn")

## TERMINAL DIVE. Inside DIVE_LOCK metres, with a line of sight, it stops and
## arms for DIVE_ARM seconds, then flies one straight line at DIVE_SPEED. The
## line leads a walking target and is fixed DIVE_COMMIT seconds before launch:
## change direction after that and it flies past, DIVE_OVERRUN metres beyond
## where it aimed, and hangs spent for DIVE_RECOVER seconds, its fuse cold.
const DIVE_LOCK := 8.0
const DIVE_ARM := 0.5
const DIVE_COMMIT := 0.2
const DIVE_SPEED := 21.0
const DIVE_OVERRUN := 5.0
const DIVE_RECOVER := 1.2

enum Dive { NONE, ARM, DIVE, RECOVER }
var _dive := Dive.NONE
var _dive_t := 0.0 ## seconds left of ARM or RECOVER
var _dive_aim := Vector3.ZERO ## where the line ends (the led chest point)
var _dive_dir := Vector3.ZERO
var _dive_left := 0.0 ## metres of the line still to fly

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
	# The hull's radius, measured too: sized by guess (0.36 and 0.42 against a
	# 0.6 m hull) the fins and the band were buried inside it and showed nothing.
	var hull_r := 0.6
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
			hull_r = maxf(merged.size.x, merged.size.z) * 0.5
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
		var fin_r := hull_r * 0.92 + 0.06 # rooted in the hull, 0.19 m proud of it
		fin.position = Vector3(sin(a) * fin_r, 0.0, cos(a) * fin_r)
		fin.rotation.y = a
		hub.add_child(fin)
	var band := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = hull_r * 1.0
	cm.bottom_radius = hull_r * 1.0
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

func pilot_flies() -> bool:
	return true # a NeuralUplink pilot climbs and dives on jump/crouch

# Rush straight at the target instead of holding at a range.
func _state_chase(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_dive = Dive.NONE
		set_state(State.IDLE)
		return
	if _tick_dive(delta):
		return
	_move_toward(target.global_position, delta)

func _state_attack(delta: float) -> void:
	_state_chase(delta)

## The terminal dive. True while it owns the seeker's movement.
func _tick_dive(delta: float) -> bool:
	match _dive:
		Dive.NONE:
			# Hold the dive, like the blast, through the opening-seconds grace.
			if GameState.attack_grace_active():
				return false
			var chest := target.global_position + Vector3.UP * intercept_height
			if global_position.distance_to(chest) > DIVE_LOCK or not _can_see(target):
				return false
			_dive = Dive.ARM
			_dive_t = DIVE_ARM
			_dive_aim = _lead_point()
			if has_node("/root/AudioBus"):
				AudioBus.play_synth_at("charge", global_position, 2.0, 1.9)
			return true
		Dive.ARM:
			_dive_t -= delta
			_danger_cd = 0.5 # a bomb on its run does not flinch from a grenade
			# The line follows the target until DIVE_COMMIT before launch.
			if _dive_t > DIVE_COMMIT:
				_dive_aim = _lead_point()
			velocity = velocity.move_toward(Vector3.ZERO, 60.0 * delta)
			var look := _dive_aim - global_position
			look.y = 0.0
			if look.length() > 0.05:
				_face_dir(look.normalized(), delta)
			if _dive_t <= 0.0:
				var line := _dive_aim - global_position
				_dive_dir = line.normalized() if line.length() > 0.05 else -global_basis.z
				_dive_left = line.length() + DIVE_OVERRUN
				_dive = Dive.DIVE
				if has_node("/root/AudioBus"):
					AudioBus.play_synth_at("rocket_fire", global_position, -1.0, 1.5)
			return true
		Dive.DIVE:
			_danger_cd = 0.5
			velocity = _dive_dir * DIVE_SPEED
			_dive_left -= DIVE_SPEED * delta
			if _dive_left <= 0.0:
				_dive = Dive.RECOVER
				_dive_t = DIVE_RECOVER
			return true
		Dive.RECOVER:
			_dive_t -= delta
			velocity = velocity.move_toward(Vector3.ZERO, 24.0 * delta)
			if _dive_t <= 0.0:
				_dive = Dive.NONE
			return true
	return false

## The target's chest, led by its ground velocity over what is left of the arm
## (at most DIVE_COMMIT) plus the flight.
func _lead_point() -> Vector3:
	var chest := target.global_position + Vector3.UP * intercept_height
	var v := Vector3.ZERO
	if target is CharacterBody3D:
		v = (target as CharacterBody3D).velocity
		v.y = 0.0
	var t := global_position.distance_to(chest) / DIVE_SPEED + minf(_dive_t, DIVE_COMMIT)
	return chest + v * t

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
	if state == State.DEAD or _detonated:
		return
	# Knocked out of the fight (EMP, stagger, lost its target): the run is off.
	if state != State.CHASE and state != State.ATTACK:
		_dive = Dive.NONE
	# A dive that meets the world goes off there.
	if _dive == Dive.DIVE and get_slide_collision_count() > 0:
		_detonate(true)
		return
	# Blink faster as it closes in — the telegraph to pop it or dodge. Armed and
	# diving, core and band burn steady and white-hot; spent, they go dark.
	if target and is_instance_valid(target) and _eye_light:
		var dist := global_position.distance_to(target.global_position)
		_pulse += delta * clampf(14.0 - dist, 3.0, 22.0)
		var b := 0.6 + 0.4 * sin(_pulse)
		var energy := (2.0 + 4.0 * (1.0 - clampf(dist / 8.0, 0.0, 1.0))) * b
		var band := 1.0 + 4.5 * b
		var hot := _dive == Dive.ARM or _dive == Dive.DIVE
		if hot:
			energy = 9.0
			band = 9.0
		elif _dive == Dive.RECOVER:
			energy = 0.4
			band = 0.2
		_eye_light.light_energy = energy
		if _band_mat:
			_band_mat.emission_energy_multiplier = band
			_band_mat.emission = Color(1.0, 0.95, 0.85) if hot else Color(1.0, 0.55, 0.1)
			_band_mat.albedo_color = Color(0.22, 0.13, 0.04) if _dive == Dive.RECOVER else Color(1.0, 0.6, 0.1)
	_check_detonate()

func _check_detonate() -> void:
	if _detonated or target == null:
		return
	# Opening-seconds grace. EnemyBase applies this gate inside _state_attack, but
	# this kamikaze deals its damage from _physics_process instead — so without
	# the gate here it flew in and blew up on a player who had just loaded the
	# level. Keep closing in (the blink telegraph still reads); just hold the
	# blast until the player has had their couple of seconds. Deferred, not
	# defused: it detonates the moment grace lapses.
	# Covered by tests/seeker_grace_probe and tests/spawn_safety_probe.
	if GameState.attack_grace_active():
		return
	if not is_instance_valid(target) or _dive == Dive.RECOVER:
		return # spent after a missed dive: the fuse is cold until it comes round
	if global_position.distance_to(target.global_position) <= detonate_radius:
		_detonate(true)

## Ridden (#343): it dives at the aim point (up to PILOT_DIVE m) and goes off there,
## full payload, credited to the pilot. The chassis is spent, which ends the ride.
const PILOT_DIVE := 14.0
var _pilot_diving := false
func pilot_signature(aim: Vector3) -> void:
	if _pilot_diving or _detonated:
		return
	_pilot_diving = true
	var to := aim - global_position
	var dest := global_position + to.limit_length(PILOT_DIVE)
	AudioBus.play_synth_at("rocket_fire", global_position, -2.0, 1.3)
	var tw := create_tween()
	tw.tween_property(self, "global_position", dest, clampf(to.length() / 40.0, 0.12, 0.35))
	tw.tween_callback(func() -> void: _detonate(true, pilot_credit()))

## Boom. `hit_player` true on a kamikaze run (full damage); false when shot down.
## `credit` is who the blast is credited to (a ridden dive: the pilot).
func _detonate(hit_player: bool, credit: Node = null) -> void:
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
		# Kamikaze pop chars the deck it went off over.
		ScorchDecal.spawn(scene, global_position, radius * 0.5)
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
		d.apply_damage(damage * falloff, credit if credit != null else self)
	for p in GameState.players():
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
