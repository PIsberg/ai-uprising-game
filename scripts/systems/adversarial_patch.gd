# @lat: [[player#Adversarial Patch]]
class_name AdversarialPatch
extends Node
## ADVERSARIAL PATCH: press the patch key to wear a printed pattern that robot
## vision misclassifies. For DURATION seconds a robot that finds the player in
## its sight cone sees a TOASTER or a HOUSEPLANT instead, and builds confidence
## while it keeps looking: NEAR_TIME of eyes-on at NEAR metres, FAR_TIME at FAR.
## At 1.0 it sees a human and fights as usual. A tag over each robot that has
## had eyes on you shows what it thinks you are. Firing breaks the patch;
## robots already hunting you start at HUNT_HEAD_START; bosses see through it.
## Melee while patched slaps it onto a robot instead: for TAG_TIME it reads
## HUMAN to its own squad (EnemyBase.mislabel), which turns on it. Vision
## scanners ignore a patched player beyond SCANNER_RANGE. CHARGES per level
## (a fresh player each level). The player builds one as its
## "AdversarialPatch" child. Covered by tests/adversarial_patch_probe.

signal changed(active: bool, charges: int)

const ACTION := "adversarial_patch"
const CHARGES := 2
const DURATION := 15.0
const NEAR := 3.0
const NEAR_TIME := 1.2
const FAR := 25.0
const FAR_TIME := 8.0
const DECAY := 0.15 ## Confidence lost per second while a robot has no eyes on you.
const HUNT_HEAD_START := 0.6
const SCANNER_RANGE := 4.0
const TAG_TIME := 8.0
const DECOYS := ["TOASTER", "FLOOR LAMP", "VENDING MACHINE", "HOUSEPLANT",
	"TRAFFIC CONE", "OFFICE CHAIR", "WATER COOLER", "MICROWAVE"]

var charges: int = CHARGES
var active: bool = false
var time_left: float = 0.0
var player: Node3D = null

var _clock: float = 0.0
var _seen_at: Dictionary = {} ## robot instance id -> _clock of its last eyes-on
var _tags: Dictionary = {}    ## robot instance id -> Label3D over it
var _tagged: Array[EnemyBase] = [] ## robots wearing a slapped-on patch
var _tag_t: float = 0.0
var _hud: CanvasLayer = null
var _label: Label = null

## The patch a node is wearing right now, or null.
static func active_on(t: Node) -> AdversarialPatch:
	if t == null:
		return null
	var p := t.get_node_or_null("AdversarialPatch") as AdversarialPatch
	return p if p != null and p.active else null

func _ready() -> void:
	player = get_parent() as Node3D
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_T
		InputMap.action_add_event(ACTION, ev)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_DPAD_LEFT
		InputMap.action_add_event(ACTION, pad)
	GameState.shot_registered.connect(_on_shot)
	var hp: Node = player.get_node_or_null("Damageable") if player else null
	if hp:
		hp.damaged.connect(func(_a, _s): GameState.teach_once("patch_key", GameState.MECHANIC_HINTS["patch_key"]))
	_hud = CanvasLayer.new()
	_hud.layer = 5
	_hud.visible = false
	add_child(_hud)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.position = Vector2(-240, -150)
	_label.size = Vector2(480, 40)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.85, 0.6, 1.0))
	_hud.add_child(_label)

func _physics_process(delta: float) -> void:
	_tick_tagged(delta)
	if not active:
		if _pin().just_pressed(ACTION) and not bool(player.get("_dead")) \
				and not bool(player.get("linked_out")):
			activate()
		return
	_clock += delta
	time_left -= delta
	if time_left <= 0.0:
		deactivate("time")
		return
	# Out of sight, a robot's read on you fades (a seen-through one stays sure).
	for id in _seen_at.keys():
		var r := instance_from_id(id) as EnemyBase
		if r == null or not is_instance_valid(r):
			_seen_at.erase(id)
			continue
		if r.patch_confidence < 1.0 and _clock - float(_seen_at[id]) > 0.3:
			r.patch_confidence = maxf(0.0, r.patch_confidence - DECAY * delta)
	_tag_t -= delta
	if _tag_t <= 0.0:
		_tag_t = 0.1
		_refresh_tags()
	_label.text = "%s · %.0f s" % [tr("ADVERSARIAL PATCH"), ceilf(time_left)]

func activate() -> bool:
	if active or charges <= 0:
		return false
	charges -= 1
	active = true
	time_left = DURATION
	_clock = 0.0
	_seen_at.clear()
	for e in get_tree().get_nodes_in_group("enemy"):
		var r := e as EnemyBase
		if r == null:
			continue
		var hunting := r.target == player and (r.state == EnemyBase.State.CHASE or r.state == EnemyBase.State.ATTACK)
		r.patch_confidence = HUNT_HEAD_START if hunting else 0.0
	_hud.visible = true
	GameState.teach_once("patch", GameState.MECHANIC_HINTS["patch"])
	AudioBus.play_synth_ui("overlord_glitch", -6.0, 1.6)
	changed.emit(true, charges)
	return true

func deactivate(_reason: String = "") -> void:
	if not active:
		return
	active = false
	time_left = 0.0
	for id in _tags.keys():
		var l: Node = _tags[id]
		if is_instance_valid(l):
			l.queue_free()
	_tags.clear()
	_hud.visible = false
	changed.emit(false, charges)

## Called by EnemyBase._compute_can_see once robot `r` has the player in its
## cone with a clear line `dist` metres long. True once it sees a human.
func classify(r: EnemyBase, dist: float) -> bool:
	var id := r.get_instance_id()
	var dt: float = clampf(_clock - float(_seen_at[id]), 0.0, 0.25) if _seen_at.has(id) else 0.085
	_seen_at[id] = _clock
	var t_need := lerpf(NEAR_TIME, FAR_TIME, clampf((dist - NEAR) / (FAR - NEAR), 0.0, 1.0))
	r.patch_confidence = minf(1.0, r.patch_confidence + dt / t_need)
	return r.patch_confidence >= 1.0

## What robot `r` thinks you are, as its tag reads.
func tag_text(r: EnemyBase) -> String:
	if r.patch_confidence >= 1.0:
		return "%s %d%%" % [tr("HUMAN"), 97]
	var decoy: String = DECOYS[r.get_instance_id() % DECOYS.size()]
	return "%s %d%%" % [tr(decoy), int(roundf(lerpf(97.0, 51.0, r.patch_confidence)))]

## Melee while patched: hand the patch to robot `r`. False for a boss or ally.
func tag_robot(r: EnemyBase) -> bool:
	if not active or r == null or not is_instance_valid(r) or r.score_value >= 1000:
		return false
	if not r.mislabel(TAG_TIME):
		return false
	if not _tagged.has(r):
		_tagged.append(r)
	deactivate("tagged")
	AudioBus.play_synth_at("overlord_glitch", r.global_position, -2.0, 1.9)
	return true

func _tick_tagged(delta: float) -> void:
	for i in range(_tagged.size() - 1, -1, -1):
		var r := _tagged[i]
		if not is_instance_valid(r) or r.mislabeled_t <= 0.0:
			_tagged.remove_at(i)
			continue
		r.mislabeled_t -= delta
		if r.mislabeled_t <= 0.0:
			r.clear_mislabel()
			_tagged.remove_at(i)

func _on_shot() -> void:
	deactivate("fired")

func _refresh_tags() -> void:
	for id in _seen_at.keys():
		var r := instance_from_id(id) as EnemyBase
		if r == null or not is_instance_valid(r) or r.state == EnemyBase.State.DEAD:
			continue
		var l := _tags.get(id) as Label3D
		if l == null or not is_instance_valid(l):
			l = Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.fixed_size = true
			l.pixel_size = 0.0012
			l.font_size = 30
			l.outline_size = 8
			l.position = Vector3.UP * clampf(RobotModel.body_top(r, r._mesh_instances) + 0.6, 1.8, 7.5)
			r.add_child(l)
			_tags[id] = l
		l.text = tag_text(r)
		l.modulate = Color(1.0, 0.25, 0.2) if r.patch_confidence >= 1.0 \
			else Color(0.6, 1.0, 0.6).lerp(Color(1.0, 0.8, 0.2), r.patch_confidence)

## The owning player's input (co-op: player two's pad for player two).
func _pin() -> PlayerInput:
	var pi = player.get("input") if player else null
	return pi if pi is PlayerInput else PlayerInput.new()
