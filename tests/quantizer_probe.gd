extends Node
## Probe: the QUANTIZER drops precision as it is damaged (enemy_quantizer.gd).
## (1) it is wired: level builder, codex, one on ALIEN and one on ARCHON;
## (2) whole it is FP32: its own materials, no extra scatter, base cadence;
## (3) at each STAGE_AT step it moves to the next precision: every chassis
##     surface on the quantize shader with that stage's grid and colour levels,
##     the tag reads it, it fires STAGE_CD faster and scatters STAGE_SPREAD more;
## (4) compression is lossy: healing back to full keeps the precision it lost;
## (5) killed at INT4 it dies like any robot and the tag goes.
##   godot --headless --path . --audio-driver Dummy res://tests/quantizer_probe.tscn

const SCENE := "res://scenes/enemies/quantizer.tscn"
const SHADER := preload("res://shaders/quantize.gdshader")
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _count(level: String) -> int:
	var n := 0
	for en in LevelDefs.get_def(level).get("enemies", []):
		if en.get("type", "") == "quantizer":
			n += 1
	return n

## [surfaces on the quantize shader, surfaces in all] over the visible chassis.
func _quantized(e: EnemyBase) -> Array:
	var q := 0
	var all := 0
	for n in (e._visual_root if e._visual_root else e).find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or KillFx._is_glow(mi):
			continue
		for s in mi.mesh.get_surface_count():
			all += 1
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m and m.shader == SHADER:
				q += 1
	return [q, all]

func _grid_ok(e: EnemyQuantizer, want: float) -> bool:
	for r in e._swap.get("saved", []):
		var mi: MeshInstance3D = r["mi"]
		if not is_equal_approx(float(mi.get_instance_shader_parameter("grid")), want):
			return false
	return not e._swap.get("saved", []).is_empty()

func _run() -> void:
	# 1. Wiring.
	_check("level builder knows quantizer", LevelBuilder.ENEMY_SCENES.get("quantizer", "") == SCENE)
	_check("codex entry", EnemyCodex.has("quantizer") and "quantizer" in EnemyCodex.ORDER)
	_check("one on ALIEN", _count("alien") == 1, str(_count("alien")))
	_check("one on ARCHON", _count("archon") == 1, str(_count("archon")))

	var e: EnemyQuantizer = (load(SCENE) as PackedScene).instantiate()
	add_child(e)
	e.global_position = Vector3(0, 3, 0)
	e.set_physics_process(false)
	await _frames(3)
	_check("whole it fires at its own cadence", is_equal_approx(e.attack_interval(), e.attack_cooldown))
	var base_spread := e.aim_spread_deg()

	# 2. Whole.
	_check("whole it is FP32 in its own materials", e.precision() == "FP32" and _quantized(e)[0] == 0
			and e.get_node("PrecisionTag").text == "FP32")

	# 3. Each step.
	for i in range(1, EnemyQuantizer.STAGES.size()):
		var target_hp: float = e.hp.max_health * (EnemyQuantizer.STAGE_AT[i] - 0.02)
		e.hp.apply_damage(e.hp.current_health - target_hp, null)
		await _frames(2)
		var q := _quantized(e)
		var name: String = EnemyQuantizer.STAGES[i]
		_check("%s at %.0f%%" % [name, EnemyQuantizer.STAGE_AT[i] * 100.0], e.stage == i and e.precision() == name
				and e.get_node("PrecisionTag").text == name, e.precision())
		_check("%s: every surface quantized on grid %.2f" % [name, EnemyQuantizer.STAGE_GRID[i]],
				q[0] == q[1] and q[1] > 0 and _grid_ok(e, EnemyQuantizer.STAGE_GRID[i]), "%d of %d" % [q[0], q[1]])
		_check("%s: fires x%.2f, scatters +%.0f deg" % [name, EnemyQuantizer.STAGE_CD[i], EnemyQuantizer.STAGE_SPREAD[i]],
				# (the base's own last-stand haste stacks on top at low health)
				is_equal_approx(e.attack_interval(), e.attack_cooldown * (0.55 if e.last_stand_active() else 1.0)
						* EnemyQuantizer.STAGE_CD[i])
				and is_equal_approx(e.aim_spread_deg(), base_spread + EnemyQuantizer.STAGE_SPREAD[i]))

	# 4. Lossy.
	e.hp.current_health = e.hp.max_health
	e.hp.apply_damage(1.0, null)
	await _frames(2)
	_check("healed to full it keeps INT4", e.precision() == "INT4", e.precision())

	# 5. Death.
	e.hp.apply_damage(99999.0, null)
	await _frames(3)
	_check("killed at INT4 it dies and the tag goes", e.state == EnemyBase.State.DEAD
			and not e.get_node("PrecisionTag").visible)

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
