class_name HaulPayload
extends Area3D
# @lat: [[level-system#Haul Payload]]
## A "haul" task: a heavy model-weights core that has to be CARRIED to an uplink
## ring. Walk into it to shoulder it. While carrying, GameState.carrying holds
## the player to a heavy walk with no sprint, dash or grapple (player.gd reads
## the flag), and `drop_damage` worth of hits knocks it loose, tossed a few
## metres behind you so recovering it costs time under fire. Dying drops it
## where you fell. Carry it inside the ring at `deliver_pos` to complete the
## task. The core stays a child of the level the whole time: a drop is a move.

@export var task_id: String = "haul"
@export var deliver_pos: Vector3 = Vector3.ZERO ## the uplink ring, in the PARENT's space
@export var deliver_radius: float = 4.0
@export var drop_damage: float = 30.0
@export var accent: Color = Color(1.0, 0.75, 0.35)
var base_label: String = "Haul the weights to the uplink"

const TOSS := 2.5 ## how far behind the player a knocked-loose core lands

var carried: bool = false
var delivered: bool = false
var drops: int = 0
var _taken: float = 0.0
var _pickup_cd: float = 0.0
var _player: Node3D
var _core: Node3D
var _beam: MeshInstance3D
var _ring: Node3D
var _ring_mat: StandardMaterial3D
var _t: float = 0.0

func _ready() -> void:
	collision_layer = 64
	collision_mask = 2 # player
	add_to_group("objective")
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.3
	cs.shape = sh
	cs.position.y = 0.9
	add_child(cs)
	body_entered.connect(_on_body_entered)
	_build()
	GameState.player_died.connect(_on_player_died)

func _build() -> void:
	_core = Node3D.new()
	add_child(_core)
	var case_mat := StandardMaterial3D.new()
	case_mat.albedo_color = Color(0.08, 0.08, 0.1)
	case_mat.metallic = 0.85
	case_mat.roughness = 0.3
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.7, 0.6)
	body.mesh = bm
	body.material_override = case_mat
	body.position.y = 0.8
	_core.add_child(body)
	var band_mat := StandardMaterial3D.new()
	band_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band_mat.albedo_color = accent
	for y in [0.62, 0.8, 0.98]:
		var band := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.94, 0.05, 0.64)
		band.mesh = b
		band.material_override = band_mat
		band.position.y = y
		_core.add_child(band)
	# A beam skyward while it sits on the ground, so a dropped core is findable.
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.18
	cm.height = 14.0
	_beam.mesh = cm
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.35)
	_beam.material_override = beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position.y = 7.5
	_core.add_child(_beam)
	var glow := OmniLight3D.new()
	glow.light_color = accent
	glow.light_energy = 1.6
	glow.omni_range = 5.0
	glow.position.y = 1.2
	_core.add_child(glow)
	# The uplink ring: a sibling in the level, so it stays put while the core moves.
	_ring = Node3D.new()
	_ring.position = deliver_pos
	var torus := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = deliver_radius - 0.35
	tm.outer_radius = deliver_radius
	tm.rings = 48
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.albedo_color = accent.darkened(0.5)
	tm.material = _ring_mat
	torus.mesh = tm
	torus.position.y = 0.06
	torus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(torus)
	var rl := OmniLight3D.new()
	rl.light_color = accent
	rl.light_energy = 1.2
	rl.omni_range = deliver_radius * 2.0
	rl.position.y = 1.5
	_ring.add_child(rl)
	get_parent().add_child.call_deferred(_ring)

func _process(delta: float) -> void:
	_t += delta
	if delivered:
		return
	_pickup_cd = maxf(0.0, _pickup_cd - delta)
	if carried:
		if not is_instance_valid(_player):
			_release()
			return
		global_position = _player.global_position
		if _ring.is_inside_tree():
			var d := Vector2(global_position.x - _ring.global_position.x, global_position.z - _ring.global_position.z).length()
			if d <= deliver_radius:
				_deliver()
				return
		# The delivery ring pulses while the core is on your back.
		_ring_mat.albedo_color = accent.lerp(Color.WHITE, 0.25 + 0.25 * sin(_t * 6.0))
	else:
		_core.rotation.y += delta * 0.8
		_core.position.y = 0.08 * sin(_t * 2.0)

func _on_body_entered(body: Node) -> void:
	if carried or delivered or _pickup_cd > 0.0 or not body.is_in_group("player"):
		return
	var hp = body.get("hp")
	if hp is Damageable and not (hp as Damageable).is_alive():
		return
	carried = true
	GameState.carrying = true
	_player = body as Node3D
	_taken = 0.0
	_core.visible = false # on your back, out of the first-person view
	remove_from_group("objective")
	_ring.add_to_group("objective") # the HUD waypoint now points at the uplink
	if hp is Damageable and not (hp as Damageable).damaged.is_connected(_on_hurt):
		(hp as Damageable).damaged.connect(_on_hurt)
	GameState.relabel_task(task_id, "%s (%s)" % [tr(base_label), tr("carrying")])
	GameState.teach_once("haul", "HEAVY PAYLOAD: no sprint, dash or grapple while you carry it. Heavy hits knock it loose.")
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("pickup_health", global_position, -4.0, 0.7)

func _on_hurt(amount: float, _source: Node) -> void:
	if not carried:
		return
	_taken += amount
	if _taken >= drop_damage:
		var back := Vector3.BACK
		if is_instance_valid(_player):
			back = _player.global_transform.basis.z
			back.y = 0.0
			back = back.normalized() if back.length() > 0.01 else Vector3.BACK
		_drop(global_position + back * TOSS, "PAYLOAD DROPPED", "Hit too hard. Get the weights back.")

func _on_player_died() -> void:
	if carried:
		_drop(global_position, "PAYLOAD LOST", "The weights are where you fell.")

func _drop(at: Vector3, title: String, desc: String) -> void:
	_release()
	drops += 1
	global_position = _floor_at(at)
	_pickup_cd = 0.6
	_core.visible = true
	add_to_group("objective")
	_ring.remove_from_group("objective")
	_ring_mat.albedo_color = accent.darkened(0.5)
	GameState.relabel_task(task_id, "%s (%s)" % [tr(base_label), tr("dropped")])
	GameState.skirmish_event.emit(title, desc)
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("impact_metal", global_position, 0.0, 0.7)

func _deliver() -> void:
	_release()
	delivered = true
	global_position = _ring.global_position
	_core.visible = true
	_beam.visible = false
	_ring.remove_from_group("objective")
	_ring_mat.albedo_color = Color(0.4, 1.0, 0.5)
	GameState.relabel_task(task_id, base_label)
	GameState.complete_task(task_id)
	GameState.skirmish_event.emit("UPLINK", "The weights are out.")
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("victory", global_position, -3.0, 1.0)

func _release() -> void:
	carried = false
	GameState.carrying = false
	if is_instance_valid(_player):
		var hp = _player.get("hp")
		if hp is Damageable and (hp as Damageable).damaged.is_connected(_on_hurt):
			(hp as Damageable).damaged.disconnect(_on_hurt)
	_taken = 0.0

## Drop onto whatever floor is below (a deck, a ramp), else the ground plane.
func _floor_at(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 30.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else Vector3(p.x, 0.0, p.z)

func _exit_tree() -> void:
	if carried:
		GameState.carrying = false
