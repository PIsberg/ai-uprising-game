# @lat: [[player#Neural Uplink]]
class_name NeuralUplink
extends Node
## NEURAL UPLINK: look at a robot you have HIJACKED (within REACH) and press
## interact to leave your body and ride it for RIDE_TIME seconds. You drive the
## chassis from a chase camera and fire it on the fire button: a gunner shoots
## at its own cadence, a brawler (EnemyBase.pilot_is_brawler) slams the ground
## in front of it, a flyer (EnemyBase.pilot_flies) climbs on jump and dives on
## crouch. Your body stays where you left it, frozen and still a target:
## BODY_BREAK damage to it snaps you back. However the ride ends (interact
## again, the clock, body damage, the chassis dying) the chassis burns out,
## credited to you. Escorted allies (AlignedEscort) are mission-critical and
## refuse the link. The player builds one of these as its "NeuralUplink" child.
## Covered by tests/neural_uplink_probe.

signal linked(robot: EnemyBase)
signal unlinked(reason: String) ## "exit", "time", "body", "lost" (chassis died) or "incompatible".

const REACH := 30.0
const RIDE_TIME := 20.0
const BODY_BREAK := 20.0 ## Damage to the vacated body that snaps the mind back.
const CAM_BACK := 4.2
const CAM_UP := 0.6
const CAM_PITCH := -0.12 ## Resting look-down so a chest-high target sits on the crosshair.
const ASSIST_DEG := 6.0 ## Third-person aim assist: a hostile this close to the ray is the aim point.
const SCAN_INTERVAL := 0.1

var player: Node3D = null
var robot: EnemyBase = null
var candidate: EnemyBase = null
var time_left: float = 0.0
var camera: Camera3D = null

var _yaw: float = 0.0
var _pitch: float = CAM_PITCH
var _fire_cd: float = 0.0
var _scan_t: float = 0.0
var _body_damage: float = 0.0
var _ride_age: float = 0.0
var _hud: CanvasLayer = null
var _label: Label = null
var _tint: ColorRect = null

func _ready() -> void:
	player = get_parent() as Node3D
	camera = Camera3D.new()
	camera.name = "UplinkCamera"
	camera.fov = 80.0
	add_child(camera)
	_hud = CanvasLayer.new()
	_hud.layer = 5
	_hud.visible = false
	add_child(_hud)
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.color = Color(0.2, 1.0, 0.45, 0.06)
	_hud.add_child(_tint)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(-260, 70)
	_label.size = Vector2(520, 60)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	_hud.add_child(_label)
	var hp: Node = player.get_node_or_null("Damageable") if player else null
	if hp:
		hp.damaged.connect(_on_body_damaged)
		hp.died.connect(_on_body_died)

func _input(event: InputEvent) -> void:
	if robot == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		var sens: float = float(player.get("mouse_sensitivity")) * float(player.get("_look_sens_mult"))
		_yaw -= m.relative.x * sens
		_pitch = clampf(_pitch - m.relative.y * sens * float(player.get("_look_y_sign")), -1.1, 0.7)

func _physics_process(delta: float) -> void:
	if robot == null:
		_scan(delta)
		# Read every frame (the scan is throttled): a tap lasts one frame.
		if candidate != null and _pin().just_pressed("interact"):
			begin(candidate)
		return
	if not is_instance_valid(robot) or robot.state == EnemyBase.State.DEAD or not robot.hp.is_alive():
		end("lost")
		return
	_ride_age += delta
	if _ride_age > 0.25 and robot.pilot_ticks == 0:
		end("incompatible") # this chassis's own loop never reached the hijack path
		return
	time_left -= delta
	if time_left <= 0.0:
		end("time")
		return
	if _pin().just_pressed("interact"):
		end("exit")
		return
	_pad_look(delta)
	var iv := _pin().vector("move_left", "move_right", "move_forward", "move_back")
	robot.pilot_move = Basis(Vector3.UP, _yaw) * Vector3(iv.x, 0.0, iv.y)
	robot.pilot_yaw = _yaw
	robot.pilot_lift = (1.0 if _pin().pressed("jump") else 0.0) - (1.0 if _pin().pressed("crouch") else 0.0)
	_place_camera()
	_fire_cd = maxf(0.0, _fire_cd - delta)
	if _fire_cd <= 0.0 and _pin().pressed("fire"):
		_fire_cd = robot.pilot_cooldown()
		robot.pilot_fire(_aim_point())
	_label.text = "%s · %s\n%.1f s  ·  CHASSIS %d%%" % [tr("NEURAL UPLINK"), robot.codex_key().to_upper(),
		time_left, int(100.0 * robot.hp.current_health / maxf(robot.hp.max_health, 1.0))]

## Ride `r` now. False (and nothing changes) when it cannot carry a mind.
func begin(r: EnemyBase) -> bool:
	if robot != null or not can_ride(r):
		return false
	robot = r
	candidate = null
	r.pilot = player
	r.pilot_ticks = 0
	r.pilot_yaw = r.rotation.y
	_yaw = r.rotation.y
	_pitch = CAM_PITCH
	time_left = RIDE_TIME
	_body_damage = 0.0
	_ride_age = 0.0
	_fire_cd = 0.0
	player.set("linked_out", true)
	_set_weapons(false)
	_place_camera()
	camera.make_current()
	_hud.visible = true
	AudioBus.play_synth_ui("overlord_glitch", -4.0, 0.8)
	linked.emit(r)
	return true

## Snap back to the body. The ridden chassis burns out on the way.
func end(reason: String) -> void:
	if robot == null:
		return
	var r := robot
	robot = null
	if is_instance_valid(r):
		r.release_pilot()
	player.set("linked_out", false)
	_set_weapons(true)
	var cam: Camera3D = player.get("camera")
	if cam:
		cam.make_current()
	_hud.visible = false
	AudioBus.play_synth_ui("tape_rewind", -8.0, 2.2)
	unlinked.emit(reason)

func can_ride(r: EnemyBase) -> bool:
	return r != null and is_instance_valid(r) and r.hijacked and r.pilot == null \
		and r.escort_goal == null and r.state != EnemyBase.State.DEAD \
		and r.hp != null and r.hp.is_alive()

func _on_body_died(_source: Node) -> void:
	end("body")

func _on_body_damaged(amount: float, _source: Node) -> void:
	if robot == null:
		return
	_body_damage += amount
	if _body_damage >= BODY_BREAK:
		end("body")

## Which hijacked robot the player's crosshair rests on (throttled).
func _scan(delta: float) -> void:
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = SCAN_INTERVAL
	candidate = null
	if player == null or bool(player.get("_dead")) or get_tree().get_first_node_in_group("hijacked") == null:
		return
	var cam: Camera3D = player.get("camera")
	if cam == null or not cam.is_inside_tree():
		return
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * REACH)
	q.collision_mask = 0b0000111 # world + player layer (hijacked robots sit on 2) + enemy
	q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var eb := hit.get("collider") as EnemyBase
	if can_ride(eb):
		candidate = eb
		GameState.teach_once("uplink", GameState.MECHANIC_HINTS["uplink"])

func _pad_look(delta: float) -> void:
	var dz: float = float(player.get("pad_look_deadzone"))
	var stick := _pin().look()
	var lx := stick.x
	var ly := stick.y
	lx = 0.0 if absf(lx) < dz else signf(lx) * pow(absf(lx), 1.5)
	ly = 0.0 if absf(ly) < dz else signf(ly) * pow(absf(ly), 1.5)
	var spd: float = float(player.get("pad_look_speed")) * float(player.get("_look_sens_mult")) * delta
	_yaw -= lx * spd
	_pitch = clampf(_pitch - ly * spd * float(player.get("_look_y_sign")), -1.1, 0.7)

## Chase camera behind and above the chassis, pulled in when a wall is in the way.
func _place_camera() -> void:
	var pivot := robot.global_position + Vector3.UP * (robot.eye.global_position.y - robot.global_position.y if robot.eye else 1.6)
	var rot := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	var want := pivot + rot * Vector3(0.0, CAM_UP, CAM_BACK)
	var q := PhysicsRayQueryParameters3D.create(pivot, want)
	q.collision_mask = 1
	var hit := robot.get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = want
	if not hit.is_empty():
		at = hit.position + (pivot - want).normalized() * 0.3
	camera.global_transform = Transform3D(rot, at)

## Where the crosshair points: a hostile within ASSIST_DEG of the camera ray
## (nearest to it), else whatever the ray hits.
func _aim_point() -> Vector3:
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var best: Vector3 = Vector3.INF
	var best_cos := cos(deg_to_rad(ASSIST_DEG))
	for e in get_tree().get_nodes_in_group("enemy"):
		var eb := e as EnemyBase
		if eb == null or eb == robot or not is_instance_valid(eb) or eb.hijacked \
				or eb.state == EnemyBase.State.DEAD or eb.hp == null or not eb.hp.is_alive():
			continue
		var chest := eb.global_position + Vector3.UP * 0.9
		var to := chest - from
		if to.length() > 90.0:
			continue
		var c := dir.dot(to.normalized())
		if c > best_cos:
			best_cos = c
			best = chest
	if best != Vector3.INF:
		return best
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 90.0)
	q.collision_mask = 0b0000101
	q.exclude = [robot.get_rid()]
	var hit := robot.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else from + dir * 90.0

func _set_weapons(on: bool) -> void:
	var wm: Node = player.get_node_or_null("Head/Camera3D/WeaponHolder")
	if wm:
		wm.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

## The owning player's input (co-op: player two's pad for player two).
func _pin() -> PlayerInput:
	var pi = player.get("input") if player else null
	return pi if pi is PlayerInput else PlayerInput.new()
