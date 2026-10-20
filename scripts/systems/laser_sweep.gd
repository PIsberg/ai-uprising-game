class_name LaserSweep
# @lat: [[level-system#Laser Sweeps]]
extends Node3D
## A rotating laser fence: an emitter post spins red beams round it at fixed
## heights, out to `radius`. A low beam (knee height) you jump over, a high
## one (chest height) you crouch or slide under; one touching you hurts
## (`damage`, once per pass). Each beam stops at the first wall in its way, so
## cover still covers. Robots are never hit. It can wake when a task is done
## (`wakes_on`) and go dark when another is (`stops_on`).
## Each beam tells you how to beat it: a jump beam (under 0.9 m) is amber with
## a JUMP tag riding it, a duck beam is red with a DUCK tag under it; a beam
## about to reach you blips and flashes its tag WARN_LEAD s ahead (`warned`),
## and the first sweep you walk up to teaches the rule once per run.
## Def key `laser_sweeps` (level_builder `_build_laser_sweeps`).
## tests/laser_sweep_probe.

@export var radius: float = 8.0
@export var speed_deg: float = 50.0          ## degrees per second
@export var beams: Array = [{"height": 0.45, "angle": 0.0}, {"height": 1.35, "angle": 180.0}]
@export var damage: float = 15.0
@export var wakes_on: String = ""            ## task id; dark until it is done
@export var stops_on: String = ""            ## task id; dark once it is done
@export var inner: float = 0.4               ## m from the centre the beams start (clear of what they spin round)
@export var post: bool = true                ## build the emitter post (off when a core is the emitter)

const HIT_HALF_WIDTH := 0.4   ## m either side of a beam that touches the player (capsule radius 0.35)
const HIT_GAP := 0.5          ## s before the same beam can hit again
const BEAM_THICK := 0.06
const DUCK_ABOVE := 0.9       ## m: a beam at or over this you duck, under it you jump
const JUMP_COLOR := Color(1.0, 0.62, 0.05)
const DUCK_COLOR := Color(1.0, 0.1, 0.1)
const WARN_LEAD := 0.6        ## s before a beam reaches you that it blips
const TEACH_REACH := 4.0      ## m outside the fence where the rule is taught
const TEACH_TEXT := "LASER FENCE: JUMP the low amber beam, DUCK (Ctrl) or slide under the high red one. A blip means one is about to reach you."

signal warned(beam: int)

var active := true
var _angle := 0.0
var _lens: Array[float] = []
var _beam_meshes: Array[MeshInstance3D] = []
var _cool: Array[float] = []
var _warn_armed: Array[bool] = []
var _flash: Array[float] = []
var _cues: Array[Label3D] = []
var _mats: Array[StandardMaterial3D] = []
var _floor_mat: StandardMaterial3D

func _ready() -> void:
	_build()
	# Always listening: wakes_on / stops_on may be set after the sweep is added.
	GameState.tasks_changed.connect(_check_tasks)
	_check_tasks()

func _check_tasks() -> void:
	var on := (wakes_on == "" or GameState.is_task_done(wakes_on)) \
		and (stops_on == "" or not GameState.is_task_done(stops_on))
	if on != active:
		active = on
		AudioBus.play_synth_at("charge" if on else "ui_back", global_position, -4.0, 1.6 if on else 0.6)
	for m in _beam_meshes:
		m.visible = active
	for c in _cues:
		c.visible = active
	_floor_mat.albedo_color.a = 0.35 if active else 0.0

## World direction beam `i` points this tick (horizontal).
func beam_direction(i: int) -> Vector3:
	var a := deg_to_rad(_angle + float((beams[i] as Dictionary).get("angle", 0.0)))
	return Vector3(cos(a), 0.0, sin(a))

## "jump" for a beam under DUCK_ABOVE, "duck" for one at or over it.
static func action_for(height: float) -> String:
	return "jump" if height < DUCK_ABOVE else "duck"

## How beam `i` is beaten: "jump" or "duck".
func beam_action(i: int) -> String:
	return action_for(float((beams[i] as Dictionary).get("height", 0.5)))

## The colour beam `i` is drawn in (amber to jump, red to duck).
func beam_color(i: int) -> Color:
	return _mats[i].albedo_color

## The tag riding beam `i` ("JUMP" / "DUCK").
func beam_cue(i: int) -> Label3D:
	return _cues[i]

## Drawn length of beam `i` this tick (to the first wall, at most `radius`).
func beam_length(i: int) -> float:
	return _lens[i]

func _build() -> void:
	var post_mi := MeshInstance3D.new()
	post_mi.visible = post
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28
	cm.bottom_radius = 0.38
	cm.height = 1.7
	post_mi.mesh = cm
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.14, 0.14, 0.16)
	steel.metallic = 0.7
	post_mi.material_override = steel
	post_mi.position = Vector3.UP * 0.85
	add_child(post_mi)
	for b in beams:
		var jump := action_for(float((b as Dictionary).get("height", 0.5))) == "jump"
		var col := JUMP_COLOR if jump else DUCK_COLOR
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 4.0
		_mats.append(mat)
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, BEAM_THICK, BEAM_THICK)
		m.mesh = bm
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_beam_meshes.append(m)
		_lens.append(radius)
		_cool.append(0.0)
		_warn_armed.append(true)
		_flash.append(0.0)
		# The tag riding the beam: over a jump beam, under a duck beam.
		var cue := Label3D.new()
		cue.text = "JUMP" if jump else "DUCK"
		cue.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		cue.font_size = 48
		cue.pixel_size = 0.006
		cue.outline_size = 10
		cue.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		cue.modulate = col * 1.6 # HDR: Label3D takes fog
		add_child(cue)
		_cues.append(cue)
		# An emitter lens on the post at the beam's height.
		var lens := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		lens.mesh = sm
		lens.material_override = mat
		lens.position = Vector3.UP * float((b as Dictionary).get("height", 0.5))
		lens.visible = post
		add_child(lens)
	# The danger zone, faint on the floor.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.08
	tm.outer_radius = radius
	ring.mesh = tm
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_floor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_floor_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.35)
	ring.material_override = _floor_mat
	ring.scale = Vector3(1, 0.05, 1)
	ring.position = Vector3.UP * 0.03
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

func _physics_process(delta: float) -> void:
	if not active:
		return
	_angle = fposmod(_angle + speed_deg * delta, 360.0)
	var space := get_world_3d().direct_space_state
	var pls := GameState.players()
	for pl in pls:
		_teach(pl)
	for i in beams.size():
		_cool[i] = maxf(0.0, _cool[i] - delta)
		_flash[i] = maxf(0.0, _flash[i] - delta)
		var h := float((beams[i] as Dictionary).get("height", 0.5))
		var dir := beam_direction(i)
		var from := global_position + Vector3.UP * h
		var q := PhysicsRayQueryParameters3D.create(from + dir * inner, from + dir * radius, 1)
		var hit := space.intersect_ray(q)
		var len := radius
		if not hit.is_empty():
			len = from.distance_to(hit["position"])
		_lens[i] = len
		var m := _beam_meshes[i]
		var shown := maxf(len - inner, 0.01)
		m.scale = Vector3(shown, 1, 1)
		m.position = Vector3.UP * h + dir * (inner + shown * 0.5)
		m.rotation = Vector3(0, -atan2(dir.z, dir.x), 0)
		var cue := _cues[i]
		var lift := 0.34 if beam_action(i) == "jump" else -0.3
		cue.position = Vector3.UP * (h + lift) + dir * (inner + shown * 0.6)
		cue.scale = Vector3.ONE * (1.0 + _flash[i] * 0.8)
		var beam_hit := false
		for pl in pls:
			_warn(i, pl, h)
			if _cool[i] <= 0.0 and _touches(pl, from, dir, len, h):
				var php: Node = pl.get_node_or_null("Damageable")
				if php:
					php.apply_damage(damage, self, false, from, true)
				beam_hit = true
				AudioBus.play_synth_at("hit_tick", pl.global_position, -2.0, 0.6)
		if beam_hit:
			_cool[i] = HIT_GAP

## Whether beam (from `from` along `dir`, `len` long, at height `h`) passes
## through the player's capsule: close to the beam's line within its length,
## and the beam's height between their feet and the top of their head.
func _touches(pl: Node3D, from: Vector3, dir: Vector3, len: float, h: float) -> bool:
	var feet := pl.global_position
	var tall := 1.0 if pl.get("_is_crouching") == true else 1.8
	var beam_y := global_position.y + h
	if beam_y < feet.y + 0.02 or beam_y > feet.y + tall:
		return false
	var rel := Vector3(feet.x - from.x, 0.0, feet.z - from.z)
	var along := rel.dot(dir)
	if along < 0.0 or along > len + 0.35:
		return false
	return (rel - dir * along).length() < HIT_HALF_WIDTH

## Blip and flash beam `i`'s tag once per pass, WARN_LEAD s before it reaches
## the player standing in its reach (whatever their stance: it is a cue to act).
func _warn(i: int, pl: Node3D, h: float) -> void:
	var rel := pl.global_position - global_position
	rel.y = 0.0
	var d := rel.length()
	var beam_y := global_position.y + h
	var in_reach := d >= inner and d <= _lens[i] + 0.35 and d <= radius + 0.35 		and beam_y >= pl.global_position.y - 0.3 and beam_y <= pl.global_position.y + 1.8
	var beam_deg := _angle + float((beams[i] as Dictionary).get("angle", 0.0))
	var ahead := fposmod((rad_to_deg(atan2(rel.z, rel.x)) - beam_deg) * signf(speed_deg), 360.0)
	if ahead > 180.0:
		_warn_armed[i] = true # it has passed them: the next approach warns again
		return
	if not _warn_armed[i] or not in_reach or absf(speed_deg) < 0.01:
		return
	if ahead / absf(speed_deg) <= WARN_LEAD:
		_warn_armed[i] = false
		_flash[i] = 0.5
		AudioBus.play_synth_at("broadcast_blip", pl.global_position, -3.0,
			1.5 if beam_action(i) == "jump" else 0.8)
		warned.emit(i)

## Teach the rule the first time a live fence is close enough to matter.
func _teach(pl: Node3D) -> void:
	var rel := pl.global_position - global_position
	rel.y = 0.0
	if rel.length() <= radius + TEACH_REACH:
		GameState.teach_once("laser_sweep", TEACH_TEXT)

## The death screen's "Taken down by" name and its tip key (player.gd reads it
## off any damage source that has it; hud.gd DEATH_TIPS).
func _kill_label() -> String:
	return "LASER SWEEP"
