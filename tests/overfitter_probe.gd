extends Node
## Probe: the OVERFITTER learns the gun that keeps hurting it (enemy_overfitter.gd).
## (1) it is wired: level builder, codex, one on GEMINI and two on UPLINK;
## (2) a weapon hit carries its WeaponData on the victim's Damageable only for
##     the duration of the hit (KillFx.tag/untag);
## (3) hits from one gun train it: full damage until FIT_DAMAGE of that gun has
##     landed, then it is OVERFIT and the same gun deals FIT_MULT of a hit;
##     the shell lights and the hologram names the gun;
## (4) a different gun is out of distribution: OOD_MULT damage for OOD_TIME,
##     the shell drops, and it cannot learn until the window closes;
## (5) untagged damage (grenades, hazards) is neither resisted nor trained on;
## (6) once the OOD window closes the new gun is back to full damage.
##   godot --headless --path . --audio-driver Dummy res://tests/overfitter_probe.tscn

const SCENE := "res://scenes/enemies/overfitter.tscn"
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
		if en.get("type", "") == "overfitter":
			n += 1
	return n

func _run() -> void:
	# 1. Wiring.
	_check("level builder knows overfitter", LevelBuilder.ENEMY_SCENES.get("overfitter", "") == SCENE)
	_check("codex entry", EnemyCodex.has("overfitter") and "overfitter" in EnemyCodex.ORDER)
	_check("one on GEMINI", _count("gemini") == 1, str(_count("gemini")))
	_check("two on UPLINK", _count("uplink") == 2, str(_count("uplink")))

	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(200, 1, 200)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var shooter := Node3D.new()
	shooter.add_to_group("player")
	add_child(shooter)
	shooter.global_position = Vector3(0, 1.5, 40)

	var rifle := _gun("rifle", shooter)
	var pistol := _gun("pistol", shooter)
	var e: EnemyOverfitter = (load(SCENE) as PackedScene).instantiate()
	e.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	e.process_mode = Node.PROCESS_MODE_DISABLED # AI off: it must not walk out of the line of fire
	add_child(e)
	e.global_position = Vector3.ZERO
	await _frames(3)
	e.hp.max_health = 100000.0
	e.hp.current_health = 100000.0
	var at := e.global_position + Vector3.UP * 0.7 # the body, under the head-crit band

	# 2. The weapon rides on the hit, and only on the hit.
	var seen: Array = []
	e.hp.damaged.connect(func(_a: float, _s: Node) -> void: seen.append(e.hp.hit_weapon))
	var d0 := _hit(rifle, at)
	_check("hit tagged with the rifle", seen.size() == 1 and seen[0] == rifle.data)
	_check("tag cleared after the hit", e.hp.hit_weapon == null)
	_check("first rifle hit: full damage", d0 > 0.0, "%.1f" % d0)
	_check("training on the rifle", e.fit_weapon == rifle.data and not e.overfit)

	# 3. Train it until it overfits.
	var landed := d0
	var shots := 1
	while not e.overfit and shots < 60:
		var d := _hit(rifle, at)
		if shots < 3:
			_check("full damage while training", is_equal_approx(d, d0), "%.1f vs %.1f" % [d, d0])
		landed += d
		shots += 1
	_check("overfit after FIT_DAMAGE of rifle", e.overfit and landed >= EnemyOverfitter.FIT_DAMAGE
			and landed < EnemyOverfitter.FIT_DAMAGE + d0 + 0.01, "%d shots, %.0f dmg" % [shots, landed])
	var d_fit := _hit(rifle, at)
	_check("overfit: rifle deals FIT_MULT", is_equal_approx(d_fit, d0 * EnemyOverfitter.FIT_MULT),
			"%.2f vs %.2f" % [d_fit, d0 * EnemyOverfitter.FIT_MULT])
	_check("overfit: shell visible", e.shell_visible())
	_check("overfit: hologram names the rifle", rifle.data.display_name.to_upper() in e.status_text(),
			e.status_text())

	# 4. Switch guns: out of distribution.
	var d_ood := _hit(pistol, at)
	_check("overfit broken, shell down", not e.overfit and not e.shell_visible())
	_check("now on the pistol, learning nothing yet", e.fit_weapon == pistol.data and e.fit_damage == 0.0)
	_check("hologram says OUT OF DISTRIBUTION", "OUT OF DISTRIBUTION" in e.status_text(), e.status_text())
	var d_ood2 := _hit(pistol, at)
	_check("OOD window: second pistol hit as boosted as the first", is_equal_approx(d_ood2, d_ood))
	var d_rifle_back := _hit(rifle, at)
	_check("rifle forgotten: back to full damage (x OOD)", is_equal_approx(d_rifle_back, d0 * EnemyOverfitter.OOD_MULT),
			"%.2f" % d_rifle_back)

	# 5. Untagged damage.
	var fw: WeaponData = e.fit_weapon
	var trained: float = e.fit_damage
	var h := e.hp.current_health
	e.hp.apply_damage(50.0, shooter, false, at)
	_check("untagged damage: not resisted (boosted inside the OOD window)",
			is_equal_approx(h - e.hp.current_health, 50.0 * EnemyOverfitter.OOD_MULT), "%.1f" % (h - e.hp.current_health))
	_check("untagged damage does not train it", e.fit_weapon == fw and is_equal_approx(e.fit_damage, trained))

	# 6. The window closes.
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.set_physics_process(false) # tick the window, not the AI
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(EnemyOverfitter.OOD_TIME * 1000.0) + 300:
		await get_tree().process_frame
	e.process_mode = Node.PROCESS_MODE_DISABLED
	var d_after := _hit(pistol, at)
	_check("pistol was OOD_MULT inside the window, full after it",
			d_after > 0.0 and is_equal_approx(d_ood, d_after * EnemyOverfitter.OOD_MULT),
			"%.2f in window, %.2f after" % [d_ood, d_after])
	_check("OOD window over", not e.out_of_distribution())

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## One hitscan from 10 m in front of the body; returns the damage it did.
func _hit(w: Weapon, at: Vector3) -> float:
	var e := get_children().filter(func(c: Node) -> bool: return c is EnemyOverfitter)[0] as EnemyOverfitter
	var h := e.hp.current_health
	w._do_hitscan(at + Vector3(0, 0, 10), Vector3(0, 0, -1))
	return h - e.hp.current_health

func _body_centre(e: Node3D) -> Vector3:
	for c in e.find_children("*", "CollisionShape3D", true, false):
		return (c as Node3D).global_position
	return e.global_position + Vector3.UP

func _gun(id: String, shooter: Node) -> Weapon:
	var w: Weapon = (load("res://scenes/weapons/%s.tscn" % id) as PackedScene).instantiate()
	add_child(w)
	w._active_shooter = shooter
	return w
