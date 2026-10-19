extends Node3D
## Probe: an explosion's fireball (ExplosionFX._fireball) is fire, not a white
## dome. It used to be a sphere with white-hot albedo and an 18x emission that
## rendered flat white through most of its 0.24 s (tests/explosion_screenshot).
## For the grenade and the robot-death explosion:
##   - the fireball is drawn by shaders/explosion_fireball.gdshader in the
##     blast's colour;
##   - it burns from fresh to spent: `burn` starts under 0.1, never goes back,
##     and passes 0.95 before the ball is gone;
##   - it lives long enough to read as fire (>= MIN_LIFE s) and is gone within
##     MAX_LIFE s;
##   - it swells to at least the blast size;
##   - the pillar of fire above it (FireColumn) burns with the same shader.
##   godot --headless --path . --audio-driver Dummy res://tests/explosion_fireball_probe.tscn

const SHADER_PATH := "res://shaders/explosion_fireball.gdshader"
const MIN_LIFE := 0.3
const MAX_LIFE := 0.8
const BLASTS := [
	["res://scenes/fx/grenade_explosion.tscn", 4.3, Color(1.0, 0.55, 0.18)],
	["res://scenes/fx/enemy_explosion.tscn", 2.0, Color(1.0, 0.62, 0.25)],
]

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 3, 9), Vector3.ZERO, Vector3.UP)
	for b: Array in BLASTS:
		var id := String(b[0]).get_file().get_basename()
		# Load first and let frames settle: a frame that pays for the load hands
		# the tweens a huge delta and the ball would burn out "early".
		var ps := load(b[0]) as PackedScene
		for i in 5:
			await get_tree().process_frame
		var fx := ps.instantiate() as Node3D
		add_child(fx)
		var ball := fx.find_child("Fireball", true, false) as MeshInstance3D
		var mat := (ball.material_override as ShaderMaterial) if ball else null
		_check("%s fireball is drawn by the fireball shader" % id,
				mat != null and mat.shader != null and mat.shader.resource_path == SHADER_PATH)
		if mat == null:
			fx.queue_free()
			continue
		var column := fx.find_child("FireColumn", true, false) as MeshInstance3D
		var cmat := (column.material_override as ShaderMaterial) if column else null
		_check("%s fire column burns with the fireball shader" % id,
				cmat != null and cmat.shader != null and cmat.shader.resource_path == SHADER_PATH)
		var tint: Color = mat.get_shader_parameter("tint")
		_check("%s fireball takes the blast colour" % id, tint.is_equal_approx(b[2]), str(tint))
		var first := -1.0
		var last := 0.0
		var backwards := false
		var widest := 0.0
		var t0 := Time.get_ticks_msec()
		while is_instance_valid(ball) and Time.get_ticks_msec() - t0 < 2000:
			var burn: float = mat.get_shader_parameter("burn")
			if first < 0.0:
				first = burn
			backwards = backwards or burn < last - 0.0001
			last = burn
			widest = maxf(widest, ball.scale.x)
			await get_tree().process_frame
		var life := (Time.get_ticks_msec() - t0) / 1000.0
		print("   %s: burn %.2f -> %.2f, widest %.2f m, gone after %.2f s" % [id, first, last, widest, life])
		_check("%s fireball starts fresh" % id, first < 0.1, "%.2f" % first)
		_check("%s fireball burns steadily to spent" % id, not backwards and last >= 0.95, "%.2f" % last)
		_check("%s fireball lives %.1f-%.1f s" % [id, MIN_LIFE, MAX_LIFE],
				not is_instance_valid(ball) and life >= MIN_LIFE and life <= MAX_LIFE, "%.2f s" % life)
		_check("%s fireball swells to the blast size" % id, widest >= float(b[1]), "%.2f of %.1f m" % [widest, b[1]])
		fx.queue_free()
		await get_tree().process_frame
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
