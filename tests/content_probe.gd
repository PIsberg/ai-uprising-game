extends Node3D
## Headless probe for the late-game content pass: TEMPEST chain lightning,
## the VORTEX grenade (pull-in + detonate), and the hoppier SKITTER.
## Run: godot --headless res://tests/content_probe.tscn
## Expect: TEMPEST/VORTEX/SKITTER/WEAPON PASS.

const VORTEX := preload("res://scenes/weapons/grenade_vortex.tscn")
const TEMPEST_PROJ := preload("res://scenes/weapons/projectile_tempest.tscn")
const SKITTER := preload("res://scenes/enemies/skitter.tscn")
const RAVAGER := preload("res://scenes/enemies/ravager.tscn")
const TEMPEST_DATA := preload("res://assets/weapons/tempest_data.tres")

## A minimal enemy stand-in: a body on the enemy layer (so shape queries find it)
## with a Damageable child (so chain/splash can hurt it) — no AI, no model.
func _make_dummy(pos: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 0b0000100   # enemy layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1, 2, 1)
	cs.shape = sh
	b.add_child(cs)
	var d := Damageable.new()
	d.name = "Damageable"
	d.max_health = 1000.0
	b.add_child(d)
	add_child(b)
	b.global_position = pos
	return b

func _hp(b: Node) -> float:
	return (b.get_node("Damageable") as Damageable).current_health

func _ready() -> void:
	await get_tree().physics_frame
	var ok_all := true

	# --- TEMPEST: chain lightning should hurt several robots from one hit. ---
	var line: Array[StaticBody3D] = []
	for i in 5:
		line.append(_make_dummy(Vector3(0, 0, -float(i) * 3.0)))  # 3 m apart, within 11 m hops
	await get_tree().physics_frame
	await get_tree().physics_frame
	var proj := TEMPEST_PROJ.instantiate()
	add_child(proj)
	proj.global_position = Vector3(0, 0.5, 0)
	proj.launch(Vector3(0, 0, -1), self, 60.0, 2.8, 55.0)
	proj._explode(Vector3(0, 0.5, -0.2))
	await get_tree().physics_frame
	var hurt := 0
	for b in line:
		if _hp(b) < 1000.0:
			hurt += 1
	var tempest_ok := hurt >= 3
	print("TEMPEST hurt=%d/5  %s" % [hurt, "PASS" if tempest_ok else "FAIL"])
	ok_all = ok_all and tempest_ok

	# --- VORTEX: pull robots inward, then detonate the bunched pack. ---
	var center := Vector3(40, 0, 0)
	var ring: Array[StaticBody3D] = []
	for i in 4:
		var a := TAU * float(i) / 4.0
		ring.append(_make_dummy(center + Vector3(cos(a) * 6.0, 0, sin(a) * 6.0)))
	await get_tree().physics_frame
	var g := VORTEX.instantiate()
	add_child(g)
	g.global_position = center
	var d0: float = ring[0].global_position.distance_to(center)
	g._begin_implosion()
	for _i in 12:
		g._pull_enemies(0.05, 1.0)
	var d1: float = ring[0].global_position.distance_to(center)
	var pulled := d1 < d0 - 0.5
	await get_tree().physics_frame
	await get_tree().physics_frame
	g._detonate()
	await get_tree().physics_frame
	var vhurt := 0
	for b in ring:
		if _hp(b) < 1000.0:
			vhurt += 1
	var vortex_ok := pulled and vhurt == 4
	print("VORTEX pulled=%.1f→%.1f hurt=%d/4  %s" % [d0, d1, vhurt, "PASS" if vortex_ok else "FAIL"])
	ok_all = ok_all and vortex_ok

	# --- SKITTER: the hop tunables read as "bouncy bug", not "charger". ---
	var sk := SKITTER.instantiate()
	add_child(sk)
	await get_tree().physics_frame
	var skitter_ok: bool = sk.leap_cooldown <= 0.5 and sk.leap_min <= 1.5 \
		and sk.hop_side > 0.0 and sk.has_method("_launch_leap")
	print("SKITTER cd=%.2f min=%.1f side=%.1f  %s" % [sk.leap_cooldown, sk.leap_min, sk.hop_side, "PASS" if skitter_ok else "FAIL"])
	ok_all = ok_all and skitter_ok

	# --- RAVAGER: the new fierce heavy leaper builds and arms its slam. ---
	var rav := RAVAGER.instantiate()
	add_child(rav)
	await get_tree().physics_frame
	var ravager_ok: bool = is_instance_valid(rav) and rav.has_method("_slam") \
		and rav.max_health >= 200.0 and rav.slam_radius > 0.0 \
		and "ravager" in LevelBuilder.ENEMY_SCENES and EnemyCodex.has("ravager")
	print("RAVAGER hp=%.0f slam_r=%.1f registered=%s  %s" % [
		rav.max_health, rav.slam_radius,
		"ravager" in LevelBuilder.ENEMY_SCENES, "PASS" if ravager_ok else "FAIL"])
	ok_all = ok_all and ravager_ok

	# --- WEAPON: TEMPEST data wired to its chaining projectile. ---
	var weapon_ok: bool = TEMPEST_DATA.projectile_scene != null and TEMPEST_DATA.damage > 0.0 \
		and "res://scenes/weapons/tempest.tscn" in GameState.ALL_WEAPONS
	print("WEAPON data ok=%s in_arsenal=%s  %s" % [
		TEMPEST_DATA.projectile_scene != null,
		"res://scenes/weapons/tempest.tscn" in GameState.ALL_WEAPONS,
		"PASS" if weapon_ok else "FAIL"])
	ok_all = ok_all and weapon_ok

	print("CONTENT_PROBE ", "ALL PASS" if ok_all else "FAIL")
	get_tree().quit()
