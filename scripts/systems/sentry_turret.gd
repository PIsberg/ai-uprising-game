class_name SentryTurret
# @lat: [[level-system#Sentry Turrets]]
extends StaticBody3D
## A site-defence gun on a post. It turns to the player within RANGE when it
## has line of sight, paints them with a red laser for LOCK_TIME (a rising
## beep), then fires a BURST of hitscan rounds, and rests BURST_GAP. A wall
## between you breaks the lock; so does getting under the gun: its barrel
## cannot depress far enough to hit anything within DEAD_ZONE of its post.
##
## Standing within HACK_RANGE for HACK_SECONDS (it ebbs at half speed when
## you step out) hacks it: the turret goes green and shoots robots instead
## (damage credited to the player) for ALLY_TIME, then burns out for good.
## An EMP grenade scrambles it for the burst's duration, and HEALTH worth of
## fire destroys it. It sits on the world and enemy collision layers, so it is
## cover, player fire hits it and an EMP burst finds it. Robots are never hit
## by a hostile turret. Def key `turrets` (level_builder `_build_turrets`).
## tests/sentry_turret_probe.

enum Phase { HOSTILE, ALLIED, BURNT, DEAD }

const RANGE := 24.0
const LOCK_TIME := 0.8
const BURST := 5
const SHOT_GAP := 0.12
const BURST_GAP := 1.5
const DAMAGE := 5.0          ## per round on the player
const ALLY_DAMAGE := 12.0    ## per round on a robot, while hacked
const DEAD_ZONE := 2.4       ## m from the post the barrel cannot reach
const HACK_RANGE := 2.2
const HACK_SECONDS := 2.5
const ALLY_TIME := 25.0
const HEALTH := 260.0
const TURN_RATE := 2.0       ## rad/s
const MUZZLE_H := 1.45
const HOSTILE_COLOR := Color(1.0, 0.2, 0.12)
const ALLY_COLOR := Color(0.3, 1.0, 0.45)
const TEACH_REACH := 26.0
const TEACH_TEXT := "SENTRY TURRET: break its line of sight, or get right under the gun, where it cannot aim, and stand by it to hack it."

var phase: Phase = Phase.HOSTILE
var hp: Damageable
var hack_t := 0.0
var ally_left := 0.0
var _emp_t := 0.0
var _lock_t := 0.0
var _shots_left := 0
var _shot_cd := 0.0
var _rest := 0.0
var _target: Node3D
var _head: Node3D
var _laser: MeshInstance3D
var _laser_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _glow: OmniLight3D

func _ready() -> void:
	collision_layer = 1 | 4
	collision_mask = 0
	add_to_group("hazard")
	add_to_group("sentry_turret")
	_build()
	hp = Damageable.new()
	hp.name = "Damageable"
	hp.max_health = HEALTH
	add_child(hp)
	hp.died.connect(_on_died)

func _build() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 1.7, 1.0)
	cs.shape = bs
	cs.position = Vector3.UP * 0.85
	add_child(cs)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.17, 0.18, 0.2)
	steel.metallic = 0.8
	steel.roughness = 0.4
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.5
	cm.height = 1.2
	base.mesh = cm
	base.material_override = steel
	base.position = Vector3.UP * 0.6
	add_child(base)
	_head = Node3D.new()
	_head.position = Vector3.UP * MUZZLE_H
	add_child(_head)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.45, 0.8)
	body.mesh = bm
	body.material_override = steel
	_head.add_child(body)
	for side in [-0.16, 0.16]:
		var barrel := MeshInstance3D.new()
		var bcm := CylinderMesh.new()
		bcm.top_radius = 0.05
		bcm.bottom_radius = 0.06
		bcm.height = 0.8
		barrel.mesh = bcm
		barrel.material_override = steel
		barrel.rotation.x = PI * 0.5
		barrel.position = Vector3(side, 0.0, -0.75)
		_head.add_child(barrel)
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_mat.albedo_color = HOSTILE_COLOR
	var eye := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.5, 0.14, 0.04)
	eye.mesh = em
	eye.material_override = _lamp_mat
	eye.position = Vector3(0, 0.08, -0.41)
	_head.add_child(eye)
	# A small state light (red hostile, green hacked): the head reads at range.
	_glow = OmniLight3D.new()
	_glow.light_color = HOSTILE_COLOR
	_glow.light_energy = 1.2
	_glow.omni_range = 3.0
	_glow.position = Vector3(0, 0.1, -0.6)
	_head.add_child(_glow)
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_laser_mat.albedo_color = Color(HOSTILE_COLOR, 0.8)
	_laser = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.025, 0.025, 1.0)
	_laser.mesh = lm
	_laser.material_override = _laser_mat
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.visible = false
	add_child(_laser)
	# The hack ring on the floor: where to stand.
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(HOSTILE_COLOR, 0.0)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = HACK_RANGE - 0.12
	tm.outer_radius = HACK_RANGE
	ring.mesh = tm
	ring.material_override = _ring_mat
	ring.position = Vector3.UP * 0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _muzzle() -> Vector3:
	return global_position + Vector3.UP * MUZZLE_H

## Clear shot from the muzzle to `aim` (world only, this body excluded).
func _clear_to(aim: Vector3, extra_exclude: Array = []) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_muzzle(), aim, 1)
	q.exclude = [get_rid()] + extra_exclude
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _aim_point(n: Node3D) -> Vector3:
	return n.global_position + Vector3.UP * 1.1

func emp_disable(duration: float) -> void:
	if phase == Phase.HOSTILE or phase == Phase.ALLIED:
		_emp_t = maxf(_emp_t, duration)
		_lock_t = 0.0
		_shots_left = 0
		_laser.visible = false

func _physics_process(delta: float) -> void:
	if phase == Phase.BURNT or phase == Phase.DEAD:
		return
	var p := _player()
	if phase == Phase.HOSTILE:
		_tick_hack(p, delta)
		if phase != Phase.HOSTILE:
			return
		if p and _flat(p.global_position, global_position) <= TEACH_REACH:
			GameState.teach_once("sentry_turret", TEACH_TEXT)
	else:
		ally_left -= delta
		if ally_left <= 0.0:
			_burn_out()
			return
	if _emp_t > 0.0:
		_emp_t -= delta
		return
	_shot_cd = maxf(0.0, _shot_cd - delta)
	_rest = maxf(0.0, _rest - delta)
	var tgt := _pick_target(p)
	if tgt == null:
		_target = null
		_lock_t = 0.0
		_shots_left = 0
		_laser.visible = false
		return
	if tgt != _target:
		_target = tgt
		_lock_t = 0.0
	var aim := _aim_point(tgt)
	_turn_toward(aim, delta)
	_show_laser(aim)
	if _shots_left > 0:
		if _shot_cd <= 0.0:
			_fire(tgt, aim)
		return
	if _rest > 0.0:
		return
	_lock_t += delta
	if _lock_t >= LOCK_TIME:
		_shots_left = BURST
		_shot_cd = 0.0
		_lock_t = 0.0

func _tick_hack(p: Node3D, delta: float) -> void:
	var near := p != null and _flat(p.global_position, global_position) <= HACK_RANGE \
		and absf(p.global_position.y - global_position.y) < 1.5
	if near:
		hack_t += delta
		if hack_t >= HACK_SECONDS:
			_hacked()
	else:
		hack_t = maxf(0.0, hack_t - delta * 0.5)
	_ring_mat.albedo_color = Color(HOSTILE_COLOR.lerp(ALLY_COLOR, hack_t / HACK_SECONDS), 0.35 + 0.5 * float(near))

func _hacked() -> void:
	phase = Phase.ALLIED
	ally_left = ALLY_TIME
	_target = null
	_lock_t = 0.0
	_shots_left = 0
	_rest = 0.4
	_lamp_mat.albedo_color = ALLY_COLOR
	_glow.light_color = ALLY_COLOR
	_laser_mat.albedo_color = Color(ALLY_COLOR, 0.8)
	_ring_mat.albedo_color = Color(ALLY_COLOR, 0.6)
	GameState.skirmish_event.emit("TURRET HACKED", "It works for you now. It will burn out soon.")
	AudioBus.play_synth_at("combo_up", global_position, 0.0, 1.2)

## The player (hostile, outside the dead zone) or the nearest robot (allied),
## in range with a clear shot.
func _pick_target(p: Node3D) -> Node3D:
	if phase == Phase.HOSTILE:
		if p == null or not p.is_inside_tree():
			return null
		var d := _flat(p.global_position, global_position)
		if d > RANGE or d < DEAD_ZONE:
			return null
		return p if _clear_to(_aim_point(p), [p.get_rid()] if p is CollisionObject3D else []) else null
	var best: Node3D = null
	var best_d := RANGE
	for e in get_tree().get_nodes_in_group("enemy"):
		var r := e as EnemyBase
		if r == null or r.hijacked or r.state == EnemyBase.State.DEAD or r.hp == null or not r.hp.is_alive():
			continue
		var d := _muzzle().distance_to(_aim_point(r))
		if d < best_d and _clear_to(_aim_point(r), [r.get_rid()]):
			best = r
			best_d = d
	return best

func _turn_toward(aim: Vector3, delta: float) -> void:
	var to := aim - _head.global_position
	var want := atan2(-to.x, -to.z)
	_head.rotation.y = rotate_toward(_head.rotation.y, want, TURN_RATE * delta * 3.0)
	_head.rotation.x = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.35, 0.6)

func _show_laser(aim: Vector3) -> void:
	var from := _muzzle()
	var len := from.distance_to(aim)
	_laser.visible = true
	_laser.global_transform = Transform3D(Basis.looking_at(aim - from, Vector3.UP), (from + aim) * 0.5)
	_laser.scale = Vector3(1.0, 1.0, len)
	# Brighter and redder as the lock completes: the warning ramps.
	var k := clampf(_lock_t / LOCK_TIME, 0.0, 1.0) if _shots_left == 0 else 1.0
	var base := HOSTILE_COLOR if phase == Phase.HOSTILE else ALLY_COLOR
	_laser_mat.albedo_color = Color(base.lerp(Color.WHITE, k * 0.5), 0.35 + 0.6 * k)

func _fire(tgt: Node3D, aim: Vector3) -> void:
	_shots_left -= 1
	_shot_cd = SHOT_GAP
	if _shots_left == 0:
		_rest = BURST_GAP
	AudioBus.play_synth_at("rifle_fire", _muzzle(), -4.0, 1.25)
	var d := tgt.get_node_or_null("Damageable") as Damageable
	if phase == Phase.HOSTILE:
		if d and d.is_alive():
			d.apply_damage(DAMAGE, self)
	elif tgt is EnemyBase and (tgt as EnemyBase).hp:
		(tgt as EnemyBase).hp.apply_damage(ALLY_DAMAGE, _player())

func _burn_out() -> void:
	phase = Phase.BURNT
	_laser.visible = false
	_lamp_mat.albedo_color = Color(0.15, 0.15, 0.15)
	_glow.visible = false
	_ring_mat.albedo_color = Color(0, 0, 0, 0)
	_head.rotation.x = -0.3 # slumps
	GameState.skirmish_event.emit("TURRET BURNT OUT", "The hack cooked its core.")
	AudioBus.play_synth_at("explosion", global_position, -10.0, 1.5)

func _on_died(_source: Node) -> void:
	phase = Phase.DEAD
	_laser.visible = false
	_lamp_mat.albedo_color = Color(0.1, 0.1, 0.1)
	_glow.visible = false
	_ring_mat.albedo_color = Color(0, 0, 0, 0)
	_head.rotation.x = -0.35
	AudioBus.play_synth_at("explosion", global_position, -4.0, 1.1)
