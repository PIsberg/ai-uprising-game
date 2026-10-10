extends Node
## Probe: the DIFFUSION robot noises out and denoises on a flank (enemy_diffusion.gd).
## (1) it is wired: level builder, codex, one on DESERT and one on FROSTBREAK;
## (2) diffuse_to: while it noises out and while it is a cloud it is off the
##     enemy layer and takes nothing (a rifle hitscan through it, direct damage);
##     the cloud is hidden-body + a static cloud in the level;
## (3) it denoises at the destination: on the layer again, HALF_FORMED_MULT
##     damage from the same hit, a DENOISING hologram;
## (4) once formed every surface has its own material back (no dissolve shader);
## (5) pick_destination flanks the target: off the side a wall blocks, with a
##     clear line to the target, at range;
## (6) live AI in a fight diffuses on its own and comes back on a flank;
## (7) killed mid-denoise, it dies with its own materials, not the noise.
##   godot --headless --path . --audio-driver Dummy res://tests/diffusion_probe.tscn

const SCENE := "res://scenes/enemies/diffusion.tscn"
const DISSOLVE := preload("res://shaders/dissolve.gdshader")
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
		if en.get("type", "") == "diffusion":
			n += 1
	return n

func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	add_child(b)
	b.global_position = pos
	return b

func _spawn(at: Vector3) -> EnemyDiffusion:
	var e: EnemyDiffusion = (load(SCENE) as PackedScene).instantiate()
	add_child(e)
	e.global_position = at
	return e

func _run() -> void:
	# 1. Wiring.
	_check("level builder knows diffusion", LevelBuilder.ENEMY_SCENES.get("diffusion", "") == SCENE)
	_check("codex entry", EnemyCodex.has("diffusion") and "diffusion" in EnemyCodex.ORDER)
	_check("one on DESERT", _count("desert") == 1, str(_count("desert")))
	_check("one on FROSTBREAK", _count("frostbreak") == 1, str(_count("frostbreak")))

	_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	# A body on the player layer: robots' sight rays must hit something.
	var player := StaticBody3D.new()
	player.collision_layer = 2
	player.collision_mask = 0
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	pcs.shape = cap
	pcs.position.y = 0.9
	player.add_child(pcs)
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(0, 0, 90) # out of sight: the AI stays idle
	var rifle: Weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
	add_child(rifle)
	rifle._active_shooter = player

	# 2-4. A scripted diffusion.
	var e := _spawn(Vector3.ZERO)
	await _frames(4)
	e.hp.max_health = 100000.0
	e.hp.current_health = 100000.0
	var base_layer := e.collision_layer
	var d0 := _hit(rifle, e)
	_check("formed: a rifle hit lands", d0 > 0.0, "%.1f" % d0)
	var dest := Vector3(9, 0, -4)
	_check("diffuse_to starts", e.diffuse_to(dest))
	await _frames(3)
	_check("noising: off the enemy layer", e.collision_layer == 0 and e.is_intangible())
	_check("noising: rifle passes through", _hit(rifle, e) == 0.0)
	_check("noising: hologram adds noise", "NOISE" in e.status_text(), e.status_text())
	var h := e.hp.current_health
	e.hp.apply_damage(40.0, player, false, e.global_position + Vector3.UP)
	_check("noising: direct damage ignored", e.hp.current_health == h)
	await _frames(int(EnemyDiffusion.NOISE_TIME * 60.0) + 4)
	_check("cloud: body hidden", e.phase == EnemyDiffusion.Phase.CLOUD and not e.visible, str(e.phase))
	_check("cloud: a static cloud is in the level", is_instance_valid(e.cloud) and e.cloud.get_parent() == self)
	e.hp.apply_damage(40.0, player, false, e.global_position + Vector3.UP)
	_check("cloud: direct damage ignored", e.hp.current_health == h)
	await _frames(int(EnemyDiffusion.CLOUD_TIME * 60.0) + 4)
	_check("denoising at the destination", e.phase == EnemyDiffusion.Phase.DENOISING
			and Vector2(e.global_position.x - dest.x, e.global_position.z - dest.z).length() < 0.3,
			"%s at %s" % [e.phase, e.global_position])
	_check("denoising: visible, back on the layer", e.visible and e.collision_layer == base_layer)
	_check("denoising: hologram counts steps", "DENOISING" in e.status_text(), e.status_text())
	_check("denoising: still wearing the noise", _noise_surfaces(e) > 0, str(_noise_surfaces(e)))
	var dh := _hit(rifle, e)
	_check("half-formed: x HALF_FORMED_MULT", is_equal_approx(dh, d0 * EnemyDiffusion.HALF_FORMED_MULT),
			"%.1f vs %.1f" % [dh, d0 * EnemyDiffusion.HALF_FORMED_MULT])
	await _frames(int(EnemyDiffusion.DENOISE_TIME * 60.0) + 4)
	_check("formed again", e.phase == EnemyDiffusion.Phase.NONE and not e.is_intangible())
	_check("formed: no surface keeps the noise", _noise_surfaces(e) == 0, str(_noise_surfaces(e)))
	_check("formed: hologram cleared", e.status_text() == "", e.status_text())
	_check("formed: full damage again", is_equal_approx(_hit(rifle, e), d0))
	e.queue_free()
	await _frames(2)

	# 5. Flank picking: a wall shuts the +x side of the target.
	var around := Vector3(0, 0, 30)
	var wall := _box(around + Vector3(5, 2, 0), Vector3(1, 4, 30))
	var f := _spawn(around + Vector3(0, 0, -12))
	await _frames(3)
	var picks_ok := true
	var picked := 0
	for i in 12:
		var p := f.pick_destination(around)
		if p == Vector3.INF:
			continue
		picked += 1
		var flat := Vector2(p.x - around.x, p.z - around.z)
		if p.x > around.x or flat.length() < 6.0 or flat.length() > 17.0:
			picks_ok = false
			print("  bad pick ", p)
	_check("flank picks found", picked >= 10, "%d/12" % picked)
	_check("flanks avoid the walled side, at range", picks_ok)
	f.queue_free()
	wall.queue_free()
	await _frames(2)

	# 6. Live AI diffuses on its own.
	player.global_position = Vector3(0, 0, 0)
	var g := _spawn(Vector3(0, 0, -12))
	g.rotation.y = PI # facing the player
	await _frames(3)
	g.hp.max_health = 100000.0
	g.hp.current_health = 100000.0
	var start_ang := _bearing(g.global_position, player.global_position)
	var saw := false
	var frames := 0
	while frames < int((EnemyDiffusion.DIFFUSE_EVERY * 1.3 + 3.0) * 60.0):
		await get_tree().physics_frame
		frames += 1
		if g.phase != EnemyDiffusion.Phase.NONE:
			saw = true
		elif saw:
			break
	var turned := absf(angle_difference(start_ang, _bearing(g.global_position, player.global_position)))
	_check("in a fight it diffuses by itself", saw, "%d frames" % frames)
	_check("and comes back on a flank", saw and g.phase == EnemyDiffusion.Phase.NONE and turned > deg_to_rad(40.0),
			"%.0f deg round the player" % rad_to_deg(turned))
	g.queue_free()
	player.global_position = Vector3(0, 0, 90)
	await _frames(2)

	# 7. Killed mid-denoise.
	var k := _spawn(Vector3(0, 0, 40))
	await _frames(3)
	k.diffuse_to(Vector3(4, 0, 40))
	await _frames(int((EnemyDiffusion.NOISE_TIME + EnemyDiffusion.CLOUD_TIME) * 60.0) + 10)
	_check("kill target is denoising", k.phase == EnemyDiffusion.Phase.DENOISING, str(k.phase))
	k.hp.apply_damage(100000.0, player, false, k.global_position + Vector3.UP)
	_check("dies wearing its own materials", not k.hp.is_alive() and _noise_surfaces(k) == 0,
			str(_noise_surfaces(k)))

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## One rifle hitscan from 10 m in front of the body; returns the damage it did.
func _hit(w: Weapon, e: EnemyDiffusion) -> float:
	var at := e.global_position + Vector3.UP * 0.8
	var h := e.hp.current_health
	w._do_hitscan(at + Vector3(0, 0, 10), Vector3(0, 0, -1))
	return h - e.hp.current_health

func _bearing(p: Vector3, around: Vector3) -> float:
	return atan2(p.x - around.x, p.z - around.z)

## Surfaces still drawn with the dissolve shader.
func _noise_surfaces(e: Node) -> int:
	var n := 0
	for c in e.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m and m.shader == DISSOLVE:
				n += 1
	return n
