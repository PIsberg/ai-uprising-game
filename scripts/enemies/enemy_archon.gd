class_name EnemyArchon
extends EnemyBase
## ARCHON — the AGI brain that controls everything. A colossal digital brain
## suspended at the heart of the arena: two glowing holographic hemispheres laced
## with circuit-gyri, a pulsing consciousness core, and orbiting data rings,
## wrapped in an energy shield.
##
## The fight is a siege loop, not a duel. ARCHON cannot be touched while its
## shield holds — and the shield only holds while its spawned legions live. It
## tears open dimensional gates and vomits out robots of every kind; the player
## has to fight THROUGH that wave to wipe it out. With the last minion down the
## shield shatters, the core is laid bare, and ARCHON panics — raking the player
## with energy fire during the brief window it stays exposed. Then it slams the
## shield back up and spits out a fresh, nastier wave. Three phases keyed to
## health escalate the legions and shorten the exposure. Uses the HUD boss bar.
##
## Visuals are built procedurally in `_build_brain` (no brain mesh asset); the
## scene supplies only the body, collider, Eye/Muzzle markers and Damageable.

@export var boss_name: String = "ARCHON"   ## Shown on the HUD boss bar.
@export var hover_height: float = 4.6      ## Brain centre height above the floor.
@export var proj_speed: float = 36.0
@export var proj_damage: float = 12.0
@export var preview: bool = false ## Briefing/menu showcase: idle the shielded brain, skip boot/waves/HUD/AI.

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

## The legions ARCHON can manufacture, keyed like LevelDefs/LevelBuilder so the
## wave tables read naturally.
const MINION_SCENES := {
	"drone": preload("res://scenes/enemies/drone.tscn"),
	"android": preload("res://scenes/enemies/android.tscn"),
	"spider": preload("res://scenes/enemies/spider.tscn"),
	"seeker": preload("res://scenes/enemies/seeker.tscn"),
	"brute": preload("res://scenes/enemies/brute.tscn"),
	"mech": preload("res://scenes/enemies/mech.tscn"),
	"mender": preload("res://scenes/enemies/mender.tscn"),
	"skitter": preload("res://scenes/enemies/skitter.tscn"),
	"strider": preload("res://scenes/enemies/strider.tscn"),
}

## Wave roster per phase (1/2/3). Each phase pours out a bigger, meaner mix; from
## phase 2 on a MENDER rides along to repair the legion under your fire, and
## SKITTER swarms flood the floor to pin you while the heavies close in.
const WAVES := {
	1: ["drone", "skitter", "skitter", "android", "android", "skitter", "drone", "spider"],
	2: ["android", "skitter", "skitter", "spider", "strider", "seeker", "mender", "skitter", "drone", "skitter", "android", "brute", "spider"],
	3: ["brute", "skitter", "strider", "skitter", "spider", "mender", "seeker", "skitter", "mech", "skitter", "strider", "android", "seeker", "skitter", "drone", "spider", "android"],
}

## How long the core stays exposed (and ARCHON stays vulnerable) after a wave is
## cleared, before it re-shields and spawns the next one. Shrinks with phase.
const EXPOSE_WINDOW := {1: 7.0, 2: 5.5, 3: 4.0}

# Cyan = shielded / computing. Hot orange = exposed / overloading.
const COL_SHIELD := Color(0.35, 0.8, 1.0)
const COL_EXPOSED := Color(1.0, 0.45, 0.18)

enum Mode { BOOTING, SHIELDED, EXPOSED }
var _mode: int = Mode.BOOTING

var _minions: Array[Node] = []       ## Living legion this wave.
var _expose_timer: float = 0.0
var _wave_index: int = 0
var _t: float = 0.0
var _spawning: bool = false          ## A wave is mid-deployment (gates still opening).
var _wave_live: bool = false         ## At least one minion of this wave has entered the arena.

# Procedural brain parts (built in _build_brain).
var _bob: Node3D                     ## Holds the brain; bobbed without fighting the flinch on Rig.
var _shell_mat: StandardMaterial3D
var _gyri_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _shield_mat: Material
var _shield: MeshInstance3D
var _core_light: OmniLight3D
var _rings: Array[Node3D] = []

@onready var _rig: Node3D = $Rig


func _ready() -> void:
	add_to_group("shield_enemies")
	super._ready()
	max_health = 2600.0
	stagger_threshold = 1.0e9        # an AGI is never stunlocked
	move_speed = 0.0                 # it hangs dead-centre; legions do the legwork
	turn_speed = 1.2
	sight_range = 120.0
	sight_angle_deg = 360.0          # omniscient
	attack_range = 90.0
	preferred_range = 40.0
	attack_cooldown = 0.9
	score_value = 4000
	head_radius = 1.6
	flinch_knockback = 0.0           # immovable
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 5.0
	if eye == null:
		eye = get_node_or_null("Eye")

	_build_brain()

	if preview:
		# Briefing/menu showcase: just the idling, shielded brain — no boot
		# cinematic, no boss bar, no minion waves, no AI. _process still spins the
		# brain and pulses the core; SHIELDED never self-exposes (no live wave).
		_mode = Mode.SHIELDED
		_bob.scale = Vector3.ONE
		_shield.visible = true
		hp.invulnerable = true
		set_physics_process(false)
		return

	# Hold the AI until the boot-up cinematic finishes.
	_mode = Mode.BOOTING
	hp.invulnerable = true
	set_physics_process(false)
	_boot.call_deferred()


# ---------- procedural digital brain ----------

func _build_brain() -> void:
	# A bob node carries the whole brain so the idle float never collides with the
	# flinch nudge EnemyBase applies to $Rig itself.
	_bob = Node3D.new()
	_bob.position = Vector3(0, hover_height, 0)
	_rig.add_child(_bob)

	# Shared holographic shell: translucent, emissive, lit from within.
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shell_mat.albedo_color = Color(COL_SHIELD.r, COL_SHIELD.g, COL_SHIELD.b, 0.5)
	_shell_mat.emission_enabled = true
	_shell_mat.emission = COL_SHIELD
	_shell_mat.emission_energy_multiplier = 1.8
	_shell_mat.rim_enabled = true
	_shell_mat.rim = 1.0
	_shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Bright circuit-gyri tracing the folds.
	_gyri_mat = StandardMaterial3D.new()
	_gyri_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gyri_mat.albedo_color = COL_SHIELD
	_gyri_mat.emission_enabled = true
	_gyri_mat.emission = COL_SHIELD
	_gyri_mat.emission_energy_multiplier = 4.0

	# The two cerebral hemispheres, flattened spheres split by a fissure.
	for side in [-1.0, 1.0]:
		var lobe := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.5
		sm.height = 2.4
		sm.radial_segments = 24
		sm.rings = 16
		sm.material = _shell_mat
		lobe.mesh = sm
		lobe.position = Vector3(side * 0.85, 0.0, 0.0)
		lobe.scale = Vector3(1.0, 1.0, 1.35)   # fronto-occipital stretch
		lobe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bob.add_child(lobe)
		# Gyri: thin tori wrapping each lobe at staggered tilts read as folds.
		for i in 3:
			var fold := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 1.18 - i * 0.16
			tm.outer_radius = 1.30 - i * 0.16
			tm.rings = 20
			tm.ring_segments = 6
			tm.material = _gyri_mat
			fold.mesh = tm
			fold.position = lobe.position
			fold.rotation_degrees = Vector3(90.0, 0.0, 22.0 * (i + 1) * side)
			fold.scale = Vector3(1.0, 1.0, 1.3)
			fold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_bob.add_child(fold)

	# Consciousness core: a bright inner sphere pulsing between the lobes.
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = Color(0.85, 0.95, 1.0)
	_core_mat.emission_enabled = true
	_core_mat.emission = COL_SHIELD
	_core_mat.emission_energy_multiplier = 6.0
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.7
	cm.height = 1.4
	cm.material = _core_mat
	core.mesh = cm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bob.add_child(core)

	# Brain stem dropping toward the floor — where the legions pour from.
	var stem := MeshInstance3D.new()
	var stm := CylinderMesh.new()
	stm.top_radius = 0.45
	stm.bottom_radius = 0.18
	stm.height = 1.6
	stm.material = _shell_mat
	stem.mesh = stm
	stem.position = Vector3(0, -1.4, 0)
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bob.add_child(stem)

	# Orbiting data rings — the "digital" halo, each on its own tilt.
	for r in 3:
		var ring := MeshInstance3D.new()
		var rtm := TorusMesh.new()
		rtm.inner_radius = 2.8 + r * 0.35
		rtm.outer_radius = 2.95 + r * 0.35
		rtm.rings = 40
		rtm.ring_segments = 8
		rtm.material = _gyri_mat
		ring.mesh = rtm
		ring.rotation_degrees = Vector3(70.0 + r * 35.0, r * 40.0, r * 25.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bob.add_child(ring)
		_rings.append(ring)

	# Core light radiating from the brain.
	_core_light = OmniLight3D.new()
	_core_light.light_color = COL_SHIELD
	_core_light.light_energy = 3.5
	_core_light.omni_range = 14.0
	_core_light.shadow_enabled = false
	_bob.add_child(_core_light)

	# Energy shield bubble: additive, double-sided, rim-lit. Present while shielded.
	_shield = MeshInstance3D.new()
	_shield.name = "ShieldBubble"
	var shm := SphereMesh.new()
	shm.radius = 3.5
	shm.height = 7.0
	shm.radial_segments = 32
	shm.rings = 20
	_shield.mesh = shm
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bob.add_child(_shield)
	
	_apply_shield_material()

func _apply_shield_material() -> void:
	if _shield == null:
		return
	
	var use_shader := bool(GraphicsSettings.get("robot_triplanar_enabled"))
	if use_shader:
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://shaders/shield.gdshader")
		sm.set_shader_parameter("shield_color", COL_SHIELD)
		sm.set_shader_parameter("pattern_scale", 12.0)
		sm.set_shader_parameter("fresnel_power", 2.2)
		sm.set_shader_parameter("grid_intensity", 0.45)
		_shield_mat = sm
		_shield.material_override = sm
	else:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(COL_SHIELD.r, COL_SHIELD.g, COL_SHIELD.b, 0.18)
		mat.emission_enabled = true
		mat.emission = COL_SHIELD
		mat.emission_energy_multiplier = 1.2
		_shield_mat = mat
		_shield.material_override = mat

func update_shield_settings() -> void:
	_apply_shield_material()
	_set_color(COL_EXPOSED if _mode == Mode.EXPOSED else COL_SHIELD)

var _next_ripple_idx := 0

func notify_shield_hit(source: Node) -> void:
	if _mode != Mode.SHIELDED or not (_shield_mat is ShaderMaterial):
		return
	if source is Node3D:
		var dir: Vector3 = ((source as Node3D).global_position - global_position).normalized()
		var local_pos: Vector3 = dir * 3.5
		var param_pos := "hit_pos_" + str(_next_ripple_idx)
		var param_time := "hit_time_" + str(_next_ripple_idx)
		_shield_mat.set_shader_parameter(param_pos, local_pos)
		_shield_mat.set_shader_parameter(param_time, Time.get_ticks_msec() / 1000.0)
		_next_ripple_idx = (_next_ripple_idx + 1) % 3
		
		if has_node("/root/AudioBus"):
			AudioBus.play_synth_at("impact_metal", global_position + dir * 3.5, -3.0, 1.25)

# ---------- boot-up entrance ----------

## ARCHON materialises: a column of light, the brain assembling from nothing with
## a glitchy boot, the core igniting and the shield snapping up before the first
## wave erupts.
func _boot() -> void:
	GameState.announce_boss(self)
	AudioBus.play_synth_ui("eas_alert", -6.0)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(0.7)

	# Boot column at the brain's position.
	AudioBus.play_synth_at("explosion", global_position, 4.0, 0.6)
	var pillar := BossPortal.new()
	pillar.radius = 4.0
	pillar.color = COL_SHIELD
	get_tree().current_scene.add_child(pillar)
	pillar.global_position = global_position + Vector3(0, hover_height, 0)
	if p:
		pillar.face(p.global_position)
	pillar.open(0.5)

	# The brain glitches into being.
	_bob.scale = Vector3.ZERO
	_shield.visible = false
	await get_tree().create_timer(0.35).timeout
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bob, "scale", Vector3.ONE, 0.8)
	AudioBus.play_synth_at("broadcast_blip", global_position, -2.0, 0.5)
	await get_tree().create_timer(0.9).timeout
	pillar.close(0.5)

	# Core ignites + shield snaps up.
	_shield.visible = true
	_shield.scale = Vector3.ZERO
	var stw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	stw.tween_property(_shield, "scale", Vector3.ONE, 0.4)
	AudioBus.play_synth_at("drone_shot", global_position, 0.0, 0.6)
	await get_tree().create_timer(0.5).timeout

	_mode = Mode.SHIELDED
	set_physics_process(true)
	_start_wave()


# ---------- siege loop ----------

func _phase() -> int:
	if hp == null or hp.max_health <= 0.0:
		return 1
	var frac := hp.current_health / hp.max_health
	if frac <= 0.34:
		return 3
	elif frac <= 0.67:
		return 2
	return 1

## Tear gates and pour out a fresh legion. Shield stays up until they're cleared.
func _start_wave() -> void:
	_mode = Mode.SHIELDED
	hp.invulnerable = true
	_wave_index += 1
	_wave_live = false
	_spawning = true
	_set_color(COL_SHIELD)
	_speak("taunt", 0.6)
	var roster: Array = WAVES.get(_phase(), WAVES[1])
	_spawn_wave(roster)

func _spawn_wave(roster: Array) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		_spawning = false
		return
	var n := roster.size()
	for i in n:
		if state == State.DEAD or not is_inside_tree():
			_spawning = false
			return
		var ang := TAU * float(i) / float(maxi(n, 1)) + _t
		var ground := Vector3(
			global_position.x + cos(ang) * 9.0,
			0.0,
			global_position.z + sin(ang) * 9.0)
		_emit_minion(String(roster[i]), ground)
		await get_tree().create_timer(0.28).timeout
	_spawning = false

## Open a gate at a ground point and birth one robot from it.
func _emit_minion(type: String, ground: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ms: PackedScene = MINION_SCENES.get(type)
	if ms == null:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D

	var gate := BossPortal.new()
	gate.radius = 2.0
	gate.color = COL_EXPOSED
	scene.add_child(gate)
	gate.global_position = ground + Vector3(0, 1.6, 0)
	if p:
		gate.face(p.global_position)
	gate.open(0.35)
	AudioBus.play_synth_at("broadcast_blip", ground, -3.0, 1.1)

	await get_tree().create_timer(0.3).timeout
	if state == State.DEAD or not is_inside_tree():
		gate.close(0.4)
		return
	var e := ms.instantiate() as Node3D
	_apply_difficulty(e)
	Elite.maybe_apply(e)
	e.position = ground
	scene.add_child(e)
	_minions.append(e)
	_wave_live = true
	gate.close(0.5)

## Mirror EnemySpawner's pre-add difficulty scaling so manufactured minions match
## placed ones.
func _apply_difficulty(e: Node3D) -> void:
	if not (e is EnemyBase):
		return
	var cfg: Dictionary = GameState.difficulty_config()
	var eb := e as EnemyBase
	eb.max_health *= cfg.get("health_mult", 1.0)
	eb.attack_cooldown *= cfg.get("cooldown_mult", 1.0)
	eb.move_speed *= cfg.get("speed_mult", 1.0)

func _living_minions() -> int:
	var n := 0
	for m in _minions:
		if is_instance_valid(m) and m is EnemyBase and (m as EnemyBase).hp.is_alive():
			n += 1
	return n

## Wave cleared: shatter the shield and lay the core bare.
func _expose() -> void:
	_mode = Mode.EXPOSED
	hp.invulnerable = false
	_minions.clear()
	_expose_timer = EXPOSE_WINDOW.get(_phase(), 5.0)
	_set_color(COL_EXPOSED)
	_speak("hurt", 0.8)
	AudioBus.play_synth_at("explosion", global_position, 2.0, 0.5)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(0.5)
	# Shield shatters outward and vanishes.
	if _shield:
		var tw := create_tween()
		tw.tween_property(_shield, "scale", Vector3.ONE * 1.5, 0.25).set_ease(Tween.EASE_OUT)
		# ShaderMaterial has no albedo_color — fade its grid out instead.
		if _shield_mat is ShaderMaterial:
			tw.parallel().tween_method(
				func(v: float): _shield_mat.set_shader_parameter("grid_intensity", v),
				0.45, 0.0, 0.25)
		else:
			tw.parallel().tween_property(_shield_mat, "albedo_color:a", 0.0, 0.25)
		tw.tween_callback(func(): if is_instance_valid(_shield): _shield.visible = false)

## Window elapsed: re-arm the shield and unleash the next, nastier wave.
func _reshield() -> void:
	if _shield:
		_shield.visible = true
		_shield.scale = Vector3.ZERO
		if _shield_mat is ShaderMaterial:
			_shield_mat.set_shader_parameter("grid_intensity", 0.45)
		else:
			_shield_mat.albedo_color.a = 0.18
		var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_shield, "scale", Vector3.ONE, 0.35)
	AudioBus.play_synth_at("drone_shot", global_position, 0.0, 0.6)
	_start_wave()

func _set_color(c: Color) -> void:
	for mat in [_shell_mat, _gyri_mat, _core_mat]:
		if mat:
			mat.emission = c
	if _shield_mat:
		if _shield_mat is ShaderMaterial:
			_shield_mat.set_shader_parameter("shield_color", c)
		else:
			_shield_mat.emission = c
			_shield_mat.albedo_color = Color(c.r, c.g, c.b, _shield_mat.albedo_color.a)
	if _shell_mat:
		_shell_mat.albedo_color = Color(c.r, c.g, c.b, 0.5)
	if _gyri_mat:
		_gyri_mat.albedo_color = c
	if _core_light:
		_core_light.light_color = c


# ---------- per-frame ----------

func _apply_gravity(_delta: float) -> void:
	pass  # it floats

func _move_toward(_dest: Vector3, _delta: float) -> void:
	pass  # dead-centre; never relocates

func _face_target(_delta: float) -> void:
	pass  # omnidirectional; the rig spins on its own

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	_t += delta
	# Idle float + slow spin + ring rotation.
	if _bob:
		_bob.position.y = hover_height + sin(_t * 1.3) * 0.18
		_bob.rotation.y += delta * 0.25
	for i in _rings.size():
		var ring := _rings[i]
		if is_instance_valid(ring):
			ring.rotate_object_local(Vector3(0, 0, 1), delta * (0.6 + i * 0.4))
	# Living pulse on the core, hotter when exposed.
	var hot := 1.0 if _mode == Mode.EXPOSED else 0.0
	if _core_mat:
		_core_mat.emission_energy_multiplier = 5.0 + sin(_t * 4.0) * 1.5 + hot * 5.0 + recoil * 6.0
	if _core_light:
		_core_light.light_energy = 3.0 + sin(_t * 3.0) * 0.8 + hot * 3.0 + float(_phase()) * 0.6

	match _mode:
		Mode.SHIELDED:
			# Once a fully-deployed legion is wiped, the shield can't hold. The
			# guards stop a premature exposure in the gap before the gates finish
			# pouring out the first robots.
			if _wave_live and not _spawning and _living_minions() == 0:
				_expose()
		Mode.EXPOSED:
			_expose_timer -= delta
			if _expose_timer <= 0.0 and state != State.DEAD:
				_reshield()


## When exposed, the cornered AGI rakes the player with energy fire from the core.
func _perform_attack() -> void:
	if _mode != Mode.EXPOSED or target == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	recoil = 1.0
	var phase := _phase()
	var shots := 2 + phase   # 3 / 4 / 5
	var origin: Vector3 = (_core_light.global_position if _core_light else global_position + Vector3(0, hover_height, 0))
	for i in shots:
		var proj := PROJECTILE.instantiate()
		scene.add_child(proj)
		(proj as Node3D).global_position = origin
		var dir := (target.global_position + Vector3.UP * 0.6 - origin).normalized()
		dir = scatter_aim(dir, 4.0 + float(i) * 1.5)
		if proj.has_method("launch"):
			proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	AudioBus.play_synth_at("drone_shot", origin, -2.0, 0.8)


# ---------- death ----------

func _on_died(source: Node) -> void:
	set_state(State.DEAD)
	GameState.add_kill(score_value, _kill_label())
	GameState.hit_stop(0.4, 0.5)
	set_physics_process(false)
	if _shield:
		_shield.visible = false
	_speak("die", 0.6)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(2.0)
	_death_cascade.call_deferred()

## The brain dies loud: a rolling storm of explosions, then it collapses inward.
func _death_cascade() -> void:
	var scene := get_tree().current_scene
	for i in 8:
		if not is_inside_tree():
			return
		var fx := EXPLOSION.instantiate()
		scene.add_child(fx)
		(fx as Node3D).global_position = global_position + Vector3(
			randf_range(-3, 3), hover_height + randf_range(-2, 2.5), randf_range(-3, 3))
		AudioBus.play_synth_at("explosion", global_position, 2.0, randf_range(0.5, 0.8))
		await get_tree().create_timer(0.16).timeout
	# Core implodes: the brain crushes down to a point and winks out.
	if is_instance_valid(_bob):
		var tw := create_tween()
		tw.tween_property(_bob, "scale", Vector3.ONE * 0.05, 0.4).set_ease(Tween.EASE_IN)
		await tw.finished
	queue_free()
