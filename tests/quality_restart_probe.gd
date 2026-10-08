extends Node
## Lowering the quality tier mid-session keeps most of the higher tier's GPU cost
## until the game restarts (#156: neon at HIGH costs ~125 ms after starting at
## HIGH, ~220 ms after starting at ULTRA, Intel Arc A370M). The root cause is still
## open; this probes the mitigation:
## (1) GraphicsSettings.restart_recommended() is true only below the launch tier;
## (2) the main menu's Settings shows a "Restart to apply" button exactly then,
##     following the real quality stepper up and down.
## (The pause menu's quality-down button posts a toast on the same condition;
## that path needs a live HUD and is not covered here.)
## user://settings.cfg is backed up and restored around the run.
##   godot --headless --path . --audio-driver Dummy res://tests/quality_restart_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := GraphicsSettings.SETTINGS_PATH
	var had := FileAccess.file_exists(path)
	var backup := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()
	var q0 := int(GraphicsSettings.quality)
	var launch0: int = GraphicsSettings.launch_quality

	GraphicsSettings.launch_quality = GraphicsSettings.Quality.ULTRA
	GraphicsSettings.set_quality(GraphicsSettings.Quality.ULTRA)
	_check("at the launch tier no restart is needed", not GraphicsSettings.restart_recommended())
	GraphicsSettings.set_quality(GraphicsSettings.Quality.HIGH)
	_check("below the launch tier a restart is recommended", GraphicsSettings.restart_recommended())

	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	var btn := menu.find_child("RestartToApplyBtn", true, false) as Button
	_check("Settings has a Restart-to-apply button", btn != null)
	if btn:
		_check("it shows after dropping below the launch tier", btn.visible, btn.text)
		menu.call("_on_graphics_up_pressed") # back to ULTRA through the real stepper
		_check("it hides again at the launch tier", not btn.visible)
		menu.call("_on_graphics_down_pressed")
		_check("...and returns after stepping down", btn.visible)
	menu.queue_free()
	await get_tree().process_frame

	GraphicsSettings.launch_quality = GraphicsSettings.Quality.MEDIUM
	_check("raising the tier never asks for a restart", not GraphicsSettings.restart_recommended())

	# Restore.
	GraphicsSettings.launch_quality = launch0
	GraphicsSettings.set_quality(q0)
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
