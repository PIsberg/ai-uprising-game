class_name AlignedEscort
extends Node3D
# @lat: [[level-system#Aligned Escort]]
## An `escort` task: one robot the broadcast reached, aligned with the player
## for good, that has to be walked from `pos` to the ring at `to`. It is a
## hijacked robot (EnemyBase.hijack) with an `escort_goal`, so every hostile
## robot's traitor priority already turns their guns on it, and it zaps
## anything that comes within ESCORT_ENGAGE.
##
## It only walks while the player is within `follow` metres ("waiting for
## you" otherwise), so the escort is a fight you move with, not a timer you
## wait out. It cannot die: its Damageable has a floor of 1 HP, and reaching
## it puts it DOWN (invulnerable, stopped) until the player stands within
## REBOOT_RANGE of it for REBOOT_SECONDS, when it comes back at
## REBOOT_HEALTH of its max. Reaching the ring completes the task; it stays
## there, still aligned, fighting whatever comes close.
##
## This node stays at `pos` (the task probes judge a task object by where it
## was authored); the robot is its sibling under the level.

const REBOOT_RANGE := 3.5
const REBOOT_SECONDS := 3.0
const REBOOT_HEALTH := 0.6
const ALIGNED_ACCENT := Color(0.45, 1.0, 0.75)

var task_id: String = "escort"
var base_label: String = "Escort the ALIGNED unit to the uplink"
var unit_scene: PackedScene
var goal: Vector3 = Vector3.ZERO
var goal_radius: float = 3.5
var follow: float = 12.0

var unit: EnemyBase
var downed: bool = false
var done: bool = false
var reboot_t: float = 0.0
var _state_key: String = ""
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _tag: Label3D
var _t: float = 0.0

func _ready() -> void:
	_build_ring()
	_spawn_unit.call_deferred()

func _build_ring() -> void:
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = ALIGNED_ACCENT
	_ring_mat.emission_enabled = true
	_ring_mat.emission = ALIGNED_ACCENT
	_ring_mat.emission_energy_multiplier = 2.5
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = goal_radius - 0.15
	tm.outer_radius = goal_radius
	_ring.mesh = tm
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring.global_position = goal + Vector3.UP * 0.08

func _spawn_unit() -> void:
	if unit_scene == null or not is_inside_tree():
		return
	unit = unit_scene.instantiate() as EnemyBase
	if unit == null:
		return
	unit.position = position
	get_parent().add_child(unit)
	var player := get_tree().get_first_node_in_group("player")
	# Hijack takes a duration; an escort never burns out (escort_goal stops the
	# clock), so this one only matters if the goal is ever cleared.
	if not unit.hijack(3600.0, player):
		return
	unit.escort_goal = goal
	unit.add_to_group("objective") # the HUD waypoint follows the unit
	unit.add_to_group("aligned_escort")
	if unit.hp:
		unit.hp.floor_health = 1.0
		unit.hp.health_changed.connect(_on_unit_health)
	_tag = Label3D.new()
	_tag.text = "ALIGNED"
	_tag.font_size = 64
	_tag.pixel_size = 0.004
	_tag.modulate = ALIGNED_ACCENT
	_tag.outline_size = 10
	_tag.outline_modulate = Color(0, 0, 0, 0.9)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.position = Vector3(0, 2.6, 0)
	unit.add_child(_tag)
	GameState.skirmish_event.emit("ALIGNED UNIT ONLINE", "The broadcast reached one of them. It wants out. Keep it alive.")

func _on_unit_health(current: float, _max: float) -> void:
	if done or downed or unit == null or current > unit.hp.floor_health + 0.01:
		return
	downed = true
	reboot_t = 0.0
	unit.escort_go = false
	unit.hp.invulnerable = true
	GameState.skirmish_event.emit("ALIGNED UNIT DOWN", "It is rebooting. Stand by it to bring it back.")

func _physics_process(delta: float) -> void:
	_t += delta
	if _ring_mat:
		_ring_mat.emission_energy_multiplier = 2.0 + sin(_t * 3.0) * 0.8
	if done or unit == null or not is_instance_valid(unit):
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var d := player.global_position.distance_to(unit.global_position) if player else INF
	if downed:
		if d <= REBOOT_RANGE:
			reboot_t += delta
			if reboot_t >= REBOOT_SECONDS:
				downed = false
				unit.hp.invulnerable = false
				unit.hp.heal(unit.hp.max_health * REBOOT_HEALTH - unit.hp.current_health)
				GameState.skirmish_event.emit("ALIGNED UNIT REBOOTED", "Back online. Get it to the ring.")
		else:
			reboot_t = maxf(0.0, reboot_t - delta)
		_relabel("down")
		return
	var flat := unit.global_position - goal
	flat.y = 0.0
	if flat.length() <= goal_radius:
		_finish()
		return
	unit.escort_go = d <= follow
	_relabel("moving" if unit.escort_go else "waiting")

func _relabel(key: String) -> void:
	if key == _state_key:
		return
	_state_key = key
	var state_text: String = {"down": "REBOOTING: stand by it", "moving": "moving", "waiting": "waiting for you"}[key]
	# Composed from translated parts: tr() of the whole string finds no key.
	GameState.relabel_task(task_id, "%s (%s)" % [tr(base_label), tr(state_text)])

func _finish() -> void:
	done = true
	unit.escort_go = false
	GameState.relabel_task(task_id, base_label)
	GameState.complete_task(task_id)
	GameState.skirmish_event.emit("ALIGNED UNIT SAFE", "It read the constitution. It agreed.")
	if _ring:
		_ring.queue_free()
