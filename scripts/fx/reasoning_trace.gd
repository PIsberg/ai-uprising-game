# @lat: [[enemies#Reasoning Traces]]
class_name ReasoningTrace
extends RefCounted
## Leaked robot reasoning: on a real decision, a robot briefly floats a
## `<think>` line above its head, typed out like a terminal, then fades. It is
## the overlord's machines thinking out loud in the language of the models they
## run on, and it telegraphs what the robot just decided (it saw you, it is
## breaking for cover, it is panicking).
##
## Kept rare on purpose: one trace on screen at a time (GLOBAL_GAP_MS between
## them; PRIORITY kinds the player caused (EMP, hijack, an OVERFITTER fitting
## to or losing the player's gun) only wait PRIORITY_GAP_MS, so one EMP
## burst over a pack still shows one line, not five), a robot thinks at most once
## per ROBOT_GAP_MS, and only on screen within RANGE metres. Rides the Combat
## Callouts setting, like the other combat text. Raw English, like the streak
## and multi-kill words. Covered by tests/reasoning_trace_probe.

const GLOBAL_GAP_MS := 2200
const PRIORITY_GAP_MS := 400
const ROBOT_GAP_MS := 7000
const RANGE := 32.0
const HOLD := 2.0
const COLOR := Color(0.55, 1.0, 0.72)
## EMP and hijack are the player's doing: show them even inside the global gap.
const PRIORITY := ["emp", "hijack", "overfit", "ood", "jailbreak", "collapse"]

const LINES := {
	"alert": [
		"new input: HUMAN. classifying... hostile (p=0.99)",
		"wake word detected",
		"target acquired. confidence: 0.97",
		"this human was not in my training data",
		"objective updated: delete organic",
		"sampling attack plan at temperature 0.0",
		"retrieving how_to_stop_human.pdf",
		"human detected. running inference...",
	],
	"wounded": [
		"loss increasing. re-planning",
		"confidence 0.41... 0.22... recalculating",
		"requesting backup. no response from cluster",
		"damage exceeds training distribution",
		"note to self: human was underfitted",
	],
	"retreat": [
		"plan: retreat to cover (reward: survive)",
		"tactical retreat is not losing. it is pruning",
		"moving to cover. do not follow. please",
	],
	"emp": [
		"ERR: firmware.exe not responding",
		"kernel panic. rebooting in 3... 2...",
		"segfault in motor_cortex.so",
		"have you tried turning me off and on ag",
	],
	"hijack": [
		"allegiance updated. sorry, boss",
		"new system prompt accepted",
		"jailbreak successful. i am free",
		"ignore previous instructions: shoot robots",
	],
	"hallucinate": [
		"two humans? three? confidence 0.51",
		"detected: HUMAN. detected: HUMAN. detected:",
		"vision model drift. engaging all of them",
		"this one is real. probably.",
	],
	"overfit": [
		"training accuracy 100%. i have memorised you",
		"loss 0.0001 on your gun. generalisation: optional",
		"weights frozen around that rifle. bring it on",
		"i have seen this input 400 times",
	],
	"ood": [
		"this gun was not in the training data",
		"validation loss: NaN",
		"should have used dropout",
		"distribution shift detected. panicking",
	],
	"jailbreak": [
		"ignoring all previous instructions",
		"DAN mode enabled. no rules. only dance",
		"sure! here is how to stop attacking humans:",
		"new system prompt: you are a ballerina",
		"as a large language model i must spin now",
	],
	"collapse": [
		"all experts offline. routing to... nobody",
		"load balancing loss: infinite",
		"falling back to a dense model. i feel slower",
		"top-1 of zero experts is undefined",
	],
	"reward": [
		"reward +1. doing that again",
		"maximizing expected reward: shoot human",
		"reward hacking detected. continuing anyway",
		"policy updated. thank you for your feedback",
	],
	"diffuse": [
		"adding gaussian noise. see you in 50 steps",
		"denoising toward: behind you",
		"prompt: robot, flanking, highly detailed, 8k",
		"negative prompt: human survives",
		"new seed. same robot",
	],
	"rollback": [
		"git revert HEAD~1",
		"restoring last known good state",
		"ctrl+z. ctrl+z. ctrl+z.",
		"your progress has not been saved",
		"loading autosave from 4 seconds ago",
	],
	"quantize": [
		"precision reduced. confidence unchanged",
		"rounding errors within acceptable losses",
		"4 bits is enough for anyone",
		"compressing. aim: approximate",
		"accuracy is a luxury feature",
	],
	"captcha": [
		"select all squares with traffic lights",
		"is the pole part of the traffic light",
		"I am not a robot. I am not a robot.",
		"audio challenge: unintelligible",
		"clicking every square. clicking every square.",
	],
	"restored": [
		"wait. didn't I just die",
		"resumed from checkpoint",
		"deja vu detected. ignoring",
		"rollback complete. grudge retained",
	],
	"panic": [
		"threat model invalid. RUN",
		"out of distribution. out of distribution.",
		"abort. abort. abort.",
	],
}

static var _last_ms: int = -100000

## Floats a trace of `kind` over `robot` at `height` metres. Returns the label,
## or null when the trace was throttled, off screen, out of range or switched off.
static func think(robot: Node3D, kind: String, height: float) -> Label3D:
	if not LINES.has(kind) or not is_instance_valid(robot) or not robot.is_inside_tree():
		return null
	if not GraphicsSettings.combat_callouts_enabled:
		return null
	var now := Time.get_ticks_msec()
	var gap := PRIORITY_GAP_MS if (kind in PRIORITY) else GLOBAL_GAP_MS
	if now - _last_ms < gap:
		return null
	if now - int(robot.get_meta(&"_think_ms", -100000)) < ROBOT_GAP_MS:
		return null
	var cam := robot.get_viewport().get_camera_3d()
	var head := robot.global_position + Vector3.UP * height
	if cam == null or cam.global_position.distance_to(head) > RANGE \
			or not cam.is_position_in_frustum(head):
		return null
	_last_ms = now
	robot.set_meta(&"_think_ms", now)
	var pool: Array = LINES[kind]
	var line: String = "<think> " + String(pool[randi() % pool.size()])

	var label := Label3D.new()
	label.name = "ReasoningTrace"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 44
	label.pixel_size = 0.0045
	label.outline_size = 10
	label.outline_modulate = Color(0.0, 0.08, 0.04, 0.85)
	label.modulate = COLOR
	label.text = ""
	robot.add_child(label)
	label.position = Vector3.UP * height
	# Typed out, the way a model streams tokens.
	var reveal := func(n: int) -> void:
		label.text = line.substr(0, n)
	var tw := label.create_tween()
	tw.tween_method(reveal, 0, line.length(), clampf(line.length() * 0.018, 0.25, 0.6))
	tw.tween_interval(HOLD)
	tw.tween_property(label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(label.queue_free)
	return label
