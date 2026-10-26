extends StaticBody3D
## A headshot-aware robot stand-in for tests/longshot_fx_probe: Weapon asks
## `is_headshot(y)` of the collider, and anything above 1.5 m is the head.

func is_headshot(y: float) -> bool:
	return y > global_position.y + 1.5
