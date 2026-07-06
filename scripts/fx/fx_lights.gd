class_name FXLights
extends Object
## Global budget for short-lived COMBAT FX lights — bullet-hit pops, muzzle
## flashes, energy-bolt end blooms. Profiling sustained rifle fire on a cluster
## of 8 enemies measured ~34 transient lights live at once, DOUBLING the scene's
## light count (31 static -> 65); a shotgun (6 pellets/shot) or the beam weapons
## push it higher. Godot's clustered forward+ renderer pays per-pixel for every
## live light, so this spikes exactly when the screen is busiest — a prime source
## of combat-only frame drops, especially at 4K.
##
## Each transient FX light calls take() before it spawns: over budget, it's
## skipped and the caller keeps only its self-lit emissive mesh (the orb/flash
## still glows — only the SPILL onto nearby surfaces is dropped, which reads as
## near-identical in the middle of a firefight). give() is called when the light
## leaves the tree (wire it to the light's tree_exited). The budget scales with
## the quality tier so low-end machines — which feel this most — cap tighter.

static var _live: int = 0

static func _budget() -> int:
	match int(GraphicsSettings.quality):
		0: return 8    # LOW
		1: return 12   # MEDIUM
		3: return 24   # ULTRA
		_: return 18   # HIGH

## Reserve one FX-light slot. Returns false when the budget is full — the caller
## should then skip creating the light (but keep its emissive mesh).
static func take() -> bool:
	if _live >= _budget():
		return false
	_live += 1
	return true

## Release a slot. Safe to over-call (clamped at 0). Wire to the light's
## tree_exited so a freed/queue_free'd FX light always returns its slot.
static func give() -> void:
	_live = maxi(0, _live - 1)
