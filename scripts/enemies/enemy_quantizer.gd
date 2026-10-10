class_name EnemyQuantizer
extends EnemyDrone
## QUANTIZER - a model compressed to fight cheaper. A flying gunner that drops
## precision as you damage it: FP32 -> FP16 -> INT8 -> INT4 at STAGE_AT of its
## health. Each step its chassis snaps to a coarser voxel grid (STAGE_GRID
## metres, world-space, so the blocks jump as it flies), its colours posterize
## (STAGE_LEVELS) and a tag over it reads the new precision. Cheaper inference:
## it fires faster at every step (STAGE_CD), but rounding errors cost it its
## aim (STAGE_SPREAD degrees of extra scatter). Half-dead, it is spraying.
##
## The look is shaders/quantize.gdshader, swapped in by KillFx.swap_to_dissolve
## the first time it drops a step (FP32 keeps its own materials). Stages ride
## hp.damaged; the drone's flight and projectile kit are untouched.
## Covered by tests/quantizer_probe.

const SHADER := preload("res://shaders/quantize.gdshader")
const STAGES := ["FP32", "FP16", "INT8", "INT4"]
const STAGE_AT := [1.0, 0.75, 0.5, 0.25] ## health fraction at or below which a stage begins
const STAGE_GRID := [0.0, 0.05, 0.11, 0.2]
const STAGE_LEVELS := [256.0, 24.0, 8.0, 3.0]
const STAGE_CD := [1.0, 0.85, 0.7, 0.55] ## x attack interval
const STAGE_SPREAD := [0.0, 2.0, 5.0, 9.0] ## + degrees of scatter
const BIT_GREEN := Color(0.35, 1.0, 0.6)

var stage := 0
var _swap := {}
var _tag: Label3D

func _ready() -> void:
	super._ready()
	max_health = 140.0
	move_speed = 5.5
	attack_cooldown = 1.3
	projectile_damage = 9.0
	score_value = 220
	hover_height = 3.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.damaged.connect(func(_a: float, _s: Node) -> void: _update_stage())
	_tag = Label3D.new()
	_tag.name = "PrecisionTag"
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.font_size = 36
	_tag.pixel_size = 0.0045
	_tag.outline_size = 8
	_tag.outline_modulate = Color(0.0, 0.06, 0.03, 0.85)
	_tag.modulate = BIT_GREEN * 1.8 # HDR: Label3D takes fog
	_tag.text = STAGES[0]
	add_child(_tag)
	_tag.position = Vector3.UP * 1.4 # over the gun turret, which hid it at 0.95

## The stage for a health fraction `f`.
static func stage_for(f: float) -> int:
	var s := 0
	for i in STAGE_AT.size():
		if f <= STAGE_AT[i] + 0.0001 and i > 0:
			s = i
	return s

func precision() -> String:
	return STAGES[stage]

func attack_interval() -> float:
	return super.attack_interval() * STAGE_CD[stage]

func aim_spread_deg() -> float:
	return super.aim_spread_deg() + STAGE_SPREAD[stage]

func _update_stage() -> void:
	if hp == null or state == State.DEAD or not hp.is_alive():
		return
	var s := stage_for(hp.current_health / maxf(hp.max_health, 1.0))
	if s <= stage:
		return
	stage = s
	if _swap.is_empty():
		# A hit flash in flight would be saved as the overlay and restored later.
		if _flash_tween and _flash_tween.is_valid():
			_flash_tween.kill()
		_clear_hit_flash()
		_swap = KillFx.swap_to_dissolve(_visual_root if _visual_root else self, BIT_GREEN, 0.0, 1.0, true, SHADER)
	for r in _swap.get("saved", []):
		var mi: MeshInstance3D = r["mi"]
		if is_instance_valid(mi):
			mi.set_instance_shader_parameter("grid", STAGE_GRID[stage])
			mi.set_instance_shader_parameter("levels", STAGE_LEVELS[stage])
	_tag.text = STAGES[stage]
	var tw := _tag.create_tween()
	tw.tween_property(_tag, "scale", Vector3.ONE * 1.5, 0.07)
	tw.tween_property(_tag, "scale", Vector3.ONE, 0.2)
	AudioBus.play_synth_at("overlord_glitch", global_position, -6.0, 1.6 - stage * 0.25)
	_think("quantize")

func _on_died(source: Node) -> void:
	if is_instance_valid(_tag):
		_tag.hide()
	super._on_died(source)
