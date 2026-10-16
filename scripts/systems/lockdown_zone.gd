class_name LockdownZone
# @lat: [[level-system#Lockdowns]]
extends Node3D
## A room that seals itself: an ARMED zone whose doors (FirewallBarrier with
## `starts_open`) stand dropped until the player steps inside its interior box
## (`half` extents about this node, which sits at floor level in the middle).
## Then, after SEAL_WARN seconds of klaxon, the doors rise and `waves` warp in
## one after another, each from its own EnemySpawners, inside the room. The
## doors only stop the player (robots walk through firewalls), so it is the
## player who is shut in with them.
##
## The doors hold until the last robot of the last wave is down, then drop:
## BONUS score and the room's safe pops its supplies at `reward` (local). A
## cleared zone never seals again. Two releases keep it from ever becoming a
## soft-lock: a player death drops the doors (the zone re-arms REARM seconds
## later, leftover robots stay), and `max_lock` seconds sealed drops them
## whatever is left. Built from an open building's `lockdown` def entry
## (level_builder `_build_open_building`). tests/lockdown_probe.

signal sealed
signal released(cleared: bool)

enum Phase { ARMED, SEALING, FIGHTING, CLEARED }

const SEAL_WARN := 1.0
const WAVE_GAP := 1.5
const REARM := 3.0
const BONUS := 400
const REWARDS: Array[String] = [
	"res://scenes/pickups/health_pack.tscn",
	"res://scenes/pickups/ammo_box.tscn",
	"res://scenes/pickups/overclock.tscn",
]

## Interior half extents about this node (x, height above floor / 2, z).
var half: Vector3 = Vector3(3.6, 3.0, 3.6)
var doors: Array[FirewallBarrier] = []
## Each wave: an Array of {type, count?, pos} with `pos` LOCAL to this node.
var waves: Array = []
var reward: Vector3 = Vector3.ZERO
var label: String = "SMART HOME SECURITY"
var max_lock: float = 90.0

var phase: Phase = Phase.ARMED
var wave: int = 0
var live: Array[EnemyBase] = []
## Robots of the current wave that have arrived so far.
var spawned_this_wave: int = 0
var _wave_size: int = 0
var _t: float = 0.0
var _locked_t: float = 0.0
var _safe_mat: StandardMaterial3D
var _safe_tag: Label3D

func _ready() -> void:
	add_to_group("lockdown")
	GameState.player_died.connect(_on_player_died)
	_build_safe()

## The lure: a smart safe at `reward`, its lamp red and tagged LOCKED until the
## house gives up. It is what makes walking in a choice.
func _build_safe() -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 1.0, 0.7)
	body.mesh = bm
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.2, 0.21, 0.24)
	steel.metallic = 0.8
	steel.roughness = 0.35
	body.material_override = steel
	body.position = reward + Vector3(0, 0.5, 0.9)
	add_child(body)
	_safe_mat = StandardMaterial3D.new()
	_safe_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_safe_mat.albedo_color = Color(1.0, 0.15, 0.1)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	lamp.mesh = sm
	lamp.material_override = _safe_mat
	lamp.position = body.position + Vector3(0.25, 0.3, -0.36)
	add_child(lamp)
	_safe_tag = Label3D.new()
	_safe_tag.text = "SMART SAFE: LOCKED"
	_safe_tag.font_size = 48
	_safe_tag.pixel_size = 0.004
	_safe_tag.modulate = Color(1.0, 0.35, 0.25)
	_safe_tag.outline_size = 8
	_safe_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_safe_tag.position = body.position + Vector3.UP * 0.9
	add_child(_safe_tag)

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D

## Player feet inside the interior box (the doorway itself does not count).
func player_inside() -> bool:
	var p := _player()
	if p == null:
		return false
	var l := p.global_position - global_position
	return absf(l.x) < half.x and absf(l.z) < half.z and l.y > -0.5 and l.y < half.y * 2.0

func _physics_process(delta: float) -> void:
	match phase:
		Phase.ARMED:
			_t = maxf(0.0, _t - delta) # REARM cool-down after a release
			if _t <= 0.0 and GameState.current_state == GameState.State.PLAYING and player_inside():
				phase = Phase.SEALING
				_t = 0.0
				GameState.skirmish_event.emit("LOCKDOWN", tr("%s: intruder contained. Doors sealed.") % tr(label))
				AudioBus.play_synth_at("eas_alert", global_position + Vector3.UP * 2.0, 0.0, 0.8)
		Phase.SEALING:
			_t += delta
			if _t >= SEAL_WARN:
				for d in doors:
					d.raise()
				phase = Phase.FIGHTING
				_locked_t = 0.0
				wave = -1
				sealed.emit()
				_next_wave()
		Phase.FIGHTING:
			_locked_t += delta
			if _locked_t >= max_lock:
				GameState.skirmish_event.emit("LOCKDOWN TIMEOUT", "Security lost the feed. The doors are open.")
				release(false)
				return
			live = live.filter(func(r: EnemyBase) -> bool:
				return is_instance_valid(r) and r.state != EnemyBase.State.DEAD and r.hp != null and r.hp.is_alive())
			if spawned_this_wave >= _wave_size and live.is_empty():
				_t += delta
				if _t >= WAVE_GAP:
					_next_wave()

func _next_wave() -> void:
	wave += 1
	_t = 0.0
	if wave >= waves.size():
		_clear()
		return
	spawned_this_wave = 0
	_wave_size = 0
	var delay := 0.3
	for spec in waves[wave]:
		var scene := LevelBuilder.enemy_scene(String(spec.get("type", "android")))
		if scene == null:
			continue
		var n: int = maxi(1, int(spec.get("count", 1)))
		var base: Vector3 = spec.get("pos", Vector3.ZERO)
		for j in n:
			var sp := EnemySpawner.new()
			sp.enemy_scene = scene
			sp.spawn_on_ready = true
			sp.spawn_delay = delay
			sp.position = base + Vector3(0.9 * (j % 2), 0.0, 0.9 * (j / 2)) - Vector3(0.45, 0.0, 0.45) * float(n > 1)
			sp.spawned.connect(_on_spawned)
			add_child(sp)
			_wave_size += 1
			delay += 0.35
	if wave > 0:
		GameState.wave_incoming.emit(tr("LOCKDOWN WAVE %d") % (wave + 1))

func _on_spawned(e: Node3D) -> void:
	spawned_this_wave += 1
	if e is EnemyBase and phase == Phase.FIGHTING:
		live.append(e)

func _clear() -> void:
	release(true)
	GameState.add_score(BONUS)
	GameState.skirmish_event.emit("LOCKDOWN LIFTED", tr("The house gave up. +%d, and its safe is open.") % BONUS)
	_safe_mat.albedo_color = Color(0.3, 1.0, 0.45)
	_safe_tag.text = "SMART SAFE: OPEN"
	_safe_tag.modulate = Color(0.4, 1.0, 0.5)
	var scene := get_tree().current_scene
	for i in REWARDS.size():
		var drop := (load(REWARDS[i]) as PackedScene).instantiate() as Node3D
		scene.add_child(drop)
		drop.global_position = to_global(reward + Vector3((i - 1) * 0.9, 0.4, 0.0))

## Drop the doors. `cleared` ends the zone for good; otherwise it re-arms.
func release(cleared: bool) -> void:
	if phase == Phase.CLEARED:
		return
	for d in doors:
		d.open()
	for c in get_children():
		if c is EnemySpawner:
			c.queue_free() # an arrival still in its telegraph never lands
	phase = Phase.CLEARED if cleared else Phase.ARMED
	_t = 0.0 if cleared else REARM
	released.emit(cleared)

func _on_player_died() -> void:
	if phase == Phase.SEALING or phase == Phase.FIGHTING:
		release(false)
