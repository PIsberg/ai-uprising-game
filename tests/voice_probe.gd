extends Node
## Dev probe for the robot voice-bark system: every category in
## AudioBus.VOICE_CATEGORIES must resolve ALL of its clips on disk (the const
## mirrors tools/gen_voices.ps1 — this catches drift), play_voice_at must fire
## per category, and the per-family pack resolution must prefer "dog_atk" while
## unknown families fall back to the shared pool.
##   godot --headless --path . res://tests/voice_probe.tscn

var _ok := true

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["ok  " if cond else "BAD ", name, detail])
	if not cond:
		_ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var ab: Node = get_node("/root/AudioBus")
	# 1. Every category fully indexed (count drift between the ps1 and the
	#    const shows up here as a short clip list).
	for cat in AudioBus.VOICE_CATEGORIES:
		var want: int = AudioBus.VOICE_CATEGORIES[cat]
		var have: int = (ab.get("_voice_clips").get(cat, []) as Array).size()
		_check("clips %s" % cat, have == want, "%d/%d" % [have, want])
	# 2. Each category actually plays (reset the global cooldown between).
	for cat in AudioBus.VOICE_CATEGORIES:
		ab.set("_voice_cooldown_until", 0.0)
		_check("plays %s" % cat, ab.play_voice_at(cat, Vector3.ZERO, 1.0), cat)
	# 3. Family resolution: a dog prefers its own pack; a family with no pack
	#    must return false from the pack lookup so _speak falls back.
	ab.set("_voice_cooldown_until", 0.0)
	_check("dog pack plays", ab.play_voice_at("dog_atk", Vector3.ZERO, 1.0))
	_check("unknown pack is silent", not ab.play_voice_at("raptor_atk", Vector3.ZERO, 1.0))
	ab.set("_voice_cooldown_until", 0.0)
	_check("fallback pool plays", ab.play_voice_at("atk", Vector3.ZERO, 1.0))
	# 4. EnemyBase derives the family key from the script class name.
	var dog := (load("res://scenes/enemies/dog.tscn") as PackedScene).instantiate()
	_check("dog family key", dog.call("_voice_family") == "dog", str(dog.call("_voice_family")))
	_check("dog pitch chirps", float(EnemyBase.VOICE_PITCH.get("dog", 0.0)) > 1.2)
	dog.queue_free()
	# 5. Override-proof death bark. Thirteen subclasses override _on_died and
	#    seven never call super, so a bark living inside _on_died is silently
	#    dropped for those chassis. EnemyBase hooks the Damageable's `died`
	#    signal instead — assert the connection exists on EVERY enemy scene so
	#    the next _on_died override can't mute a robot's dying gasp again.
	await _check_death_barks()
	print("RESULT ", "PASS" if _ok else "FAIL")
	get_tree().quit()

func _check_death_barks() -> void:
	var missing: Array[String] = []
	var checked := 0
	for f in DirAccess.get_files_at("res://scenes/enemies/"):
		if not f.ends_with(".tscn"):
			continue
		var e: Node = (load("res://scenes/enemies/%s" % f) as PackedScene).instantiate()
		if not (e is EnemyBase):
			e.queue_free()
			continue
		add_child(e)
		await get_tree().process_frame
		var hp: Node = e.get("hp")
		if hp == null or not hp.died.is_connected(e._on_died_voice):
			missing.append(f.get_basename())
		checked += 1
		e.queue_free()
		await get_tree().process_frame
	_check("death bark wired on all enemies", missing.is_empty(),
		"%d scenes%s" % [checked, "" if missing.is_empty() else " MISSING: " + ", ".join(missing)])
