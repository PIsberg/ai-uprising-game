extends Node
## Windowed look check for the finale's choice (EndingChoice) as a run that
## hijacked 3 robots and breached 2 machines sees it: SHUT IT DOWN and TAKE ITS
## SEAT open, SET IT FREE locked at 2/5. Writes <out>/ending_choice.png.
##   godot --path . res://tests/ending_choice_shot.tscn -- --out=<dir>

var out := "user://"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	_run.call_deferred()

func _run() -> void:
	GameState.endings_path = "user://records_ending_shot.cfg"
	GameState.run_hijacks = 3
	GameState.run_breaches = 2
	add_child(EndingChoice.new())
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("ending_choice.png"))
	print("RESULT PASS")
	get_tree().quit()
