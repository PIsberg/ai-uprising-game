extends Node3D

func _ready() -> void:
	# Play the procedural explosion sound at slightly higher volume for punchiness
	AudioBus.play_synth_at("explosion", global_position, 3.0)
	# Fireball core + shockwave ring + light pop + proximity kick. The scene's
	# particle systems layer debris/sparks on top of it.
	ExplosionFX.detonate(self, 2.0)
	# Wait for the smoke plume to finish billowing before freeing.
	var death_timer := create_tween()
	death_timer.tween_interval(1.5)
	death_timer.tween_callback(queue_free)
