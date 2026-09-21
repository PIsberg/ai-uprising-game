extends Node3D
## HIVE's model carries its character: a networked, shielded flanker wears an uplink
## mast (Blender fork quaternius_bot_hive.glb, tools/blender/cfg_bot_hive.json), and a
## beacon on the mast tip shows the network link - lit while networked, dead while a
## jam zone has cut the unit off. Asserts the fork is wired + still animates, the
## beacon rides the Head bone at the mast tip, and it follows the jam state.

const HIVE := preload("res://scenes/enemies/hive.tscn")
const ARMED := preload("res://assets/models/robots/quaternius_bot_armed.glb")

var _fails := 0

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1

func _mesh_top(root: Node) -> float:
	var top := 0.0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			top = maxf(top, m.mesh.get_aabb().end.y)
	return top

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)

	var hive := HIVE.instantiate() as Node3D
	add_child(hive)
	hive.global_position = Vector3(0, 0.1, 0)
	for i in 4:
		await get_tree().physics_frame

	# 1) The scene uses the uplink fork, and the fork really is taller than the plain
	#    armed bot it replaced (the mast), with its clips intact.
	var model := hive.get_node("Model/Mesh")
	var armed := ARMED.instantiate()
	var top_hive := _mesh_top(model)
	var top_armed := _mesh_top(armed)
	armed.free()
	print("mesh top: hive=%.2f armed=%.2f" % [top_hive, top_armed])
	_check(top_hive > top_armed + 0.3, "hive model carries a mast (top %.2f > armed %.2f + 0.3)" % [top_hive, top_armed])
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_check(ap != null, "fork kept its AnimationPlayer")
	for clip in ["CharacterArmature|Idle", "CharacterArmature|Run", "CharacterArmature|Shoot"]:
		_check(ap != null and ap.has_animation(clip), "fork kept clip %s" % clip)

	# 2) The link beacon exists, rides the Head bone, and sits at the mast tip.
	var beacon := hive.find_child("UplinkBeacon", true, false) as MeshInstance3D
	_check(beacon != null, "UplinkBeacon exists")
	if beacon == null:
		print("RESULT FAIL")
		get_tree().quit(1)
		return
	_check(beacon.get_parent() is BoneAttachment3D, "beacon rides a BoneAttachment3D (follows the animated mast)")
	var rel: Vector3 = beacon.global_position - hive.global_position
	print("beacon rel pos: %s" % rel)
	_check(rel.y > 1.9 and rel.y < 2.5, "beacon at mast-tip height (%.2f m)" % rel.y)
	_check(Vector2(rel.x, rel.z).length() < 0.8, "beacon over the chassis (%.2f m off-axis)" % Vector2(rel.x, rel.z).length())

	# The rig carries a large internal scale; a beacon that inherits it becomes a
	# screen-filling ball (caught in tests/hive_uplink_shot, not by position checks).
	var world_d: float = (beacon.global_transform.basis.get_scale() * beacon.mesh.get_aabb().size).x
	print("beacon world diameter: %.3f m" % world_d)
	_check(world_d > 0.03 and world_d < 0.2, "beacon is beacon-sized in the world (%.3f m)" % world_d)

	# 3) Networked: lit. Jammed: dead. Un-jammed: lit again.
	for i in 20:
		await get_tree().physics_frame
	var lit: float = hive.call("uplink_glow")
	_check(lit > 0.5, "networked: beacon lit (%.2f)" % lit)
	# What the renderer actually draws: the material is unshaded (emission is dropped
	# there), so the visible glow is its albedo.
	var bmat := beacon.mesh.surface_get_material(0) as StandardMaterial3D
	_check(bmat.albedo_color.v > 1.0, "networked: beacon material bright (v=%.2f)" % bmat.albedo_color.v)
	hive.enter_jam()
	for i in 40:
		await get_tree().physics_frame
	var cut: float = hive.call("uplink_glow")
	_check(cut < 0.1, "jammed: beacon dead (%.2f)" % cut)
	_check(bmat.albedo_color.v < 0.1, "jammed: beacon material dark (v=%.2f)" % bmat.albedo_color.v)
	hive.exit_jam()
	for i in 40:
		await get_tree().physics_frame
	var back: float = hive.call("uplink_glow")
	_check(back > 0.5, "un-jammed: beacon relit (%.2f)" % back)

	print("RESULT PASS" if _fails == 0 else "RESULT FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
