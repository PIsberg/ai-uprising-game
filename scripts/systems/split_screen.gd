# @lat: [[player#Co-op]]
class_name SplitScreen
extends Node
## Local co-op split screen (#402, stage 3): the screen in two halves, player one
## left, player two right. The players stay where they are in the level (every
## get_viewport() and _input path keeps working); each half is a SubViewport on
## the level's own World3D with a camera that copies its player's view every
## frame, and the root viewport stops drawing 3D (it would be a third, full
## view under the halves). Each player's own CanvasLayers (post FX, uplink and
## breach HUDs) draw in that player's half through custom_viewport. Each gun
## viewmodel sits on its player's render layer and each player wears an avatar
## only the other camera draws. Player one's HUD moves into the left half;
## player two gets a CoopHud. tests/coop_split_probe.

## Render layer bit (0-based) for player i's viewmodel: 10 + i (layers 11, 12).
const VIEWMODEL_BIT := 10
## Render layer bit for player i's avatar: 12 + i (layers 13, 14).
const AVATAR_BIT := 12
const RESCAN := 0.5 ## s between checks for new canvas layers and new guns

var viewports: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var players: Array[Node3D] = []
var _layer: CanvasLayer
var _scan_t := 0.0

## Splits `level`'s screen when it holds more than one player; null otherwise.
static func attach(level: Node) -> SplitScreen:
	if GameState.players().size() < 2:
		return null
	var s := SplitScreen.new()
	s.name = "SplitScreen"
	level.add_child(s)
	return s

func _ready() -> void:
	process_priority = 1000 # after the players have moved and turned this frame
	players = GameState.players()
	var root_vp := get_viewport()
	_layer = CanvasLayer.new()
	_layer.layer = -10 # under every HUD
	add_child(_layer)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(row)
	for i in players.size():
		var box := SubViewportContainer.new()
		box.stretch = true
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(box)
		var vp := SubViewport.new()
		vp.world_3d = root_vp.world_3d
		vp.audio_listener_enable_3d = false # the root keeps listening from player one
		vp.msaa_3d = root_vp.msaa_3d
		vp.screen_space_aa = root_vp.screen_space_aa
		vp.use_taa = root_vp.use_taa
		vp.use_debanding = root_vp.use_debanding
		vp.scaling_3d_mode = root_vp.scaling_3d_mode
		vp.scaling_3d_scale = root_vp.scaling_3d_scale
		vp.mesh_lod_threshold = root_vp.mesh_lod_threshold
		box.add_child(vp)
		var cam := Camera3D.new()
		cam.name = "SplitCamera%d" % (i + 1)
		vp.add_child(cam)
		cam.make_current()
		viewports.append(vp)
		cameras.append(cam)
		_add_avatar(players[i], i)
	root_vp.disable_3d = true
	_place_huds()
	_rescan.call_deferred()
	_follow()

func _exit_tree() -> void:
	var vp := get_viewport()
	if vp:
		vp.disable_3d = false

func _process(delta: float) -> void:
	_follow()
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = RESCAN
		_rescan()

## Each half's camera takes its player's current view: the uplink's chassis
## camera while riding, the head camera otherwise.
func _follow() -> void:
	for i in players.size():
		var p := players[i]
		if not is_instance_valid(p):
			continue
		var src: Camera3D = p.get("camera")
		var uplink := p.get_node_or_null("NeuralUplink")
		if uplink and uplink.get("riding") == true and uplink.get("camera") is Camera3D:
			src = uplink.get("camera")
		if src == null:
			continue
		var cam := cameras[i]
		cam.global_transform = src.global_transform
		cam.fov = src.fov
		cam.near = src.near
		cam.far = src.far
		cam.h_offset = src.h_offset
		cam.v_offset = src.v_offset
		cam.environment = src.environment
		cam.attributes = src.attributes
		cam.cull_mask = _cull_for(i, src.cull_mask)

## A camera draws everything its source does, minus the other players' guns
## and its own player's avatar.
func _cull_for(i: int, base: int) -> int:
	var mask := base | (1 << (VIEWMODEL_BIT + i))
	for j in players.size():
		if j != i:
			mask &= ~(1 << (VIEWMODEL_BIT + j))
			mask |= 1 << (AVATAR_BIT + j)
	mask &= ~(1 << (AVATAR_BIT + i))
	return mask

## Route each player's canvas layers into its half and tag its guns' meshes.
func _rescan() -> void:
	for i in players.size():
		var p := players[i]
		if not is_instance_valid(p):
			continue
		for n in p.find_children("*", "CanvasLayer", true, false):
			var cl := n as CanvasLayer
			if cl.custom_viewport != viewports[i]:
				_route(cl, viewports[i])
			_frame(cl, viewports[i])
		var holder := p.get_node_or_null("Head/Camera3D/WeaponHolder")
		if holder:
			for n in holder.find_children("*", "VisualInstance3D", true, false):
				(n as VisualInstance3D).layers = 1 << (VIEWMODEL_BIT + i)

## Point `cl` at `vp`, out of the tree: a CanvasLayer hooks its parent's
## child_order_changed to the viewport it enters with and unhooks from the one
## it has when it leaves, so switching custom_viewport in place left a stale
## hook that errored on every layer when the level was freed.
func _route(cl: CanvasLayer, vp: SubViewport) -> void:
	var parent := cl.get_parent()
	var at := cl.get_index()
	parent.remove_child(cl)
	cl.custom_viewport = vp
	parent.add_child(cl)
	parent.move_child(cl, at)

## A Control placed straight under a CanvasLayer is laid out against
## get_viewport()'s rect, which for a layer in the main tree is the WINDOW even
## when custom_viewport points at a half: full-rect overlays came out window
## sized and centred things sat on the half's edge (#422). Hang the layer's
## controls off one SplitFrame sized to the half instead; controls added to the
## layer later are moved in on the next rescan.
func _frame(cl: CanvasLayer, vp: SubViewport) -> void:
	var frame := cl.get_node_or_null("SplitFrame") as Control
	if frame == null:
		frame = Control.new()
		frame.name = "SplitFrame"
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(frame)
		cl.move_child(frame, 0)
		var fit := func() -> void:
			if is_instance_valid(frame):
				frame.position = Vector2.ZERO
				frame.size = vp.get_visible_rect().size
		vp.size_changed.connect(fit)
		fit.call()
	for c in cl.get_children():
		if c != frame and c is Control:
			c.reparent(frame, false)

## A plain capsule standing in for player `i`, on a layer only the other camera draws.
func _add_avatar(p: Node3D, i: int) -> void:
	if p.get_node_or_null("CoopAvatar"):
		return
	var mi := MeshInstance3D.new()
	mi.name = "CoopAvatar"
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0) if i == 0 else Color(1.0, 0.55, 0.15)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.4
	cap.material = mat
	mi.mesh = cap
	mi.position = Vector3(0, 0.9, 0)
	mi.layers = 1 << (AVATAR_BIT + i)
	p.add_child(mi)

## Player one's HUD into the left half; a CoopHud for every other player.
func _place_huds() -> void:
	var hud := get_parent().get_node_or_null("HUD")
	if hud:
		hud.reparent.call_deferred(viewports[0], false)
	for i in range(1, players.size()):
		var ch := CoopHud.new()
		ch.player = players[i]
		viewports[i].add_child(ch)
