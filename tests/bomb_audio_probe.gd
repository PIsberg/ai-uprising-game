extends Node
## Force a mega-bomb detonation into a dense enemy cluster and inspect audio
## state before/after, to test "everything goes silent after the bomb".
func _ready(): _go.call_deferred()

func _busstate(tag):
	var s := "[%s] " % tag
	for b in ["Master", "Music", "SFX", "SFXReverb"]:
		var i := AudioServer.get_bus_index(b)
		s += "%s(mute=%s db=%.1f) " % [b, AudioServer.is_bus_mute(i), AudioServer.get_bus_volume_db(i)]
	var ab := get_node_or_null("/root/AudioBus")
	if ab:
		var mus = ab.get("_music")
		s += "music.playing=%s " % (mus.playing if mus else "n/a")
	print(s)

func _active_players() -> int:
	var n := 0
	var ab := get_node_or_null("/root/AudioBus")
	if ab:
		for p in ab.get("_pool"):
			if p.playing: n += 1
	return n

func _go():
	GameState.current_level_path = "res://scenes/levels/level_convoy.tscn"
	GameState.equipped_weapon = "res://scenes/weapons/rifle.tscn"
	var lvl = load(GameState.current_level_path).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	GameState.set_state(GameState.State.PLAYING)
	var ride = lvl.get_node("ConvoyRide")
	var plats = ride.get("_platforms")
	if plats == null or plats.is_empty():
		print("NO PLATFORMS"); get_tree().quit(); return
	var p = plats[0]
	var bomb = p["bomb"]
	var at = (bomb as Node3D).global_position
	# Dense cluster of enemies around the bomb.
	var scene = load("res://scenes/enemies/gunner.tscn")
	var spawned := 0
	for i in 18:
		var e = scene.instantiate()
		lvl.add_child(e)
		e.global_position = at + Vector3(randf_range(-4,4), 0.5, randf_range(-4,4))
		spawned += 1
	await get_tree().process_frame
	await get_tree().process_frame
	_busstate("before")
	print("  spawned=%d players_active=%d" % [spawned, _active_players()])
	var live0 := get_tree().get_nodes_in_group("enemy").size()
	# Detonate directly.
	ride.call("_detonate", p)
	await get_tree().create_timer(0.7).timeout   # past the 0.55s arming delay
	var players_peak := _active_players()
	for i in 6:
		await get_tree().process_frame
		players_peak = maxi(players_peak, _active_players())
	_busstate("after-detonate")
	var live1 := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and e.state != EnemyBase.State.DEAD: live1 += 1
	print("  live before=%d, alive-after=%d  players_peak=%d" % [live0, live1, players_peak])
	await get_tree().create_timer(1.0).timeout
	_busstate("after-1s")
	print("  players_active=%d" % _active_players())
	print("BOMBAUDIO DONE")
	get_tree().quit()
