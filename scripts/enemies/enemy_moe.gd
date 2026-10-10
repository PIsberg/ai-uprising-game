class_name EnemyMoE
extends EnemyAndroid
## MIXTURE OF EXPERTS - an unarmed router chassis with four expert pods in
## orbit around its head. Every ROUTE_TIME seconds in a fight its gate picks one
## live expert (top-1 routing) and that expert decides how it fights; the shots
## come out of the active pod:
##   SNIPER  one heavy, tight shot on a long cooldown
##   SCATTER a wide six-round burst
##   SHIELD  slow, and the chassis takes SHIELD_MULT of every hit (a blue shell)
##   SPRINT  fast, flanking, short bursts
## A hologram over it shows the routing decision. Each pod is its own target
## (POD_HP, enemy layer): shoot one off and its expert is gone for good. Lose
## all four and the router collapses: it falls back to a plain burst and takes
## COLLAPSE_MULT from everything. Killing the body takes the pods with it.
## Covered by tests/moe_probe.

enum { SNIPER, SCATTER, SHIELD, SPRINT }
const EXPERTS := ["SNIPER", "SCATTER", "SHIELD", "SPRINT"]
const EXPERT_COLORS := [Color(1.0, 0.3, 0.25), Color(1.0, 0.72, 0.2), Color(0.35, 0.7, 1.0), Color(0.5, 1.0, 0.45)]
const ROUTE_TIME := 3.2
const POD_HP := 60.0
const SHIELD_MULT := 0.3
const COLLAPSE_MULT := 1.5
const ORBIT_R := 1.05
const ORBIT_H := 1.65 ## just over the dome: the base bot stands ~1.2 m
const STATUS_H := 2.3
const THINK_H := 2.68 ## the trace floats just over the routing hologram
const SHELL_SHADER := preload("res://shaders/overfit_shell.gdshader")

var active := -1 ## the routed expert, -1 when collapsed
var collapsed := false
var _pods: Array = [] ## by expert; null once shot off
var _pod_mats: Array[StandardMaterial3D] = []
var _orbit: Node3D
var _status: Label3D
var _shell: MeshInstance3D
var _route_t := ROUTE_TIME
var _base_speed := 0.0

func _ready() -> void:
	super._ready()
	max_health = 320.0
	move_speed = 4.6
	sight_range = 36.0
	attack_range = 28.0
	preferred_range = 14.0
	score_value = 380
	hp.max_health = max_health
	hp.current_health = max_health
	_base_speed = move_speed
	_think_h = THINK_H
	_build_pods()
	_build_status()
	_build_shell()
	route_now()
	hp.died.connect(func(_s: Node) -> void: _pods_die())

func pods() -> Array:
	return _pods.duplicate()

func is_alive_expert(k: int) -> bool:
	return k >= 0 and k < _pods.size() and is_instance_valid(_pods[k]) \
			and not (_pods[k] as Node).is_queued_for_deletion()

func status_text() -> String:
	return _status.text if is_instance_valid(_status) else ""

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if collapsed or state == State.DEAD or _emp_t > 0.0:
		return
	if state == State.ATTACK or state == State.CHASE:
		_route_t -= delta
		if _route_t <= 0.0:
			route_now()

func _process(delta: float) -> void:
	if is_instance_valid(_orbit):
		_orbit.rotation.y += delta * (3.2 if active == SPRINT else 1.5)
	# The active expert fires: the muzzle rides its pod.
	if muzzle and is_alive_expert(active):
		muzzle.global_position = (_pods[active] as Node3D).global_position

## The gate: one live expert, a different one when there is a choice.
func route_now() -> void:
	_route_t = ROUTE_TIME
	var live: Array[int] = []
	for k in EXPERTS.size():
		if is_alive_expert(k):
			live.append(k)
	if live.is_empty():
		_collapse()
		return
	if live.size() > 1:
		live.erase(active)
	route_to(live[randi() % live.size()])

func route_to(k: int) -> void:
	active = k
	move_speed = _base_speed
	flank_chance = 0.55
	match k:
		SNIPER:
			burst_count = 1
			hitscan_damage = 20.0
			burst_spread_deg = 0.5
			attack_cooldown = 2.2
		SCATTER:
			burst_count = 6
			hitscan_damage = 4.0
			burst_spread_deg = 8.0
			attack_cooldown = 1.8
		SHIELD:
			burst_count = 2
			hitscan_damage = 6.0
			burst_spread_deg = 3.0
			attack_cooldown = 2.4
			move_speed = _base_speed * 0.7
		SPRINT:
			burst_count = 3
			hitscan_damage = 6.0
			burst_spread_deg = 3.0
			attack_cooldown = 1.4
			move_speed = _base_speed * 1.8
			flank_chance = 0.9
	for i in _pod_mats.size():
		_pod_mats[i].emission_energy_multiplier = 7.0 if i == k else 0.8
	_shell.visible = k == SHIELD
	_status.text = "ROUTER > EXPERT %d: %s\ngate p=0.%02d" % [k + 1, EXPERTS[k], randi_range(71, 98)]
	var c: Color = EXPERT_COLORS[k] * 1.8
	_status.modulate = Color(c.r, c.g, c.b, 1.0)
	AudioBus.play_synth_at("broadcast_blip", global_position + Vector3.UP * ORBIT_H, -6.0, 0.8 + k * 0.15)

func modify_incoming_damage(amount: float, _source, _origin = null) -> float:
	if collapsed:
		return amount * COLLAPSE_MULT
	if active == SHIELD:
		return amount * SHIELD_MULT
	return amount

func _collapse() -> void:
	if collapsed:
		return
	collapsed = true
	active = -1
	move_speed = _base_speed
	burst_count = 4
	hitscan_damage = 6.0
	burst_spread_deg = 4.0
	attack_cooldown = 1.8
	_shell.visible = false
	_status.text = "ROUTER COLLAPSED\nfalling back to dense"
	_status.modulate = Color(2.0, 0.4, 0.35, 1.0)
	AudioBus.play_synth_at("overlord_glitch", global_position + Vector3.UP, -2.0, 0.85)
	_think("collapse")

func _on_pod_died(k: int) -> void:
	var pod: Node3D = _pods[k]
	if is_instance_valid(pod) and get_parent():
		KillFx._flash(get_parent(), pod.global_position, EXPERT_COLORS[k], 4.0, 0.3)
		AudioBus.play_synth_at("explosion", pod.global_position, -8.0, 1.7)
		# Collision off now; the shell pops (swells and blinks out) before it goes.
		pod.collision_layer = 0
		var tw := pod.create_tween()
		tw.tween_property(pod, "scale", Vector3.ONE * 1.8, 0.12)
		tw.tween_property(pod, "scale", Vector3.ONE * 0.05, 0.1)
		tw.tween_callback(pod.queue_free)
	_pods[k] = null
	if k == active or not is_alive_expert(active):
		route_now()

func _pods_die() -> void:
	for k in _pods.size():
		if is_instance_valid(_pods[k]):
			(_pods[k] as Node).queue_free()
			_pods[k] = null
	if is_instance_valid(_status):
		_status.hide()
	if is_instance_valid(_shell):
		_shell.hide()

func _build_pods() -> void:
	_orbit = Node3D.new()
	_orbit.name = "ExpertOrbit"
	_orbit.position.y = ORBIT_H
	add_child(_orbit)
	for k in EXPERTS.size():
		var pod := AnimatableBody3D.new()
		pod.name = "Expert%d" % k
		pod.collision_layer = 4 # the enemy layer: player fire finds it
		pod.collision_mask = 0
		pod.sync_to_physics = false
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.3
		cs.shape = sph
		pod.add_child(cs)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.26
		sm.height = 0.52
		sm.radial_segments = 12
		sm.rings = 6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = EXPERT_COLORS[k].darkened(0.4)
		mat.metallic = 0.5
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = EXPERT_COLORS[k]
		mat.emission_energy_multiplier = 0.8
		sm.material = mat
		mi.mesh = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pod.add_child(mi)
		var d := Damageable.new()
		d.name = "Damageable"
		d.max_health = POD_HP
		pod.add_child(d)
		d.died.connect(func(_s: Node) -> void: _on_pod_died(k))
		_orbit.add_child(pod)
		var a := TAU * k / float(EXPERTS.size())
		pod.position = Vector3(cos(a) * ORBIT_R, sin(a * 2.0) * 0.15, sin(a) * ORBIT_R)
		_pods.append(pod)
		_pod_mats.append(mat)

func _build_status() -> void:
	_status = Label3D.new()
	_status.name = "RouterStatus"
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.font_size = 36
	_status.pixel_size = 0.0045
	_status.outline_size = 8
	_status.outline_modulate = Color(0.0, 0.03, 0.05, 0.8)
	_status.position = Vector3.UP * STATUS_H
	add_child(_status)

func _build_shell() -> void:
	_shell = MeshInstance3D.new()
	_shell.name = "ShieldExpert"
	var sm := SphereMesh.new()
	sm.radius = 0.95
	sm.height = 1.75
	var mat := ShaderMaterial.new()
	mat.shader = SHELL_SHADER
	mat.set_shader_parameter("color", EXPERT_COLORS[SHIELD])
	sm.material = mat
	_shell.mesh = sm
	_shell.position.y = 0.8
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.visible = false
	add_child(_shell)
