class_name EnemySentinel
extends EnemyBase
## Heavy weapons platform. Slow and very tanky; plants itself at range and lobs
## heavy bolts. Visuals from a real robot model in sentinel.tscn.

@export var proj_speed: float = 34.0
@export var proj_damage: float = 18.0
## Every few volleys it LOBS A BOMB instead: an arcing charge that lands at
## your feet and detonates a beat later — camping one spot near a sentinel
## is no longer safe, but the blinking fuse gives you time to move.
@export var bomb_damage: float = 30.0
@export var bomb_every: int = 3

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

var _volley_n: int = 0


func _ready() -> void:
	max_health = 185.0
	move_speed = 3.4
	turn_speed = 4.0
	sight_range = 42.0
	sight_angle_deg = 180.0
	attack_range = 34.0
	preferred_range = 22.0
	attack_cooldown = 1.9
	telegraph_time = 0.0 # a planted weapons platform fires on cadence — no generic wind-up (its bolts are the threat)
	score_value = 180
	stagger_threshold = 120.0
	super._ready()


func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var origin: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP
	_volley_n += 1
	if _volley_n % bomb_every == 0:
		_mortar_salvo(origin)
		return
	var proj := PROJECTILE.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = origin
	var dir := (target.global_position + Vector3.UP * 0.4 - origin).normalized()
	dir = scatter_aim(dir, 2.0)
	if proj.has_method("launch"):
		proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()

## MORTAR SALVO: the lone lobbed bomb, promoted to what this heavy-platform
## chassis (quaternius_heavy) always suggested — a 3-round artillery barrage
## bracketing the player: one shell on them, two scattered around, staggered.
## Each impact point flashes its ground warning ring for the shell's flight,
## so the answer is to MOVE and keep moving, not to eat 3× the old bomb.
## After the salvo the platform re-rolls its approach angle: a siege piece
## that resets its firing lane between barrages instead of standing forever.
func _mortar_salvo(origin: Vector3) -> void:
	recoil = 1.0
	_muzzle_flash()
	AudioBus.play_synth_at("plasma_fire", origin, -2.0, 0.55)
	var center: Vector3 = target.global_position
	for i in 3:
		var pt := center
		if i > 0:
			var ang := randf() * TAU
			pt += Vector3(cos(ang), 0.0, sin(ang)) * randf_range(2.2, 4.5)
		var delay := 0.35 * float(i)
		# Warning ring + lob together per shell, so each ring burns exactly
		# while its shell is in the air. Captures by value: safe if we die.
		var fire := func() -> void:
			if not is_instance_valid(self) or not is_inside_tree() or state == State.DEAD:
				return
			spawn_ground_warning(pt, 2.4, 0.9)
			EnemyBomb.lob_at(get_tree().current_scene, origin, pt, 0.9, bomb_damage * 0.75)
			AudioBus.play_synth_at("grenade_throw", origin, -6.0, 0.7)
		if delay <= 0.0:
			fire.call()
		else:
			get_tree().create_timer(delay).timeout.connect(fire)
	_approach_angle = randf() * TAU # displace: reset the firing lane
