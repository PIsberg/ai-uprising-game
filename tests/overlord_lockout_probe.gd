extends Node
## Probe: OVERLORD LOCKOUT (AIDirector.lockout_update / is_jammed, Weapon.try_fire).
## Within one level, when the gun you are holding is the dominant gun AND it carries
## LOCKOUT_FOCUS (72%) of the level's shots (after calibration), the overlord jams it
## for LOCKOUT_JAM_SEC, at most LOCKOUT_MAX_PER_LEVEL times, with LOCKOUT_COOLDOWN
## between jams. A jammed gun will not fire; the trigger dry-clicks.
## (1) a calibrating level (under MIN_SAMPLES shots) never jams;
## (2) a gun at 83% focus that is held and dominant jams; other guns are unaffected;
## (3) the jam ends on its own after LOCKOUT_JAM_SEC and emits lockout_started once;
## (4) the cooldown holds off a second jam, then it fires again;
## (5) at most three jams per level, even with the gun still favoured;
## (6) a gun that is not the dominant one, or a spread-out loadout (<72%), never jams;
## (7) on a real Weapon: a jammed trigger fires nothing (no shot, no ammo spent) and the
##     same trigger fires once the jam has ended (so the gate is what blocked it).
##   godot --headless --path . --audio-driver Dummy res://tests/overlord_lockout_probe.tscn

const SHOTGUN := "SG-12 Breacher"
const RIFLE := "AR-7 Pulse Rifle"

var ok := true
var _started: Array = []

func _ready() -> void:
	AIDirector.lockout_started.connect(func(n: String) -> void: _started.append(n))
	_run.call_deferred()

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _shots(weapon: String, n: int) -> void:
	for i in n:
		AIDirector.note_shot(weapon)

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	AIDirector.persist = false
	AIDirector.forget_dossier(false)

	# (1) calibrating: 5 shots of one gun is not enough to read a habit.
	AIDirector.reset_profile()
	_shots(SHOTGUN, 5)
	AIDirector.lockout_update(0.0, SHOTGUN)
	_check("calibrating level never jams", not AIDirector.is_jammed(SHOTGUN) and _started.is_empty())

	# (2) 20 shotgun shots (100% focus) and the shotgun held: jam fires.
	AIDirector.reset_profile()
	_shots(SHOTGUN, 20)
	AIDirector.lockout_update(0.0, SHOTGUN)
	_check("held dominant gun at 72%+ focus jams", AIDirector.is_jammed(SHOTGUN), "started=%s" % str(_started))
	_check("the jam is for that gun only", not AIDirector.is_jammed(RIFLE))
	_check("lockout_started names the jammed gun once", _started == [SHOTGUN], str(_started))

	# (3) the jam expires after LOCKOUT_JAM_SEC.
	AIDirector.lockout_update(1.0, SHOTGUN)
	_check("still jammed part way through", AIDirector.is_jammed(SHOTGUN))
	AIDirector.lockout_update(0.6, SHOTGUN)
	_check("the jam ends on its own at 1.5 s", not AIDirector.is_jammed(SHOTGUN))

	# (4) cooldown: 20 s from the jam start. 1.6 s so far, so 15 s more is still cooling.
	AIDirector.lockout_update(15.0, SHOTGUN)
	_check("cooldown holds off a second jam", not AIDirector.is_jammed(SHOTGUN) and _started.size() == 1)
	AIDirector.lockout_update(4.0, SHOTGUN)
	_check("second jam once the cooldown is up", AIDirector.is_jammed(SHOTGUN) and _started.size() == 2,
		"started=%d" % _started.size())

	# (5) cap: three per level. Finish jam 2, then jam 3, then nothing more.
	AIDirector.lockout_update(2.0, SHOTGUN)
	AIDirector.lockout_update(25.0, SHOTGUN)
	_check("third jam of the level", AIDirector.is_jammed(SHOTGUN) and _started.size() == 3,
		"started=%d" % _started.size())
	AIDirector.lockout_update(2.0, SHOTGUN)
	AIDirector.lockout_update(60.0, SHOTGUN)
	_check("no fourth jam in one level", not AIDirector.is_jammed(SHOTGUN) and _started.size() == 3,
		"started=%d" % _started.size())

	# (6a) held gun is not the dominant one (20 shotgun vs 4 rifle = 83%, but the rifle is held).
	AIDirector.reset_profile()
	_started.clear()
	_shots(SHOTGUN, 20)
	_shots(RIFLE, 4)
	AIDirector.lockout_update(0.0, RIFLE)
	_check("a non-dominant held gun never jams", not AIDirector.is_jammed(RIFLE) and _started.is_empty())
	# (6b) spread out: 10 shotgun, 10 rifle = 50% focus, held shotgun.
	AIDirector.reset_profile()
	_started.clear()
	_shots(SHOTGUN, 10)
	_shots(RIFLE, 10)
	AIDirector.lockout_update(0.0, SHOTGUN)
	_check("a spread loadout (<72%) never jams", not AIDirector.is_jammed(SHOTGUN) and _started.is_empty())

	# (7) a real Weapon: the jam stops the trigger, and the same trigger fires once it ends.
	AIDirector.reset_profile()
	_started.clear()
	var pl: Node3D = load("res://scenes/player/player.tscn").instantiate()
	add_child(pl)
	await get_tree().process_frame
	await get_tree().process_frame
	var wm: Node = pl.get_node_or_null("Head/Camera3D/WeaponHolder")
	var cam := pl.get_node_or_null("Head/Camera3D") as Camera3D
	var w = wm.current if wm else null
	_check("probe player has a weapon", w != null and w.data != null)
	if w != null and w.data != null:
		var nm: String = w.data.display_name
		w.mag = maxi(w.mag, 8)
		w._cooldown = 0.0
		w._reloading = false
		var fired := [0]
		w.fired.connect(func(_x) -> void: fired[0] += 1)
		_shots(nm, 20)
		AIDirector.lockout_update(0.0, nm)
		var mag_before: int = w.mag
		w.try_fire(true, false, cam, pl)
		w._trigger_held_last = false
		_check("a jammed trigger fires nothing", fired[0] == 0 and w.mag == mag_before,
			"fired=%d mag=%d->%d" % [fired[0], mag_before, w.mag])
		AIDirector.lockout_update(2.0, nm)
		w._cooldown = 0.0
		w.try_fire(true, false, cam, pl)
		_check("the same trigger fires once the jam ends", fired[0] == 1, "fired=%d" % fired[0])
	pl.queue_free()
	await get_tree().process_frame

	AIDirector.reset_profile()
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
