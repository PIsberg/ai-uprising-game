class_name GenerativeZone
extends Node3D
## "GENERATIVE GUARDRAILS" objective.
##
## A rogue AI floods a corridor with unstable, self-generating terrain: the field
## floor is a live hazard, and every couple of seconds the AI raises a HAZARD
## PILLAR on a random cell to wall you in and cook you. You carry the ANCHOR
## TAGGER — aim at a cell and fire (default [T] / gamepad Y) to slam an "anchor
## tag" into it. A tagged cell is ripped out of the AI's generative boundary and
## LOCKED as a safe raised cover slab (a guardrail): the AI can no longer spawn a
## hazard there, and you can stand on it unharmed. Anchor a path of slabs across
## the field to the override gate at the far end. You're literally turning the
## enemy's own terrain-generation against it to build your bridge.
##
## Self-contained task manager (spawned by LevelBuilder for a "generative_zone"
## task). Registers its own input action, finds the player + camera, and calls
## GameState.complete_task when you reach the gate.

@export var task_id := "guardrails"
@export var field_center := Vector3.ZERO
@export var field_size := Vector2(26, 34)   ## x = width, y = depth toward the gate
@export var cell := 4.0                       ## grid cell size (m)
@export var accent := Color(0.3, 0.82, 1.0)   ## safe / anchor colour
@export var hazard_color := Color(1.0, 0.32, 0.16)
@export var hazard_period := 1.6              ## seconds between AI hazard mutations
@export var floor_dot := 7.0                  ## damage/tick on the unstable floor
@export var tick := 0.35
@export var anchor_cooldown := 0.4
@export var max_hazards := 9                  ## live hazard-pillar cap

enum { UNSTABLE, HAZARD, ANCHORED }

const PLAYER_LAYER := 2
const SLAB_H := 0.62          ## anchored slab height — tall enough to stand clear of the floor hazard
const PILLAR_H := 3.2

var _cols: int
var _rows: int
var _state: Array = []        ## [r][c] -> int
var _tile: Array = []         ## [r][c] -> MeshInstance3D (floor tile)
var _tile_mat: Array = []     ## [r][c] -> StandardMaterial3D
var _pillar: Dictionary = {}  ## "r,c" -> Node3D (live hazard pillar)
var _floor_y := 0.0

var _player: Node3D
var _cam: Camera3D
var _done := false
var _t_tick := 0.0
var _t_haz := 0.0
var _t_cd := 0.0
var _clock := 0.0
var _gate: Node3D
var _gate_pos := Vector3.ZERO
var _hint_shown := false

func _ready() -> void:
	_floor_y = field_center.y
	_cols = maxi(2, int(field_size.x / cell))
	_rows = maxi(2, int(field_size.y / cell))
	_register_action()
	_build_grid()
	_build_start_pad()
	_build_gate()
	add_to_group("objective")
	# A brief timer so the level's teach/toast systems and player exist first.
	get_tree().create_timer(0.6).timeout.connect(_intro)

func _register_action() -> void:
	if not InputMap.has_action("anchor_tag"):
		InputMap.add_action("anchor_tag")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_T
		InputMap.action_add_event("anchor_tag", k)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_Y
		InputMap.action_add_event("anchor_tag", pad)

func _intro() -> void:
	if has_node("/root/GameState"):
		var gs := get_node("/root/GameState")
		if gs.has_method("teach_once"):
			gs.teach_once("anchor_tagger",
				"ANCHOR TAGGER ONLINE — aim at the unstable floor and fire [T] to lock safe cover. Bridge a path to the override gate.")

# ---------- grid coords ----------

func _cell_world(r: int, c: int) -> Vector3:
	return Vector3(
		field_center.x + (float(c) - (_cols - 1) * 0.5) * cell,
		_floor_y,
		field_center.z + (float(r) - (_rows - 1) * 0.5) * cell)

func _world_cell(p: Vector3) -> Vector2i:
	var c := int(round((p.x - field_center.x) / cell + (_cols - 1) * 0.5))
	var r := int(round((p.z - field_center.z) / cell + (_rows - 1) * 0.5))
	return Vector2i(c, r)

func _in_field(c: int, r: int) -> bool:
	return c >= 0 and c < _cols and r >= 0 and r < _rows

# ---------- build ----------

func _build_grid() -> void:
	for r in _rows:
		var srow: Array = []
		var trow: Array = []
		var mrow: Array = []
		for c in _cols:
			srow.append(UNSTABLE)
			var mi := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(cell - 0.25, cell - 0.25)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.emission_enabled = true
			mat.albedo_color = hazard_color * 0.5
			mat.emission = hazard_color
			mat.emission_energy_multiplier = 1.1
			pm.material = mat
			mi.mesh = pm
			mi.position = _cell_world(r, c) + Vector3(0, 0.04, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			trow.append(mi)
			mrow.append(mat)
		_state.append(srow)
		_tile.append(trow)
		_tile_mat.append(mrow)
	# A charred perimeter kerb so the field reads as a sunken hazard bed.
	_build_kerb()

func _build_kerb() -> void:
	var kerb := StandardMaterial3D.new()
	kerb.albedo_color = Color(0.05, 0.05, 0.06)
	kerb.roughness = 1.0
	var hx := _cols * cell * 0.5
	var hz := _rows * cell * 0.5
	for spec in [
		[Vector3(field_center.x, _floor_y, field_center.z - hz), Vector3(hx * 2 + 0.6, 0.5, 0.5)],
		[Vector3(field_center.x, _floor_y, field_center.z + hz), Vector3(hx * 2 + 0.6, 0.5, 0.5)],
		[Vector3(field_center.x - hx, _floor_y, field_center.z), Vector3(0.5, 0.5, hz * 2)],
		[Vector3(field_center.x + hx, _floor_y, field_center.z), Vector3(0.5, 0.5, hz * 2)],
	]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[1]
		bm.material = kerb
		mi.mesh = bm
		mi.position = (spec[0] as Vector3) + Vector3(0, 0.2, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

## The near row(s) start pre-anchored so the player has safe ground to fire from.
func _build_start_pad() -> void:
	for c in _cols:
		_anchor_cell(c, 0, false)
		if _rows > 6:
			_anchor_cell(c, 1, false)

func _build_gate() -> void:
	# A safe raised pad + a glowing gate just past the far row.
	var gz := field_center.z + (_rows * 0.5 + 0.7) * cell
	_gate_pos = Vector3(field_center.x, _floor_y, gz)
	var pad := _make_slab(Vector3(field_center.x, _floor_y, gz), _cols * cell * 0.5, accent)
	pad.name = "GatePad"
	_gate = Node3D.new()
	_gate.position = _gate_pos + Vector3(0, 0, 0)
	add_child(_gate)
	# An arch of light marking the override gate.
	var arch := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.6
	tm.outer_radius = 3.0
	var am := StandardMaterial3D.new()
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.emission_enabled = true
	am.emission = accent
	am.albedo_color = accent
	am.emission_energy_multiplier = 3.0
	tm.material = am
	arch.mesh = tm
	arch.rotation.x = PI * 0.5
	arch.position = _gate_pos + Vector3(0, 3.0, 0)
	arch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gate.add_child(arch)
	var gl := OmniLight3D.new()
	gl.light_color = accent
	gl.light_energy = 3.0
	gl.omni_range = 12.0
	gl.position = _gate_pos + Vector3(0, 2.5, 0)
	add_child(gl)

# ---------- anchoring ----------

## Convert a cell into a locked safe slab (guardrail). `fx` plays the tag impact.
func _anchor_cell(c: int, r: int, fx: bool) -> void:
	if not _in_field(c, r) or _state[r][c] == ANCHORED:
		return
	_state[r][c] = ANCHORED
	_clear_pillar(c, r)
	if _tile[r][c]:
		(_tile[r][c] as Node3D).queue_free()
		_tile[r][c] = null
	var slab := _make_slab(_cell_world(r, c), cell * 0.5, accent)
	slab.get_parent() # already added
	if fx:
		_tag_fx(_cell_world(r, c))

## A solid, safe, walkable slab (StaticBody) with a glowing rim — the guardrail.
func _make_slab(center: Vector3, half: float, col: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center + Vector3(0, SLAB_H * 0.5, 0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(half * 2.0, SLAB_H, half * 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.17, 0.2)
	mat.metallic = 0.5
	mat.roughness = 0.5
	bm.material = mat
	mi.mesh = bm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	body.add_child(mi)
	body.add_child(cs)
	# A glowing safe rim on top so anchored ground reads as "locked / safe".
	var rim := MeshInstance3D.new()
	var rp := PlaneMesh.new()
	rp.size = Vector2(half * 2.0 - 0.2, half * 2.0 - 0.2)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.emission_enabled = true
	rmat.emission = col
	rmat.albedo_color = col * 0.5
	# Kept just under the level's glow HDR threshold so the safe slabs read as a
	# lit grid line, not a blown-out white block.
	rmat.emission_energy_multiplier = 0.6
	rp.material = rmat
	rim.mesh = rp
	rim.position = Vector3(0, SLAB_H * 0.5 + 0.02, 0)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(rim)
	add_child(body)
	return body

## Anchor-tag impact flourish: a bright pop of the safe colour at the hit point.
func _tag_fx(at: Vector3) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = accent
	flash.light_energy = 4.0
	flash.omni_range = 6.0
	flash.position = at + Vector3(0, 1.0, 0)
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.35)
	tw.tween_callback(flash.queue_free)
	if has_node("/root/AudioBus"):
		var ab := get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("impact_metal", at, -4.0, 1.6)

## A tracer from the gun toward the anchored cell so the tag reads as a shot.
func _tracer(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var len := from.distance_to(to)
	cm.top_radius = 0.03
	cm.bottom_radius = 0.03
	cm.height = len
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = accent
	mat.albedo_color = accent
	cm.material = mat
	mi.mesh = cm
	mi.position = (from + to) * 0.5
	mi.look_at_from_position(mi.position, to, Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.18)
	tw.tween_callback(mi.queue_free)

# ---------- hazard generation (the rogue AI) ----------

func _spawn_hazard() -> void:
	if _pillar.size() >= max_hazards:
		return
	# Bias generation toward cells near/ahead of the player — the AI reacts to you.
	var pc := Vector2i(-1, -1)
	if _player:
		pc = _world_cell(_player.global_position)
	var candidates: Array = []
	for r in _rows:
		for c in _cols:
			if _state[r][c] != UNSTABLE:
				continue
			var key := "%d,%d" % [r, c]
			if _pillar.has(key):
				continue
			# weight: closer to the player's row (ahead of them) = more likely
			var w := 1
			if pc.x >= 0:
				var dr: int = absi(r - pc.y)
				if dr <= 3:
					w = 4 - dr
			for _i in maxi(1, w):
				candidates.append(Vector2i(c, r))
	if candidates.is_empty():
		return
	var pick: Vector2i = candidates[randi() % candidates.size()]
	_state[pick.y][pick.x] = HAZARD
	_raise_pillar(pick.x, pick.y)

func _raise_pillar(c: int, r: int) -> void:
	var base := _cell_world(r, c)
	var node := Node3D.new()
	node.position = base
	add_child(node)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(cell * 0.7, PILLAR_H, cell * 0.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = hazard_color * 0.6
	mat.emission_enabled = true
	mat.emission = hazard_color
	mat.emission_energy_multiplier = 2.0
	bm.material = mat
	mi.mesh = bm
	mi.position = Vector3(0, PILLAR_H * 0.5, 0)
	node.add_child(mi)
	# Physical blocker so pillars actually wall off routes.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	cs.position = Vector3(0, PILLAR_H * 0.5, 0)
	body.add_child(cs)
	node.add_child(body)
	# Rise-up animation.
	node.scale = Vector3(1, 0.05, 1)
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pillar["%d,%d" % [r, c]] = node
	if has_node("/root/AudioBus"):
		var ab := get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("impact_metal", base, -6.0, 0.7)

func _clear_pillar(c: int, r: int) -> void:
	var key := "%d,%d" % [r, c]
	if _pillar.has(key):
		var n: Node = _pillar[key]
		if is_instance_valid(n):
			n.queue_free()
		_pillar.erase(key)

# ---------- per-frame ----------

func _process(delta: float) -> void:
	_clock += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player:
			_cam = _player.find_child("Camera3D", true, false) as Camera3D
		return
	_t_cd = maxf(0.0, _t_cd - delta)

	# Anchor Tagger fire.
	if Input.is_action_just_pressed("anchor_tag") and _t_cd <= 0.0 and not _done:
		_fire_anchor()

	# The AI keeps generating hazards.
	if not _done:
		_t_haz += delta
		if _t_haz >= hazard_period:
			_t_haz = 0.0
			_spawn_hazard()

	# Unstable-floor / hazard damage: you're safe only while standing on your cell's
	# anchored slab (or off the field entirely).
	_t_tick += delta
	if _t_tick >= tick:
		_t_tick = 0.0
		_apply_floor_damage()

	_pulse()
	_check_goal()

func _fire_anchor() -> void:
	if _cam == null:
		_cam = _player.find_child("Camera3D", true, false) as Camera3D
	if _cam == null:
		return
	var from := _cam.global_position
	var to := from - _cam.global_transform.basis.z * 45.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 # world
	q.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var point: Vector3 = hit.get("position", to) if not hit.is_empty() else to
	var cellv := _world_cell(point)
	_t_cd = anchor_cooldown
	_tracer(from - _cam.global_transform.basis.y * 0.2, point)
	if _in_field(cellv.x, cellv.y) and _state[cellv.y][cellv.x] != ANCHORED:
		_anchor_cell(cellv.x, cellv.y, true)
	else:
		# Dry tag: nothing valid to lock there.
		if has_node("/root/AudioBus"):
			var ab := get_node("/root/AudioBus")
			if ab.has_method("play_synth_ui"):
				ab.play_synth_ui("empty_click", -12.0, 1.4)

func _apply_floor_damage() -> void:
	var pc := _world_cell(_player.global_position)
	if not _in_field(pc.x, pc.y):
		return
	if _state[pc.y][pc.x] == ANCHORED:
		return
	# On bare unstable/hazard floor of the field: it cooks you.
	var d := _player.get_node_or_null("Damageable") as Damageable
	if d and d.is_alive():
		var dmg := floor_dot * (2.0 if _state[pc.y][pc.x] == HAZARD else 1.0)
		d.apply_damage(dmg, self)
		if has_node("/root/GameState"):
			var gs := get_node("/root/GameState")
			if gs.has_method("teach_once"):
				gs.teach_once("guardrails_floor",
					"⚠ The floor is UNSTABLE — tag [T] cells to lock safe slabs and cross on them.")

func _pulse() -> void:
	var e := 0.8 + sin(_clock * 3.0) * 0.4
	for r in _rows:
		for c in _cols:
			var m: StandardMaterial3D = _tile_mat[r][c]
			if m and _state[r][c] == UNSTABLE:
				m.emission_energy_multiplier = e

func _check_goal() -> void:
	if _done:
		return
	# Progress bar tracks how far across the field you've bridged.
	var pc := _world_cell(_player.global_position)
	var frac := clampf(float(pc.y) / float(maxi(1, _rows)), 0.0, 0.95)
	if has_node("/root/GameState"):
		var gs := get_node("/root/GameState")
		if gs.has_method("set_task_progress"):
			gs.set_task_progress(task_id, frac)
	if Vector2(_player.global_position.x - _gate_pos.x, _player.global_position.z - _gate_pos.z).length() < 3.4 \
			and _player.global_position.y > _floor_y - 0.5:
		_complete()

func _complete() -> void:
	_done = true
	if has_node("/root/GameState"):
		var gs := get_node("/root/GameState")
		if gs.has_method("set_task_progress"):
			gs.set_task_progress(task_id, 1.0)
		if gs.has_method("complete_task"):
			gs.complete_task(task_id)
	if has_node("/root/AudioBus"):
		var ab := get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("victory", _gate_pos, -2.0, 1.1)
