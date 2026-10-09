class_name WeatherShift
extends Node
# @lat: [[level-system#Weather Shifts]]
## A survive wave's "weather": the level's own Environment turns against the
## player for the rest of the hold. The distance fog thickens by `fog_mult` (and
## can shift colour) over `fade` seconds, and the level's weather particles
## (the node the builder names "Weather") speed up by `gust`. Frostbreak's thaw
## kicks its blizzard into a whiteout: the threats come out of the snow at close
## range instead of being picked off across the yard.
##
## When the hold completes, everything eases back to the values captured at the
## start, so the walk to the exit has the level's normal sightlines. Death does
## not reset it: unlike a flood, fog cannot kill a respawned player.
##
## A BLACKOUT ("blackout": true) cuts the level's own lights and their lit
## fixture panels (group "level_light") and scales the ambient by
## `ambient_mult`, so the fight is lit by emissives, muzzle flashes and the
## robots' eyes. A task can carry the same spec as a survive wave: it starts
## when the stage goes live and clears when it completes (sublevel's night
## shift is fought in a power cut).
##
## A level with no weather of its own can raise some for the storm
## ("particles" in the wave, built by LevelBuilder._start_weather): the shift
## owns those particles, and on completion stops them and frees them once the
## last ones have drifted out. Desert's counterstrike is a sandstorm this way.

@export var task_id: String = "survive"
@export var fog_mult: float = 4.0
@export var fade: float = 3.0
@export var gust: float = 1.0
@export var blackout: bool = false
@export var ambient_mult: float = 1.0
## Scales the Environment's tonemap exposure. Cutting the lights alone darkened
## sublevel by 7% (mean luma 38.8 -> 36.2): its emissive floor grid, accent
## strips and alarm beacons carry the frame. Exposure dims those too, and the
## robots' eyes stay the brightest thing in the room.
@export var exposure_mult: float = 1.0
var env: Environment
var weather: Node                   ## the level's weather particles, if any
var owns_weather: bool = false      ## raised for this storm: stop + free them on completion
var fog_color: Variant = null       ## Color to shift the fog to, or null to keep it
var warn_title: String = "WEATHER TURNING"
var warn_text: String = "Visibility is dropping."
var clear_title: String = ""
var clear_text: String = ""

var _fog0: float = 0.0
var _col0: Color
var _speed0: float = 1.0
var _cleared: bool = false
var _amb0: float = 0.0
var _exp0: float = 1.0
var _dark: Array = []                ## lights + panels this blackout hid

func _ready() -> void:
	if env == null:
		queue_free()
		return
	_fog0 = env.fog_density
	_col0 = env.fog_light_color
	_amb0 = env.ambient_light_energy
	_exp0 = env.tonemap_exposure
	if blackout:
		# A power cut is a snap, not a fade. The god-ray shafts under the
		# luminaires go with their lights.
		for n in get_tree().get_nodes_in_group("level_light") + get_tree().get_nodes_in_group("light_shaft_meshes"):
			if n is Node3D and (n as Node3D).visible:
				(n as Node3D).visible = false
				_dark.append(n)
	if is_instance_valid(weather) and "speed_scale" in weather:
		_speed0 = weather.speed_scale
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tw.tween_property(env, "fog_density", _fog0 * fog_mult, fade)
	if not is_equal_approx(ambient_mult, 1.0):
		tw.tween_property(env, "ambient_light_energy", _amb0 * ambient_mult, fade)
	if not is_equal_approx(exposure_mult, 1.0):
		tw.tween_property(env, "tonemap_exposure", _exp0 * exposure_mult, fade)
	if fog_color is Color:
		tw.tween_property(env, "fog_light_color", fog_color, fade)
	if is_instance_valid(weather) and "speed_scale" in weather:
		tw.tween_property(weather, "speed_scale", _speed0 * gust, fade)
	GameState.skirmish_event.emit(warn_title, warn_text)
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_ui("overlord_glitch", -4.0, 0.45)

func _process(_delta: float) -> void:
	if _cleared or not GameState.is_task_done(task_id):
		return
	_cleared = true
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tw.tween_property(env, "fog_density", _fog0, fade)
	tw.tween_property(env, "fog_light_color", _col0, fade)
	tw.tween_property(env, "ambient_light_energy", _amb0, fade)
	tw.tween_property(env, "tonemap_exposure", _exp0, fade)
	for n in _dark:
		if is_instance_valid(n):
			(n as Node3D).visible = true
	_dark.clear()
	if is_instance_valid(weather) and "speed_scale" in weather:
		tw.tween_property(weather, "speed_scale", _speed0, fade)
	tw.chain().tween_callback(queue_free)
	if owns_weather and is_instance_valid(weather):
		weather.set("emitting", false)
		var w := weather
		get_tree().create_timer(float(weather.get("lifetime")) + fade).timeout.connect(
			func(): if is_instance_valid(w): w.queue_free())
	if clear_title != "":
		GameState.skirmish_event.emit(clear_title, clear_text)
