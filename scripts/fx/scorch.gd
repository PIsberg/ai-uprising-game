class_name ScorchMark
extends Decal
## A lasting burn mark projected onto the ground (e.g. where a robot was
## destroyed). Holds, then fades out and frees itself. Fully code-built — its
## albedo texture is a procedurally-generated, cached radial scorch so no art
## asset is needed.

@export var hold: float = 6.0
@export var fade: float = 2.5
@export var radius: float = 1.6

static var _tex: Texture2D = null

func _ready() -> void:
	texture_albedo = _scorch_texture()
	size = Vector3(radius * 2.0, 3.0, radius * 2.0)
	rotation.y = randf() * TAU # vary the burn so repeats don't tile
	modulate = Color(1, 1, 1, 1)
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_property(self, "modulate:a", 0.0, fade)
	tw.tween_callback(queue_free)

## A soft, slightly irregular dark radial burn (alpha fades to the edge). Built
## once and shared by every scorch mark.
static func _scorch_texture() -> Texture2D:
	if _tex != null:
		return _tex
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s * 0.5, s * 0.5)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var d: float = p.distance_to(c) / (s * 0.5)
			# Irregular edge: wobble the radius by angle so it isn't a perfect disc.
			var ang := (p - c).angle()
			var edge := 0.82 + 0.12 * sin(ang * 5.0) + 0.06 * sin(ang * 11.0 + 1.3)
			var a := clampf(1.0 - d / edge, 0.0, 1.0)
			a = pow(a, 1.4) * 0.85 # darker core, soft falloff
			var burn := 0.03 + 0.05 * (1.0 - a) # near-black center, faint brown rim
			img.set_pixel(x, y, Color(burn, burn * 0.85, burn * 0.7, a))
	_tex = ImageTexture.create_from_image(img)
	return _tex
