extends Node3D
## Verifies the gamepad-rumble plumbing headless (no pad needed): the
## accessibility scalar mirrors into the static Haptics helper on load and on
## set, and pulse() is a safe no-op with zero pads connected / strength 0.

func _ready() -> void:
	# GraphicsSettings._load_settings ran at autoload init and must have
	# mirrored whatever was persisted (default 1.0 on a clean profile).
	print("mirror_on_load: %.2f" % Haptics.strength)
	GraphicsSettings.set_rumble(0.4)
	print("mirror_after_set: %.2f (want 0.40)" % Haptics.strength)
	Haptics.pulse(1.0, 1.0, 0.1) # zero pads connected: must not error
	GraphicsSettings.set_rumble(0.0)
	Haptics.pulse(1.0, 1.0, 0.1) # strength 0: early-out path
	print("mirror_off: %.2f (want 0.00)" % Haptics.strength)
	GraphicsSettings.set_rumble(1.0) # leave the persisted profile at default
	print("HAPTICS_PROBE_DONE")
	get_tree().quit()
