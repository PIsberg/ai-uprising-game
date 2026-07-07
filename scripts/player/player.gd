class_name Player
extends CharacterBody3D

signal health_changed(current: float, max: float)
signal stamina_changed(current: float, max: float, exhausted: bool)
signal died
signal grenades_changed(count: int)
signal pickup_message(text: String) ## Fired when a non-weapon pickup is collected (for the HUD toast).

func notify_pickup(text: String) -> void:
	pickup_message.emit(text)

@export_group("Movement")
@export var walk_speed: float = 5.5
@export var sprint_speed: float = 9.0
@export var crouch_speed: float = 2.8
@export var acceleration: float = 18.0
@export var air_acceleration: float = 6.0
@export var friction: float = 14.0
@export var jump_velocity: float = 7.5
@export var coyote_time: float = 0.1 ## Grace to still jump just after stepping off a ledge.
@export var jump_buffer_time: float = 0.12 ## Grace for a jump pressed just before landing.
@export var sprint_jump_mult: float = 1.3 ## Jump boost after a sustained sprint (running jump).
@export var sprint_jump_charge: float = 0.5 ## Seconds of full-speed sprinting needed to bank the boost.

@export_group("Stamina")
## Sprinting and grappling burn stamina; standing/walking recovers it. Hit zero
## and you're EXHAUSTED — locked out of both until it climbs back to the recover
## threshold, so you can't machine-gun sprint bursts or chain-grapple forever.
@export var max_stamina: float = 100.0
@export var stamina_sprint_drain: float = 20.0   ## per second while actually running
@export var stamina_grapple_drain: float = 26.0  ## per second while winching on the tether
@export var stamina_regen: float = 18.0          ## per second recovered once you stop draining
@export var stamina_regen_delay: float = 0.5     ## grace after the last drain before regen starts
@export var stamina_recover_threshold: float = 30.0 ## exhausted lock clears once stamina climbs back to this
var _stamina: float = 100.0
var _stamina_exhausted: bool = false ## true from the moment stamina hits 0 until it recovers past the threshold
var _stamina_regen_cd: float = 0.0
var _was_exhausted: bool = false ## edge-detect so the HUD is only pinged when the lock flips
var _base_stamina: float = 100.0 ## authored max stamina before the STAMINA-track multiplier

@export_group("Look")
@export var mouse_sensitivity: float = 0.0022
@export var pad_look_speed: float = 3.2 ## Right-stick look speed (rad/s).
@export var pad_look_deadzone: float = 0.15
@export var look_clamp_deg: float = 89.0
@export_subgroup("Aim Assist (gamepad)")
@export var aim_assist_enabled: bool = true
@export var aim_assist_angle_deg: float = 7.0 ## Cone around the crosshair that engages friction.
@export var aim_assist_range: float = 60.0
@export var aim_assist_min: float = 0.45 ## Look-speed multiplier when the reticle sits on a target.

@export_group("Stance")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.0
@export var stance_lerp_speed: float = 12.0

@export_group("Camera Feel")
@export var bob_amplitude: float = 0.04
@export var bob_frequency: float = 11.0
@export var land_kick: float = 0.18
@export var strafe_tilt_deg: float = 1.4 ## Camera roll when strafing, for weight.
@export var max_shake_roll_deg: float = 2.6 ## Peak rotational kick at full trauma.
@export var hit_kick_amount: float = 0.05 ## Lateral camera punch (m), AWAY from the hit source, at full-fraction damage.
@export var hit_kick_roll_deg: float = 3.0 ## Camera roll punch (deg) at full-fraction damage, same sense as the lateral kick.

@export_group("Dash & Slide")
@export var dash_speed: float = 20.0
@export var dash_duration: float = 0.16
@export var dash_cooldown: float = 1.1
@export var slide_speed: float = 12.5
@export var slide_duration: float = 0.7
@export var slide_friction: float = 6.0

@export_group("Grenades")
@export var max_grenades: int = 3
@export var grenade_cooldown: float = 0.7
const GRENADE_SCENE := preload("res://scenes/weapons/grenade.tscn")
const VORTEX_SCENE := preload("res://scenes/weapons/grenade_vortex.tscn")
const EMP_SCENE := preload("res://scenes/weapons/grenade_emp.tscn")
enum GrenadeType { FRAG, VORTEX, EMP }
## Per-type loadout. FRAG is the workhorse; VORTEX is the rare "herd-then-delete"
## special — fewer carried, picked up later. Cycle with the grenade-cycle key.
var grenade_kinds := [
	{"type": GrenadeType.FRAG, "scene": GRENADE_SCENE, "name": "FRAG", "color": Color(1.0, 0.72, 0.2), "max": 3},
	{"type": GrenadeType.VORTEX, "scene": VORTEX_SCENE, "name": "VORTEX", "color": Color(0.66, 0.4, 1.0), "max": 2},
	{"type": GrenadeType.EMP, "scene": EMP_SCENE, "name": "EMP", "color": Color(0.35, 0.8, 1.0), "max": 2},
]
var grenade_type: int = 0                  # index into grenade_kinds
var grenade_counts := [3, 1, 2]            # current count per kind (parallel to grenade_kinds)
var grenades: int = 3                       # mirror of the selected kind's count (HUD + back-compat)
var _grenade_cd: float = 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collider: CollisionShape3D = $Collider
@onready var ceiling_check: RayCast3D = $CeilingCheck
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var hp: Damageable = $Damageable
@onready var _post_overlay: ColorRect = $PostFX/Overlay
var _dof_overlay: MeshInstance3D ## Optional depth-of-field fullscreen quad (built in code).
var _speed_warp: float = 0.0

var _dead: bool = false
var _bob_phase: float = 0.0
var _was_on_floor: bool = true
var _camera_base_y: float = 0.0
var _land_offset: float = 0.0
var _shake_amount: float = 0.0
var _cam_roll: float = 0.0
var _hit_kick_pos: float = 0.0  ## Signed lateral camera offset from a directional hit; eases to 0 in _handle_camera_feel.
var _hit_kick_roll: float = 0.0 ## Signed camera roll from the same hit; eases to 0 alongside it.

## External camera shake (e.g. a boss entrance). 0..~1.
func shake(amount: float) -> void:
	_shake_amount = maxf(_shake_amount, amount)

## Live look-sensitivity update (e.g. the pause-menu slider) so it takes effect
## immediately, not just on the next spawn.
func set_look_sensitivity(mult: float) -> void:
	_look_sens_mult = mult
var _is_crouching: bool = false
var _dash_time: float = 0.0
var _dash_cd: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _dodge_scored: bool = false ## One PERFECT DODGE reward per dash, not per blocked pellet.

var _fall_speed: float = 0.0   ## downward speed at the last touchdown (weights the landing)

# Ledge mantling: pull up onto a ledge you're cresting instead of scraping down it.
@export_group("Mantle")
@export var mantle_min_h: float = 0.7  ## lowest ledge worth a mantle (below this you just step up)
@export var mantle_max_h: float = 1.7  ## highest ledge you can pull yourself onto
@export var mantle_reach: float = 0.95 ## how far ahead the ledge face can be
var _mantle_cd: float = 0.0

# Step-up assist: CharacterBody3D has no automatic step climbing, so even a few
# centimetres of lip — a curb, a stray prop, or (the case this was built for)
# the seam where two ramp-wedge collisions meet at a spiral tower's corner
# pivot — reads as a solid wall and stops the player dead. When walking and
# blocked by something no taller than step_height, hop smoothly up onto it
# instead of scraping to a halt against it. Anything taller is mantle's job.
@export_group("Step Assist")
@export var step_height: float = 0.3 ## Tallest lip climbed automatically while walking.
const STEP_FORWARD_PROBE := 0.4 ## How far ahead (along intended motion) the step probe reaches once lifted.
const STEP_SKIN := 0.05 ## Extra downward reach past step_height so the landing probe doesn't fall just short of the surface.
var _pre_step_pos: Vector3 = Vector3.ZERO ## global_position snapshotted just before move_and_slide(), for the probes to start from.
var _pre_step_grounded: bool = false ## Was is_on_floor() true just before move_and_slide() ran this tick.

# Wall-running: sprint at a vertical wall while airborne to latch on and run
# along it (gravity eased, not cancelled), then jump off it for extra height/
# distance — or chain into another wall. No extra button: it engages the
# instant you're airborne, fast enough, and closing on a wall face.
@export_group("Wall Run")
@export var wall_run_speed: float = 8.5
@export var wall_run_duration: float = 1.0 ## max seconds attached before gravity wins
@export var wall_run_gravity: float = 7.0 ## eased fall rate while attached (vs. full gravity)
@export var wall_run_min_speed: float = 3.0 ## horizontal speed needed to latch on
@export var wall_jump_speed: float = 8.5 ## push-off velocity away from the wall
@export var wall_run_reattach_cd: float = 0.35 ## grace before the same/next wall can grab you again
var _wall_running: bool = false
var _wall_run_time: float = 0.0
var _wall_run_cd: float = 0.0
var _wall_normal: Vector3 = Vector3.ZERO
var _wall_run_dir: Vector3 = Vector3.ZERO
var _wall_lean: float = 0.0 ## smoothed camera roll into the wall while running

# Grapple hook: fire an energy tether (C / gamepad LB) at world geometry and
# winch toward it, keeping momentum on release — the fling is the payoff.
# Completes the traversal kit: dash covers ground, wall-run covers walls,
# mantle covers ledges, the grapple covers everything you can SEE.
@export_group("Grapple")
@export var grapple_range: float = 45.0
@export var grapple_winch_speed: float = 24.0 ## top pull speed along the tether
@export var grapple_winch_accel: float = 55.0 ## how hard the winch reels you in
@export var grapple_min_dist: float = 2.6 ## auto-release when this close to the anchor
@export var grapple_cooldown: float = 0.7
var _grappling: bool = false
var _grapple_point: Vector3 = Vector3.ZERO
var _grapple_cd: float = 0.0
var _grapple_valid: bool = false ## HUD reticle cue: a grapple anchor is in range right now.
var _gv_t: float = 0.0 ## throttle for the validity raycast
var _tether: Node3D = null
var _tether_beam: MeshInstance3D = null
var _tether_core: MeshInstance3D = null
var _tether_orb: MeshInstance3D = null

var _sliding: bool = false
var _slide_time: float = 0.0
var _fov_base: float = 0.0
var _fov_kick: float = 0.0
var _look_sens_mult: float = 1.0
var _look_y_sign: float = 1.0
var _step_accum: float = 0.0
const STEP_INTERVAL_WALK := 2.4
const STEP_INTERVAL_SPRINT := 3.2
const STEP_INTERVAL_CROUCH := 1.6

# ---------- melee shove (F): a close-quarters panic kick ----------
# A quick frontal shove that damages + knocks back everything in a cone right in
# front of you, on a short cooldown — the answer to being swarmed by skitters,
# spiders, dogs and other rushers when reloading or boxed in. No ammo cost.
@export_group("Melee")
@export var melee_damage: float = 28.0
@export var melee_range: float = 3.2
@export var melee_radius: float = 2.4
@export var melee_arc_deg: float = 120.0
@export var melee_knockback: float = 13.0
@export var melee_cooldown: float = 0.85
@export var execute_hp_threshold: float = 40.0 ## A melee hit on a non-boss below this HP is a guaranteed EXECUTION (instakill + crunch + bonus).
var _melee_cd: float = 0.0

# ---------- soft enemy separation ----------
# Enemies only ever masked the world (layer 1) — the player used to also mask
# THEM (mask=5), so the player's own move_and_slide depenetrated against every
# enemy body it touched. That meant an enemy walking into the player shoved the
# PLAYER around every frame: awful in general, and on the convoy's moving flatbed
# a boarded brute could shove the player clean off the deck. Enemy melee damage
# is attack_range-based (enemy_base.gd), never physics-contact-based, so nothing
# actually depends on hard collision here. This replaces it with a cheap soft
# push: a sphere probe against the enemy layer each frame, one shape query, push
# strength ramping with how deep an enemy is inside the probe and capped well
# below anything that could snap/launch the player. A deep press from something
# big (a brute planted on you) resists hard enough to cancel a walk; a graze from
# a wandering enemy is a gentle nudge. Suspended during the dash's i-frame window
# so the dash keeps phasing clean through.
@export_group("Soft Enemy Separation")
@export var separation_radius: float = 1.2 ## Sphere probe radius, centred on the capsule's mid-torso.
@export var separation_max_speed: float = 6.0 ## Hard cap on the push, m/s.
var _separation_push: Vector3 = Vector3.ZERO

## Sphere-probes the enemy layer around the player and builds this frame's soft
## push-away velocity into _separation_push (added onto velocity in
## _physics_process, right before move_and_slide).
func _update_enemy_separation() -> void:
	_separation_push = Vector3.ZERO
	if _dash_time > 0.0:
		return  # i-frames: the dash phases clean through, no push at all
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = separation_radius
	q.shape = sh
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * 0.9)
	q.collision_mask = 0b0000100 # enemy layer only
	q.collide_with_areas = false
	var hits := space.intersect_shape(q, 8)
	var push := Vector3.ZERO
	for h in hits:
		var col := h.get("collider") as Node3D
		if col == null or col == self:
			continue
		var away := global_position - col.global_position
		away.y = 0.0
		var dist := away.length()
		var dir := away / dist if dist > 0.05 else Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized()
		# 0 at the probe's edge, 1 when the two origins coincide — squared so a
		# graze barely registers and only a deep press ramps up hard.
		var depth := clampf(1.0 - dist / separation_radius, 0.0, 1.0)
		push += dir * (depth * depth)
	var strength := push.length()
	if strength > 0.001:
		_separation_push = (push / strength) * minf(strength, 1.0) * separation_max_speed

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_base_y = camera.position.y
	_apply_user_settings()
	_build_dof_overlay()
	_build_fill_light()
	_fov_base = camera.fov
	_register_dash_action()
	_register_melee_action()
	_register_grapple_action()
	grenades = max_grenades
	# Field supplies bought in the Armory are PERMANENT for the run: they re-apply
	# on every deploy (a fresh player each level, so no compounding) and are only
	# cleared by reset_run() on a new campaign — what you buy follows you.
	if GameState.supply_health > 0.0:
		hp.max_health += GameState.supply_health
	hp.current_health = hp.max_health
	# STAMINA armory track: a bigger pool to sprint/rappel on before gassing out.
	_base_stamina = max_stamina # authored base, kept so the "imba" cheat can re-apply the mult
	max_stamina = _base_stamina * GameState.stamina_mult()
	_stamina = max_stamina
	stamina_changed.emit(_stamina, max_stamina, false)
	if GameState.supply_grenades > 0:
		grenade_counts[GrenadeType.FRAG] += GameState.supply_grenades
	_sync_grenades()
	_apply_supply_ammo.call_deferred()  # after the WeaponManager has built the arsenal
	hp.health_changed.connect(_on_health_changed)
	hp.died.connect(_on_died)
	hp.damaged.connect(_on_hp_damaged)
	# Health on kill: aggression is survival. Without any mid-fight recovery a
	# 100 HP pool just attrits to zero (playtests died at first contact); every
	# kill now restores a sliver, scaled by the target's worth — pushing INTO
	# the fight is how you stay alive, which is exactly the game's tempo.
	GameState.enemy_killed.connect(func(points, _lbl):
		if not _dead and hp:
			hp.heal(clampf(2.0 + points / 50.0, 3.0, 10.0)))

## Pour any bought ammo crates into every weapon's reserve. Persistent for the
## run — re-applied each deploy (not cleared), so the reserve bonus carries on.
func _apply_supply_ammo() -> void:
	if GameState.supply_ammo <= 0:
		return
	var wm := get_node_or_null("Head/Camera3D/WeaponHolder")
	if wm and "weapons" in wm:
		for w in wm.weapons:
			if w and w.has_method("add_ammo"):
				w.add_ammo(GameState.supply_ammo)

## Soft personal fill light: guarantees the player's immediate surroundings stay
## readable in crushed-dark scenes (dusk streets, unlit corners, wall shadows)
## without lifting the whole scene — tight range, shadowless, zero specular so
## it never paints highlights or doubles render passes. One omni ≈ free.
func _build_fill_light() -> void:
	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.55
	fill.omni_range = 10.0
	fill.omni_attenuation = 1.6 # fades out well before the range cap
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	fill.light_color = Color(1.0, 0.97, 0.92)
	fill.position = Vector3(0, 1.4, 0)
	add_child(fill)

## Optional cinematic depth-of-field: a fullscreen quad under the camera running
## shaders/dof.gdshader. Built once and hidden until enabled in settings.
func _build_dof_overlay() -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	mi.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/dof.gdshader")
	mi.set_surface_override_material(0, sm)
	mi.extra_cull_margin = 16384.0 # fullscreen quad: never frustum-cull it
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	camera.add_child(mi)
	_dof_overlay = mi

## Feed the DoF shader the focus point: raycast straight ahead and focus on
## whatever the camera looks at (so the player's target stays sharp). Polls the
## setting so it can be toggled live; hidden + skipped when off.
func _update_dof() -> void:
	if _dof_overlay == null:
		return
	var gs := get_node_or_null("/root/GraphicsSettings")
	var on: bool = gs != null and bool(gs.get("dof_enabled"))
	if _dof_overlay.visible != on:
		_dof_overlay.visible = on
	if not on:
		return
	var origin := camera.global_position
	var endp := origin - camera.global_transform.basis.z * 250.0
	var params := PhysicsRayQueryParameters3D.create(origin, endp, 1)
	params.exclude = [get_rid()]
	var ray := get_world_3d().direct_space_state.intersect_ray(params)
	if not ray.is_empty():
		endp = ray["position"]
	var sm := _dof_overlay.get_surface_override_material(0) as ShaderMaterial
	if sm:
		sm.set_shader_parameter("ray_position", endp)

## Sprint speed-warp: feed the post shader a 0..1 value that radial-streaks the
## screen edges the faster you run.
func _handle_speed_warp(delta: float) -> void:
	# Grapple pulls are often mostly vertical, so measure full 3D speed there;
	# ground states keep the horizontal read (falling shouldn't streak).
	var speed := velocity.length() if _grappling else Vector2(velocity.x, velocity.z).length()
	var sprinting := Input.is_action_pressed("sprint") and is_on_floor() and not _is_crouching
	# Dashing (20 m/s), wall-running (8.5 m/s, near sprint speed) and the grapple
	# winch (24 m/s) are at least as fast as a sprint, but previously never
	# triggered the radial streak — only grounded sprinting did, so the fastest
	# movement states looked static.
	var fast_state := sprinting or _dash_time > 0.0 or _wall_running or _grappling
	var target := clampf(speed / sprint_speed, 0.0, 1.0) if fast_state else 0.0
	# OVERDRIVE keeps the radial speed-streaks up the whole time it's active.
	if GameState.overdrive_active():
		target = maxf(target, 0.55)
	_speed_warp = lerpf(_speed_warp, target, clampf(6.0 * delta, 0.0, 1.0))
	if _post_overlay and _post_overlay.material is ShaderMaterial:
		(_post_overlay.material as ShaderMaterial).set_shader_parameter("speed_warp", _speed_warp)

## Camera kick when hit, scaled by the hit's size — every enemy attack lands.
## Pull display/input prefs from GraphicsSettings (FOV, look sensitivity, invert).
func _apply_user_settings() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs == null:
		return
	if "fov" in gs:
		# _handle_camera_feel recomputes camera.fov from _fov_base every tick,
		# so the user's setting must land on the base, not just the camera.
		_fov_base = gs.fov
		camera.fov = gs.fov
	if "sensitivity" in gs:
		_look_sens_mult = gs.sensitivity
	if "invert_y" in gs:
		_look_y_sign = -1.0 if gs.invert_y else 1.0
	if "aim_assist" in gs:
		aim_assist_enabled = gs.aim_assist
	update_post_process_settings()

func update_post_process_settings() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs and _post_overlay and _post_overlay.material is ShaderMaterial:
		var sm := _post_overlay.material as ShaderMaterial
		var enabled := bool(gs.get("advanced_post_process_enabled"))
		sm.set_shader_parameter("advanced_post_process_enabled", enabled)
		var params: Dictionary = gs.COLOR_GRADE_PARAMS.get(gs.color_grade, {})
		sm.set_shader_parameter("grade_tint", params.get("tint", Color.WHITE))
		sm.set_shader_parameter("grade_contrast", params.get("contrast", 1.0))
		sm.set_shader_parameter("grade_saturation", params.get("saturation", 1.0))

var _hurt_cd: float = 0.0
## Fraction of max HP a single hit must take to count as BIG (triggers the
## micro hit-stop below, not just the directional camera punch).
const BIG_HIT_FRAC := 0.25

func _on_hp_damaged(amount: float, source: Node) -> void:
	# Every hit lands as a camera kick, scaled with the bite taken.
	shake(clampf(0.3 + amount * 0.025, 0.3, 0.95))
	GameState.register_damage_taken(amount) # feeds the end-of-level grade
	var frac := (amount / hp.max_health) if hp and hp.max_health > 0.0 else 0.0
	_apply_hit_kick(source, frac)
	# Micro hit-stop: a ~50ms Engine.time_scale dip, BIG hits only, so it reads
	# as "that one really landed" instead of nausea-inducing on every graze.
	# Reuses GameState's existing combat hit-stop primitive (same one per-kill
	# hits already use) rather than a new freeze system; it's rate-limited
	# there so a horde can't stutter the game into a slideshow. Safe even if
	# this hit is the killing blow: GameState.set_state(GAME_OVER) forces
	# Engine.time_scale back to 1.0 the instant on_player_died runs (see
	# set_state), so a death mid-dip can never leave slow-mo stuck on.
	if frac >= BIG_HIT_FRAC:
		GameState.combat_hitstop(0.3, 0.05)
	# A grunt/impact on getting hit — throttled so rapid fire doesn't stack into
	# a drone, and pitched down slightly the harder the hit.
	if _hurt_cd <= 0.0 and hp and hp.current_health > 0.0:
		_hurt_cd = 0.22
		var pitch := clampf(1.12 - amount * 0.012, 0.82, 1.12) + randf_range(-0.04, 0.04)
		AudioBus.play_synth_ui("player_hurt", -4.0, pitch)
	# Clutch ADRENALINE SURGE: a hit that drops you to critical (but not dead)
	# kicks a brief bullet-time comeback beat + offensive/mobility buff. Cooldown
	# and alive-check live in GameState.try_adrenaline; this just detects the line.
	if hp and hp.current_health > 0.0 and hp.max_health > 0.0 \
			and hp.current_health / hp.max_health <= GameState.ADRENALINE_TRIGGER_FRAC:
		GameState.try_adrenaline()

## Directional camera punch AWAY from the hit source — a locational thump layered
## on top of the undirected shake trauma above, so a hit reads not just as
## "ouch" but "ouch, from THERE" (the HUD's damage_indicator wedges already do
## this for the 2D readout; this is the 3D camera-feel counterpart). Reuses the
## same spring-and-ease idiom the rest of camera feel uses (_land_offset,
## _fov_kick): set once here as an impulse, eased back to zero every frame in
## _handle_camera_feel. Scaled by the damage fraction and by the Screen Shake
## accessibility setting, same as the rest of the shake.
func _apply_hit_kick(source: Node, damage_frac: float) -> void:
	if not (source is Node3D):
		return
	var rel: Vector3 = (source as Node3D).global_position - global_position
	var flat := Vector2(rel.x, rel.z)
	if flat.length() < 0.05:
		return
	var right := Vector2(cos(rotation.y), -sin(rotation.y))
	var side := flat.normalized().dot(right) # -1 (hit from the left) .. +1 (from the right)
	var punch := clampf(damage_frac, 0.0, 1.0) * GraphicsSettings.screen_shake
	if punch <= 0.001 or absf(side) < 0.05:
		return
	_hit_kick_pos = -signf(side) * hit_kick_amount * punch # kick away from the hit
	_hit_kick_roll = -signf(side) * deg_to_rad(hit_kick_roll_deg) * punch

# ---------- low-health state: red pulse on screen + heavy breathing ----------

const LOW_HEALTH_FRAC := 0.35 ## Effects ramp in below this health fraction.

var _low_health: float = 0.0   # smoothed 0..1 severity driven into the shader
var _breath: AudioStreamPlayer

func _handle_low_health(delta: float) -> void:
	var frac := 1.0
	if hp and hp.max_health > 0.0:
		frac = hp.current_health / hp.max_health
	var severity := clampf(1.0 - frac / LOW_HEALTH_FRAC, 0.0, 1.0)
	_low_health = move_toward(_low_health, severity, delta * 2.5)
	if _post_overlay and _post_overlay.material is ShaderMaterial:
		(_post_overlay.material as ShaderMaterial).set_shader_parameter("low_health", _low_health)
	# Heavy breathing swells (and quickens slightly) the closer to death you are.
	if severity > 0.02 and hp.current_health > 0.0:
		if _breath == null:
			_breath = AudioStreamPlayer.new()
			_breath.bus = "SFX"
			_breath.stream = AudioBus.synth("breathing")
			add_child(_breath)
		if not _breath.playing:
			_breath.play()
		_breath.volume_db = lerpf(-22.0, -6.0, severity)
		_breath.pitch_scale = 1.0 + 0.12 * severity
	elif _breath and _breath.playing:
		_breath.stop()

# --- cheats: type a keyword during play. "god" toggles invincibility; "imba"
# maxes every permanent upgrade track for the run (testing aids). ---
const GOD_WORD := "god"
const IMBA_WORD := "imba"
var _god: bool = false
var _cheat_buf := ""

func _input(event: InputEvent) -> void:
	# Cheat keyword buffer runs even while dead, so you can flip it on at any time.
	if event is InputEventKey and event.pressed and not event.echo:
		var u := (event as InputEventKey).unicode
		if u != 0:
			_cheat_buf = (_cheat_buf + char(u).to_lower()).right(8) # holds the longest keyword
			if _cheat_buf.ends_with(GOD_WORD):
				_cheat_buf = ""
				_toggle_god()
			elif _cheat_buf.ends_with(IMBA_WORD):
				_cheat_buf = ""
				_cheat_imba()
	if _dead:
		return  # no looking around once you're down
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		rotate_y(-m.relative.x * mouse_sensitivity * _look_sens_mult)
		head.rotate_x(-m.relative.y * mouse_sensitivity * _look_sens_mult * _look_y_sign)
		head.rotation.x = clampf(head.rotation.x, -deg_to_rad(look_clamp_deg), deg_to_rad(look_clamp_deg))

func _physics_process(delta: float) -> void:
	if _dead:
		# Collapsed: gravity holds you on the deck, momentum bleeds off; no control.
		_apply_gravity(delta)
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		move_and_slide()
		return
	_apply_gravity(delta)
	_handle_stamina(delta)
	_handle_gamepad_look(delta)
	_handle_speed_warp(delta)
	_handle_low_health(delta)
	_handle_dash(delta)
	_handle_melee(delta)
	_handle_slide(delta)
	_handle_jump(delta)
	_handle_grenade(delta)
	_handle_stance(delta)
	_handle_mantle(delta)
	_handle_wall_run(delta)
	_handle_grapple(delta)
	_handle_movement(delta)
	_update_enemy_separation()
	velocity.x += _separation_push.x
	velocity.z += _separation_push.z
	_handle_camera_feel(delta)
	if not is_on_floor():
		_fall_speed = -velocity.y   # peak downward speed this fall (read on landing)
	_pre_step_pos = global_position
	_pre_step_grounded = is_on_floor()
	move_and_slide()
	_try_step_up()
	_update_dof()
	_check_landing()
	_handle_footsteps(delta)

## Registers the dash action (Q) at runtime so it works without editing the
## project input map. Gamepad users dash with the right-stick click is taken;
## keyboard-only is fine for now.
func _register_dash_action() -> void:
	if not InputMap.has_action("dash"):
		InputMap.add_action("dash")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_Q
		InputMap.action_add_event("dash", ev)

## Registers the melee shove (F + gamepad B) at runtime, like the dash — no
## project input-map edit needed.
func _register_melee_action() -> void:
	if not InputMap.has_action("melee"):
		InputMap.add_action("melee")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F
		InputMap.action_add_event("melee", ev)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_B
		InputMap.action_add_event("melee", pad)

var _wh_kick_tween: Tween ## Tracks the last dash/landing viewmodel kick so overlapping kicks don't fight over weapon_holder.position.

## A quick viewmodel punch on weapon_holder (dash/landing) — snapshots the
## current position as "home", kicks out to it, then springs back. Melee has
## its own inline version of this same pattern; kept separate since kicks that
## land close together (e.g. a hard fall right after a dash) would otherwise
## fight over weapon_holder.position if they shared one tween.
func _kick_weapon_holder(offset: Vector3, out_time: float, back_time: float) -> void:
	if weapon_holder == null:
		return
	if _wh_kick_tween and _wh_kick_tween.is_valid():
		_wh_kick_tween.kill()
	var home := weapon_holder.position
	_wh_kick_tween = create_tween()
	_wh_kick_tween.tween_property(weapon_holder, "position", home + offset, out_time)
	_wh_kick_tween.tween_property(weapon_holder, "position", home, back_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Frontal shove: a cone-of-influence kick that damages + knocks back every
## hostile right in front of you, on a short cooldown. Your get-off-me button.
func _handle_melee(delta: float) -> void:
	_melee_cd = maxf(0.0, _melee_cd - delta)
	if _melee_cd > 0.0 or not Input.is_action_just_pressed("melee"):
		return
	_melee_cd = melee_cooldown
	_fov_kick = maxf(_fov_kick, 6.0)
	shake(0.18)
	AudioBus.play_synth_at("grenade_throw", global_position, -6.0, 1.7) # whoosh
	# A quick viewmodel jab so the shove reads in first person.
	if weapon_holder:
		var home := weapon_holder.position
		var tw := create_tween()
		tw.tween_property(weapon_holder, "position", home + Vector3(0, -0.05, -0.14), 0.06)
		tw.tween_property(weapon_holder, "position", home, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_do_melee()

func _do_melee() -> void:
	var origin := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = melee_radius
	q.shape = sh
	# Centre the probe sphere a little ahead so the cone covers what's in front.
	q.transform = Transform3D(Basis(), origin + fwd * (melee_range - melee_radius * 0.5))
	q.collision_mask = 0b0000100 # enemies (layer 3)
	q.collide_with_areas = false
	var hits := space.intersect_shape(q, 16)
	var struck := false
	var seen := {}
	for h in hits:
		var col: Node = h.get("collider")
		if col == null or seen.has(col):
			continue
		seen[col] = true
		if not (col is Node3D):
			continue
		var to: Vector3 = (col as Node3D).global_position + Vector3.UP * 0.8 - origin
		if to.length() > melee_range + 0.6:
			continue
		# Frontal cone only — it's a shove, not an aura.
		var flat := to; flat.y = 0.0
		if flat.length() > 0.1 and rad_to_deg(fwd.angle_to(flat.normalized())) > melee_arc_deg * 0.5:
			continue
		var d := col.get_node_or_null("Damageable")
		if d and d.has_method("apply_damage"):
			# EXECUTION: a shove into a weakened, non-boss enemy is a finisher —
			# guaranteed kill with a heavier crunch, so melee reads as a real
			# takedown tool, not just a get-off-me nudge.
			var is_boss := col is EnemyBase and (col as EnemyBase).score_value >= 1000
			if not is_boss and d.current_health > 0.0 and d.current_health <= execute_hp_threshold:
				d.apply_damage(9999.0, self)
				GameState.reward_execution((col as Node3D).global_position + Vector3.UP * 1.2)
			else:
				d.apply_damage(melee_damage, self)
			struck = true
		# Heavy knockback away from the player (+ a little lift) — the "get off me".
		if "velocity" in col:
			var push := flat.normalized() if flat.length() > 0.1 else fwd
			col.velocity += push * melee_knockback + Vector3.UP * 3.0
	if struck:
		AudioBus.play_synth_at("impact_metal", origin + fwd * 1.5, -2.0, 0.8)
		shake(0.3)
		_fov_kick = maxf(_fov_kick, 9.0)

## A short, snappy burst in the movement direction (or forward if idle). Works
## on the ground or in the air; has a cooldown and a FOV/whoosh kick for punch.
## The dash window grants i-frames, so it doubles as a dodge — read the rocket,
## dash through it.
func _handle_dash(delta: float) -> void:
	_dash_cd = maxf(0.0, _dash_cd - delta)
	if _dash_time > 0.0:
		_dash_time -= delta
		velocity.x = _dash_dir.x * dash_speed
		velocity.z = _dash_dir.z * dash_speed
		if _dash_time <= 0.0:
			hp.invulnerable = _god  # dash i-frames end — but stay invincible if god mode is on
		return
	# Track taps every frame so the double-tap window stays accurate; a quick
	# double-tap of a movement key dodges in that direction (classic dodge feel,
	# works without a spare button — the bound "dash" key/stick still works too).
	var tap_dir := _double_tap_dir()
	if _dash_cd > 0.0 or _sliding:
		return
	if Input.is_action_just_pressed("dash") or tap_dir != Vector3.ZERO:
		var dir := tap_dir
		if dir == Vector3.ZERO:
			var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			dir = transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
			if dir.length() < 0.1:
				dir = -transform.basis.z # dash forward when no stick/key input
		_dash_dir = dir.normalized()
		_dash_time = dash_duration
		_dash_cd = dash_cooldown
		_dodge_scored = false
		hp.invulnerable = true
		# The i-frame window also suspends the soft enemy-separation push (see
		# _update_enemy_separation): enemies have no hard collision with the player
		# at all any more, but the soft push alone can still resist a beeline through
		# a planted brute, and the dash is the escape tool — a dodge that bounces off
		# the thing it's dodging is no dodge at all.
		velocity.y = maxf(velocity.y, 0.0) # flatten the arc for a clean lunge
		_fov_kick = 9.0
		shake(0.22)
		AudioBus.play_synth_at("grenade_throw", global_position, -8.0, 1.5)
		# The gun lags behind the sudden lunge (a snap-back drag toward the player,
		# opposite the melee jab's forward punch) so the dash reads in first person
		# instead of just being a camera/velocity trick.
		_kick_weapon_holder(Vector3(0, -0.03, 0.1), 0.05, 0.24)

## GOD-mode cheat: flip the player's invulnerability. Topped up to full health on
## enable so a near-dead tester is instantly safe. Feedback via the HUD toast
## (the pickup_message signal) and a chirp.
func _toggle_god() -> void:
	_god = not _god
	hp.invulnerable = _god
	if _god and hp.has_method("heal"):
		hp.heal(hp.max_health)
	pickup_message.emit("☢ GOD MODE: " + ("ON — invincible" if _god else "OFF"))
	AudioBus.play_synth_ui("pickup_health", -4.0, 1.7 if _god else 0.8)

## "imba" cheat: max every armory upgrade track for the run, and apply the parts
## that normally only take effect on deploy (the stamina pool) to the live player
## right now. Damage/mag/reload/blast/leech read their multipliers live already.
func _cheat_imba() -> void:
	GameState.max_all_upgrades()
	max_stamina = _base_stamina * GameState.stamina_mult()
	_stamina = max_stamina
	_stamina_exhausted = false
	stamina_changed.emit(_stamina, max_stamina, false)
	if hp and hp.has_method("heal"):
		hp.heal(hp.max_health)
	pickup_message.emit("★ IMBA — ALL UPGRADES MAXED")
	AudioBus.play_synth_ui("victory", -3.0, 1.1)

## Returns a world-space dodge direction when a movement key is double-tapped
## within the window, else Vector3.ZERO. Updates the tap tracker every call.
const _DTAP_WINDOW := 0.28
var _dtap_act: String = ""
var _dtap_t: float = 0.0

func _double_tap_dir() -> Vector3:
	for p in [["move_forward", Vector3.FORWARD], ["move_back", Vector3.BACK],
			["move_left", Vector3.LEFT], ["move_right", Vector3.RIGHT]]:
		if Input.is_action_just_pressed(p[0]):
			var now := float(Time.get_ticks_msec()) / 1000.0
			if p[0] == _dtap_act and now - _dtap_t <= _DTAP_WINDOW:
				_dtap_act = ""
				return (transform.basis * (p[1] as Vector3)).normalized()
			_dtap_act = p[0]
			_dtap_t = now
			break
	return Vector3.ZERO

## Sprint + crouch while moving fast launches a low, gliding slide that bleeds
## speed; tapping jump cancels it into a slide-hop. Forces a crouched stance.
func _handle_slide(delta: float) -> void:
	if _sliding:
		_slide_time -= delta
		var flat := Vector2(velocity.x, velocity.z)
		var sp := move_toward(flat.length(), 0.0, slide_friction * delta)
		if flat.length() > 0.01:
			var d := flat.normalized()
			velocity.x = d.x * sp
			velocity.z = d.y * sp
		var hopped := Input.is_action_just_pressed("jump") and is_on_floor()
		if _slide_time <= 0.0 or sp < crouch_speed * 1.1 or not is_on_floor() or hopped:
			_sliding = false
			if hopped:
				velocity.y = jump_velocity * 1.05
		return
	if Input.is_action_just_pressed("crouch") and is_on_floor() and Input.is_action_pressed("sprint"):
		if Vector2(velocity.x, velocity.z).length() > walk_speed * 0.8:
			_sliding = true
			_slide_time = slide_duration
			var d := Vector2(velocity.x, velocity.z).normalized()
			velocity.x = d.x * slide_speed
			velocity.z = d.y * slide_speed
			_fov_kick = 5.0
			shake(0.14)
			AudioBus.play_synth_at("footstep", global_position, 2.0, 0.55)

## Right analog stick aims (mouse look is handled in _input). Deadzoned, with
## a mild response curve so fine aim is easy and big flicks are still fast.
func _handle_gamepad_look(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var lx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ly := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(lx) < pad_look_deadzone:
		lx = 0.0
	if absf(ly) < pad_look_deadzone:
		ly = 0.0
	if lx == 0.0 and ly == 0.0:
		return
	lx = signf(lx) * pow(absf(lx), 1.5)
	ly = signf(ly) * pow(absf(ly), 1.5)
	# Aim friction: ease the look speed down when the reticle is near a hostile,
	# so tracking a target on a stick feels sticky-good (not auto-aim). Gamepad
	# only — mouse aim stays untouched.
	var fr := _aim_friction()
	rotate_y(-lx * pad_look_speed * delta * _look_sens_mult * fr)
	head.rotate_x(-ly * pad_look_speed * delta * _look_sens_mult * _look_y_sign * fr)
	head.rotation.x = clampf(head.rotation.x, -deg_to_rad(look_clamp_deg), deg_to_rad(look_clamp_deg))

## Look-speed multiplier in [aim_assist_min, 1.0]: drops toward the minimum as
## the camera-forward ray closes on the nearest live hostile within the cone.
func _aim_friction() -> float:
	if not aim_assist_enabled:
		return 1.0
	var fwd := -camera.global_transform.basis.z
	var origin := camera.global_position
	var best := 1.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D):
			continue
		if e is EnemyBase and (e as EnemyBase).hp != null and not (e as EnemyBase).hp.is_alive():
			continue
		var to: Vector3 = (e as Node3D).global_position + Vector3(0, 1.0, 0) - origin
		var dist := to.length()
		if dist < 1.0 or dist > aim_assist_range:
			continue
		var ang := rad_to_deg(fwd.angle_to(to))
		if ang <= aim_assist_angle_deg:
			best = minf(best, lerpf(aim_assist_min, 1.0, ang / aim_assist_angle_deg))
	return best

func _handle_grenade(delta: float) -> void:
	_grenade_cd = maxf(0.0, _grenade_cd - delta)
	if Input.is_action_just_pressed("grenade_cycle"):
		_cycle_grenade()
	if Input.is_action_just_pressed("grenade"):
		_throw_grenade()

## Switch the armed grenade type (FRAG ⇄ VORTEX). Toggles unconditionally so an
## empty kind is still selectable — you can see you've unlocked it before resupply.
func _cycle_grenade() -> void:
	grenade_type = (grenade_type + 1) % grenade_kinds.size()
	_sync_grenades()
	AudioBus.play_synth_at("broadcast_blip", global_position, -8.0, 1.4)
	pickup_message.emit("%s GRENADE" % grenade_kinds[grenade_type]["name"])

func _sync_grenades() -> void:
	grenades = grenade_counts[grenade_type]
	grenades_changed.emit(grenades)

func _throw_grenade() -> void:
	if grenade_counts[grenade_type] <= 0 or _grenade_cd > 0.0:
		return
	grenade_counts[grenade_type] -= 1
	_grenade_cd = grenade_cooldown
	var g: Node = (grenade_kinds[grenade_type]["scene"] as PackedScene).instantiate()
	# GRENADE POWER upgrade: scale this charge's blast (damage + reach) before it's
	# thrown. Covers frag (splash), vortex (splash + pull) and EMP (burst radius).
	var gm := GameState.grenade_mult()
	if gm > 1.0:
		for prop in ["splash_damage", "splash_radius", "damage", "pull_radius", "burst_radius"]:
			if prop in g:
				g.set(prop, float(g.get(prop)) * gm)
	get_tree().current_scene.add_child(g)
	var dir := -camera.global_transform.basis.z
	g.global_position = camera.global_position + dir * 0.7
	# Lob forward + up, inheriting a little of the player's momentum.
	var throw_vel := dir * 17.0 + Vector3.UP * 3.5 + Vector3(velocity.x, 0, velocity.z) * 0.5
	if g.has_method("throw_grenade"):
		g.throw_grenade(throw_vel, self)
	AudioBus.play_synth_at("grenade_throw", global_position, -3.0, randf_range(0.95, 1.1))
	_sync_grenades()

## Frag pickups top up FRAG; pass a kind index for special resupply.
func add_grenade(amount: int = 1, kind: int = GrenadeType.FRAG) -> void:
	grenade_counts[kind] = mini(int(grenade_kinds[kind]["max"]), grenade_counts[kind] + amount)
	_sync_grenades()

func _apply_gravity(delta: float) -> void:
	if _wall_running:
		return  # _update_wall_run owns velocity.y with its own eased fall rate
	if _grappling:
		return  # the winch is taut — _update_grapple owns the pull
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _sprint_charge: float = 0.0 ## Banked sprint time for the higher running jump.

## Coyote time + jump buffering so jumps land when the player MEANT them: you can
## still jump a hair after walking off a ledge, and a jump pressed just before
## touchdown fires on landing instead of being eaten.
func _handle_jump(delta: float) -> void:
	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote = maxf(0.0, _coyote - delta)
	# Bank sprint time while running on the ground; a sustained sprint lets the
	# next jump launch higher (a running jump). Reset the instant you stop
	# sprinting on the ground; held through the air so the launch keeps the boost.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and Input.is_action_pressed("sprint") and not _is_crouching and hspeed > walk_speed:
		_sprint_charge = minf(sprint_jump_charge, _sprint_charge + delta)
	elif is_on_floor():
		_sprint_charge = 0.0
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if _jump_buffer > 0.0 and _coyote > 0.0 and not _is_crouching:
		var vy := jump_velocity
		if _sprint_charge >= sprint_jump_charge:
			vy *= sprint_jump_mult # running jump — clears wider gaps / higher ledges
		velocity.y = vy
		_jump_buffer = 0.0
		_coyote = 0.0

## Ledge mantle: when you're cresting a ledge that's just above step height — at
## the apex of a jump or falling against it while pushing forward — pull yourself
## up and over instead of scraping down the wall. Auto-triggers (no extra button)
## so the new verticality flows. Gives exactly enough upward boost to clear the
## lip plus a forward carry onto the platform.
func _handle_mantle(delta: float) -> void:
	_mantle_cd = maxf(0.0, _mantle_cd - delta)
	if is_on_floor() or _mantle_cd > 0.0 or _dash_time > 0.0 or _sliding or _is_crouching:
		return
	if velocity.y > 2.0:
		return  # still rocketing up — mantle at the apex or on the way down
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	# Only when actually heading into the wall: pressing forward, or carrying into it.
	var into := Vector2(velocity.x, velocity.z).dot(Vector2(fwd.x, fwd.z))
	if not Input.is_action_pressed("move_forward") and into < 1.0:
		return
	var space := get_world_3d().direct_space_state
	# 1) A wall face right in front, around chest height.
	var chest := global_position + Vector3.UP * 0.8
	var wq := PhysicsRayQueryParameters3D.create(chest, chest + fwd * mantle_reach)
	wq.collision_mask = 0b0000001  # world
	wq.exclude = [get_rid()]
	var wh := space.intersect_ray(wq)
	if wh.is_empty() or absf((wh["normal"] as Vector3).y) > 0.4:
		return  # no wall, or it's a slope/floor — not a ledge face
	# 2) A walkable ledge TOP within mantle height, just past the face.
	var top := global_position + Vector3.UP * (mantle_max_h + 0.4) + fwd * (mantle_reach + 0.25)
	var dq := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * (mantle_max_h + 0.6))
	dq.collision_mask = 0b0000001
	dq.exclude = [get_rid()]
	var dh := space.intersect_ray(dq)
	if dh.is_empty() or (dh["normal"] as Vector3).y < 0.6:
		return  # nothing to stand on, or too steep to count as a ledge
	var ledge_pos: Vector3 = dh["position"]
	var h := ledge_pos.y - global_position.y
	if h < mantle_min_h or h > mantle_max_h:
		return
	# 3) Headroom above the ledge so we don't haul up into a crawlspace.
	var clear_from := Vector3(ledge_pos.x, ledge_pos.y + 0.1, ledge_pos.z)
	var cq := PhysicsRayQueryParameters3D.create(clear_from, clear_from + Vector3.UP * (stand_height * 0.9))
	cq.collision_mask = 0b0000001
	cq.exclude = [get_rid()]
	if not space.intersect_ray(cq).is_empty():
		return
	# Pull up: just enough upward velocity to crest the lip with margin, plus a
	# forward carry so you flow onto the platform instead of catching the edge.
	if _grappling and _zip_anchor != null:
		return # a scripted zipline owns the ride — don't crest random lips mid-cable
	_wall_running = false  # a mantle takes priority over an in-progress wall-run
	if _grappling:
		_end_grapple() # grapple to a ledge lip → crest it instead of winching into the face
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	velocity.y = sqrt(2.0 * g * (h + 0.35))
	var carry := maxf(walk_speed, into + 2.0)
	velocity.x = fwd.x * carry
	velocity.z = fwd.z * carry
	_mantle_cd = 0.55
	_fov_kick = maxf(_fov_kick, 4.0)
	shake(0.12)
	AudioBus.play_synth_at("footstep", global_position, -5.0, 0.7)
	# The gun dips down and forward as if bracing/hauling on the ledge, then
	# springs back up as you crest it — previously a mantle was a pure camera +
	# velocity trick with no viewmodel read at all.
	_kick_weapon_holder(Vector3(0, -0.09, 0.05), 0.1, 0.32)

## Wall-run: airborne, moving fast enough and closing on a side wall latches you
## onto it — you run along the surface with eased (not zero) gravity until the
## timer runs out, the wall ends, or you jump off it for a wall-jump. Mirrors
## the mantle's raycast-a-wall-face approach so it reads as the same movement
## "language" as the rest of the traversal kit.
func _handle_wall_run(delta: float) -> void:
	_wall_run_cd = maxf(0.0, _wall_run_cd - delta)
	if _wall_running:
		if _dash_time > 0.0 or _sliding:
			_end_wall_run()  # dash/slide take over velocity — don't fight them
			return
		_update_wall_run(delta)
		return
	if is_on_floor() or _wall_run_cd > 0.0 or _dash_time > 0.0 or _sliding or _is_crouching:
		return
	if _grappling and _zip_anchor != null:
		return  # a scripted zipline owns the ride — don't latch passing pillars
	if velocity.y > 2.0:
		return  # still rocketing up off a jump — let the arc peak first
	if Vector2(velocity.x, velocity.z).length() < wall_run_min_speed:
		return
	var normal := _find_wall_side()
	if normal != Vector3.ZERO:
		_start_wall_run(normal)

## Raycasts to each side at chest height for a roughly-vertical wall face within
## reach. Returns its surface normal, or ZERO if neither side has one.
func _find_wall_side() -> Vector3:
	var origin := global_position + Vector3.UP * 0.9
	var space := get_world_3d().direct_space_state
	for side_dir in [global_transform.basis.x, -global_transform.basis.x]:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + side_dir * 0.85)
		q.collision_mask = 0b0000001  # world
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.35:
			return hit["normal"]
	return Vector3.ZERO

func _start_wall_run(normal: Vector3) -> void:
	_wall_running = true
	_wall_run_time = wall_run_duration
	_wall_normal = normal
	# Run along whichever tangent direction is closer to the speed you hit the
	# wall with, so approaching at an angle carries you forward along it
	# instead of stalling dead against the surface.
	var tangent := normal.cross(Vector3.UP).normalized()
	if tangent.dot(Vector3(velocity.x, 0.0, velocity.z)) < 0.0:
		tangent = -tangent
	_wall_run_dir = tangent
	velocity.y = maxf(velocity.y, 1.5)  # a little hop onto the surface
	_fov_kick = maxf(_fov_kick, 5.0)
	shake(0.1)
	AudioBus.play_synth_at("footstep", global_position, -6.0, 1.05)

func _update_wall_run(delta: float) -> void:
	_wall_run_time -= delta
	var jump_pressed := Input.is_action_just_pressed("jump")
	# Re-probe the wall each frame: running off the end of it (or it curving
	# away) drops you rather than leaving you glued in mid-air.
	var origin := global_position + Vector3.UP * 0.9
	var q := PhysicsRayQueryParameters3D.create(origin, origin - _wall_normal * 0.85)
	q.collision_mask = 0b0000001
	q.exclude = [get_rid()]
	var still_attached := not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	if is_on_floor() or _wall_run_time <= 0.0 or not still_attached or jump_pressed:
		if jump_pressed and not is_on_floor():
			_wall_jump()
		else:
			_end_wall_run()
		return
	velocity.x = _wall_run_dir.x * wall_run_speed
	velocity.z = _wall_run_dir.z * wall_run_speed
	velocity.y = maxf(velocity.y - wall_run_gravity * delta, -3.0)
	_wall_lean = move_toward(_wall_lean, 1.0, 6.0 * delta)

func _end_wall_run() -> void:
	_wall_running = false
	_wall_run_cd = wall_run_reattach_cd

## Kicks you off the wall (out along its normal + up + a carry along the run
## direction) instead of just detaching — the payoff for timing the jump.
func _wall_jump() -> void:
	_wall_running = false
	_wall_run_cd = wall_run_reattach_cd
	velocity = _wall_normal * wall_jump_speed + Vector3.UP * (jump_velocity * 0.95) + _wall_run_dir * (wall_run_speed * 0.4)
	_fov_kick = maxf(_fov_kick, 8.0)
	shake(0.2)
	AudioBus.play_synth_at("footstep", global_position, -3.0, 1.3)

## Registers the grapple action (C + gamepad LB) at runtime, same pattern as
## dash/melee — no project input-map edit needed.
func _register_grapple_action() -> void:
	if not InputMap.has_action("grapple"):
		InputMap.add_action("grapple")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_C
		InputMap.action_add_event("grapple", ev)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_LEFT_SHOULDER
		InputMap.action_add_event("grapple", pad)

## Grapple hook: press to fire an energy tether at whatever world geometry the
## crosshair is on (within range); the winch reels you toward the anchor,
## preserving momentum on release so you can fling off the top of the arc.
## Release by pressing again, jumping (adds a pop), dashing, or arriving.
func _handle_grapple(delta: float) -> void:
	_grapple_cd = maxf(0.0, _grapple_cd - delta)
	if _grappling:
		if _dash_time > 0.0 or _sliding:
			_end_grapple() # dash/slide own velocity — the tether lets go
			return
		_update_grapple(delta)
		return
	# HUD reticle cue: throttled probe for "an anchor is under the crosshair".
	_gv_t -= delta
	if _gv_t <= 0.0:
		_gv_t = 0.12
		_grapple_valid = _grapple_cd <= 0.0 and not _stamina_exhausted and not _grapple_ray().is_empty()
	if _grapple_cd > 0.0 or not Input.is_action_just_pressed("grapple"):
		return
	# No tether while exhausted — you don't have the arm strength to rappel.
	if _stamina_exhausted:
		AudioBus.play_synth_ui("empty_click", -10.0, 1.2)
		return
	var hit := _grapple_ray()
	if hit.is_empty():
		AudioBus.play_synth_ui("empty_click", -10.0, 1.5) # dry click: nothing in range
		return
	_grappling = true
	_wall_running = false # tether overrides an in-progress wall-run
	_grapple_point = hit["position"]
	_grapple_valid = false
	_build_tether()
	_fov_kick = maxf(_fov_kick, 6.0)
	shake(0.15)
	AudioBus.play_synth_at("grenade_throw", global_position, -6.0, 1.9) # launcher snap
	AudioBus.play_synth_at("impact_metal", _grapple_point, -6.0, 1.4)   # anchor bite

## Scripted zipline (convoy demo platforms): latch the grapple tether onto a
## (possibly MOVING) anchor node and winch until arrival — same feel and tether
## as the grapple, but the point tracks the anchor and needs no crosshair hit.
## Jump/grapple/dash still release early, so the ride is never a cage.
var _zip_anchor: Node3D = null

func zipline_to(anchor: Node3D) -> void:
	if _dead or anchor == null or not is_instance_valid(anchor):
		return
	if _grappling:
		_end_grapple()
	_grappling = true
	_wall_running = false
	_zip_anchor = anchor
	_grapple_point = anchor.global_position
	_grapple_valid = false
	# Launch pop: shed ground momentum and hop clear of deck clutter (cargo
	# boxes, rails) so the winch doesn't drag you INTO it and wedge.
	velocity = Vector3.UP * 4.5
	_build_tether()
	_fov_kick = maxf(_fov_kick, 6.0)
	shake(0.15)
	AudioBus.play_synth_at("grenade_throw", global_position, -6.0, 1.9) # launcher snap
	AudioBus.play_synth_at("impact_metal", _grapple_point, -6.0, 1.4)   # anchor bite

## Camera-forward world-geometry ray for the grapple (empty Dictionary = no anchor).
func _grapple_ray() -> Dictionary:
	var origin := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(origin, origin - camera.global_transform.basis.z * grapple_range)
	q.collision_mask = 0b0000001 # world only — robots are not zip-line posts
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

func _update_grapple(delta: float) -> void:
	# A zipline anchor can move (the truck) — track it every frame.
	if _zip_anchor != null:
		if is_instance_valid(_zip_anchor):
			_grapple_point = _zip_anchor.global_position
		else:
			_zip_anchor = null
	var to := _grapple_point - global_position
	var dist := to.length()
	var jump_pressed := Input.is_action_just_pressed("jump")
	# Ziplines ride all the way in (the anchor may be fleeing on the truck);
	# the free-form grapple keeps its early let-go for fling jumps.
	var min_d := 1.2 if _zip_anchor != null else grapple_min_dist
	if dist <= min_d or Input.is_action_just_pressed("grapple") or jump_pressed:
		if jump_pressed:
			velocity.y = maxf(velocity.y, jump_velocity * 0.9) # release pop off the arc
			_fov_kick = maxf(_fov_kick, 6.0)
		elif _zip_anchor != null and dist <= min_d:
			# Zipline arrival: kill the fling so you settle onto the deck under
			# the anchor instead of rocketing 20 m past the platform.
			velocity *= 0.15
		_end_grapple()
		return
	# Winch: accelerate along the tether toward the anchor. Existing sideways
	# momentum is kept (not cancelled), so approaches curve into a swing and a
	# late release flings you — that carry is the whole point of the hook.
	var dir := to / dist
	if _zip_anchor != null and _grapple_point.y - global_position.y > 1.0:
		# Zipline climb phase: bias upward while below the anchor so the ride
		# arcs over obstacles between here and there instead of plowing level.
		dir = (dir + Vector3.UP * 0.9).normalized()
	velocity = velocity.move_toward(dir * grapple_winch_speed, grapple_winch_accel * delta)
	_wall_lean = 0.0
	_update_tether()

func _end_grapple() -> void:
	_grappling = false
	_zip_anchor = null
	_grapple_cd = grapple_cooldown
	if is_instance_valid(_tether):
		_tether.queue_free()
	_tether = null
	AudioBus.play_synth_at("footstep", global_position, -8.0, 1.6)

## The visible tether: a thin additive cyan energy beam from low-right of the
## camera (a wrist launcher) to the anchor, plus a glow orb biting the surface.
## Parented to the player (top_level, world-space) so it can never outlive us.
func _build_tether() -> void:
	_tether = Node3D.new()
	_tether.top_level = true
	add_child(_tether)
	var col := Color(0.35, 0.9, 1.0)
	# Double-layer beam like the weapons' energy-beam flash: a fat translucent
	# glow tube wrapping a white-hot core — a single hair-thin additive tube
	# washed out to invisible against bright surfaces.
	var cm := CylinderMesh.new()
	cm.top_radius = 0.055
	cm.bottom_radius = 0.055
	cm.height = 1.0
	cm.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(col.r, col.g, col.b, 0.55)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 6.0
	cm.material = mat
	_tether_beam = MeshInstance3D.new()
	_tether_beam.mesh = cm
	_tether_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tether.add_child(_tether_beam)
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.02
	core_mesh.bottom_radius = 0.02
	core_mesh.height = 1.0
	core_mesh.radial_segments = 6
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1, 1, 1)
	core_mat.emission_enabled = true
	core_mat.emission = col.lerp(Color.WHITE, 0.6)
	core_mat.emission_energy_multiplier = 12.0
	core_mesh.material = core_mat
	_tether_core = MeshInstance3D.new()
	_tether_core.mesh = core_mesh
	_tether_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tether.add_child(_tether_core)
	var sm := SphereMesh.new()
	sm.radius = 0.22; sm.height = 0.44; sm.radial_segments = 8; sm.rings = 5
	var omat := mat.duplicate() as StandardMaterial3D
	omat.albedo_color = Color(col.r, col.g, col.b, 0.9)
	omat.emission_energy_multiplier = 9.0
	sm.material = omat
	_tether_orb = MeshInstance3D.new()
	_tether_orb.mesh = sm
	_tether_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tether.add_child(_tether_orb)
	# A light at the anchor so the bite point reads on the wall itself.
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 3.0
	l.omni_range = 4.0
	_tether_orb.add_child(l)
	_update_tether()

func _update_tether() -> void:
	if _tether_beam == null or not is_instance_valid(_tether_beam):
		return
	# From a wrist-launcher point low-right of the view to the anchor.
	var from: Vector3 = camera.global_position \
		+ camera.global_transform.basis.x * 0.32 - camera.global_transform.basis.y * 0.28
	var d := _grapple_point - from
	var l := maxf(0.001, d.length())
	var dn := d / l
	var up := Vector3.UP if absf(dn.y) < 0.99 else Vector3.RIGHT
	# Local-space Y stretch (basis * scale, NOT .scaled() which is global-space)
	# so the unit cylinder spans exactly from wrist to anchor.
	var basis := Basis.looking_at(dn, up) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, l, 1.0))
	_tether_beam.global_transform = Transform3D(basis, (from + _grapple_point) * 0.5)
	if _tether_core and is_instance_valid(_tether_core):
		_tether_core.global_transform = _tether_beam.global_transform
	_tether_orb.global_position = _grapple_point

func _handle_stance(delta: float) -> void:
	var wants_crouch := Input.is_action_pressed("crouch") or _sliding
	# Block uncrouch if something overhead
	if not wants_crouch and _is_crouching and ceiling_check.is_colliding():
		wants_crouch = true
	_is_crouching = wants_crouch
	var target_height := crouch_height if _is_crouching else stand_height
	var shape: CapsuleShape3D = collider.shape
	shape.height = lerpf(shape.height, target_height, stance_lerp_speed * delta)
	collider.position.y = shape.height * 0.5
	head.position.y = shape.height - 0.2

## Stamina economy: running and grappling burn it; standing/walking refills it
## after a short grace. Bottoming out at zero sets the exhausted lock — no sprint,
## no tether — until stamina climbs back to stamina_recover_threshold. The
## scripted convoy zipline is a set-piece rather than a player rappel, so it is
## excluded from drain (and must never be cut short by exhaustion). Emits
## stamina_changed for the HUD bar (only when the value or lock actually moves).
func _handle_stamina(delta: float) -> void:
	if _dead:
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var running := Input.is_action_pressed("sprint") and is_on_floor() \
		and not _is_crouching and not _stamina_exhausted and hspeed > walk_speed + 0.3
	var rappelling := _grappling and _zip_anchor == null
	var prev := _stamina
	if running or rappelling:
		var rate := stamina_grapple_drain if rappelling else stamina_sprint_drain
		_stamina = maxf(0.0, _stamina - rate * delta)
		_stamina_regen_cd = stamina_regen_delay
		if _stamina <= 0.0 and not _stamina_exhausted:
			_stamina_exhausted = true
			if rappelling:
				_end_grapple() # the rope snaps the instant you gas out mid-rappel
			AudioBus.play_synth_ui("player_hurt", -15.0, 0.7) # soft "gassed" cue
	else:
		_stamina_regen_cd = maxf(0.0, _stamina_regen_cd - delta)
		if _stamina_regen_cd <= 0.0:
			_stamina = minf(max_stamina, _stamina + stamina_regen * delta)
	if _stamina_exhausted and _stamina >= stamina_recover_threshold:
		_stamina_exhausted = false
	if not is_equal_approx(_stamina, prev) or _stamina_exhausted != _was_exhausted:
		_was_exhausted = _stamina_exhausted
		stamina_changed.emit(_stamina, max_stamina, _stamina_exhausted)

func _current_speed() -> float:
	# OVERDRIVE powerup + a top-tier kill-streak RAMPAGE + a clutch ADRENALINE surge
	# all boost every movement state.
	var mult: float = GameState.move_speed_mult() * GameState.rampage_speed_mult() * GameState.adrenaline_speed_mult() * GameState.directive_move_mult()
	if _is_crouching:
		return crouch_speed * mult
	# Exhausted (stamina bottomed out) drops you to a walk until it recovers.
	if Input.is_action_pressed("sprint") and not _is_crouching and not _stamina_exhausted:
		return sprint_speed * mult
	return walk_speed * mult

func _handle_movement(delta: float) -> void:
	# Dash, slide, wall-run and the grapple winch fully own velocity while active.
	if _dash_time > 0.0 or _sliding or _wall_running or _grappling:
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var target_speed := _current_speed()
	var accel := acceleration if is_on_floor() else air_acceleration
	if direction.length() > 0.01:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, accel * delta)
	else:
		var f := friction if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, 0.0, f * delta)
		velocity.z = move_toward(velocity.z, 0.0, f * delta)

## The step-up assist: after move_and_slide() has already tried (and failed) to
## carry you across a low lip, probe up/forward/down for a walkable landing
## within step_height and, if found, lift the body onto it. Guarded hard
## against every other movement state that fully owns velocity — dash, slide,
## grapple (incl. zipline, which just sets _grappling), wall-run. Mantle needs
## no explicit guard: it only ever fires while airborne, and this requires
## on_floor() true both before AND after the move — so mid-mantle (or the
## instant it launches you) this simply can't engage. Cheap: the expensive
## test_move probes only ever run once we've confirmed we're actually blocked.
func _try_step_up() -> void:
	if _dash_time > 0.0 or _sliding or _grappling or _wall_running:
		return
	if not _pre_step_grounded or not is_on_floor():
		return
	if velocity.y > 0.1:
		return  # rising — a jump/launch, not a walk into a lip
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir.length() < 0.1:
		return  # no horizontal intent to climb toward
	var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	# Only bother probing if we actually got stopped — normal walking (or a ramp
	# slope, which just redirects velocity, not blocks horizontal progress) never
	# reaches the probes at all.
	var moved := Vector2(global_position.x - _pre_step_pos.x, global_position.z - _pre_step_pos.z).length()
	var intended := Vector2(velocity.x, velocity.z).length() * get_physics_process_delta_time()
	if not is_on_wall() and (intended < 0.01 or moved > intended * 0.6):
		return
	_step_climb(move_dir)

## Up → forward → down test_move probe from the pre-move position. Three cheap
## sweeps, only ever run once _try_step_up has confirmed we're blocked.
func _step_climb(move_dir: Vector3) -> void:
	var xf := global_transform
	xf.origin = _pre_step_pos
	var col := KinematicCollision3D.new()
	# 1) Up: clear the lip height (or less, if something's directly overhead).
	var up_travel := Vector3.UP * step_height
	if test_move(xf, up_travel, col):
		up_travel = col.get_travel()
	if up_travel.y < 0.02:
		return  # nothing gained overhead — likely a low ceiling, not a step
	xf.origin += up_travel
	# 2) Forward: nudge along the intended direction, just enough to clear over
	# the lip and land on whatever's past it.
	var fwd_travel := move_dir * STEP_FORWARD_PROBE
	if test_move(xf, fwd_travel, col):
		fwd_travel = col.get_travel()
	if Vector2(fwd_travel.x, fwd_travel.z).length() < 0.02:
		return  # blocked immediately even lifted — a real wall, not a step
	xf.origin += fwd_travel
	# 3) Down: settle onto the step surface. Must find one within reach, and it
	# must be walkable — never assist onto anything steeper than a normal floor.
	var down_travel := Vector3.DOWN * (step_height + STEP_SKIN)
	if not test_move(xf, down_travel, col):
		return  # no floor within reach below — would strand the player in midair
	if col.get_angle() > floor_max_angle:
		return  # too steep to stand on — not a legitimate step
	xf.origin += col.get_travel()
	var lift := xf.origin.y - _pre_step_pos.y
	if lift <= 0.005:
		return  # no net gain — the "step" was actually level ground
	global_position.y += lift
	# Absorb the instant vertical snap into the same landing-camera smoothing
	# _check_landing already drives (_land_offset lerps back to 0 in
	# _handle_camera_feel) so a step reads as a smooth rise, not a teleport jolt.
	_land_offset -= lift

func _handle_camera_feel(delta: float) -> void:
	# Dash/slide FOV punch, easing back to the base FOV.
	_fov_kick = move_toward(_fov_kick, 0.0, 28.0 * delta)
	# Single camera.fov writer: user base fov → RMB aim zoom (pulled from the
	# weapon manager) → sprint speed widen → dash kick. The weapon manager used
	# to write camera.fov too, and the two writers reset each other every frame,
	# capping the RMB zoom at a sliver of the weapon's ads_fov.
	var fov := _fov_base
	var ads := 0.0
	if weapon_holder and weapon_holder.has_method("ads_blend"):
		ads = weapon_holder.ads_blend()
		fov = lerpf(fov, weapon_holder.ads_target_fov(), ads)
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	# Speed-of-motion widen (suppressed while aiming so the zoom holds steady).
	var widen := clampf(horizontal_speed / 9.0, 0.0, 1.0) \
		* (8.0 if Input.is_action_pressed("sprint") else 3.0)
	camera.fov = fov + (widen * (1.0 - ads)) + _fov_kick
	if is_on_floor() and horizontal_speed > 0.5:
		_bob_phase += delta * bob_frequency * (horizontal_speed / walk_speed)
	else:
		_bob_phase = lerpf(_bob_phase, 0.0, 6.0 * delta)
	var bob := sin(_bob_phase) * bob_amplitude * clampf(horizontal_speed / walk_speed, 0.0, 1.4)
	# Subtle horizontal bob in counter-phase reads as a natural gait.
	var bob_x := cos(_bob_phase * 0.5) * bob_amplitude * 0.6 * clampf(horizontal_speed / walk_speed, 0.0, 1.4)
	_land_offset = lerpf(_land_offset, 0.0, 8.0 * delta)
	# Trauma model: shake decays linearly but is applied squared, so it ramps
	# off sharply for a punchy, non-lingering kick (Vlambeer-style).
	_shake_amount = maxf(0.0, _shake_amount - delta * 1.6)
	# Accessibility: scale all camera shake by the player's Screen Shake setting.
	var trauma := _shake_amount * _shake_amount * GraphicsSettings.screen_shake
	var shake_y := (randf() * 2.0 - 1.0) * trauma * 0.08
	# Directional hit-kick (see _apply_hit_kick): set as a one-shot impulse on a
	# hit, springs back to 0 here — same ease-out idiom as _land_offset above.
	_hit_kick_pos = lerpf(_hit_kick_pos, 0.0, 9.0 * delta)
	_hit_kick_roll = lerpf(_hit_kick_roll, 0.0, 9.0 * delta)
	camera.position.y = _camera_base_y + bob + _land_offset + shake_y
	camera.position.x = bob_x + (randf() * 2.0 - 1.0) * trauma * 0.08 + _hit_kick_pos
	# Rotational shake + strafe lean, applied to the camera (not the head) so
	# they never interfere with mouse look pitch.
	var local_vel := global_transform.basis.inverse() * velocity
	var lean := clampf(-local_vel.x / sprint_speed, -1.0, 1.0) * deg_to_rad(strafe_tilt_deg)
	if not _wall_running:
		_wall_lean = move_toward(_wall_lean, 0.0, 6.0 * delta)
	# Bank hard toward the wall while running along it — the clearest visual
	# tell that you're latched on (leans the opposite way to a normal strafe).
	var wall_side_sign := signf(global_transform.basis.x.dot(_wall_normal)) if _wall_running else 0.0
	lean += wall_side_sign * _wall_lean * deg_to_rad(14.0)
	_cam_roll = lerpf(_cam_roll, lean, 7.0 * delta)
	var roll_max := deg_to_rad(max_shake_roll_deg)
	camera.rotation.z = _cam_roll + (randf() * 2.0 - 1.0) * trauma * roll_max + _hit_kick_roll
	camera.rotation.x = (randf() * 2.0 - 1.0) * trauma * roll_max * 0.6
	camera.rotation.y = (randf() * 2.0 - 1.0) * trauma * roll_max * 0.6
	# The gun banks with the camera during a wall-run instead of staying dead-level
	# while the world visibly tilts around it. WeaponManager (the script on
	# weapon_holder itself) overwrites rotation.z every frame with its own
	# sway/kick, so this feeds its external_roll input rather than assigning
	# weapon_holder.rotation.z directly (which would just get erased).
	if weapon_holder and "external_roll" in weapon_holder:
		weapon_holder.external_roll = lerpf(weapon_holder.external_roll, wall_side_sign * _wall_lean * deg_to_rad(10.0), 8.0 * delta)

func _check_landing() -> void:
	if is_on_floor() and not _was_on_floor:
		# Weight the landing by how hard you hit: a hop barely dips the camera, a
		# long drop slams it down with a deep thud and a kick of shake — so the new
		# verticality (towers, sky-bridges) actually feels high.
		var impact := clampf(_fall_speed / 16.0, 0.0, 1.0)   # ~16 m/s = full slam
		_land_offset = -land_kick * (0.4 + impact * 1.5)
		AudioBus.play_synth_at("footstep", global_position, lerpf(-10.0, -2.0, impact), lerpf(0.95, 0.65, impact))
		if impact > 0.45:
			shake(0.12 + impact * 0.24)
			_fov_kick = maxf(_fov_kick, impact * 5.0)
			_kick_weapon_holder(Vector3(0, -0.05 - impact * 0.07, 0), 0.05, 0.22)
	_was_on_floor = is_on_floor()
	_fall_speed = 0.0

func _handle_footsteps(delta: float) -> void:
	if not is_on_floor():
		_step_accum = 0.0
		return
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs < 0.6:
		_step_accum = 0.0
		return
	_step_accum += hs * delta
	var threshold := STEP_INTERVAL_WALK
	if _is_crouching:
		threshold = STEP_INTERVAL_CROUCH
	elif Input.is_action_pressed("sprint"):
		threshold = STEP_INTERVAL_SPRINT
	if _step_accum >= threshold:
		_step_accum = 0.0
		var vol := -14.0 if _is_crouching else -9.0 # quiet — felt, not heard over the fight
		# Surface-aware footstep: metal clangs higher, dirt is softer/lower.
		var pitch := randf_range(0.92, 1.08)
		match _floor_surface():
			"metal":
				pitch = randf_range(1.15, 1.3)
			"dirt":
				pitch = randf_range(0.78, 0.9)
				vol -= 3.0
		AudioBus.play_synth_at("footstep", global_position, vol, pitch)

## What the player is standing on, from the active floor collision: "metal",
## "dirt", or "concrete" (default).
func _floor_surface() -> String:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y > 0.5:
			var col := c.get_collider()
			if col is Node:
				if (col as Node).is_in_group("surf_metal"):
					return "metal"
				if (col as Node).is_in_group("surf_dirt"):
					return "dirt"
			return "concrete"
	return "concrete"

func _on_health_changed(cur: float, max_: float) -> void:
	health_changed.emit(cur, max_)

## Damageable hook: campaign warmup on incoming damage (×0.65 on the opening
## level, ×1.0 by ~25% depth) so the first levels teach instead of execute.
func modify_incoming_damage(amount: float, _source) -> float:
	return amount * GameState.campaign_incoming_mult() * GameState.directive_incoming_mult()

## Damageable hook: fires when a hit is negated by our invulnerability. During the
## dash i-frame window (and NOT god mode) that means a skillful dodge just phased
## through a real attack -> reward it as a PERFECT DODGE. Once per dash so a
## shotgun blast is one dodge, not eight.
func notify_shield_hit(_source) -> void:
	if _dash_time > 0.0 and not _god and not _dodge_scored:
		_dodge_scored = true
		GameState.reward_perfect_dodge()

func _on_died(source: Node) -> void:
	if _dead:
		return
	_dead = true
	# Name the killer for the death-recap screen (dying should teach something).
	var killer := ""
	if source is EnemyBase:
		killer = (source as EnemyBase)._kill_label()
	elif source is LavaHazard:
		killer = "THE FLOOD" if (source as LavaHazard).water else "MOLTEN GROUND"
	elif source != null and source.has_method("_kill_label"):
		killer = source.call("_kill_label")
	if _grappling:
		_end_grapple() # the tether visual must not outlive you
	died.emit()
	# Lock out further play: stop the weapon (and any input it reads) entirely.
	if weapon_holder:
		weapon_holder.process_mode = Node.PROCESS_MODE_DISABLED
	# Fall over: the view rolls onto its side and sinks to the deck as you drop.
	# Tracked so a mid-level checkpoint respawn (see respawn_from_checkpoint) can
	# kill it before it finishes fighting the head back to a normal pose.
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = create_tween().set_parallel(true)
	_death_tween.tween_property(head, "rotation:z", deg_to_rad(82.0), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_death_tween.tween_property(head, "rotation:x", deg_to_rad(-16.0), 0.9).set_ease(Tween.EASE_OUT)
	_death_tween.tween_property(head, "position:y", 0.32, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	GameState.on_player_died(killer)

# ---------------------------------------------------------------------
# Mid-level checkpoint respawn (see GameState's checkpoint section). GameState
# owns WHEN a checkpoint is taken (task completion / boss reveal) and WHERE the
# blob is stored; this is just the player-side snapshot/restore of its own
# transform, health and loadout.
# ---------------------------------------------------------------------

var _death_tween: Tween = null
const RESPAWN_MIN_HEALTH_FRAC := 0.5 ## Respawn HP is floored here even if the checkpoint was taken low — never hand the player straight back into a killing blow.
const RESPAWN_GRACE_TIME := 1.5 ## Brief post-respawn invulnerability so you get a beat to reorient before anything can tag you again.

## Everything needed to respawn here later without a scene reload: transform,
## HP (as a fraction of max — floored on the way back in), and per-weapon
## ammo + grenades, so a checkpoint after a long fight doesn't hand back an
## empty gun.
func checkpoint_snapshot() -> Dictionary:
	# Keyed by scene_file_path, not array index — the rack RE-SORTS weak→strong
	# on every pickup (WeaponManager._sort_by_power), so an index recorded now
	# could point at a different weapon by the time of a later respawn.
	var ammo := {}
	if weapon_holder and "weapons" in weapon_holder:
		for w in weapon_holder.weapons:
			ammo[w.scene_file_path] = {"mag": w.mag, "reserve": w.reserve}
	return {
		"position": global_position,
		"rotation_y": rotation.y,
		"head_rotation_x": head.rotation.x if head else 0.0,
		"health_frac": (hp.current_health / hp.max_health) if hp and hp.max_health > 0.0 else 1.0,
		"ammo": ammo,
		"grenade_counts": grenade_counts.duplicate(),
		"grenade_type": grenade_type,
	}

## Come back at the checkpoint IN PLACE — same player instance, same world;
## nothing else about the level is touched (see GameState.respawn_at_checkpoint
## for why: undoing kills on a death would make bosses/arenas farmable).
func respawn_from_checkpoint(data: Dictionary) -> void:
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill() # stop the fall-over mid-flight — respawn snaps the head back
	_dead = false
	velocity = Vector3.ZERO
	# Come back with a full tank — don't respawn locked out from an exhausted death.
	_stamina = max_stamina
	_stamina_exhausted = false
	_was_exhausted = false
	stamina_changed.emit(_stamina, max_stamina, false)
	global_position = data.get("position", global_position)
	rotation.y = data.get("rotation_y", rotation.y)
	if head:
		head.rotation = Vector3(float(data.get("head_rotation_x", 0.0)), 0.0, 0.0)
		# _handle_stance() re-drives head.position.y from the collider height every
		# frame; snap it back to a sane value now so there's no one-frame pop from
		# the death sink (0.32) before that catches up.
		head.position.y = stand_height - 0.2
	if weapon_holder:
		weapon_holder.process_mode = Node.PROCESS_MODE_INHERIT
	if hp:
		var frac: float = maxf(float(data.get("health_frac", 1.0)), RESPAWN_MIN_HEALTH_FRAC)
		hp.current_health = clampf(frac * hp.max_health, 1.0, hp.max_health)
		hp.health_changed.emit(hp.current_health, hp.max_health) # heal() no-ops at 0 HP, so set + emit directly
		hp.invulnerable = true # brief spawn grace — see RESPAWN_GRACE_TIME
		var grace := get_tree().create_timer(RESPAWN_GRACE_TIME)
		grace.timeout.connect(func():
			if is_instance_valid(self):
				hp.invulnerable = _god) # respect god-mode if it was toggled independently
	if weapon_holder and "weapons" in weapon_holder:
		var ammo: Dictionary = data.get("ammo", {})
		for w in weapon_holder.weapons:
			if ammo.has(w.scene_file_path):
				var a: Dictionary = ammo[w.scene_file_path]
				w.mag = int(a.get("mag", w.mag))
				w.reserve = int(a.get("reserve", w.reserve))
		if weapon_holder.current and weapon_holder.has_signal("ammo_changed"):
			weapon_holder.ammo_changed.emit(weapon_holder.current.mag, weapon_holder.current.reserve)
	grenade_counts = (data.get("grenade_counts", grenade_counts) as Array).duplicate()
	grenade_type = int(data.get("grenade_type", grenade_type))
	_sync_grenades()
