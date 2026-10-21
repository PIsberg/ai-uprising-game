# @lat: [[player#Co-op]]
class_name PlayerInput
extends RefCounted
## One player's view of the input (local co-op, stage 2). Player one reads the
## project's actions as they are; player two reads "p2_" copies of them, made on
## first use from the action's gamepad bindings with the device set to player
## two's pad, and at the same moment player one's pad bindings for that action are
## narrowed to player one's pad, so one controller never drives both. Keyboard and
## mouse stay with player one. With co-op off every player is player one and this
## is Input, unchanged. reset_coop() puts the actions back. tests/coop_input_probe.

const P2 := "p2_"

## Co-op pads, set by setup_coop: player one's (-1 = keyboard only) and player two's.
static var p1_device: int = -1
static var p2_device: int = -1
static var coop_on: bool = false

## Actions a press latches on and the next press latches off (Toggle Aim /
## Sprint / Crouch in Settings, pushed here by GraphicsSettings). Every other
## action, and these with their toggle off, read as the button is held.
static var toggled: Dictionary = {}

var prefix: String = ""
var keyboard: bool = true ## owns keyboard and mouse
var device: int = 0       ## the pad whose right stick turns this player's view

## The input for player `index` under the current co-op setup.
static func for_player(index: int) -> PlayerInput:
	var pi := PlayerInput.new()
	if coop_on and index == 1:
		pi.prefix = P2
		pi.keyboard = false
		pi.device = p2_device
	else:
		pi.device = maxi(p1_device, 0)
	return pi

## Turn co-op input on: player two on pad `p2`, player one on keyboard and pad `p1`
## (-1 for keyboard only).
static func setup_coop(p1: int, p2: int) -> void:
	reset_coop()
	p1_device = p1
	p2_device = p2
	coop_on = true

## Back to one player: drop every p2_ action and let every pad drive player one again.
static func reset_coop() -> void:
	for a in InputMap.get_actions():
		var s := String(a)
		if s.begins_with(P2):
			InputMap.erase_action(s)
		else:
			for e in InputMap.action_get_events(s):
				if e is InputEventJoypadButton or e is InputEventJoypadMotion:
					e.device = -1
	coop_on = false
	p1_device = -1
	p2_device = -1

## The action this player reads for `a`, creating player two's copy on first use.
## While co-op is on, player one's pad bindings of `a` are narrowed to player one's
## pad on every lookup (idempotent), so even an action only player one reads (the
## flashlight) cannot be fired from player two's pad.
func act(a: String) -> String:
	if not coop_on or not InputMap.has_action(a):
		return a
	for e in InputMap.action_get_events(a):
		if (e is InputEventJoypadButton or e is InputEventJoypadMotion) and e.device == -1:
			e.device = p1_device if p1_device >= 0 else 99 # 99: no such pad, keyboard only
	if prefix == "":
		return a
	var p := prefix + a
	if not InputMap.has_action(p):
		InputMap.add_action(p, InputMap.action_get_deadzone(a))
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				var c: InputEvent = e.duplicate()
				c.device = device
				InputMap.action_add_event(p, c)
	return p

func pressed(a: String) -> bool:
	var held := Input.is_action_pressed(act(a))
	if not toggled.get(a, false):
		return held
	# A press edge seen on any read flips the latch; more reads in the same
	# frame see no new edge, so it does not matter how many callers ask.
	if held and not _was_held.get(a, false):
		_latched[a] = not _latched.get(a, false)
	_was_held[a] = held
	return _latched.get(a, false)

## Drop a latched action: a toggled sprint ends when the player stops moving.
func release(a: String) -> void:
	_latched.erase(a)

var _latched: Dictionary = {} ## action -> latched on (toggled actions only)
var _was_held: Dictionary = {} ## action -> held at the last read, for press edges

func just_pressed(a: String) -> bool:
	return Input.is_action_just_pressed(act(a))

func just_released(a: String) -> bool:
	return Input.is_action_just_released(act(a))

func strength(a: String) -> float:
	return Input.get_action_strength(act(a))

func vector(neg_x: String, pos_x: String, neg_y: String, pos_y: String) -> Vector2:
	return Input.get_vector(act(neg_x), act(pos_x), act(neg_y), act(pos_y))

## An input event pressing `a` for this player (keyboard events never reach player two).
func event_pressed(ev: InputEvent, a: String) -> bool:
	return ev.is_action_pressed(act(a))

## The right stick as a look vector (x right, y down), from the look_* actions,
## so each player's copy answers only their own pad.
func look() -> Vector2:
	return Vector2(strength("look_right") - strength("look_left"), strength("look_down") - strength("look_up"))

## The right-stick look actions (deadzone 0: the player applies its own curve).
static func register_look_actions() -> void:
	for spec in [["look_left", JOY_AXIS_RIGHT_X, -1.0], ["look_right", JOY_AXIS_RIGHT_X, 1.0],
			["look_up", JOY_AXIS_RIGHT_Y, -1.0], ["look_down", JOY_AXIS_RIGHT_Y, 1.0]]:
		if InputMap.has_action(spec[0]):
			continue
		InputMap.add_action(spec[0], 0.0)
		var ev := InputEventJoypadMotion.new()
		ev.axis = spec[1]
		ev.axis_value = spec[2]
		InputMap.action_add_event(spec[0], ev)
