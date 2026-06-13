class_name Portal
extends Area3D
## The level exit, reimagined as a real portal to the next sector. It stays
## LOCKED (a roiling red barrier) until the level objective is met — every
## hostile that has spawned is destroyed — then UNLOCKS into a calm green gate.
## Walking into a locked portal pushes the player back out and posts the
## remaining-objective message to the HUD, so reaching it early is never silent.

signal completed

@export var objective_text: String = "Reach the extraction point"

const LOCK_COLOR := Color(1.0, 0.22, 0.16)
const OPEN_COLOR := Color(0.35, 1.0, 0.55)

var _completed: bool = false
var _locked: bool = true
var _seen_enemies: bool = false
var _check_timer: float = 0.0
var _t: float = 0.0
var _deny_flash: float = 0.0

var _visual: Node3D
var _ring: MeshInstance3D
var _ring2: MeshInstance3D
var _membrane: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _ring2_mat: StandardMaterial3D
var _mem_mat: StandardMaterial3D
var _beacon_mat: StandardMaterial3D
var _light: OmniLight3D
var _swirl: CPUParticles3D
var _swirl_mat: StandardMaterial3D

func _ready() -> void:
	collision_layer = 64
	collision_mask = 2 # player
	body_entered.connect(_on_body_entered)
	add_to_group("objective")
	_build_visual()
	_apply_color(LOCK_COLOR)

func _build_visual() -> void:
	# A monumental vertical gateway, raised so its arch sits on the ground and
	# towers over the player — visible from across the arena. The torus rings
	# stand upright (hole facing the player) inside a built metal frame.
	_build_frame()
	_visual = Node3D.new()
	_visual.rotation_degrees = Vector3(90, 0, 0)
	_visual.position = Vector3(0, 1.7, 0) # lift the ring centre to ~gate mid-height
	add_child(_visual)

	_ring_mat = _emissive(LOCK_COLOR, 5.0)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.5
	tm.outer_radius = 3.0
	tm.rings = 40
	tm.ring_segments = 18
	_ring.mesh = tm
	_ring.material_override = _ring_mat
	_visual.add_child(_ring)

	_ring2_mat = _emissive(LOCK_COLOR, 6.0)
	_ring2 = MeshInstance3D.new()
	var tm2 := TorusMesh.new()
	tm2.inner_radius = 1.95
	tm2.outer_radius = 2.2
	tm2.rings = 32
	tm2.ring_segments = 14
	_ring2.mesh = tm2
	_ring2.material_override = _ring2_mat
	_visual.add_child(_ring2)

	# Energy membrane filling the gate — a flat translucent disc that pulses.
	_mem_mat = _emissive(LOCK_COLOR, 2.2)
	_mem_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mem_mat.albedo_color.a = 0.4
	_membrane = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.4
	cyl.bottom_radius = 2.4
	cyl.height = 0.08
	cyl.radial_segments = 40
	_membrane.mesh = cyl
	_membrane.material_override = _mem_mat
	_visual.add_child(_membrane)

	# A vortex of sparks spiralling into the gate.
	_swirl = CPUParticles3D.new()
	_swirl.amount = 48
	_swirl.lifetime = 1.3
	_swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_swirl.emission_ring_radius = 2.7
	_swirl.emission_ring_inner_radius = 2.2
	_swirl.emission_ring_height = 0.2
	_swirl.emission_ring_axis = Vector3(0, 0, 1)
	_swirl.direction = Vector3(0, 0, 0)
	_swirl.spread = 30.0
	_swirl.initial_velocity_min = 0.2
	_swirl.initial_velocity_max = 0.6
	_swirl.tangential_accel_min = 1.5
	_swirl.tangential_accel_max = 2.5
	_swirl.radial_accel_min = -1.2
	_swirl.radial_accel_max = -0.6
	_swirl.gravity = Vector3.ZERO
	_swirl.scale_amount_min = 0.4
	_swirl.scale_amount_max = 0.9
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 6
	sm.rings = 3
	var pmat := _emissive(LOCK_COLOR, 5.0)
	sm.material = pmat
	_swirl.mesh = sm
	_swirl.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_swirl.position = Vector3(0, 1.7, 0)
	add_child(_swirl)
	_swirl_mat = pmat

	# Collision: a generous slab so the player can't slip past the big gate.
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(6.4, 6.4, 1.8)
	cs.position = Vector3(0, 1.7, 0)
	cs.shape = bs
	add_child(cs)

	_light = OmniLight3D.new()
	_light.light_color = LOCK_COLOR
	_light.light_energy = 5.0
	_light.omni_range = 20.0
	_light.position = Vector3(0, 2.2, 0)
	add_child(_light)

## A built metal gate frame around the energy ring: two side pylons on a base
## plinth, plus a sky-piercing beacon column so the exit is visible map-wide.
func _build_frame() -> void:
	var gy: float = -position.y # local y of world ground (portal sits ~1.5 up)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.11, 0.14)
	dark.metallic = 0.8
	dark.roughness = 0.35
	# Base plinth the gate stands on.
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(7.0, 0.5, 2.0)
	base.mesh = bm
	base.material_override = dark
	base.position = Vector3(0, gy + 0.25, 0)
	add_child(base)
	# Two side pylons flanking the ring.
	for sx in [-1.0, 1.0]:
		var pylon := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.7, 6.4, 1.2)
		pylon.mesh = pm
		pylon.material_override = dark
		pylon.position = Vector3(3.3 * sx, gy + 3.2, 0)
		add_child(pylon)
	# A vertical beacon column rising from the gate so it reads from afar.
	_beacon_mat = _emissive(LOCK_COLOR, 3.0)
	_beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_mat.albedo_color.a = 0.32
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.25
	cyl.bottom_radius = 0.5
	cyl.height = 26.0
	beam.mesh = cyl
	beam.material_override = _beacon_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(0, gy + 13.0, 0)
	add_child(beam)

func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

func _apply_color(c: Color) -> void:
	for m in [_ring_mat, _ring2_mat, _swirl_mat]:
		if m:
			m.albedo_color = Color(c.r, c.g, c.b, m.albedo_color.a)
			m.emission = c
	if _mem_mat:
		_mem_mat.albedo_color = Color(c.r, c.g, c.b, _mem_mat.albedo_color.a)
		_mem_mat.emission = c
	if _beacon_mat:
		_beacon_mat.albedo_color = Color(c.r, c.g, c.b, _beacon_mat.albedo_color.a)
		_beacon_mat.emission = c
	if _light:
		_light.light_color = c

func _process(delta: float) -> void:
	_t += delta
	if _ring:
		_ring.rotate_object_local(Vector3.UP, delta * 0.8)
	if _ring2:
		_ring2.rotate_object_local(Vector3.UP, -delta * 1.5)
	if _membrane:
		var pulse := 1.0 + 0.06 * sin(_t * 3.0)
		_membrane.scale = Vector3(pulse, 1.0, pulse)
		_mem_mat.albedo_color.a = (0.45 if _locked else 0.22) + 0.12 * sin(_t * 2.0)
	if _light:
		var base := 4.0 if _locked else 5.5
		_light.light_energy = base + 1.2 * sin(_t * (3.0 if _locked else 1.6))
	if _deny_flash > 0.0:
		_deny_flash = maxf(0.0, _deny_flash - delta * 2.5)
		if _light:
			_light.light_energy += _deny_flash * 8.0

	_check_timer += delta
	if _check_timer >= 0.35:
		_check_timer = 0.0
		_refresh_lock()

## Re-evaluates the level task checklist. The "kill_all" task is driven from the
## live enemy count (completed once hostiles have existed and none remain); other
## tasks (keycard, etc.) complete themselves. The gate opens when all are done.
func _refresh_lock() -> void:
	if _completed or not _locked:
		return
	if GameState.has_task("kill_all") and not GameState.is_task_done("kill_all"):
		var alive := _alive_enemies()
		if alive > 0:
			_seen_enemies = true
		elif _seen_enemies:
			GameState.complete_task("kill_all")
	if GameState.all_tasks_done():
		unlock()

func _alive_enemies() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as EnemyBase).hp != null and (e as EnemyBase).hp.is_alive():
			n += 1
	return n

func unlock() -> void:
	if not _locked:
		return
	_locked = false
	_apply_color(OPEN_COLOR)
	if _swirl:
		_swirl.amount = 72
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("pickup_health", global_position, -2.0, 0.9)
	# Triumphant flare on opening.
	if _visual:
		var tw := _visual.create_tween()
		tw.tween_property(_visual, "scale", Vector3.ONE * 1.25, 0.18)
		tw.tween_property(_visual, "scale", Vector3.ONE, 0.22)
	GameState.objective_unlocked.emit("✔ Objective complete — step into the portal")

func _on_body_entered(body: Node) -> void:
	if _completed:
		return
	if not body.is_in_group("player"):
		return
	if _locked:
		_deny(body)
		return
	complete()

## Reaching the gate early: shove the player back out and tell them why.
func _deny(body: Node) -> void:
	_deny_flash = 1.0
	if body is CharacterBody3D:
		var cb: CharacterBody3D = body
		var away: Vector3 = cb.global_position - global_position
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3.BACK
		cb.velocity += away.normalized() * 6.0 + Vector3.UP * 2.0
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("empty_click", global_position, -2.0, 0.7)
	# Spell out exactly what's left: live hostile count for the kill task, plus
	# the label of every other unfinished task (keycard, etc.).
	var parts: Array = []
	for t in GameState.level_tasks:
		if t["done"]:
			continue
		if t["id"] == "kill_all":
			var n := _alive_enemies()
			parts.append("1 hostile remains" if n == 1 else "%d hostiles remain" % n)
		else:
			parts.append(t["label"])
	var msg := "⚠ Portal sealed — objective incomplete"
	if not parts.is_empty():
		msg = "⚠ Portal sealed — " + "; ".join(PackedStringArray(parts))
	GameState.objective_blocked.emit(msg)

func complete() -> void:
	if _completed:
		return
	_completed = true
	completed.emit()
	GameState.on_level_complete()
