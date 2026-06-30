extends Node
## Isolates the frame-time bottleneck on one level: baseline, then with enemies
## removed (CPU/AI), then with volumetric fog off, then with sun shadows off, then
## with the VoxelGI removed. fps jump => that subsystem is the cost.
const ID := "gpt"
const WARM := 12
const M := 45
var _lvl: Node

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if GraphicsSettings:
		GraphicsSettings.quality = 2
		GraphicsSettings._apply_viewport()
	_lvl = load("res://scenes/levels/level_%s.tscn" % ID).instantiate()
	add_child(_lvl)
	await _m("baseline")
	# remove enemies
	for e in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	await get_tree().process_frame
	await _m("no-enemies")
	# volumetric fog off
	var we = _find(_lvl, "WorldEnvironment")
	if we and we.environment:
		we.environment.volumetric_fog_enabled = false
	await _m("no-volfog")
	# sun shadows off
	for l in _all(_lvl):
		if l is DirectionalLight3D: l.shadow_enabled = false
	await _m("no-sun-shadow")
	# voxel gi off
	for n in _all(_lvl):
		if n is VoxelGI: n.visible = false
	await _m("no-voxelgi")
	get_tree().quit()

func _m(tag: String) -> void:
	for i in WARM: await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for i in M: await get_tree().process_frame
	var dt := (Time.get_ticks_usec() - t0) / 1000000.0
	var d := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("DIAG %-14s fps=%6.1f draws=%5d" % [tag, M/dt, d])

func _find(n, cls):
	if n.get_class()==cls or n.is_class(cls): return n
	for c in n.get_children():
		var r=_find(c,cls)
		if r: return r
	return null
func _all(n, acc=null):
	if acc==null: acc=[]
	acc.append(n)
	for c in n.get_children(): _all(c,acc)
	return acc
