class_name TeslaFx
extends SignatureFx
## The VK-7 Tesla Projector's signature: you can see it cook. While the beam
## holds a robot, a cage of jagged arcs crawls over its body (ArcBolts between
## random points on its bounds, redrawn every frame) with a flickering blue
## light, and when the beam lets go the robot keeps crackling a moment, the arcs
## thinning out as the charge bleeds off. One cage per robot, refreshed by every
## tick of the beam. Covered by tests/tesla_fx_probe.

const CAGE_ARCS := 5
const CAGE_SEGS := 5
const CAGE_WIDTH := 0.014
const RESIDUAL := 0.7 ## seconds the cage crackles on after the last beam tick
const CAGE_NAME := "TeslaCage"

func on_beam_tick(_pos: Vector3, _normal: Vector3, target: Node, hit_enemy: bool) -> void:
	if not hit_enemy or not (target is Node3D) or not is_instance_valid(target):
		return
	var cage := target.get_node_or_null(CAGE_NAME) as Cage
	if cage == null:
		var data: WeaponData = weapon.get("data")
		cage = Cage.new()
		cage.name = CAGE_NAME
		cage.set_meta("sig_fx", "tesla_cage")
		cage.color = data.tracer_color if data else Color(0.45, 0.85, 1.0)
		target.add_child(cage)
	cage.charge()

## The electrocution cage on one robot. Measures the robot's visual bounds once,
## then each frame re-zaps its arcs between random points on those bounds.
class Cage extends Node3D:
	var color := Color(0.45, 0.85, 1.0)
	var arcs: Array[ArcBolt] = []
	var bounds := AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.8, 0.8)) ## in the robot's frame
	var since := 0.0 ## seconds since the last beam tick
	var _light: OmniLight3D = null

	func _ready() -> void:
		_measure()
		for i in TeslaFx.CAGE_ARCS:
			var b := ArcBolt.make(TeslaFx.CAGE_SEGS, TeslaFx.CAGE_WIDTH, color)
			add_child(b)
			arcs.append(b)
		if FXLights.take():
			_light = OmniLight3D.new()
			_light.light_color = color
			_light.omni_range = 3.0
			_light.position = bounds.get_center()
			add_child(_light)
			_light.tree_exited.connect(FXLights.give)
		_zap()

	## A beam tick landed: full strength again.
	func charge() -> void:
		since = 0.0

	## 1 while beamed, falling to 0 over RESIDUAL after the last tick.
	func strength() -> float:
		return clampf(1.0 - since / TeslaFx.RESIDUAL, 0.0, 1.0)

	func _process(delta: float) -> void:
		since += delta
		var k := strength()
		if k <= 0.0:
			queue_free()
			return
		_zap()
		# Fewer arcs as the charge bleeds off: all of them while beamed, one at the end.
		var live := maxi(1, int(ceil(TeslaFx.CAGE_ARCS * k)))
		for i in arcs.size():
			arcs[i].visible = i < live
			arcs[i].set_alpha(k * randf_range(0.6, 1.0))
		if _light:
			_light.light_energy = GraphicsSettings.flash_energy(3.0) * k * randf_range(0.4, 1.0)

	func _zap() -> void:
		for b in arcs:
			var a := to_global(_on_bounds())
			var c := to_global(_on_bounds())
			b.zap(a, c, 0.12)

	## A random point on the surface of the bounds box (a face, then a spot on it).
	func _on_bounds() -> Vector3:
		var p := bounds.position + Vector3(randf(), randf(), randf()) * bounds.size
		var axis := randi() % 3
		p[axis] = bounds.position[axis] + (bounds.size[axis] if randf() < 0.5 else 0.0)
		return p

	## The robot's merged visual bounds in its own frame (falls back to a 0.8 x
	## 1.8 m column when it has no meshes).
	func _measure() -> void:
		var host := get_parent() as Node3D
		if host == null:
			return
		var inv := host.global_transform.affine_inverse()
		var merged := AABB()
		var any := false
		for vi in host.find_children("*", "VisualInstance3D", true, false):
			if vi == self or is_ancestor_of(vi) or not (vi as VisualInstance3D).is_visible_in_tree():
				continue
			if vi is Light3D or vi is GPUParticles3D or vi is CPUParticles3D:
				continue
			var box := (vi as VisualInstance3D).get_aabb()
			if box.size.length() < 0.01:
				continue
			var local := inv * (vi as Node3D).global_transform * box
			merged = local if not any else merged.merge(local)
			any = true
		if any and merged.size.length() < 12.0:
			bounds = merged
