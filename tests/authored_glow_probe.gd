extends Node3D
## Probe: a light built into a robot's model stays lit in the game.
## The models this game builds itself (tools/blender/build_*.py) carry their
## lamps as emissive materials: the HOWITZER's amber optics, the REAPER's eye
## slits and core, the GUNSLINGER's furnace grate and monocle. RobotModel
## re-materials every surface for the damage flare, which set each one's
## emission to the flare colour at zero energy, and with robot triplanar on (the
## default) swapped in a shader with no emission at all, so every built-in lamp
## was dark. For each model, with triplanar on and off:
## (1) it has at least one surface whose material is a lamp;
## (2) alive, every such surface still emits its own colour at its own energy;
## (3) dead, those surfaces go dark with the wreck (energy under 0.05 in 2 s).
##   godot --headless --path . --audio-driver Dummy res://tests/authored_glow_probe.tscn

const SCENES := [
	"res://scenes/enemies/howitzer.tscn",
	"res://scenes/enemies/reaper.tscn",
	"res://scenes/enemies/gunslinger.tscn",
	"res://scenes/enemies/server.tscn",   # its own build too, and no flare at all (menace_glow 0)
]
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

## [MeshInstance3D, surface, imported material] for every lamp surface of the
## robot's model (under its RobotModel node: a part the enemy script lights
## itself, the COLOSSUS's reactor weak point, is that script's business).
func _lamps(e: Node) -> Array:
	var out := []
	for mi in e.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var src := m.surface_get_material(s) as BaseMaterial3D
			if src and src.emission_enabled and src.emission_energy_multiplier > 0.0 \
					and src.emission.get_luminance() > 0.05 and src.emission_texture == null:
				out.append([mi, s, src])
	return out

func _energy(mi: MeshInstance3D, s: int) -> float:
	var m := mi.get_active_material(s) as BaseMaterial3D
	if m == null or not m.emission_enabled:
		return 0.0
	return m.emission_energy_multiplier

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_floor()
	var was: bool = GraphicsSettings.robot_triplanar_enabled
	for triplanar in [true, false]:
		GraphicsSettings.robot_triplanar_enabled = triplanar
		for path in SCENES:
			var name := "%s (triplanar %s)" % [path.get_file().get_basename(), "on" if triplanar else "off"]
			var e: Node3D = (load(path) as PackedScene).instantiate()
			e.set_physics_process(false)
			add_child(e)
			e.global_position = Vector3(0, 0.05, 0)
			for i in 10:
				await get_tree().process_frame
			var lamps := _lamps(e)
			_check("%s has a built-in light" % name, not lamps.is_empty(), "(%d surfaces)" % lamps.size())
			var lit := 0
			var worst := ""
			for l in lamps:
				var src: BaseMaterial3D = l[2]
				var m := (l[0] as MeshInstance3D).get_active_material(l[1]) as BaseMaterial3D
				if m and m.emission_enabled and absf(m.emission_energy_multiplier - src.emission_energy_multiplier) < 0.01 \
						and m.emission.is_equal_approx(src.emission):
					lit += 1
				elif worst == "":
					worst = "%s surface %d: %s" % [(l[0] as Node).name, l[1], "no emissive material" if m == null or not m.emission_enabled \
						else "energy %.2f colour %s, imported %.2f %s" % [m.emission_energy_multiplier, m.emission, src.emission_energy_multiplier, src.emission]]
			if not lamps.is_empty():
				_check("%s: every built-in light is lit" % name, lit == lamps.size(), "(%d of %d) %s" % [lit, lamps.size(), worst])
				var hp: Node = e.get_node("Damageable")
				hp.apply_damage(100000.0, null)
				var t := 0.0
				var dark := false
				while t < 2.0 and not dark:
					await get_tree().create_timer(0.25).timeout
					t += 0.25
					dark = true
					for l in lamps:
						if is_instance_valid(l[0]) and _energy(l[0], l[1]) > 0.05:
							dark = false
				_check("%s: built-in lights go dark when it dies" % name, dark, "(%.2f s)" % t)
			if is_instance_valid(e):
				e.queue_free()
			await get_tree().process_frame
	GraphicsSettings.robot_triplanar_enabled = was
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
