extends Node3D

@onready var scorch: Decal = $Scorch

func _ready() -> void:
	# Play explosion audio at high volume
	AudioBus.play_synth_at("explosion", global_position, 4.0, randf_range(0.85, 1.05))

	# Fireball core + shockwave ring + light pop + proximity kick; the scene's
	# fire/smoke/spark/debris particles dress it. Grenades hit harder, so the
	# whole read is bigger than the enemy-death pop.
	ExplosionFX.detonate(self, 3.2, Color(1.0, 0.58, 0.2))

	# Ground scorch lingers well past the blast, then fades out.
	if scorch:
		scorch.rotate_y(randf() * TAU) # vary the burn each time
		var burn := create_tween()
		burn.tween_interval(3.5)
		burn.tween_property(scorch, "modulate:a", 0.0, 2.5)

	# Free after the scorch has fully faded.
	var death_timer := create_tween()
	death_timer.tween_interval(6.2)
	death_timer.tween_callback(queue_free)
