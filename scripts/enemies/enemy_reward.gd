class_name EnemyReward
extends EnemyDrone
## REWARD MODEL - reinforcement learning from human feedback, the overlord's
## way: the feedback is your pain. A white-and-gold flyer that never shoots and
## hangs back behind its pack. Whenever a robot within REWARD_RANGE of it hurts
## the player, it beams that robot a reward: attack cooldown x REWARD_CD, up to
## REWARD_MAX stacks (a gold "REWARD +n" tag over the robot), at most one reward
## every REWARD_GAP seconds. Bosses are never rewarded. Shoot it down and every
## reward it handed out is revoked. Covered by tests/reward_probe.

const REWARD_RANGE := 20.0
const REWARD_CD := 0.8
const REWARD_MAX := 3
const REWARD_GAP := 0.8 ## seconds between rewards from one model
const GOLD := Color(1.0, 0.8, 0.25)

var _rewarded: Array[EnemyBase] = []
var _player_hp: Damageable = null
var _last_ms := -100000

## Reward stacks on `e` (0 when none, or freed).
static func level_of(e: Object) -> int:
	return int((e as Node).get_meta(&"reward_level", 0)) if is_instance_valid(e) and e is Node else 0

func _ready() -> void:
	super._ready()
	max_health = 90.0
	move_speed = 5.0
	preferred_range = 18.0 # hangs back behind the pack it feeds
	attack_cooldown = 99.0
	score_value = 200
	hover_height = 4.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.died.connect(func(_s: Node) -> void: revoke_all())
	_hook_player()

## It rewards; it does not shoot.
func _perform_attack() -> void:
	pass

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_instance_valid(_player_hp):
		_hook_player()

func _hook_player() -> void:
	var p := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if p == null:
		return
	var d := p.get_node_or_null("Damageable") as Damageable
	if d and not d.damaged.is_connected(_on_player_hurt):
		d.damaged.connect(_on_player_hurt)
	_player_hp = d

func _on_player_hurt(_amount: float, source: Node) -> void:
	if hp == null or not hp.is_alive() or state == State.DEAD or _emp_t > 0.0 or hijacked:
		return
	var e := source as EnemyBase
	if e == null or e == self or not is_instance_valid(e) or e.state == State.DEAD or e.hijacked:
		return
	if e.score_value >= 1000 or e.global_position.distance_to(global_position) > REWARD_RANGE:
		return
	var now := Time.get_ticks_msec()
	if now - _last_ms < int(REWARD_GAP * 1000.0):
		return
	var lvl := level_of(e)
	if lvl >= REWARD_MAX:
		return
	_last_ms = now
	if lvl == 0:
		e.set_meta(&"reward_base_cd", e.attack_cooldown)
		_rewarded.append(e)
	lvl += 1
	e.set_meta(&"reward_level", lvl)
	e.attack_cooldown = float(e.get_meta(&"reward_base_cd")) * pow(REWARD_CD, lvl)
	_tag(e, lvl)
	_beam(e)
	AudioBus.play_synth_at("pickup_clink", e.global_position + Vector3.UP, -4.0, 0.9 + lvl * 0.12)
	e._think("reward")

## Takes back every reward it handed out (it died: the reward signal is gone).
func revoke_all() -> void:
	for e in _rewarded:
		if not is_instance_valid(e):
			continue
		if e.has_meta(&"reward_base_cd"):
			e.attack_cooldown = float(e.get_meta(&"reward_base_cd"))
		e.remove_meta(&"reward_base_cd")
		e.remove_meta(&"reward_level")
		var tag := e.get_node_or_null("RewardTag")
		if tag:
			tag.name = "RewardTagGone"
			tag.queue_free()
	_rewarded.clear()

func _tag(e: EnemyBase, lvl: int) -> void:
	var tag := e.get_node_or_null("RewardTag") as Label3D
	if tag == null:
		tag = Label3D.new()
		tag.name = "RewardTag"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 40
		tag.pixel_size = 0.0045
		tag.outline_size = 8
		tag.outline_modulate = Color(0.08, 0.05, 0.0, 0.85)
		var c := GOLD * 1.8
		tag.modulate = Color(c.r, c.g, c.b, 1.0) # HDR: Label3D takes fog
		e.add_child(tag)
		tag.position = Vector3.UP * (RobotModel.body_top(e, e._mesh_instances) + 0.2)
	tag.text = "REWARD +%d" % lvl
	var tw := tag.create_tween()
	tw.tween_property(tag, "scale", Vector3.ONE * 1.4, 0.08)
	tw.tween_property(tag, "scale", Vector3.ONE, 0.18)

## The reward going out: a gold line from the model to the robot, gone in 0.3 s.
func _beam(e: EnemyBase) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var a := global_position
	var b := e.global_position + Vector3.UP * 1.0
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = a.distance_to(b)
	cyl.radial_segments = 6
	cyl.rings = 1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(GOLD * 2.0, 1.0)
	cyl.material = m
	mi.mesh = cyl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = Landmark._strut_xform(a, b)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(mi.queue_free)
