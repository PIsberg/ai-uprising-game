class_name EnemyOverfitter
extends EnemyAndroid
## OVERFITTER - a robot that learns your gun. Every hit it takes from one weapon
## trains it on that weapon; once FIT_DAMAGE of it has landed, it has OVERFIT:
## that gun deals FIT_MULT of its damage, a shell in the gun's tracer colour
## lights up round it and a hologram over it names the gun it memorised.
## Hit it with any other gun and it is out of distribution: the shell drops and
## for OOD_TIME it takes OOD_MULT from everything and learns nothing; after
## that it trains on whichever gun hits it next, from zero. Swapping to a gun it
## is merely training on does nothing special: the window only opens when an
## overfit breaks.
##
## The gun travels on the hit (Damageable.hit_weapon, set by KillFx.tag), so
## grenades, hazards and melee are untagged: never resisted, never trained on.
## A burst rifleman otherwise (the android's kit) on the base GUNNER chassis.
## Covered by tests/overfitter_probe.

const FIT_DAMAGE := 90.0 ## damage from one gun before it overfits to it
const FIT_MULT := 0.25
const OOD_MULT := 1.5
const OOD_TIME := 3.0
const OOD_COLOR := Color(1.0, 0.25, 0.85)
const TRAIN_COLOR := Color(0.55, 1.0, 0.72)
const SHELL_SHADER := preload("res://shaders/overfit_shell.gdshader")

var fit_weapon: WeaponData = null ## the gun it is training on, or has overfit to
var fit_damage := 0.0 ## damage that gun has landed since training began
var overfit := false
var _ood_t := 0.0
var _shell: MeshInstance3D
var _shell_mat: ShaderMaterial
var _status: Label3D
## The trace floats over the fit hologram rather than at the default
## body-top + 0.45, which would put the two on the same line.
const STATUS_H := 2.5
const THINK_H := 2.9

func _ready() -> void:
	super._ready()
	max_health = 260.0
	move_speed = 4.6
	sight_range = 36.0
	attack_range = 26.0
	preferred_range = 14.0
	attack_cooldown = 1.7
	hitscan_damage = 9.0
	score_value = 300
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 0.0 # flat armour would bend the fit/OOD ratios on small hits
	_think_h = THINK_H
	_build_shell()
	_build_status()
	hp.died.connect(func(_s: Node) -> void: _status.hide(); _shell.hide())

func _process(delta: float) -> void:
	if _ood_t > 0.0:
		_ood_t = maxf(0.0, _ood_t - delta)
		if _ood_t == 0.0:
			_refresh_status()
		elif is_instance_valid(_status):
			# Glitching: the hologram cannot hold still while it is lost.
			_status.position.x = randf_range(-0.06, 0.06) if randf() < 0.3 else 0.0

func out_of_distribution() -> bool:
	return _ood_t > 0.0

func shell_visible() -> bool:
	return is_instance_valid(_shell) and _shell.visible

func status_text() -> String:
	return _status.text if is_instance_valid(_status) else ""

func modify_incoming_damage(amount: float, _source, _origin = null) -> float:
	var w: WeaponData = hp.hit_weapon if hp else null
	if w != null:
		if w == fit_weapon:
			if overfit:
				amount *= FIT_MULT
				_shell_ping()
		else:
			if overfit:
				_break_fit()
			fit_weapon = w
			fit_damage = 0.0
	if _ood_t > 0.0:
		amount *= OOD_MULT
	if w != null and w == fit_weapon and not overfit and _ood_t <= 0.0:
		fit_damage += amount
		if fit_damage >= FIT_DAMAGE:
			_overfit()
	if w != null:
		_refresh_status()
	return amount

func _overfit() -> void:
	overfit = true
	var col := _gun_color(fit_weapon)
	_shell_mat.set_shader_parameter("color", col)
	_shell.show()
	var tw := _shell.create_tween()
	tw.tween_method(func(v: float) -> void: _shell_mat.set_shader_parameter("strength", v), 0.0, 1.0, 0.35)
	AudioBus.play_synth_at("charge", global_position + Vector3.UP, -4.0, 1.35)
	_think("overfit")

func _break_fit() -> void:
	overfit = false
	_ood_t = OOD_TIME
	_shell.hide()
	var parent := get_parent()
	if parent:
		DeepfakeDecoy._burst(parent, global_position + Vector3.UP * 1.1)
	AudioBus.play_synth_at("overlord_glitch", global_position + Vector3.UP, -2.0, 0.9)
	_think("ood")

func _shell_ping() -> void:
	var tw := _shell.create_tween()
	tw.tween_method(func(v: float) -> void: _shell_mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.2)

static func _gun_color(w: WeaponData) -> Color:
	if w == null:
		return TRAIN_COLOR
	var c := w.tracer_color
	return Color(c.r, c.g, c.b, 1.0)

## What the hologram says: training progress as a falling loss, the gun it
## memorised, or that it is lost.
func _refresh_status() -> void:
	if not is_instance_valid(_status):
		return
	_status.position.x = 0.0
	if _ood_t > 0.0:
		_status.text = "OUT OF DISTRIBUTION\nloss NaN"
		_status.modulate = OOD_COLOR * 2.2
	elif overfit:
		_status.text = "OVERFIT: %s\nloss 0.0001" % fit_weapon.display_name.to_upper()
		var c := _gun_color(fit_weapon) * 2.2
		_status.modulate = Color(c.r, c.g, c.b, 1.0)
	elif fit_weapon != null:
		var k := clampf(fit_damage / FIT_DAMAGE, 0.0, 1.0)
		var bars := int(round(k * 8.0))
		_status.text = "TRAINING: %s\n[%s%s] loss %.2f" % [fit_weapon.display_name.to_upper(),
				"#".repeat(bars), ".".repeat(8 - bars), lerpf(2.3, 0.05, k)]
		_status.modulate = TRAIN_COLOR * 1.8
	else:
		_status.text = ""
	_status.modulate.a = 1.0

func _build_status() -> void:
	_status = Label3D.new()
	_status.name = "FitStatus"
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.font_size = 36
	_status.pixel_size = 0.0045
	_status.outline_size = 8
	_status.outline_modulate = Color(0.0, 0.05, 0.03, 0.8)
	_status.text = ""
	add_child(_status)
	_status.position = Vector3.UP * STATUS_H # under the <think> traces

func _build_shell() -> void:
	_shell = MeshInstance3D.new()
	_shell.name = "FitShell"
	var sm := SphereMesh.new()
	sm.radius = 0.95
	sm.height = 2.25
	sm.radial_segments = 32
	sm.rings = 16
	_shell_mat = ShaderMaterial.new()
	_shell_mat.shader = SHELL_SHADER
	sm.material = _shell_mat
	_shell.mesh = sm
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.position = Vector3.UP * 1.1
	_shell.hide()
	add_child(_shell)
