class_name BehaviourClone
# @lat: [[meta-systems#Behaviour Clone]]
extends StaticBody3D
## The BEHAVIOUR CLONE skirmish event: the overlord trains a model on the
## player and sends it after them. For TRAIN_TIME it stands where the player
## was when the event fired, forming out of red scanlines, while it records
## every physics frame of the player (position, eye, aim, whether a shot went
## off: GameState.stat_shots moved). Then for LIFE seconds it REPLAYS that
## recording TRAIN_TIME behind the player: it walks their exact path, looks
## where they looked, and fires a hitscan bolt (world + player, SHOT_DAMAGE,
## at most one per SHOT_GAP) along every recorded shot. A red laser shows
## where its aim points at every moment, so the answer is to not be where you
## were aiming 4 s ago: strafe off your own line, never stand still (a bolt
## from inside the player still hits). Robots are never hurt. HEALTH damage
## deletes it (BONUS, CLONE DELETED); otherwise it overfits and fades when
## LIFE runs out. Enemy collision layer (player fire finds it), not in the
## "enemy" group. tests/behaviour_clone_probe.

enum Phase { TRAIN, REPLAY, DONE }

const TRAIN_TIME := 4.0
const LIFE := 20.0
const HEALTH := 160.0
const BONUS := 250
const SHOT_DAMAGE := 5.0
const SHOT_GAP := 0.12
const SHOT_RANGE := 60.0
const LASER_RANGE := 40.0
const COLOR := Color(1.0, 0.18, 0.15)

var phase: Phase = Phase.TRAIN
var shots_fired := 0
var hits := 0
var _t := 0.0
var _frames: Array[Dictionary] = []
var _play := 0
var _last_shots := 0
var _gap := 0.0
var hp: Damageable
var _mat: ShaderMaterial
var _laser: MeshInstance3D
var _laser_mat: StandardMaterial3D
var _tag: Label3D

func _ready() -> void:
	add_to_group("behaviour_clone")
	collision_layer = 4
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	hp = Damageable.new()
	hp.name = "Damageable"
	hp.max_health = HEALTH
	add_child(hp)
	hp.died.connect(_on_died)
	_build()
	_last_shots = GameState.stat_shots
	var p := _player()
	if p:
		global_position = p.global_position

func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/hologram.gdshader")
	_mat.set_shader_parameter("holo_color", COLOR)
	_mat.set_shader_parameter("alpha", 0.1)
	_mat.set_shader_parameter("scan_count", 60.0)
	_limb(0.2, 0.75, Vector3(0, 1.18, 0), 0.0)
	for s in [-1.0, 1.0]:
		_limb(0.09, 0.9, Vector3(0.11 * s, 0.45, 0), 0.0)
	# Both arms forward, holding a gun that is not there.
	for s in [-1.0, 1.0]:
		var arm := _limb(0.07, 0.6, Vector3(0.16 * s, 1.35, -0.28), 0.0)
		arm.rotation.x = PI * 0.5
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.13
	hm.height = 0.26
	head.mesh = hm
	head.position.y = 1.68
	head.material_override = _mat
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)
	_tag = Label3D.new()
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.font_size = 40
	_tag.pixel_size = 0.004
	_tag.outline_size = 8
	_tag.modulate = COLOR
	_tag.position.y = 2.2
	add_child(_tag)
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_laser_mat.albedo_color = Color(COLOR, 0.8)
	_laser = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, 1.0)
	_laser.mesh = bm
	_laser.material_override = _laser_mat
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.top_level = true
	_laser.visible = false
	add_child(_laser)

func _limb(r: float, h: float, at: Vector3, roll: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	mi.mesh = cm
	mi.position = at
	mi.rotation.z = roll
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _player() -> Node3D:
	return GameState.primary_player() # the clone trains on player one

## One frame of the player: feet, eye, aim, and whether they fired.
func _record(p: Node3D) -> void:
	var cam := p.get_node_or_null("Head/Camera3D") as Node3D
	var eye := cam.global_position if cam else p.global_position + Vector3.UP * 1.6
	var dir := -(cam.global_transform.basis.z if cam else p.global_transform.basis.z)
	var shot := GameState.stat_shots != _last_shots
	_last_shots = GameState.stat_shots
	_frames.append({"pos": p.global_position, "eye": eye, "dir": dir.normalized(), "shot": shot})

func _physics_process(delta: float) -> void:
	if phase == Phase.DONE:
		return
	var p := _player()
	if p == null or not is_instance_valid(p):
		queue_free()
		return
	_record(p)
	_t += delta
	_gap = maxf(0.0, _gap - delta)
	if phase == Phase.TRAIN:
		var k := clampf(_t / TRAIN_TIME, 0.0, 1.0)
		_mat.set_shader_parameter("alpha", lerpf(0.1, 0.6, k))
		_tag.text = tr("TRAINING %d%%") % int(k * 100.0)
		if _t >= TRAIN_TIME:
			phase = Phase.REPLAY
			_t = 0.0
			_tag.text = tr("BEHAVIOUR CLONE")
			_laser.visible = true
			AudioBus.play_synth_at("overlord_glitch", global_position, -2.0, 0.6)
		return
	if _t >= LIFE:
		_end(false)
		return
	var f: Dictionary = _frames[_play]
	_play += 1
	global_position = f["pos"]
	var dir: Vector3 = f["dir"]
	rotation.y = atan2(-dir.x, -dir.z)
	var eye: Vector3 = f["eye"]
	var space := get_world_3d().direct_space_state
	var lq := PhysicsRayQueryParameters3D.create(eye, eye + dir * LASER_RANGE, 1)
	var lh := space.intersect_ray(lq)
	var lend: Vector3 = lh["position"] if not lh.is_empty() else eye + dir * LASER_RANGE
	_beam(_laser, eye, lend)
	if f["shot"] and _gap <= 0.0:
		_gap = SHOT_GAP
		_fire(eye, dir)

func _fire(eye: Vector3, dir: Vector3) -> void:
	shots_fired += 1
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * SHOT_RANGE, 0b0000011)
	q.hit_from_inside = true # standing where you stood is standing in the shot
	q.exclude = [get_rid()]
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = h["position"] if not h.is_empty() else eye + dir * SHOT_RANGE
	if not h.is_empty() and (h["collider"] as Node).is_in_group("player"):
		var d := (h["collider"] as Node).get_node_or_null("Damageable") as Damageable
		if d:
			hits += 1
			d.apply_damage(SHOT_DAMAGE, self, false, eye)
	_tracer(eye, end)
	AudioBus.play_synth_at("drone_shot", eye, -8.0, 1.3)

func _beam(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	if a.distance_to(b) < 0.01:
		return # a point-blank hit (from inside the player) has no beam to draw
	var len := a.distance_to(b)
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(b - a, up), (a + b) * 0.5)
	mi.scale = Vector3(1, 1, len)

func _tracer(a: Vector3, b: Vector3) -> void:
	var parent := get_parent()
	if parent == null or a.distance_to(b) < 0.01:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, 1.0)
	mi.mesh = bm
	var m := _laser_mat.duplicate() as StandardMaterial3D
	m.albedo_color = Color(1.0, 0.5, 0.4, 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_beam(mi, a, b)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(mi.queue_free)

func _on_died(_source: Node) -> void:
	if phase == Phase.DONE:
		return
	GameState.add_score(BONUS)
	GameState.skirmish_event.emit("CLONE DELETED", tr("You beat your own model. +%d") % BONUS)
	_end(true)

func _end(killed: bool) -> void:
	phase = Phase.DONE
	collision_layer = 0
	_laser.visible = false
	var parent := get_parent()
	if parent:
		DeepfakeDecoy._burst(parent, global_position + Vector3.UP * 1.0)
	AudioBus.play_synth_at("overlord_glitch", global_position, -4.0 if killed else -10.0, 1.7)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.6, 0.05, 1.6), 0.15).set_trans(Tween.TRANS_EXPO)
	tw.tween_callback(queue_free)

## The death screen's "Taken down by" name and its tip key (player.gd reads it
## off any damage source that has it; hud.gd DEATH_TIPS).
func _kill_label() -> String:
	return "BEHAVIOUR CLONE"
