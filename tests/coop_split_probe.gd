extends Node
## Probe: co-op split screen, stage 3 of local co-op (#402). With co-op input on,
## a built level:
## (1) spawns player two beside player one (1.6 m to the right, index 1);
## (2) splits the screen: two SubViewports sharing the level's world, each with a
##     current camera that follows its player's view, and the root viewport's own
##     3D render turned off (it would draw a third, full-screen view);
## (3) puts player one's HUD in the left half and a CoopHud bound to player two
##     in the right half;
## (4) routes each player's own CanvasLayers (post FX, uplink and breach HUDs) to
##     that player's half, re-checked as new ones appear;
## (5) puts each player's gun viewmodel on that player's render layer, which the
##     other camera does not draw, and gives each player an avatar only the OTHER
##     camera draws;
## (6) solo play (co-op off) builds no split and leaves the root rendering 3D.
##   godot --headless --path . --audio-driver Dummy res://tests/coop_split_probe.tscn

const LEVEL := "res://scenes/levels/level_gpt.tscn"
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

func _run() -> void:
	# 6 first: solo builds no split.
	PlayerInput.reset_coop()
	var solo: Node = (load(LEVEL) as PackedScene).instantiate()
	add_child(solo)
	await _frames(20)
	_check("solo: one player", GameState.players().size() == 1)
	_check("solo: no split screen", solo.find_children("*", "SplitScreen", true, false).is_empty() and _split(solo) == null)
	_check("solo: the root viewport renders 3D", not get_viewport().disable_3d)
	solo.queue_free()
	await _frames(5)

	PlayerInput.setup_coop(0, 1)
	var lvl: Node = (load(LEVEL) as PackedScene).instantiate()
	add_child(lvl)
	await _frames(20)
	var ps := GameState.players()
	_check("co-op: two players", ps.size() == 2, str(ps.size()))
	if ps.size() < 2:
		_finish()
		return
	var p1: Node3D = ps[0]
	var p2: Node3D = ps[1]
	_check("player two is index 1", int(p2.get("player_index")) == 1)
	var gap := p1.global_position.distance_to(p2.global_position)
	_check("player two spawns beside player one", gap > 1.0 and gap < 2.5, "%.2f m" % gap)

	var split := _split(lvl)
	_check("co-op: a split screen is built", split != null)
	if split == null:
		_finish()
		return
	var vps: Array = split.get("viewports")
	var cams: Array = split.get("cameras")
	_check("two viewports", vps.size() == 2 and cams.size() == 2)
	_check("they share the level's world", vps.size() == 2 and vps[0].world_3d == get_viewport().world_3d and vps[1].world_3d == get_viewport().world_3d)
	_check("each has a current camera", cams.size() == 2 and cams[0].is_current() and cams[1].is_current() and cams[0].get_viewport() == vps[0] and cams[1].get_viewport() == vps[1])
	_check("the root viewport's 3D render is off", get_viewport().disable_3d)

	# 2. The cameras follow their players.
	p2.rotation.y += 1.0
	await _frames(3)
	# The halves follow in _process, after everything else (process_priority), so
	# each frame renders the view as it ended. A probe resumes mid-frame (the
	# process_frame signal comes before _process), so check the order and the
	# copy separately rather than racing the frame.
	for p in ps:
		_check("the halves follow after player %d moves" % (int(p.get("player_index")) + 1), split.process_priority > p.process_priority)
	split.call("_follow")
	for i in 2:
		var src: Camera3D = ps[i].get("camera")
		var d: float = cams[i].global_position.distance_to(src.global_position)
		var a: float = rad_to_deg((-cams[i].global_basis.z).angle_to(-src.global_basis.z))
		_check("camera %d follows player %d's view" % [i + 1, i + 1], d < 0.01 and a < 0.5, "%.3f m, %.2f deg" % [d, a])

	# 3. HUDs.
	var hud := lvl.find_child("HUD", true, false)
	_check("player one's HUD is in the left half", hud != null and vps[0].is_ancestor_of(hud))
	var chud: Node = null
	for n in vps[1].get_children():
		if n is CoopHud:
			chud = n
	_check("player two has a CoopHud in the right half", chud != null)
	_check("the CoopHud is bound to player two", chud != null and chud.get("player") == p2)
	# Player one's HUD fits its half even with a long objectives line (#418: the
	# unwrapped line set the layout's minimum width past the half, pushing the
	# health bar off its left edge).
	if hud:
		var obj := hud.get_node_or_null("Margin/Layout/Top/ObjectiveLabel") as Label
		if obj:
			obj.text = "  ".join(PackedStringArray(["◇ Exfiltrate the weight fragments (0/4)", "◇ FOUNDRY OVERLOAD: survive the purge protocol", "★ BONUS: no damage taken", "▢ Hack the terminal"])).repeat(2)
		await _frames(4)
		var half: Rect2 = vps[0].get_visible_rect()
		var margin := hud.get_node("Margin") as Control
		var hb := hud.get_node("Margin/Layout/BottomLeft/HealthRow/HealthBar") as Control
		_check("player one's HUD fits the left half", margin.get_global_rect().position.x >= -0.5 and margin.get_global_rect().end.x <= half.size.x + 0.5,
			"layout %s in a %s half" % [margin.get_global_rect(), half.size])
		var score := hud.get_node("Margin/Layout/Top/ScoreLabel") as Control
		var radar := hud.get_node_or_null("Radar") as Control
		_check("the objectives and score stay clear of the radar", radar != null
				and not obj.get_global_rect().intersects(radar.get_global_rect())
				and not score.get_global_rect().intersects(radar.get_global_rect()),
			"objectives %s score %s radar %s" % [obj.get_global_rect(), score.get_global_rect(), radar.get_global_rect() if radar else "none"])
		_check("player one's health bar is inside the half", hb.get_global_rect().position.x >= 0.0 and hb.get_global_rect().end.x <= half.size.x,
			str(hb.get_global_rect()))

	# 4. Per-player canvas layers.
	var postfx := p2.get_node_or_null("PostFX") as CanvasLayer
	_check("player two's post FX draws in the right half", postfx != null and postfx.custom_viewport == vps[1])
	# A full-rect control under a routed layer is laid out against the HALF, not
	# the window (#422: the breach meter, centred on the window, sat on the half's
	# right edge, and a centred vignette would too).
	var overlay := p2.get_node_or_null("PostFX/Overlay") as Control
	if overlay == null and postfx:
		for n in postfx.find_children("*", "ColorRect", true, false):
			overlay = n
			break
	var half2: Vector2 = vps[1].get_visible_rect().size
	_check("player two's full-screen overlay fills the right half exactly", overlay != null and overlay.get_global_rect().size.distance_to(half2) < 1.0 and overlay.get_global_rect().position.length() < 1.0,
		"%s vs half %s" % [overlay.get_global_rect() if overlay else "none", half2])
	var late := CanvasLayer.new()
	p1.add_child(late)
	await get_tree().create_timer(0.8, true, false, true).timeout
	_check("a canvas layer added later is routed too", late.custom_viewport == vps[0])

	# 5. Viewmodels and avatars.
	var vm1 := _first_visual(p1.get_node("Head/Camera3D/WeaponHolder"))
	var vm2 := _first_visual(p2.get_node("Head/Camera3D/WeaponHolder"))
	_check("each player has a viewmodel mesh", vm1 != null and vm2 != null)
	if vm1 and vm2:
		_check("player one's gun is drawn by camera 1, not camera 2", (cams[0].cull_mask & vm1.layers) != 0 and (cams[1].cull_mask & vm1.layers) == 0)
		_check("player two's gun is drawn by camera 2, not camera 1", (cams[1].cull_mask & vm2.layers) != 0 and (cams[0].cull_mask & vm2.layers) == 0)
	var av1 := p1.get_node_or_null("CoopAvatar") as VisualInstance3D
	var av2 := p2.get_node_or_null("CoopAvatar") as VisualInstance3D
	_check("each player has an avatar", av1 != null and av2 != null)
	if av1 and av2:
		_check("only the other camera draws each avatar",
			(cams[0].cull_mask & av1.layers) == 0 and (cams[1].cull_mask & av1.layers) != 0
			and (cams[1].cull_mask & av2.layers) == 0 and (cams[0].cull_mask & av2.layers) != 0)

	lvl.queue_free()
	await _frames(5)
	_check("leaving the level turns the root's 3D render back on", not get_viewport().disable_3d)
	_finish()

func _finish() -> void:
	PlayerInput.reset_coop()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _split(lvl: Node) -> Node:
	for n in lvl.find_children("*", "", true, false):
		if n.get_script() != null and n.get_script().get_global_name() == "SplitScreen":
			return n
	return null

func _first_visual(root: Node) -> VisualInstance3D:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).visible:
			return n
	return null
