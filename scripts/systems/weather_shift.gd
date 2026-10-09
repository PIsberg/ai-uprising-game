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

@export var task_id: String = "survive"
@export var fog_mult: float = 4.0
@export var fade: float = 3.0
@export var gust: float = 1.0
var env: Environment
var weather: Node                   ## the level's weather particles, if any
var fog_color: Variant = null       ## Color to shift the fog to, or null to keep it
var warn_title: String = "WEATHER TURNING"
var warn_text: String = "Visibility is dropping."
var clear_title: String = ""
var clear_text: String = ""

var _fog0: float = 0.0
var _col0: Color
var _speed0: float = 1.0
var _cleared: bool = false

func _ready() -> void:
	if env == null:
		queue_free()
		return
	_fog0 = env.fog_density
	_col0 = env.fog_light_color
	if is_instance_valid(weather) and "speed_scale" in weather:
		_speed0 = weather.speed_scale
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tw.tween_property(env, "fog_density", _fog0 * fog_mult, fade)
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
	if is_instance_valid(weather) and "speed_scale" in weather:
		tw.tween_property(weather, "speed_scale", _speed0, fade)
	tw.chain().tween_callback(queue_free)
	if clear_title != "":
		GameState.skirmish_event.emit(clear_title, clear_text)
