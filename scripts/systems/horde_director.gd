class_name HordeDirector
extends Node
## Last Stand wave director. Runs an endless escalating siege: each wave buys
## enemies from a budget that grows with the wave number, harder archetypes
## unlock as waves climb, spawns telegraph with a light pillar at perimeter
## points, and the lull between waves drops supplies at the arena centre.
## Best wave reached persists to user://records.cfg. The run ends when the
## player dies (standard game-over flow) — there is no winning, only the leaderboard.

## [min_wave, scene_path, budget_cost]
const POOL := [
	[1, "res://scenes/enemies/drone.tscn", 1],
	[1, "res://scenes/enemies/android.tscn", 1],
	[2, "res://scenes/enemies/spider.tscn", 2],
	[3, "res://scenes/enemies/seeker.tscn", 2],
	[4, "res://scenes/enemies/sniper.tscn", 3],
	[5, "res://scenes/enemies/mech.tscn", 4],
	[6, "res://scenes/enemies/brute.tscn", 4],
	[7, "res://scenes/enemies/terminator.tscn", 5],
	[10, "res://scenes/enemies/colossus.tscn", 12],
]
const RECORDS_PATH := "user://records.cfg"
const INTERMISSION := 8.0
const FIRST_WAVE_DELAY := 5.0

var spawn_points: Array = [] ## Perimeter Vector3s, set by the builder from the def.
var supply_center := Vector3.ZERO

var wave: int = 0
var best: int = 0
var _alive: int = 0
var _lull: float = FIRST_WAVE_DELAY
var _running: bool = true
var _scenes: Dictionary = {} # path -> PackedScene, loaded lazily once

const PICKUP_HEALTH := preload("res://scenes/pickups/health_pack.tscn")
const PICKUP_AMMO := preload("res://scenes/pickups/ammo_box.tscn")
const PICKUP_OVERCLOCK := preload("res://scenes/pickups/overclock.tscn")

func _ready() -> void:
	best = _load_best()
	GameState.player_died.connect(func(): _running = false)
	_update_hud("Hold out. First wave in %d…" % int(ceil(_lull)))

func _process(delta: float) -> void:
	if not _running:
		return
	if _lull > 0.0:
		var before := int(ceil(_lull))
		_lull -= delta
		var now := int(ceil(_lull))
		if now != before and now > 0:
			_update_hud("WAVE %d incoming in %d…  ·  BEST: %d" % [wave + 1, now, best])
			if now <= 3:
				AudioBus.play_synth_ui("broadcast_blip", -6.0, 0.8 + (3 - now) * 0.15)
		if _lull <= 0.0:
			_start_wave()

func _start_wave() -> void:
	wave += 1
	if wave > best:
		best = wave
		_save_best()
	AudioBus.play_synth_ui("eas_alert", -8.0)
	# Spend the wave budget on whatever is unlocked, weighted random.
	var budget := 5 + wave * 2
	var picks: Array = []
	var unlocked := POOL.filter(func(e): return e[0] <= wave)
	while budget > 0:
		var e: Array = unlocked.pick_random()
		if e[2] > budget and not picks.is_empty():
			break
		picks.append(e[1])
		budget -= e[2]
	_alive = picks.size()
	_update_hud("WAVE %d — %d hostiles  ·  BEST: %d" % [wave, _alive, best])
	# Stagger the spawns so the wave pours in instead of blinking in.
	for i in picks.size():
		_telegraph_spawn(picks[i], spawn_points.pick_random(), 0.4 + i * 0.35)

## A rising light pillar marks the point, then the enemy materializes there.
func _telegraph_spawn(path: String, point: Vector3, delay: float) -> void:
	var t := get_tree().create_timer(delay)
	t.timeout.connect(func():
		if not _running:
			return
		var pillar := _make_pillar(point)
		var t2 := get_tree().create_timer(0.7)
		t2.timeout.connect(func():
			if is_instance_valid(pillar):
				pillar.queue_free()
			if _running:
				_spawn(path, point)))

func _make_pillar(point: Vector3) -> Node3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.7
	cm.height = 6.0
	cm.radial_segments = 10
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.25, 0.15, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.15)
	mat.emission_energy_multiplier = 2.5
	cm.material = mat
	mi.mesh = cm
	add_child(mi)
	mi.global_position = point + Vector3.UP * 3.0
	AudioBus.play_synth_at("broadcast_blip", point, -4.0, 0.6)
	return mi

func _spawn(path: String, point: Vector3) -> void:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var e := (_scenes[path] as PackedScene).instantiate() as Node3D
	var eb := e as EnemyBase
	if eb:
		# Campaign-difficulty scaling plus a steady per-wave ramp.
		var cfg: Dictionary = GameState.difficulty_config()
		eb.max_health *= cfg.get("health_mult", 1.0) * (1.0 + (wave - 1) * 0.06)
		eb.attack_cooldown *= cfg.get("cooldown_mult", 1.0)
		eb.move_speed *= cfg.get("speed_mult", 1.0)
		# Elites get steadily more common in deep waves.
		Elite.maybe_apply(e, minf(0.3, Elite.roll_chance() + wave * 0.012))
	e.position = point
	get_parent().add_child(e) # parent to the level root, not current_scene
	var d := e.get_node_or_null("Damageable") as Damageable
	if d:
		d.died.connect(func(_src: Node): _on_enemy_down())

func _on_enemy_down() -> void:
	_alive -= 1
	_update_hud("WAVE %d — %d hostiles  ·  BEST: %d" % [wave, maxi(_alive, 0), best])
	if _alive <= 0 and _running:
		_lull = INTERMISSION
		_drop_supplies()
		AudioBus.play_synth_ui("victory_sting", -10.0, 1.2)

## Between waves: a few supplies pop in near the arena centre. Every 5th
## cleared wave also drops an OVERCLOCK to spend on the milestone wave ahead.
func _drop_supplies() -> void:
	var drops := [PICKUP_AMMO, PICKUP_AMMO, PICKUP_HEALTH]
	if (wave + 1) % 5 == 0:
		drops.append(PICKUP_OVERCLOCK)
	for i in drops.size():
		var p := (drops[i] as PackedScene).instantiate() as Node3D
		get_parent().add_child(p)
		p.global_position = supply_center + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		p.scale = Vector3.ONE * 0.2
		var tw := p.create_tween()
		tw.tween_property(p, "scale", Vector3.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _update_hud(text: String) -> void:
	var hud := get_parent().get_node_or_null("HUD")
	if hud and hud.has_method("set_objective"):
		hud.set_objective(text)

func _load_best() -> int:
	var cf := ConfigFile.new()
	if cf.load(RECORDS_PATH) != OK:
		return 0
	return int(cf.get_value("horde", "best_wave", 0))

func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.load(RECORDS_PATH)
	cf.set_value("horde", "best_wave", best)
	cf.save(RECORDS_PATH)
