class_name Player
extends CharacterBody3D

signal health_changed(current: float, max: float)
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

var _fall_speed: float = 0.0   ## downward speed at the last touchdown (weights the landing)

# Ledge mantling: pull up onto a ledge you're cresting instead of scraping down it.
@export_group("Mantle")
@export var mantle_min_h: float = 0.7  ## lowest ledge worth a mantle (below this you just step up)
@export var mantle_max_h: float = 1.7  ## highest ledge you can pull yourself onto
@export var mantle_reach: float = 0.95 ## how far ahead the ledge face can be
var _mantle_cd: float = 0.0

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
var _melee_cd: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_base_y = camera.position.y
	_apply_user_settings()
	_build_dof_overlay()
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
	if GameState.supply_grenades > 0:
		grenade_counts[GrenadeType.FRAG] += GameState.supply_grenades
	_sync_grenades()
	_apply_supply_ammo.call_deferred()  # after the WeaponManager has built the arsenal
	hp.health_changed.connect(_on_health_changed)
	hp.died.connect(_on_died)
	hp.damaged.connect(_on_hp_damaged)

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

func _on_hp_damaged(amount: float, _source: Node) -> void:
	# Every hit lands as a camera kick, scaled with the bite taken.
	shake(clampf(0.3 + amount * 0.025, 0.3, 0.95))
	GameState.register_damage_taken(amount) # feeds the end-of-level grade
	# A grunt/impact on getting hit — throttled so rapid fire doesn't stack into
	# a drone, and pitched down slightly the harder the hit.
	if _hurt_cd <= 0.0 and hp and hp.current_health > 0.0:
		_hurt_cd = 0.22
		var pitch := clampf(1.12 - amount * 0.012, 0.82, 1.12) + randf_range(-0.04, 0.04)
		AudioBus.play_synth_ui("player_hurt", -4.0, pitch)

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

# --- cheat: type "god" during play to toggle invincibility (testing aid) ---
const GOD_WORD := "god"
var _god: bool = false
var _cheat_buf := ""

func _input(event: InputEvent) -> void:
	# Cheat keyword buffer runs even while dead, so you can flip it on at any time.
	if event is InputEventKey and event.pressed and not event.echo:
		var u := (event as InputEventKey).unicode
		if u != 0:
			_cheat_buf = (_cheat_buf + char(u).to_lower()).right(GOD_WORD.length())
			if _cheat_buf == GOD_WORD:
				_cheat_buf = ""
				_toggle_god()
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
	_handle_camera_feel(delta)
	if not is_on_floor():
		_fall_speed = -velocity.y   # peak downward speed this fall (read on landing)
	move_and_slide()
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
		hp.invulnerable = true
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
		_grapple_valid = _grapple_cd <= 0.0 and not _grapple_ray().is_empty()
	if _grapple_cd > 0.0 or not Input.is_action_just_pressed("grapple"):
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

## Camera-forward world-geometry ray for the grapple (empty Dictionary = no anchor).
func _grapple_ray() -> Dictionary:
	var origin := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(origin, origin - camera.global_transform.basis.z * grapple_range)
	q.collision_mask = 0b0000001 # world only — robots are not zip-line posts
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

func _update_grapple(delta: float) -> void:
	var to := _grapple_point - global_position
	var dist := to.length()
	var jump_pressed := Input.is_action_just_pressed("jump")
	if dist <= grapple_min_dist or Input.is_action_just_pressed("grapple") or jump_pressed:
		if jump_pressed:
			velocity.y = maxf(velocity.y, jump_velocity * 0.9) # release pop off the arc
			_fov_kick = maxf(_fov_kick, 6.0)
		_end_grapple()
		return
	# Winch: accelerate along the tether toward the anchor. Existing sideways
	# momentum is kept (not cancelled), so approaches curve into a swing and a
	# late release flings you — that carry is the whole point of the hook.
	var dir := to / dist
	velocity = velocity.move_toward(dir * grapple_winch_speed, grapple_winch_accel * delta)
	_wall_lean = 0.0
	_update_tether()

func _end_grapple() -> void:
	_grappling = false
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

func _current_speed() -> float:
	# OVERDRIVE powerup boosts every movement state.
	var mult: float = GameState.move_speed_mult()
	if _is_crouching:
		return crouch_speed * mult
	if Input.is_action_pressed("sprint") and not _is_crouching:
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

func _handle_camera_feel(delta: float) -> void:
	# Dash/slide FOV punch, easing back to the base FOV.
	_fov_kick = move_toward(_fov_kick, 0.0, 28.0 * delta)
	camera.fov = _fov_base + _fov_kick
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
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
	camera.position.y = _camera_base_y + bob + _land_offset + shake_y
	camera.position.x = bob_x + (randf() * 2.0 - 1.0) * trauma * 0.08
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
	camera.rotation.z = _cam_roll + (randf() * 2.0 - 1.0) * trauma * roll_max
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

func _on_died(_source: Node) -> void:
	if _dead:
		return
	_dead = true
	if _grappling:
		_end_grapple() # the tether visual must not outlive you
	died.emit()
	# Lock out further play: stop the weapon (and any input it reads) entirely.
	if weapon_holder:
		weapon_holder.process_mode = Node.PROCESS_MODE_DISABLED
	# Fall over: the view rolls onto its side and sinks to the deck as you drop.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(head, "rotation:z", deg_to_rad(82.0), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(head, "rotation:x", deg_to_rad(-16.0), 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(head, "position:y", 0.32, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	GameState.on_player_died()
