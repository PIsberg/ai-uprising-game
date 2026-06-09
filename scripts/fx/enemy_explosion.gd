extends Node3D

@onready var light: OmniLight3D = $Light

func _ready() -> void:
	# Play the procedural explosion sound at slightly higher volume for punchiness
	AudioBus.play_synth_at("explosion", global_position, 3.0)
	
	# Light flash tween
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Wait for particles to finish before freeing
	var death_timer := create_tween()
	death_timer.tween_interval(0.9)
	death_timer.tween_callback(queue_free)
