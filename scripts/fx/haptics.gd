class_name Haptics
## Gamepad rumble for the combat feedback taps (weapon fire, hits taken, blast
## shock, kill confirms, hard landings). Every pulse routes through `strength`,
## an accessibility scalar mirrored from GraphicsSettings.rumble (0..1 slider,
## 0 = off) so the static call sites never need to reach for the autoload.
##
## Godot's API is fire-and-forget per device: a new pulse replaces the running
## one, which is exactly right for rapid-fire feedback — the freshest impulse
## wins instead of queueing into mush. With no pad connected every call is a
## no-op, so keyboard/mouse players pay nothing.

static var strength: float = 1.0

## One rumble pulse on every connected pad. `weak` drives the high-frequency
## buzz motor (texture: gunfire ticks, confirms), `strong` the low-frequency
## thump motor (weight: damage, blasts, landings); both 0..1, `dur` in seconds.
static func pulse(weak: float, strong: float, dur: float) -> void:
	if strength <= 0.001:
		return
	for dev in Input.get_connected_joypads():
		Input.start_joy_vibration(dev,
			clampf(weak * strength, 0.0, 1.0),
			clampf(strong * strength, 0.0, 1.0), dur)
