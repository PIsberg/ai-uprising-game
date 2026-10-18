# @lat: [[level-system#Reward Rewrite Consoles]]
class_name RewardRewriter
extends Area3D
## A REWARD REWRITE console (def key `rewriters`). Stand at it and it shows the
## local robots' reward function; press interact to cycle the line you will
## write, and stay on one line for UPLOAD_TIME to upload it. Every robot within
## RADIUS then optimises that line, literally, for REWRITE_TIME:
## - "shots": MAXIMIZE shots fired. It stands still and empties its gun into the sky.
## - "huddle": MINIMIZE distance to the nearest robot. The squad packs into one knot.
## - "kills": MAXIMIZE kill count. Robots read each other as targets
##   (EnemyBase.mislabel) and fight among themselves.
## Bosses ignore it. One use: the overlord patches the reward model after.
## Covered by tests/reward_rewrite_probe.

const UPLOAD_TIME := 2.5
const RADIUS := 26.0
const REWRITE_TIME := 12.0
const HUDDLE_REPLAN := 0.5
const COLOR := Color(0.35, 1.0, 0.75)
const PATCHED_COLOR := Color(1.0, 0.25, 0.2)
const OPTIONS := ["shots", "huddle", "kills"]
const LINES := {
	"shots": "reward := MAXIMIZE(shots_fired)",
	"huddle": "reward := MINIMIZE(dist_to_nearest_robot)",
	"kills": "reward := MAXIMIZE(kill_count)",
}

var used := false
var option: int = 0
var _inside := 0
var _t := 0.0
var _hacked: Array[EnemyBase] = []
var _hack_t := 0.0
var _replan_t := 0.0
var _screen: Label3D
var _glyph: Label3D
var _light: OmniLight3D
var _frame_mat: StandardMaterial3D

func _ready() -> void:
	collision_layer = 64
	collision_mask = 2 # player
	add_to_group("rewriter")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.4
	cyl.height = 2.4
	cs.shape = cyl
	cs.position.y = 1.2
	add_child(cs)
	body_entered.connect(func(b: Node) -> void:
			if b.is_in_group("player"):
				_inside += 1)
	body_exited.connect(func(b: Node) -> void:
			if b.is_in_group("player"):
				_inside = maxi(0, _inside - 1))
	_build_visual()

## The reward line currently selected.
func current() -> String:
	return OPTIONS[option]

func _physics_process(delta: float) -> void:
	_tick_hacked(delta)
	if used:
		return
	if _inside > 0:
		if Input.is_action_just_pressed("interact"):
			option = (option + 1) % OPTIONS.size()
			_t = 0.0 # a new line starts its upload from scratch
			AudioBus.play_synth_at("hit_tick", global_position + Vector3.UP, -4.0, 1.4)
		_t += delta
		GameState.teach_once("rewriter", GameState.MECHANIC_HINTS["rewriter"])
	else:
		_t = maxf(0.0, _t - delta * 0.8)
	var k := clampf(_t / UPLOAD_TIME, 0.0, 1.0)
	_screen.text = "> %s\n[%s%s]" % [LINES[current()], "#".repeat(int(round(k * 12.0))), ".".repeat(12 - int(round(k * 12.0)))]
	_frame_mat.emission_energy_multiplier = 1.6 + k * 3.0
	if _t >= UPLOAD_TIME:
		_upload()

func _upload() -> void:
	used = true
	var kind := current()
	_hacked.clear()
	for e in get_tree().get_nodes_in_group("enemy"):
		var r := e as EnemyBase
		if r == null or not is_instance_valid(r) or r.score_value >= 1000 or r.hijacked \
				or r.state == EnemyBase.State.DEAD or r.global_position.distance_to(global_position) > RADIUS:
			continue
		var took: bool = r.mislabel(REWRITE_TIME) if kind == "kills" else r.reward_hack_set(kind)
		if took:
			_hacked.append(r)
	_hack_t = REWRITE_TIME
	_replan_t = 0.0
	AudioBus.play_synth_at("overlord_glitch", global_position + Vector3.UP, 0.0, 1.2)
	_screen.text = "REWARD MODEL PATCHED v%d.%d" % [randi() % 9 + 3, randi() % 20]
	_screen.modulate = Color(PATCHED_COLOR * 1.6, 1.0)
	_glyph.text = "x"
	_glyph.modulate = Color(PATCHED_COLOR * 1.4, 1.0)
	_frame_mat.albedo_color = PATCHED_COLOR
	_frame_mat.emission = PATCHED_COLOR
	_frame_mat.emission_energy_multiplier = 0.8
	_light.light_color = PATCHED_COLOR
	_light.light_energy = 0.5
	var n := _hacked.size()
	match kind:
		"shots":
			GameState.skirmish_event.emit("REWARD REWRITTEN", tr("MAXIMIZE shots fired: %d robots empty their guns into the sky.") % n)
		"huddle":
			GameState.skirmish_event.emit("REWARD REWRITTEN", tr("MINIMIZE distance to the nearest robot: %d robots pack into one knot.") % n)
		_:
			GameState.skirmish_event.emit("REWARD REWRITTEN", tr("MAXIMIZE kill count: %d robots turn on each other.") % n)

## Count the rewrite down on every robot it took, and steer the huddle.
func _tick_hacked(delta: float) -> void:
	if _hacked.is_empty():
		return
	_hack_t -= delta
	for i in range(_hacked.size() - 1, -1, -1):
		if not is_instance_valid(_hacked[i]) or _hacked[i].state == EnemyBase.State.DEAD:
			_hacked.remove_at(i)
	if _hack_t <= 0.0:
		for r in _hacked:
			r.reward_hack_clear()
			r.clear_mislabel()
		_hacked.clear()
		return
	if current() == "kills":
		for r in _hacked:
			r.mislabeled_t = _hack_t # the console owns the clock (cleared above at 0)
	_replan_t -= delta
	if _replan_t <= 0.0 and current() == "huddle":
		_replan_t = HUDDLE_REPLAN
		var c := Vector3.ZERO
		for r in _hacked:
			c += r.global_position
		c /= float(_hacked.size())
		for r in _hacked:
			r.reward_goal = c

func _build_visual() -> void:
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.1, 0.13, 0.12)
	plastic.metallic = 0.65
	plastic.roughness = 0.4
	var pedestal := MeshInstance3D.new()
	var pm := BeveledBoxMesh.new()
	pm.size = Vector3(0.9, 1.0, 0.5)
	pm.bevel = 0.03
	pm.material = plastic
	pedestal.mesh = pm
	pedestal.position.y = 0.5
	add_child(pedestal)
	_frame_mat = StandardMaterial3D.new()
	_frame_mat.albedo_color = COLOR
	_frame_mat.emission_enabled = true
	_frame_mat.emission = COLOR
	_frame_mat.emission_energy_multiplier = 1.6
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.94, 0.05, 0.42)
	dm.material = _frame_mat
	deck.mesh = dm
	deck.position = Vector3(0, 1.03, 0.02)
	deck.rotation.x = deg_to_rad(-18.0)
	add_child(deck)
	_screen = Label3D.new()
	_screen.name = "RewardLine"
	_screen.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_screen.font_size = 36
	_screen.pixel_size = 0.004
	_screen.outline_size = 8
	_screen.outline_modulate = Color(0.0, 0.05, 0.03, 0.85)
	_screen.modulate = Color(COLOR * 1.6, 1.0) # HDR: Label3D takes fog
	_screen.position = Vector3(0, 1.85, 0)
	add_child(_screen)
	_glyph = Label3D.new()
	_glyph.name = "Glyph"
	_glyph.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glyph.text = "R(s)"
	_glyph.font_size = 120
	_glyph.pixel_size = 0.006
	_glyph.outline_size = 12
	_glyph.modulate = Color(COLOR * 1.8, 1.0)
	_glyph.position = Vector3(0, 2.55, 0)
	add_child(_glyph)
	var bob := _glyph.create_tween().set_loops()
	bob.tween_property(_glyph, "position:y", 2.7, 1.1).set_trans(Tween.TRANS_SINE)
	bob.tween_property(_glyph, "position:y", 2.55, 1.1).set_trans(Tween.TRANS_SINE)
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.light_energy = 1.4
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.6, 0.4)
	add_child(_light)
