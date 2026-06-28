extends Node3D
## Verify the "god" cheat: typing g-o-d toggles invincibility and a god-mode
## player survives lethal damage.
##   godot --headless --path . res://tests/god_cheat_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var p: Node = load("res://scenes/player/player.tscn").instantiate()
	add_child(p)
	await get_tree().process_frame
	var hp = p.get("hp")
	var before_inv: bool = hp.invulnerable
	# Type "god".
	for ch in "god":
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.unicode = ch.unicode_at(0)
		p._input(ev)
	var on_inv: bool = hp.invulnerable
	var god_on: bool = p.get("_god")
	# Lethal hit while god is on — should be ignored.
	hp.apply_damage(99999.0, null)
	var survived: bool = hp.current_health > 0.0
	# Type "god" again to toggle off.
	for ch in "god":
		var ev2 := InputEventKey.new()
		ev2.pressed = true
		ev2.unicode = ch.unicode_at(0)
		p._input(ev2)
	var off_inv: bool = hp.invulnerable
	print("before_inv=%s  god_on=%s  on_inv=%s  survived_lethal=%s  off_inv=%s"
		% [before_inv, god_on, on_inv, survived, off_inv])
	var ok := not before_inv and god_on and on_inv and survived and not off_inv
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
