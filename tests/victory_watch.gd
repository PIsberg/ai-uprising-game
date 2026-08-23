extends Node
## Watcher for tests/victory_probe, parented directly under /root so it survives
## the change_scene calls that free the probe's own scene root (see tests/README
## -> probe-writing rules). Polls current_scene and records every distinct scene
## the campaign-end handoff passes through.

const TIMEOUT := 25.0

var _seen: PackedStringArray = []
var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta
	var cur := get_tree().current_scene
	if cur:
		var s: Variant = cur.get_script()
		var id: String = (str(s.resource_path).get_file() if s else cur.get_class())
		if _seen.is_empty() or _seen[_seen.size() - 1] != id:
			_seen.append(id)
		if id == "victory_cutscene.gd":
			_finish(true)
			return
	if _t >= TIMEOUT:
		_finish(false)

func _finish(ok: bool) -> void:
	set_process(false)
	print("SCENE CHAIN: ", " -> ".join(_seen))
	print("elapsed=%.1fs" % _t)
	# The handoff must go THROUGH the loading screen: building the cutscene's 3D
	# dawn set synchronously froze the main thread on a black frame, so
	# GameState.advance_level routes it like every other scene change. Landing on
	# the cutscene without that hop would be the freeze regressing.
	var via_loader := "loading_screen.gd" in _seen
	if not via_loader:
		print("FAIL campaign end did not route through the loading screen")
	elif not ok:
		print("FAIL never reached the victory cutscene within %.0fs" % TIMEOUT)
	else:
		print("PASS campaign end -> loading screen -> victory cutscene")
	print("RESULT %s" % ("PASS" if (ok and via_loader) else "FAIL"))
	get_tree().quit(0 if (ok and via_loader) else 1)
