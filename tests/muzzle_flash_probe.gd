extends Node3D
## Probe: a gunshot's muzzle flash is a three-card flash (scripts/fx/muzzle_flash.gd),
## not a ball with box spikes. For every gun that throws one, fired from the
## player's real camera:
##   - it has a front star across the bore (its face turned down the barrel) and
##     two side prongs that lie along the bore and reach out ahead of the muzzle;
##   - every card is drawn in the gun's shot colour (shot_color);
##   - seen from the eye it is big enough to read (>= MIN_DEG) and never
##     covers the view (< MAX_DEG), on every frame of its life;
##   - two shots in a row never draw the same flash (petal count / roll differ);
##   - its cards are dark by `lifetime` and the node is gone within 0.6 s.
## A flash with nothing to align to (an enemy's, `along_bore` off) is a single
## camera-facing star with no prongs.
##   godot --headless --path . --audio-driver Dummy res://tests/muzzle_flash_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const FLASH_SCENE := preload("res://scenes/fx/muzzle_flash.tscn")
const FLASH_SCRIPT := preload("res://scripts/fx/muzzle_flash.gd")
const MIN_DEG := 2.0
const MAX_DEG := 16.0

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(60, 1, 60)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	for i in 10:
		await get_tree().physics_frame
	player.set_physics_process(false)
	var cam := player.get_node("Head/Camera3D") as Camera3D
	var wm: Node = player.get_node("Head/Camera3D/WeaponHolder")
	var guns := 0
	for p: String in GameState.WEAPON_ORDER:
		var id := p.get_file().get_basename()
		wm.add_weapon(load(p), false)
		for i in wm.weapons.size():
			if (wm.weapons[i] as Weapon).scene_file_path == p:
				wm._equip(i)
		await get_tree().process_frame
		var w: Weapon = wm.current
		if w.data.muzzle_flash_scene == null:
			continue
		guns += 1
		w._play_muzzle()
		var f := _newest_flash(w)
		_check("%s throws a flash" % id, f != null)
		if f == null:
			continue
		var bore := -w.muzzle.global_basis.z.normalized()
		var star: MeshInstance3D = f.star
		_check("%s flash has a front star across the bore" % id,
				star != null and absf(star.global_basis.z.normalized().dot(bore)) > 0.95)
		var prongs: Array = f.prongs
		var along := prongs.size() == 2 and prongs.all(func(m: MeshInstance3D) -> bool:
				var ahead := (m.global_position - w.muzzle.global_position).dot(bore) > 0.05
				return ahead and absf(m.global_basis.y.normalized().dot(bore)) > 0.95)
		_check("%s flash has two prongs along the bore, ahead of the muzzle" % id, along)
		var col := w.shot_color()
		var tinted: bool = f.cards().all(func(m: MeshInstance3D) -> bool:
				var c: Color = (m.material_override as ShaderMaterial).get_shader_parameter("tint")
				return c.is_equal_approx(col))
		_check("%s flash is drawn in the gun's colour" % id, tinted)
		var seed_a: float = f.seed_value()
		w._play_muzzle()
		var f2 := _newest_flash(w)
		_check("%s two shots draw two different flashes" % id, f2 != null and f2 != f
				and not is_equal_approx(seed_a, f2.seed_value()))
		var lo := INF
		var hi := 0.0
		var t0 := Time.get_ticks_msec()
		var dark_by_lifetime := true
		while is_instance_valid(f) and Time.get_ticks_msec() - t0 < 1000:
			var age: float = f._age
			if age <= f.lifetime:
				var deg := _angular_radius_deg(star, cam)
				lo = minf(lo, deg)
				hi = maxf(hi, deg)
			elif f.cards().any(func(m: MeshInstance3D) -> bool: return m.visible):
				dark_by_lifetime = false
			await get_tree().process_frame
		var life := (Time.get_ticks_msec() - t0) / 1000.0
		print("   %-10s flash star %.1f-%.1f deg, gone after %.2f s" % [id, lo, hi, life])
		_check("%s flash reads from the eye (>= %.0f deg)" % [id, MIN_DEG], lo >= MIN_DEG, "%.1f" % lo)
		_check("%s flash never covers the view (< %.0f deg)" % [id, MAX_DEG], hi < MAX_DEG, "%.1f" % hi)
		_check("%s flash goes dark at its lifetime" % id, dark_by_lifetime)
		_check("%s flash is gone within 0.6 s" % id, not is_instance_valid(f) and life <= 0.6, "%.2f s" % life)
		for i in 30:
			await get_tree().process_frame
	_check("the flash-throwing guns were all checked", guns >= 13, str(guns))
	# An enemy's flash: no bore to align to, so one camera-facing star.
	var lone: Node3D = FLASH_SCENE.instantiate()
	add_child(lone)
	_check("an enemy flash is one star and no prongs",
			lone.star != null and lone.prongs.is_empty() and lone.cards().size() == 1)
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## The flash most recently added under the gun's muzzle.
func _newest_flash(w: Weapon) -> Node3D:
	var kids := w.muzzle.get_children().filter(func(n: Node) -> bool:
			return n.get_script() == FLASH_SCRIPT and not n.is_queued_for_deletion())
	return kids.back() if not kids.is_empty() else null

## Half the angle the star card's width spans from the camera.
func _angular_radius_deg(card: MeshInstance3D, cam: Camera3D) -> float:
	var q := card.mesh as QuadMesh
	var r := q.size.x * 0.5 * card.global_basis.get_scale().x
	var d := maxf(0.01, cam.global_position.distance_to(card.global_position))
	return rad_to_deg(atan(r / d))
