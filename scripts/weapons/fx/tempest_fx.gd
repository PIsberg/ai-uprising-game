class_name TempestFx
extends SignatureFx
## The TPX-9 Tempest Coil's signature: a storm in a ball. In flight, arcs crackle
## out of the orb in every direction (TENDRILS ArcBolts re-struck every
## RESTRIKE seconds), and while the floor is within GROUND_REACH below it one
## arc licks down to the ground, dragged along under the orb. Where it goes off
## a bolt strikes down out of the sky onto the blast (LightningStrike) with a
## thunderclap, before the chain lightning runs through the pack. Covered by
## tests/tempest_fx_probe.

const TENDRILS := 3
const TENDRIL_REACH := Vector2(0.35, 0.65) ## metres an arc reaches off the orb
const RESTRIKE := 0.05 ## seconds between re-strikes
const GROUND_REACH := 2.5 ## metres: the floor this close below draws a ground arc
const STRIKE_HEIGHT := 10.0

func on_projectile(proj: Node3D) -> void:
	if proj == null:
		return
	var rig := Storm.new()
	rig.name = "TempestStorm"
	rig.set_meta("sig_fx", "tempest_storm")
	rig.color = _color()
	proj.add_child(rig)

func on_projectile_hit(_proj: Node3D, pos: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	var s := LightningStrike.new()
	s.set_meta("sig_fx", "sky_strike")
	s.height = STRIKE_HEIGHT
	s.bolts = 3
	s.lifetime = 0.5
	s.color = _color().lerp(Color.WHITE, 0.25)
	s.light_budgeted = true
	s.sound_id = "thunder"
	s.sound_pitch = 1.4
	root.add_child(s)
	s.global_position = pos

func _color() -> Color:
	var data: WeaponData = weapon.get("data") if is_instance_valid(weapon) else null
	return data.tracer_color if data else Color(0.45, 0.85, 1.0)

## Rides the orb: crackling tendrils, and a ground arc when the floor is near.
class Storm extends Node3D:
	var color := Color(0.45, 0.85, 1.0)
	var tendrils: Array[ArcBolt] = []
	var ground: ArcBolt = null
	var ground_point := Vector3.ZERO ## where the ground arc lands, when it shows
	var _clock := 0.0

	func _ready() -> void:
		for i in TempestFx.TENDRILS:
			var b := ArcBolt.make(4, 0.012, color)
			add_child(b)
			tendrils.append(b)
		ground = ArcBolt.make(6, 0.018, color)
		ground.visible = false
		add_child(ground)
		strike()

	func _process(delta: float) -> void:
		_clock += delta
		if _clock >= TempestFx.RESTRIKE:
			_clock = 0.0
			strike()

	## Re-strike every arc from where the orb is now.
	func strike() -> void:
		var o := global_position
		for b in tendrils:
			var d := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
			if d.length() < 0.1:
				d = Vector3.UP
			b.zap(o, o + d.normalized() * randf_range(TempestFx.TENDRIL_REACH.x, TempestFx.TENDRIL_REACH.y), 0.08)
			b.set_alpha(randf_range(0.6, 1.0))
		var q := PhysicsRayQueryParameters3D.create(o, o - Vector3.UP * TempestFx.GROUND_REACH)
		q.collision_mask = 1
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		ground.visible = not hit.is_empty()
		if ground.visible:
			ground_point = (hit.position as Vector3) + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
			ground.zap(o, ground_point, 0.25)
