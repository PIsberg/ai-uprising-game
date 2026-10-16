class_name EnemyAegis
extends EnemyMender
## AEGIS — a shield drone. It flies the MENDER's support pattern (hangs back,
## flees the player, beams an ally) but instead of healing it WARDS: the ally
## nearest the player wears a gold bubble and takes no damage at all
## (Damageable.warded_by) while the beam holds. Shoot the AEGIS and the ward
## drops at once. Boss-class robots (EnemyBase.HIJACK_BOSS_HP) are never
## warded, nor other support drones. The first shot into a bubble teaches the
## rule once. Reuses the EyeDrone chassis, tinted gold. tests/aegis_probe.

const COLOR := Color(1.0, 0.78, 0.22)
const TEACH_TEXT := "AEGIS DRONE: a gold bubble makes a robot immune. Shoot the drone feeding it first."

var _ward: EnemyBase = null
var _bubble: MeshInstance3D
var _bubble_mat: StandardMaterial3D
var _flash := 0.0

func _ready() -> void:
	super._ready()
	max_health = 80.0
	score_value = 190
	hp.max_health = max_health
	hp.current_health = max_health

func support_color() -> Color:
	return COLOR

## Stale when gone, dead, or warded by another AEGIS. Never stale for being
## at full health (a ward is not a heal).
func _support_stale(t: EnemyBase) -> bool:
	return t == null or not is_instance_valid(t) or t.state == State.DEAD or t.hp == null \
		or not t.hp.is_alive() or (t.hp.warded_by != null and t.hp.warded_by != self)

## The ally nearest the player: the one the player is about to shoot.
func _pick_support_target() -> EnemyBase:
	var player := _find_player()
	if player == null:
		return null
	var best: EnemyBase = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		var a := e as EnemyBase
		if a == null or a == self or a is EnemyMender or a.state == State.DEAD or a.hijacked:
			continue
		if a.hp == null or not a.hp.is_alive():
			continue
		if a.max_health * a._health_mult >= HIJACK_BOSS_HP:
			continue
		if a.hp.warded_by != null and a.hp.warded_by != self:
			continue
		var d := a.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = a
	return best

func _support(t: EnemyBase, delta: float) -> void:
	if t != _ward:
		_unward()
		_ward = t
		t.hp.warded_by = self
		_bubble = _make_bubble(t)
		AudioBus.play_synth_at("charge", t.global_position, -6.0, 1.3)
	_flash = maxf(0.0, _flash - delta * 3.0)
	if _bubble_mat:
		_bubble_mat.albedo_color = Color(COLOR, 0.14 + 0.06 * sin(_hover_phase * 2.0) + 0.5 * _flash)

func _support_lost() -> void:
	_unward()

func _make_bubble(t: EnemyBase) -> MeshInstance3D:
	var b := MeshInstance3D.new()
	b.name = "AegisBubble"
	var sm := SphereMesh.new()
	sm.radius = 1.3
	sm.height = 2.6
	sm.radial_segments = 24
	sm.rings = 12
	b.mesh = sm
	_bubble_mat = StandardMaterial3D.new()
	_bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bubble_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_bubble_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bubble_mat.albedo_color = Color(COLOR, 0.16)
	b.material_override = _bubble_mat
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.position = Vector3.UP * 1.0
	t.add_child(b)
	return b

func _unward() -> void:
	if is_instance_valid(_ward) and _ward.hp and _ward.hp.warded_by == self:
		_ward.hp.warded_by = null
	if is_instance_valid(_bubble):
		_bubble.get_parent().remove_child(_bubble)
		_bubble.queue_free()
	_ward = null
	_bubble = null
	_bubble_mat = null

## Damageable calls this when a shot lands on the bubble.
func on_ward_hit(_owner: Node, source: Node) -> void:
	_flash = 1.0
	if source != null and is_instance_valid(source) and source.is_in_group("player"):
		GameState.teach_once("aegis", TEACH_TEXT)
	if is_instance_valid(_ward):
		AudioBus.play_synth_at("impact_metal", _ward.global_position + Vector3.UP, -6.0, 1.7)

func _on_died(source: Node) -> void:
	_unward()
	super._on_died(source)

func _exit_tree() -> void:
	_unward()
