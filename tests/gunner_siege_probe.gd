extends Node3D
## GUNNER's model carries its way of fighting: it plants and suppresses, so the Blender
## fork (quaternius_gunner_siege.glb, tools/blender/cfg_gunner_siege.json) gives it recoil
## spades, a gun shield, an ammo drum and a rotary-cannon mount, and Godot hangs a real
## barrel cluster on the Gun bone that spins up BEFORE the first round (the telegraph)
## and glows hotter with every round of the burst. Asserts the fork is wired + still
## animates, the rotor is the right size and place, the chassis sits on its hitbox, and
## spin/heat follow the attack.

const GUNNER := preload("res://scenes/enemies/gunner.tscn")
const ARMED := preload("res://assets/models/robots/quaternius_gunner_armed.glb")

var _fails := 0

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1

func _mesh_depth(root: Node) -> float:
	var w := 0.0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			w = maxf(w, m.mesh.get_aabb().size.z)
	return w

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)

	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	pcs.shape = cap
	player.add_child(pcs)
	add_child(player)
	player.global_position = Vector3(0, 0.9, -20)

	var g := GUNNER.instantiate() as Node3D
	add_child(g)
	g.global_position = Vector3(0, 0.1, 0)
	await _frames(4)

	# 1) The scene uses the siege fork: deeper than the armed bot it replaced (the
	#    rotary mount's cradle reaches out past the old static barrels), clips intact.
	var model := g.get_node("Model/Mesh")
	var armed := ARMED.instantiate()
	var w_siege := _mesh_depth(model)
	var w_armed := _mesh_depth(armed)
	armed.free()
	_check(w_siege > w_armed + 0.1, "siege model carries the rotary mount (depth %.2f > armed %.2f + 0.1)" % [w_siege, w_armed])
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_check(ap != null, "fork kept its AnimationPlayer")
	for clip in ["CharacterArmature|Idle", "CharacterArmature|Run", "CharacterArmature|Shoot"]:
		_check(ap != null and ap.has_animation(clip), "fork kept clip %s" % clip)

	# 2) The chassis stands on its hitbox. The Quaternius gunner is authored ~0.5 units
	#    ahead of its origin, so un-offset the visible body stood a metre in front of the
	#    box the player's shots actually hit.
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var body_w: Vector3 = (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Body"))).origin
	var col_w: Vector3 = (g.get_node("CollisionShape3D") as Node3D).global_position
	var off := Vector2(body_w.x - col_w.x, body_w.z - col_w.z).length()
	_check(off < 0.35, "visible body sits on the hitbox (%.2f m off)" % off)

	# 3) The rotor exists, rides the Gun bone, is rotor-sized, and points where it aims.
	var rotor := g.find_child("BarrelRotor", true, false) as Node3D
	_check(rotor != null, "BarrelRotor exists")
	if rotor == null:
		print("RESULT FAIL")
		get_tree().quit(1)
		return
	_check(rotor.get_parent() is BoneAttachment3D, "rotor rides a BoneAttachment3D (follows the animated gun)")
	var barrel := rotor.find_child("Barrel0", true, false) as MeshInstance3D
	var world_len: float = (barrel.global_transform.basis.get_scale() * barrel.mesh.get_aabb().size).y
	print("barrel world length: %.3f m" % world_len)
	_check(world_len > 0.5 and world_len < 1.0, "barrels are barrel-sized in the world (%.3f m)" % world_len)
	var fwd: Vector3 = -g.global_transform.basis.z
	var axis: Vector3 = rotor.global_transform.basis.z.normalized()
	_check(absf(axis.dot(fwd)) > 0.9, "rotor axis lies along the aim line (dot %.2f)" % axis.dot(fwd))
	var rel: Vector3 = rotor.global_position - g.global_position
	print("rotor rel pos: %s" % rel)
	_check(rel.y > 2.0 and rel.y < 2.7, "rotor at gun height (%.2f m)" % rel.y)
	_check(rel.dot(fwd) > 1.0 and rel.dot(fwd) < 2.2, "rotor ahead of the gun face (%.2f m)" % rel.dot(fwd))
	var muzzle := g.get_node("Muzzle") as Node3D
	var mz: Vector3 = muzzle.global_position - rotor.global_position
	_check(mz.length() < 0.6, "rounds leave from the barrels (muzzle %.2f m from rotor)" % mz.length())

	# 4) Cold and still at rest; spins up during the windup BEFORE any round is out;
	#    heats through the burst; cools in the reset window.
	_check(float(g.call("rotor_spin")) == 0.0, "idle: rotor still")
	_check(float(g.call("barrel_heat")) == 0.0, "idle: barrels cold")
	g.set("target", player)
	g.call("_perform_attack")
	var windup_frames := int(float(g.get("windup")) * Engine.physics_ticks_per_second)
	await _frames(maxi(2, windup_frames - 6))
	var spin_tele: float = g.call("rotor_spin")
	var heat_tele: float = g.call("barrel_heat")
	_check(spin_tele > 5.0, "windup: rotor already spinning (%.1f rad/s)" % spin_tele)
	_check(heat_tele == 0.0, "windup: no round fired yet (heat %.2f)" % heat_tele)
	var burst_frames := int(float(g.get("burst_count")) * float(g.get("burst_interval")) * Engine.physics_ticks_per_second)
	await _frames(burst_frames + 8)
	var heat_hot: float = g.call("barrel_heat")
	_check(heat_hot > 0.6, "after the burst: barrels hot (%.2f)" % heat_hot)
	var mat := barrel.mesh.surface_get_material(0) as StandardMaterial3D
	_check(mat.emission_enabled and mat.emission_energy_multiplier > 1.0, "hot barrels actually glow (emission x%.2f)" % mat.emission_energy_multiplier)
	# Take the target away so its own AI cannot start the next burst mid-measurement;
	# 1.3 s is the real gap between bursts (attack_cooldown minus windup + burst).
	player.queue_free()
	g.set("target", null)
	await _frames(int(1.3 * Engine.physics_ticks_per_second))
	var heat_cool: float = g.call("barrel_heat")
	var spin_rest: float = g.call("rotor_spin")
	_check(heat_cool < 0.2, "reset window: barrels cooled (%.2f)" % heat_cool)
	_check(spin_rest < 1.0, "reset window: rotor spun down (%.1f rad/s)" % spin_rest)

	print("RESULT PASS" if _fails == 0 else "RESULT FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
