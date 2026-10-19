extends Node3D
## Probe: every hazard that can kill the player names itself on the death screen.
## Only lava/flood and robots did: the other hazards passed themselves as the damage
## source with no _kill_label(), so the recap read "K.I.A." with a generic tip (seen
## as killers=["", ""] on guardrails in tests/uprising_playtest).
## For each hazard script: a real player on a floor is killed with the hazard as the
## source; GameState.last_killer must be non-empty, match a hud.gd DEATH_TIPS key,
## and that tip must have a German row. A grenade the player threw (source = the
## player) reads as the player's own blast.
##   godot --headless --path . --audio-driver Dummy res://tests/hazard_kill_label_probe.tscn

const PLAYER := "res://scenes/player/player.tscn"
const HAZARDS := ["behaviour_clone", "escape_zone", "firewall_barrier", "fire_vent", "floor_saw",
	"generative_zone", "honeypot_cache", "laser_gate", "laser_sweep", "orbital_strike",
	"pendulum_blade", "sentry_turret", "shock_floor", "stamp_press", "destructible"]

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _floor() -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	add_child(sb)

## Kill a fresh player with `source` and return the killer the death screen shows.
func _killer_for(source: Node) -> String:
	var p: Node3D = (load(PLAYER) as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector3(0, 1, 0)
	await _frames(2)
	GameState.last_killer = "?"
	var hp: Damageable = p.get("hp")
	hp.apply_damage(99999.0, p if source == null else source, false, null, true)
	await _frames(2)
	var k := GameState.last_killer
	p.queue_free()
	await _frames(2)
	return k

func _tip_for(killer: String) -> String:
	var tips: Dictionary = (load("res://scripts/ui/hud.gd") as GDScript).get_script_constant_map()["DEATH_TIPS"]
	for key in tips:
		if killer.contains(key):
			return String(tips[key])
	return ""

func _run() -> void:
	_floor()
	var prev := TranslationServer.get_locale()
	for h in HAZARDS:
		var node: Node = (load("res://scripts/systems/%s.gd" % h) as GDScript).new()
		var killer := await _killer_for(node)
		var tip := _tip_for(killer)
		TranslationServer.set_locale("de")
		var german := tip != "" and TranslationServer.translate(tip) != tip
		TranslationServer.set_locale(prev)
		_check("%s names itself, with a translated tip" % h, killer != "" and tip != "" and german, "killer=%s tip=%s" % [killer, tip.left(40)])
		node.free()
	var own := await _killer_for(null)
	_check("your own blast names you", own != "" and _tip_for(own) != "", "killer=%s" % own)
	GameState.set_state(GameState.State.MENU)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
