class_name KillSplatter
extends Control
## Screen-space robot-oil splatter for point-blank kills: a burst of dark
## droplets hits the "camera lens", drips a little, and fades. The classic
## arcade-shooter payoff for getting your hands dirty — gated to genuinely
## close kills by the HUD so ranged play never smears the screen.
##
## Everything is drawn procedurally (no textures): each splash is a handful of
## squashed circles with per-blob drip speed. Alpha scales with the Flash
## Intensity accessibility slider, so photosensitive players who dimmed the
## screen flashes dim this too (0 disables it outright).

var _blobs: Array[Dictionary] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Throw a fresh splash on the lens. strength ~1 for a normal close kill;
## the HUD passes a touch more for executions/crits.
func splash(strength: float = 1.0) -> void:
	var vp := get_viewport_rect().size
	for _i in 3 + randi() % 3:
		_blobs.append({
			"pos": vp * 0.5 + Vector2(randf_range(-0.32, 0.32) * vp.x, randf_range(-0.30, 0.22) * vp.y),
			"r": randf_range(14.0, 42.0) * strength,
			"a": randf_range(0.4, 0.65),
			"vy": randf_range(14.0, 55.0), # drip: heavier blobs slide down the glass
			"squash": randf_range(0.75, 1.35),
		})
	# Hard cap so a melee rampage can't accumulate an opaque screen.
	while _blobs.size() > 24:
		_blobs.pop_front()
	queue_redraw()

func _process(delta: float) -> void:
	if _blobs.is_empty():
		return
	for b in _blobs:
		b["a"] = float(b["a"]) - delta * 0.55
		b["pos"] = (b["pos"] as Vector2) + Vector2(0.0, float(b["vy"]) * delta)
		b["vy"] = float(b["vy"]) * maxf(0.0, 1.0 - 1.6 * delta) # drips slow as they dry
	_blobs = _blobs.filter(func(b) -> bool: return float(b["a"]) > 0.0)
	queue_redraw()

func _draw() -> void:
	var tint: float = GraphicsSettings.flash_intensity
	if tint <= 0.001:
		return
	for b in _blobs:
		var col := Color(0.07, 0.08, 0.07, clampf(float(b["a"]), 0.0, 1.0) * 0.75 * tint)
		draw_set_transform(b["pos"], 0.0, Vector2(1.0, float(b["squash"])))
		draw_circle(Vector2.ZERO, float(b["r"]), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
