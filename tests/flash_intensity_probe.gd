extends Node3D
## Verifies the "Flash Intensity" accessibility slider (GraphicsSettings.flash_intensity)
## reaches world light BURSTS, not just the HUD's full-screen flashes:
##   * GraphicsSettings.flash_energy(peak) is a straight peak * flash_intensity scale.
##   * The muzzle-flash OmniLight3D pops with energy > 0 at flash_intensity=1.0, and
##     is suppressed (freed) at flash_intensity=0.0 — checked right after _ready, since
##     the flash's own lifetime is only 0.06s and a slow headless frame can otherwise
##     expire it before the next process tick (unrelated to this slider).
##   * ExplosionFX._light_pop rises off zero at 1.0 and stays pinned at zero through
##     its whole tween at 0.0.
## Logic-only, runs headless. Restores flash_intensity to its pre-probe value before
## quitting (set_flash_intensity persists to user://settings.cfg immediately).
##   godot --headless --path . res://tests/flash_intensity_probe.tscn

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var orig_fi: float = GraphicsSettings.flash_intensity

	# --- flash_energy helper -------------------------------------------------
	GraphicsSettings.set_flash_intensity(1.0)
	_check(is_equal_approx(GraphicsSettings.flash_energy(9.0), 9.0),
		"flash_energy(9.0) == 9.0 at flash_intensity=1.0")
	GraphicsSettings.set_flash_intensity(0.0)
	_check(GraphicsSettings.flash_energy(9.0) == 0.0,
		"flash_energy(9.0) == 0.0 at flash_intensity=0.0")
	GraphicsSettings.set_flash_intensity(0.5)
	_check(is_equal_approx(GraphicsSettings.flash_energy(9.0), 4.5),
		"flash_energy(9.0) == 4.5 at flash_intensity=0.5")

	# --- muzzle flash OmniLight3D --------------------------------------------
	# Read the light right after add_child (which runs _ready synchronously,
	# before any _process tick) — the flash's own lifetime is only 0.06s, short
	# enough that a slow headless frame delta can otherwise expire and free the
	# light before the next process tick, which would be noise unrelated to the
	# slider under test.
	GraphicsSettings.set_flash_intensity(1.0)
	var mf1: Node3D = (load("res://scenes/fx/muzzle_flash.tscn") as PackedScene).instantiate()
	add_child(mf1)
	var light1 := mf1.get_node_or_null("OmniLight3D") as OmniLight3D
	_check(light1 != null and light1.light_energy > 0.0,
		"muzzle flash light energy > 0 at flash_intensity=1.0")
	await get_tree().process_frame
	if is_instance_valid(mf1):
		mf1.queue_free()
	await get_tree().process_frame

	GraphicsSettings.set_flash_intensity(0.0)
	var mf0: Node3D = (load("res://scenes/fx/muzzle_flash.tscn") as PackedScene).instantiate()
	add_child(mf0)
	var light0 := mf0.get_node_or_null("OmniLight3D") as OmniLight3D
	# At 0 the light is queue_free'd in _ready — it is still a child until the
	# end of the frame, so accept "gone", "going", or "dark".
	_check(light0 == null or light0.is_queued_for_deletion() or light0.light_energy <= 0.0,
		"muzzle flash light suppressed (freed or zero-energy) at flash_intensity=0.0")
	await get_tree().process_frame
	if is_instance_valid(mf0):
		mf0.queue_free()
	await get_tree().process_frame

	# --- ExplosionFX._light_pop -----------------------------------------------
	GraphicsSettings.set_flash_intensity(1.0)
	var root1 := Node3D.new()
	add_child(root1)
	var light_a := OmniLight3D.new()
	light_a.name = "Light"
	light_a.light_energy = 8.0
	root1.add_child(light_a)
	ExplosionFX._light_pop(root1)
	_check(light_a.light_energy > 0.0,
		"explosion light pop energy > 0 right after the call at flash_intensity=1.0")
	var rose := false
	var prev := light_a.light_energy
	for i in 4:
		await get_tree().process_frame
		if light_a.light_energy > prev + 0.001:
			rose = true
		prev = light_a.light_energy
	_check(rose, "explosion light pop energy rises during the tween at flash_intensity=1.0")
	root1.queue_free()
	await get_tree().process_frame

	GraphicsSettings.set_flash_intensity(0.0)
	var root0 := Node3D.new()
	add_child(root0)
	var light_b := OmniLight3D.new()
	light_b.name = "Light"
	light_b.light_energy = 8.0
	root0.add_child(light_b)
	ExplosionFX._light_pop(root0)
	var stayed_zero := is_zero_approx(light_b.light_energy)
	for i in 6:
		await get_tree().process_frame
		if not is_zero_approx(light_b.light_energy):
			stayed_zero = false
	_check(stayed_zero, "explosion light pop stays at zero through the whole tween at flash_intensity=0.0")
	root0.queue_free()
	await get_tree().process_frame

	# --- restore --------------------------------------------------------------
	GraphicsSettings.set_flash_intensity(orig_fi)
	_check(is_equal_approx(GraphicsSettings.flash_intensity, orig_fi),
		"flash_intensity restored to its pre-probe value")

	# Let queue_free()'d nodes actually leave the tree before quitting.
	await get_tree().process_frame
	await get_tree().process_frame

	print("RESULT ", "PASS" if _fail.is_empty() else "FAIL")
	get_tree().quit()
