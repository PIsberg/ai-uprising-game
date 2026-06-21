class_name Weapon
extends Node3D

signal fired(weapon: Weapon)
signal reload_started(weapon: Weapon)
signal reload_finished(weapon: Weapon)
signal ammo_changed(mag: int, reserve: int)

@export var data: WeaponData
@export var viewmodel: Node3D
@export var muzzle: Node3D

# ---------- effective stats (base data × armory upgrades) ----------
# WeaponData resources are shared, so upgrades are never written into them —
# every read goes through these. GameState owns the multipliers.

func eff_damage() -> float:
	return data.damage * GameState.upgrade_mult("damage") * GameState.damage_mult() * _alt_boost

## Effective fire rate — OVERDRIVE cranks it up so cooldowns shorten across all
## fire modes (semi/auto/burst/beam).
func eff_fire_rate() -> float:
	return data.fire_rate * GameState.fire_rate_mult()

func eff_mag_size() -> int:
	return int(round(data.mag_size * GameState.upgrade_mult("mag")))

func eff_reload_time() -> float:
	return data.reload_time * GameState.upgrade_reload_mult()

var mag: int = 0
var reserve: int = 0
var _cooldown: float = 0.0
var _reloading: bool = false
var _reload_timer: float = 0.0
var _burst_remaining: int = 0
var _burst_timer: float = 0.0
var _trigger_held_last: bool = false

# Cached for animation
var _viewmodel_home: Vector3
var _slide_home: Vector3
var _pump_home: Vector3
var _mag_home: Vector3
var _slide_node: Node3D
var _pump_node: Node3D
var _mag_node: Node3D

# Continuous-beam (FireMode.BEAM) state: the visual updates every frame while
# the trigger is held; damage/ammo tick at data.fire_rate.
var _beam: ElectricBeam
var _beam_wanted: bool = false
var _beam_tick: float = 0.0
var _beam_pop: int = 0

# Barrel heat: rises with every shot, bleeds off when you stop. The muzzle tip
# glows from a dull ember to a fierce orange as you mag-dump.
var _heat: float = 0.0
var _heat_glow: MeshInstance3D = null
var _heat_mat: StandardMaterial3D = null
var _heat_light: OmniLight3D = null

func _ready() -> void:
	if viewmodel == null:
		viewmodel = get_node_or_null("Viewmodel")
	if muzzle == null and viewmodel:
		muzzle = viewmodel.get_node_or_null("Muzzle")
	if viewmodel:
		_viewmodel_home = viewmodel.position
		_slide_node = viewmodel.get_node_or_null("Slide") as Node3D
		_pump_node = viewmodel.get_node_or_null("Pump") as Node3D
		_mag_node = viewmodel.get_node_or_null("Magazine") as Node3D
		if _slide_node:
			_slide_home = _slide_node.position
		if _pump_node:
			_pump_home = _pump_node.position
		if _mag_node:
			_mag_home = _mag_node.position
	if data:
		mag = eff_mag_size()
		reserve = data.reserve_max
		ammo_changed.emit(mag, reserve)
	if not _apply_real_model():
		_bevel_viewmodel()
	_build_heat_glow()

## Imported gun models (Kenney "Blaster Kit", CC0) keyed by weapon scene name.
## `len` is the wanted barrel-to-stock length in metres (the GLB is uniformly
## scaled to it), `tint` multiplies the kit's white-plastic albedo so each gun
## reads as gunmetal with the weapon's energy-color identity.
const REAL_MODELS := {
	"pistol":     {"glb": "res://assets/models/weapons/blaster-b.glb", "len": 0.42, "tint": Color(0.5, 0.52, 0.56)},
	"smg":        {"glb": "res://assets/models/weapons/blaster-c.glb", "len": 0.5, "tint": Color(0.48, 0.5, 0.54)},
	"rifle":      {"glb": "res://assets/models/weapons/blaster-d.glb", "len": 0.78, "tint": Color(0.46, 0.48, 0.52)},
	"shotgun":    {"glb": "res://assets/models/weapons/blaster-a.glb", "len": 0.72, "tint": Color(0.52, 0.48, 0.44)},
	"plasma":     {"glb": "res://assets/models/weapons/blaster-l.glb", "len": 0.58, "tint": Color(0.44, 0.56, 0.46)},
	"gauss":      {"glb": "res://assets/models/weapons/blaster-e.glb", "len": 0.95, "tint": Color(0.44, 0.5, 0.6)},
	"tesla":      {"glb": "res://assets/models/weapons/blaster-o.glb", "len": 0.52, "tint": Color(0.42, 0.54, 0.58)},
	"arccoil":    {"glb": "res://assets/models/weapons/blaster-q.glb", "len": 0.68, "tint": Color(0.58, 0.5, 0.4)},
	"twinrail":   {"glb": "res://assets/models/weapons/blaster-f.glb", "len": 0.95, "tint": Color(0.46, 0.52, 0.62)},
	"devastator": {"glb": "res://assets/models/weapons/blaster-p.glb", "len": 0.8, "tint": Color(0.56, 0.44, 0.42)},
	"singularity": {"glb": "res://assets/models/weapons/blaster-r.glb", "len": 0.98, "tint": Color(0.5, 0.32, 0.66)},
	"nova":        {"glb": "res://assets/models/weapons/blaster-m.glb", "len": 0.82, "tint": Color(0.62, 0.42, 0.28)},
	"swarm":       {"glb": "res://assets/models/weapons/blaster-n.glb", "len": 0.74, "tint": Color(0.62, 0.4, 0.3)},
	"omega":       {"glb": "res://assets/models/weapons/blaster-g.glb", "len": 1.0, "tint": Color(0.74, 0.58, 0.32)},
	"sniper":      {"glb": "res://assets/models/weapons/blaster-h.glb", "len": 1.22, "tint": Color(0.4, 0.48, 0.62)},
	"magnum":      {"glb": "res://assets/models/weapons/blaster-j.glb", "len": 0.42, "tint": Color(0.62, 0.5, 0.36)},
}

## Swap the primitive viewmodel for the real imported gun model, auto-fitted:
## scaled to the configured length, grip parked at the viewmodel origin, the
## Muzzle node moved to the new barrel tip. The primitive parts are hidden (not
## freed) so the Slide/Pump/Magazine animation lookups stay valid. Returns
## false when this weapon has no model mapped (grenade etc. keep primitives).
func _apply_real_model() -> bool:
	if viewmodel == null:
		return false
	var key := scene_file_path.get_file().get_basename()
	var cfg: Dictionary = REAL_MODELS.get(key, {})
	if cfg.is_empty():
		return false
	var ps: PackedScene = load(cfg["glb"])
	if ps == null:
		return false
	var model := ps.instantiate() as Node3D
	# Hide the primitive placeholder parts; Muzzle (plain Node3D) is unaffected.
	for n in viewmodel.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).visible = false
	viewmodel.add_child(model)
	# Measure the model in its own space, then fit: uniform scale to `len`,
	# rear of the gun parked just behind the grip (origin), vertically centred
	# on the barrel line the old viewmodels used.
	var aabb := _merged_aabb(model)
	if aabb.size.z <= 0.001:
		return true
	var s: float = cfg["len"] / aabb.size.z
	model.scale = Vector3.ONE * s
	model.position = Vector3(
		-(aabb.position.x + aabb.size.x * 0.5) * s,
		0.02 - (aabb.position.y + aabb.size.y * 0.8) * s,
		0.18 - aabb.end.z * s)
	# Barrel tip = front face of the fitted model, slightly proud of it.
	if muzzle:
		muzzle.position.z = 0.18 - cfg["len"] - 0.03
	# Gunmetal/energy tint over the kit's flat plastic albedo.
	var tint: Color = cfg["tint"]
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m is BaseMaterial3D:
				var dup := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				dup.albedo_color = dup.albedo_color * tint
				dup.metallic = 0.55
				dup.roughness = 0.45
				mi.set_surface_override_material(i, dup)
	return true

func _merged_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			var xf := mi.transform
			var p := mi.get_parent()
			while p != null and p != root and p is Node3D:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var ab: AABB = xf * mi.mesh.get_aabb()
			merged = ab if first else merged.merge(ab)
			first = false
	return merged

## Swap every plain BoxMesh in the viewmodel for a BeveledBoxMesh of the same
## size/material. Chamfered edges catch specular highlights, which is most of
## what separates "machined" from "programmer art" — and doing it here upgrades
## every weapon scene without touching them.
func _bevel_viewmodel() -> void:
	if viewmodel == null:
		return
	for n in viewmodel.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box := mi.mesh as BoxMesh
		if box == null:
			continue
		var bev := BeveledBoxMesh.new()
		bev.size = box.size
		bev.bevel = minf(0.008, box.size[box.size.min_axis_index()] * 0.18)
		bev.material = box.material
		mi.mesh = bev

## A small emissive element pinned at the muzzle tip; alpha/energy ride _heat so
## the barrel visibly glows hotter the longer you hold the trigger.
func _build_heat_glow() -> void:
	if muzzle == null:
		return
	_heat_glow = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.16
	sm.radial_segments = 8
	sm.rings = 4
	_heat_glow.mesh = sm
	_heat_mat = StandardMaterial3D.new()
	_heat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_heat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_heat_mat.emission_enabled = true
	_heat_mat.albedo_color = Color(1.0, 0.45, 0.1, 0.0)
	_heat_mat.emission = Color(1.0, 0.4, 0.08)
	_heat_mat.emission_energy_multiplier = 0.0
	_heat_glow.material_override = _heat_mat
	_heat_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle.add_child(_heat_glow)
	_heat_light = OmniLight3D.new()
	_heat_light.light_color = Color(1.0, 0.45, 0.12)
	_heat_light.light_energy = 0.0
	_heat_light.omni_range = 1.6
	_heat_glow.add_child(_heat_light)

func _process(delta: float) -> void:
	_update_heat(delta)
	_update_beam(delta)
	if _cooldown > 0.0:
		_cooldown -= delta
	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()
	if _burst_remaining > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst_timer = 1.0 / maxf(0.1, eff_fire_rate())
			_burst_remaining -= 1
			_do_shot()

func try_fire(trigger_down: bool, aiming: bool, camera: Camera3D, shooter: Node) -> void:
	var just_pressed := trigger_down and not _trigger_held_last
	_trigger_held_last = trigger_down
	if data and data.fire_mode == WeaponData.FireMode.BEAM:
		# Beam weapons don't use the shot/cooldown machinery: try_fire just
		# records intent + context; _update_beam() does the work each frame.
		_beam_wanted = trigger_down and not _reloading and mag > 0
		if _beam_wanted:
			_active_camera = camera
			_active_shooter = shooter
			_active_aiming = aiming
		elif just_pressed and mag <= 0 and not _reloading:
			_play_empty()
		return
	if _reloading or _cooldown > 0.0 or data == null:
		return
	if mag <= 0:
		if just_pressed:
			_play_empty()
		return
	match data.fire_mode:
		WeaponData.FireMode.SEMI:
			if just_pressed:
				_fire_once(camera, shooter, aiming)
		WeaponData.FireMode.AUTO:
			if trigger_down:
				_fire_once(camera, shooter, aiming)
		WeaponData.FireMode.BURST:
			if just_pressed:
				_burst_remaining = data.burst_count
				_burst_timer = 0.0
				_fire_once(camera, shooter, aiming)

func _fire_once(camera: Camera3D, shooter: Node, aiming: bool) -> void:
	if mag <= 0:
		return
	mag -= 1
	_cooldown = 1.0 / maxf(0.1, eff_fire_rate())
	ammo_changed.emit(mag, reserve)
	# Low-mag warning: a dry tick under the report that rises in pitch as the
	# mag runs down — you hear the reload coming without checking the HUD.
	var low := ceili(eff_mag_size() * 0.25)
	if mag > 0 and mag <= low:
		AudioBus.play_synth_ui("empty_click", -14.0, 1.3 + 0.9 * (1.0 - float(mag) / float(low)))
	_active_camera = camera
	_active_shooter = shooter
	_active_aiming = aiming
	_do_shot()
	# Per-shot camera punch — small, but it sells the report; heavier-recoil
	# guns thump the view harder. (Charged alt-fire adds its own on top.)
	if shooter and shooter.has_method("shake"):
		shooter.shake(clampf(0.04 + data.recoil_pitch * 0.045, 0.05, 0.22))

var _active_camera: Camera3D
var _active_shooter: Node
var _active_aiming: bool = false

# ---------- alt-fire (V / mouse thumb; mode per WeaponData.alt_mode) ----------

const ALT_COST := 3            # ammo per CHARGE/VOLLEY use
const ALT_CHARGE_TIME := 0.9   # seconds to a full charge

var _alt_boost := 1.0          # damage multiplier folded into eff_damage()
var _alt_tight := false        # zero-spread flag read by _do_shot
var _alt_slug := false         # collapse pellets read by _do_shot
var _alt_charge := 0.0
var _alt_held := false
var _alt_prev := false
var _alt_step := 0             # rising charge-tick audio stage

## Driven every frame by WeaponManager with the alt-fire button state.
func try_alt_fire(pressed: bool, delta: float, camera: Camera3D, shooter: Node) -> void:
	var just := pressed and not _alt_prev
	_alt_prev = pressed
	if data == null or data.alt_mode == WeaponData.AltMode.NONE or _reloading:
		_cancel_charge()
		return
	match data.alt_mode:
		WeaponData.AltMode.CHARGE:
			_alt_charge_logic(pressed, delta, camera, shooter)
		WeaponData.AltMode.VOLLEY:
			if just and _cooldown <= 0.0 and mag >= ALT_COST:
				_fire_volley(camera, shooter)
			elif just and mag < ALT_COST:
				_play_empty()
		WeaponData.AltMode.SLUG:
			if just and _cooldown <= 0.0 and mag > 0:
				_alt_slug = true
				_alt_tight = true
				# One pellet carries most of the spread-pattern's payload.
				_alt_boost = maxf(1.0, data.pellets * 0.8)
				_fire_once(camera, shooter, true)
				_alt_boost = 1.0
				_alt_tight = false
				_alt_slug = false
				_cooldown *= 1.6 # heavier shot, slower follow-up

## Hold to charge (barrel heat ramps as feedback), release to loose a single
## perfectly-accurate shot at up to ~3.4× damage for 3 ammo.
func _alt_charge_logic(pressed: bool, delta: float, camera: Camera3D, shooter: Node) -> void:
	if pressed and _cooldown <= 0.0 and mag >= ALT_COST:
		_alt_held = true
		_alt_charge = minf(1.0, _alt_charge + delta / ALT_CHARGE_TIME)
		_heat = maxf(_heat, _alt_charge) # the muzzle visibly builds up
		var step := int(_alt_charge * 4.0)
		if step != _alt_step:
			_alt_step = step
			AudioBus.play_synth_ui("empty_click", -12.0, 0.9 + 0.25 * step)
		return
	if _alt_held: # released (or interrupted)
		_alt_held = false
		_alt_step = 0
		if _alt_charge >= 0.25 and mag >= ALT_COST:
			_alt_boost = 1.0 + 2.4 * _alt_charge
			_alt_tight = true
			mag -= ALT_COST - 1 # _fire_once spends the last round
			_fire_once(camera, shooter, true)
			_alt_boost = 1.0
			_alt_tight = false
			_cooldown = maxf(_cooldown, 0.55)
			if shooter and shooter.has_method("shake"):
				shooter.shake(0.3 + 0.3 * _alt_charge)
		_alt_charge = 0.0

func _cancel_charge() -> void:
	_alt_held = false
	_alt_charge = 0.0
	_alt_step = 0

## Instant 3-round laser-tight burst, spaced just enough to read as a volley.
func _fire_volley(camera: Camera3D, shooter: Node) -> void:
	_alt_tight = true
	for i in ALT_COST:
		if mag <= 0 or data == null:
			break
		_fire_once(camera, shooter, true)
		if i < ALT_COST - 1:
			await get_tree().create_timer(0.07).timeout
			if not is_instance_valid(self) or not is_inside_tree():
				return
	_alt_tight = false
	_cooldown = (1.0 / maxf(0.1, eff_fire_rate())) * 2.2 # breather after the volley

func _do_shot() -> void:
	if _active_camera == null or data == null:
		return
	GameState.register_shot() # accuracy stat for the end-of-level grade
	var spread := deg_to_rad(data.spread_deg)
	if _active_aiming:
		spread *= data.aim_spread_mult
	if _alt_tight:
		spread = 0.0 # alt-fire shots are laser-accurate
	var origin := _active_camera.global_position
	var base_dir := -_active_camera.global_transform.basis.z
	for _i in (1 if _alt_slug else data.pellets):
		var dir := _scattered(base_dir, spread)
		match data.damage_type:
			WeaponData.DamageType.HITSCAN:
				_do_hitscan(origin, dir)
			WeaponData.DamageType.PROJECTILE:
				_spawn_projectile(origin, dir)
	_play_muzzle()
	if data.damage_type == WeaponData.DamageType.PROJECTILE:
		_energy_muzzle()
		if data.splash_radius > 0.0:
			_launch_flame()
	_muzzle_sparks()
	_muzzle_shockwave()
	_eject_brass()
	_muzzle_smoke()
	_play_fire_sound()
	_play_fire_anim()
	fired.emit(self)

func _scattered(dir: Vector3, max_angle: float) -> Vector3:
	if max_angle <= 0.0:
		return dir
	var rand_axis := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
	var angle := randf() * max_angle
	return dir.rotated(rand_axis, angle).normalized()

func _do_hitscan(origin: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var exclude: Array = []
	if _active_shooter and _active_shooter is CollisionObject3D:
		exclude.append((_active_shooter as CollisionObject3D).get_rid())
	var cur := origin
	var remaining := data.range_m
	var pierces_left := data.pierce
	var end_point := origin + dir * data.range_m
	# Walk the beam forward: punch through enemies up to `pierce`, but stop dead
	# on world geometry. A single tracer is drawn from origin to the final point.
	while true:
		var q := PhysicsRayQueryParameters3D.create(cur, cur + dir * remaining)
		q.collision_mask = 0b0000101 # world + enemy
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			end_point = cur + dir * remaining
			break
		var hpos: Vector3 = hit.position
		var col := hit.collider as Node
		var dmg_node: Node = null
		if col:
			dmg_node = _find_damageable(col)
		var surf := _surface_of(col, dmg_node != null) if col else "concrete"
		_spawn_impact(hpos, hit.normal, surf)
		var snd := "impact_metal" if surf == "metal" else "impact_concrete"
		var pitch := randf_range(0.7, 0.85) if surf == "dirt" else randf_range(0.9, 1.1)
		AudioBus.play_synth_at(snd, hpos, -8.0, pitch)
		if dmg_node == null:
			_spawn_bullet_hole(hpos, hit.normal)
		if dmg_node:
			var final_damage := eff_damage()
			var is_head := false
			if col.has_method("is_headshot"):
				is_head = col.is_headshot(hpos.y)
			elif col is Node3D:
				is_head = hpos.y - (col as Node3D).global_position.y > 0.6
			if is_head:
				final_damage *= data.headshot_mult
				AudioBus.play_synth_at("headshot", hpos, -1.0, 1.0)
			dmg_node.apply_damage(final_damage, _active_shooter)
			_enemy_hit_pop(hpos, is_head, final_damage)
			# Punch through to the next enemy if this weapon pierces.
			if pierces_left > 0 and col is CollisionObject3D:
				pierces_left -= 1
				exclude.append((col as CollisionObject3D).get_rid())
				remaining -= cur.distance_to(hpos) + 0.05
				cur = hpos + dir * 0.05
				if remaining > 0.0:
					continue
			end_point = hpos
			break
		else:
			end_point = hpos # world geometry stops the beam
			break
	# Draw the visible round from the muzzle (not the eye) to where it landed, so
	# it reads as leaving the rifle and striking the target.
	_spawn_tracer(muzzle.global_position if muzzle else origin, end_point)

## A bright expanding flash + light when a shot connects with an enemy, plus a
## burst of metal embers/debris that scales with how hard the hit landed.
func _enemy_hit_pop(pos: Vector3, is_head: bool, dmg: float = 10.0) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_spawn_debris(scene, pos, dmg, is_head)
	var col := Color(1.0, 0.95, 0.7) if is_head else Color(1.0, 0.85, 0.5)
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var r := 0.16 if is_head else 0.1
	sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 8; sm.rings = 5
	orb.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 10.0
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(orb)
	orb.global_position = pos
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 4.0
	light.omni_range = 3.0
	orb.add_child(light)
	var tw := orb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "scale", Vector3.ONE * (2.4 if is_head else 1.8), 0.11)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.11)
	tw.tween_property(light, "light_energy", 0.0, 0.11)
	tw.chain().tween_callback(orb.queue_free)

## Metal chunks/embers flung off the enemy on a hit; more on heavier hits.
func _spawn_debris(scene: Node, pos: Vector3, dmg: float, is_head: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.04, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.55)
	mat.metallic = 0.8
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.25) if is_head else Color(1.0, 0.5, 0.2)
	mat.emission_energy_multiplier = 2.5
	mesh.material = mat

	var amount := clampi(int(4 + dmg * 0.4), 5, 26)
	if GraphicsSettings.gpu_particles_enabled:
		amount *= 3
		
	var p := GraphicsSettings.create_particles(
		amount,
		0.5,
		1.0,
		Vector3.UP,
		80.0,
		Vector3(0, -22, 0),
		3.0,
		7.0 + dmg * 0.1,
		0.2,
		0.5,
		mesh
	)
	scene.add_child(p)
	p.global_position = pos
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

func _spawn_projectile(origin: Vector3, dir: Vector3) -> void:
	if data.projectile_scene == null:
		return
	var proj := data.projectile_scene.instantiate()
	get_tree().current_scene.add_child(proj)
	proj.global_position = origin + dir * 0.5
	# Bound the round's reach to the weapon's range_m so projectile guns obey the
	# same range envelope as hitscan ones (past it, the round expires —
	# detonating splash rounds at their max range instead of flying forever).
	if data.projectile_speed > 0.0 and "lifetime" in proj:
		proj.lifetime = data.range_m / data.projectile_speed
	if proj.has_method("launch"):
		proj.launch(dir * data.projectile_speed, _active_shooter, eff_damage(), data.splash_radius, data.splash_damage)

func _find_damageable(node: Node) -> Node:
	var n := node
	while n:
		var d := n.get_node_or_null("Damageable")
		if d:
			return d
		n = n.get_parent()
	return null

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	if data.tracer_scene == null:
		return
	var t := data.tracer_scene.instantiate()
	get_tree().current_scene.add_child(t)
	# Fly the round as a visible bolt from the muzzle to the impact point so the
	# player sees the shot travel and connect (damage stays instant hitscan; the
	# bolt is fast enough — 150 m/s — to stay snappy).
	if "bolt" in t:
		t.bolt = true
		t.bolt_speed = 150.0
		t.bolt_length = 2.2
		t.bolt_width = 1.5
	if t.has_method("setup"):
		t.setup(from, to, data.tracer_color)

# Persistent bullet scars on world geometry. Capped: the oldest hole is
# recycled once the budget is full, so mag-dumping never piles up decals.
const MAX_BULLET_HOLES := 36

func _spawn_bullet_hole(pos: Vector3, normal: Vector3) -> void:
	var tree := get_tree()
	var holes := tree.get_nodes_in_group("bullet_hole")
	if holes.size() >= MAX_BULLET_HOLES:
		holes[0].queue_free()
	var d := Decal.new()
	d.add_to_group("bullet_hole")
	d.texture_albedo = ScorchMark._scorch_texture() # radial burn doubles as a scar
	var s := randf_range(0.14, 0.24)
	d.size = Vector3(s, 0.35, s)
	d.cull_mask = 1
	tree.current_scene.add_child(d)
	# Project along the surface normal (Decal boxes project down local -Y).
	var up := normal.normalized()
	var x := up.cross(Vector3.FORWARD)
	if x.length_squared() < 0.01:
		x = up.cross(Vector3.RIGHT)
	x = x.normalized()
	d.global_transform = Transform3D(Basis(x, up, x.cross(up)).rotated(up, randf() * TAU), pos + up * 0.02)
	var tw := d.create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(d, "modulate:a", 0.0, 2.0)
	tw.tween_callback(d.queue_free)

func _spawn_impact(pos: Vector3, normal: Vector3, surface: String = "concrete") -> void:
	if data.impact_scene == null:
		return
	var i := data.impact_scene.instantiate()
	get_tree().current_scene.add_child(i)
	i.global_position = pos
	if i.has_method("orient"):
		i.orient(normal)
	if i.has_method("set_surface"):
		i.set_surface(surface)

## Continuous beam: raycast + redraw the lightning every frame while firing;
## damage and ammo tick at data.fire_rate (1 cell per tick).
func _update_beam(delta: float) -> void:
	if data == null or data.fire_mode != WeaponData.FireMode.BEAM:
		return
	if not _beam_wanted or _reloading or mag <= 0 or _active_camera == null or not visible:
		if _beam:
			_beam.deactivate()
		_beam_tick = 0.0 # first tick lands the instant the trigger is pressed
		return
	_ensure_beam()
	# Aim ray from the camera (where the crosshair is), draw from the muzzle.
	var origin := _active_camera.global_position
	var dir := -_active_camera.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * data.range_m)
	q.collision_mask = 0b0000101 # world + enemy
	if _active_shooter and _active_shooter is CollisionObject3D:
		q.exclude = [(_active_shooter as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	var end_point := origin + dir * data.range_m
	if not hit.is_empty():
		end_point = hit.position
	var from := muzzle.global_position if muzzle else global_position
	_beam.update_beam(from, end_point, not hit.is_empty())
	# Damage / ammo / feedback ticks.
	_beam_tick -= delta
	if _beam_tick > 0.0:
		return
	_beam_tick += 1.0 / maxf(0.1, eff_fire_rate())
	_beam_pop += 1
	mag -= 1
	ammo_changed.emit(mag, reserve)
	GameState.register_shot()
	_heat = minf(1.0, _heat + 0.06)
	AudioBus.play_synth_at("drone_shot", from, -12.0, randf_range(1.5, 2.1))
	if not hit.is_empty():
		var col := hit.collider as Node
		var dmg_node: Node = _find_damageable(col) if col else null
		if dmg_node:
			dmg_node.apply_damage(eff_damage(), _active_shooter)
			# Hit pop on every 4th tick — constant feedback without the FX spam.
			if _beam_pop % 4 == 0:
				_enemy_hit_pop(hit.position, false, eff_damage() * 2.0)
		elif _beam_pop % 6 == 0:
			_spawn_impact(hit.position, hit.normal, _surface_of(col, false) if col else "concrete")
	fired.emit(self)

func _ensure_beam() -> void:
	if _beam:
		return
	_beam = ElectricBeam.new()
	add_child(_beam)
	if data:
		_beam.set_color(data.tracer_color)

## Classify a hit surface from collider groups (enemies/destructibles read metal).
func _surface_of(col: Node, is_enemy: bool) -> String:
	if is_enemy or col.is_in_group("surf_metal"):
		return "metal"
	if col.is_in_group("surf_dirt"):
		return "dirt"
	return "concrete"

## Bleeds barrel heat off over time and drives the muzzle-tip glow from it.
func _update_heat(delta: float) -> void:
	if _heat > 0.0:
		_heat = maxf(0.0, _heat - delta * 0.9)
	if _heat_mat == null:
		return
	_heat_mat.albedo_color.a = _heat * 0.85
	_heat_mat.emission_energy_multiplier = _heat * 6.0
	if _heat_glow:
		_heat_glow.scale = Vector3.ONE * (1.0 + _heat * 0.6)
	if _heat_light:
		_heat_light.light_energy = _heat * 3.0

func _play_muzzle() -> void:
	# Each shot stokes the barrel; rapid fire pushes it toward white-hot.
	_heat = minf(1.0, _heat + 0.16)
	if data.muzzle_flash_scene == null or muzzle == null:
		return
	var m := data.muzzle_flash_scene.instantiate()
	muzzle.add_child(m)

## A bright expanding energy bloom at the muzzle for plasma/energy weapons.
func _energy_muzzle() -> void:
	if muzzle == null:
		return
	var col := data.tracer_color
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13; sm.height = 0.26; sm.radial_segments = 10; sm.rings = 6
	orb.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.9)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 9.0
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle.add_child(orb)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 5.0
	light.omni_range = 5.0
	orb.add_child(light)
	var tw := orb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "scale", Vector3.ONE * 1.7, 0.13)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.13)
	tw.tween_property(light, "light_energy", 0.0, 0.13)
	tw.chain().tween_callback(orb.queue_free)

## A brief gout of flame + smoke blooming off the muzzle when a heavy splash
## round (the rocket) launches — the back-pressure of the firing tube. A short
## additive flame cone down the barrel that flares then collapses.
func _launch_flame() -> void:
	if muzzle == null:
		return
	var flame := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.18
	cm.height = 0.7
	cm.radial_segments = 10
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.75, 0.4, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.25)
	mat.emission_energy_multiplier = 10.0
	cm.material = mat
	flame.mesh = cm
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lay the cone down the barrel (-Z), wide mouth out front.
	flame.rotation_degrees = Vector3(-90, 0, 0)
	flame.position = Vector3(0, 0, -0.35)
	muzzle.add_child(flame)
	var tw := flame.create_tween().set_parallel(true)
	tw.tween_property(flame, "scale", Vector3(1.6, 1.1, 1.6), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.14)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.14)
	tw.chain().tween_callback(flame.queue_free)

## Eject a tumbling brass casing out the right of the weapon (projectile weapons
## like the rocket/plasma don't use cartridges, so skip them).
func _eject_brass() -> void:
	if data.damage_type == WeaponData.DamageType.PROJECTILE or _active_camera == null:
		return
	var cam := _active_camera
	var p := CPUParticles3D.new()
	p.emitting = true; p.one_shot = true; p.amount = 1; p.lifetime = 1.1; p.explosiveness = 1.0
	p.local_coords = false
	p.direction = (cam.global_basis.x + cam.global_basis.y * 0.7).normalized()
	p.spread = 14.0
	p.initial_velocity_min = 1.8; p.initial_velocity_max = 2.7
	p.gravity = Vector3(0, -9.0, 0)
	p.angular_velocity_min = -900.0; p.angular_velocity_max = 900.0
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.006; mesh.bottom_radius = 0.006; mesh.height = 0.03; mesh.radial_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.62, 0.22); mat.metallic = 0.85; mat.roughness = 0.35
	mat.emission_enabled = true; mat.emission = Color(0.6, 0.4, 0.12); mat.emission_energy_multiplier = 0.4
	mesh.material = mat
	p.mesh = mesh
	get_tree().current_scene.add_child(p)
	p.global_position = global_position + cam.global_basis.x * 0.14 - cam.global_basis.y * 0.04
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)

## A short puff of smoke off the muzzle after firing.
func _muzzle_smoke() -> void:
	if muzzle == null:
		return
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	grad.colors = PackedColorArray([Color(0.7, 0.7, 0.72, 0.0), Color(0.62, 0.62, 0.64, 0.32), Color(0.5, 0.5, 0.52, 0.0)])
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4)); curve.add_point(Vector2(1.0, 1.0))
	var sm := SphereMesh.new()
	sm.radius = 0.04; sm.height = 0.08; sm.radial_segments = 6; sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	smat.albedo_color = Color(1, 1, 1, 1)
	sm.material = smat
	
	var amount := 5
	if GraphicsSettings.gpu_particles_enabled:
		amount = 15
		
	var p := GraphicsSettings.create_particles(
		amount,
		0.6,
		0.65,
		-muzzle.global_basis.z,
		24.0,
		Vector3(0, 0.5, 0),
		0.4,
		1.1,
		1.0,
		1.0,
		sm,
		grad,
		curve
	)
	get_tree().current_scene.add_child(p)
	p.global_position = muzzle.global_position
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

## A burst of hot sparks/embers flung from the barrel on every shot — warm for
## ballistic guns, the round's energy colour for plasma/energy weapons. Spawned
## in world space at the muzzle so they streak as the gun moves.
func _muzzle_sparks() -> void:
	if muzzle == null:
		return
	var energy := data.damage_type == WeaponData.DamageType.PROJECTILE
	var col: Color = data.tracer_color if energy else Color(1.0, 0.78, 0.4)
	
	var dart := BoxMesh.new()
	dart.size = Vector3(0.012, 0.012, 0.06)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 6.0
	dart.material = mat
	
	var amount := 8
	if GraphicsSettings.gpu_particles_enabled:
		amount = 24
		
	var p := GraphicsSettings.create_particles(
		amount,
		0.22,
		1.0,
		-muzzle.global_basis.z,
		26.0,
		Vector3(0, -14.0, 0),
		5.0,
		11.0,
		0.5,
		1.2,
		dart
	)
	get_tree().current_scene.add_child(p)
	p.global_position = muzzle.global_position
	get_tree().create_timer(0.6).timeout.connect(p.queue_free)

## A flat air-pressure ring snapping off the muzzle — only the heavy hitters
## (high recoil or splash rounds) earn it, so it reads as real blast force.
func _muzzle_shockwave() -> void:
	if muzzle == null:
		return
	if data.recoil_pitch < 1.8 and data.splash_radius <= 0.0:
		return
	var col := data.tracer_color
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.05
	tm.outer_radius = 0.12
	tm.rings = 20
	tm.ring_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(col.r, col.g, col.b, 0.6)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	tm.material = mat
	ring.mesh = tm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Stand the ring up facing down the barrel (TorusMesh axis is +Y).
	ring.rotation_degrees = Vector3(90, 0, 0)
	muzzle.add_child(ring)
	ring.position = Vector3(0, 0, -0.1)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * 6.0, 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.chain().tween_callback(ring.queue_free)

func _resolve_sound(explicit: AudioStream, fallback_id: String) -> AudioStream:
	if explicit:
		return explicit
	if fallback_id != "":
		return AudioBus.synth(fallback_id)
	return null

func _play_fire_sound() -> void:
	if muzzle == null:
		return
	var s := _resolve_sound(data.fire_sound, data.sound_id + "_fire" if data.sound_id != "" else "")
	if s:
		AudioBus.play_at(s, muzzle.global_position, -2.0, randf_range(0.97, 1.03))

func _play_empty() -> void:
	if muzzle == null:
		return
	var s := _resolve_sound(data.empty_sound, "empty_click")
	if s:
		AudioBus.play_at(s, muzzle.global_position, -6.0)

func start_reload() -> void:
	if _reloading or mag == eff_mag_size() or reserve <= 0:
		return
	_reloading = true
	_reload_timer = eff_reload_time()
	if muzzle:
		var s := _resolve_sound(data.reload_sound, "reload")
		if s:
			AudioBus.play_at(s, muzzle.global_position)
	_play_reload_anim()
	reload_started.emit(self)

## Visual reload: the gun tilts down toward the chest, the magazine drops out,
## a fresh one seats with a snap, and the gun levels back out — the whole
## timeline spans exactly data.reload_time so it never outlives the timer.
func _play_reload_anim() -> void:
	if viewmodel == null:
		return
	var t: float = maxf(0.6, eff_reload_time())
	var tw := create_tween()
	tw.tween_property(viewmodel, "rotation:x", -0.45, t * 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _mag_node:
		tw.tween_property(_mag_node, "position", _mag_home + Vector3(0, -0.24, 0.03), t * 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(t * 0.18)
		tw.tween_callback(_play_mag_seat_sound)
		tw.tween_property(_mag_node, "position", _mag_home, t * 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_interval(t * 0.6)
	tw.tween_property(viewmodel, "rotation:x", 0.0, t * 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _play_mag_seat_sound() -> void:
	AudioBus.play_synth_at("empty_click", global_position, -4.0, 0.7)

func _play_fire_anim() -> void:
	if viewmodel == null or data == null:
		return
	# Viewmodel recoil kick (back along z, then back home)
	var kick := minf(0.05, data.recoil_pitch * 0.012 + 0.018)
	var vt := create_tween()
	vt.tween_property(viewmodel, "position", _viewmodel_home + Vector3(0, 0, kick), 0.045)
	vt.tween_property(viewmodel, "position", _viewmodel_home, 0.13).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Slide kick
	if _slide_node and data.slide_kick > 0.0:
		var st := create_tween()
		st.tween_property(_slide_node, "position", _slide_home + Vector3(0, 0, data.slide_kick), 0.04)
		st.tween_property(_slide_node, "position", _slide_home, 0.09).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Pump cycle (delayed, with sound)
	if _pump_node and data.has_pump_action and data.pump_throw > 0.0:
		var pt := create_tween()
		pt.tween_interval(0.12)
		pt.tween_property(_pump_node, "position", _pump_home + Vector3(0, 0, data.pump_throw), 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pt.tween_callback(_play_pump_sound)
		pt.tween_property(_pump_node, "position", _pump_home, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _play_pump_sound() -> void:
	if muzzle == null:
		return
	AudioBus.play_synth_at("pump_action", muzzle.global_position, -3.0)

func _finish_reload() -> void:
	var needed := eff_mag_size() - mag
	var take := mini(needed, reserve)
	mag += take
	reserve -= take
	_reloading = false
	ammo_changed.emit(mag, reserve)
	reload_finished.emit(self)

func add_ammo(amount: int) -> void:
	reserve = mini(data.reserve_max, reserve + amount)
	ammo_changed.emit(mag, reserve)

func on_equip() -> void:
	visible = true
	ammo_changed.emit(mag, reserve)

func on_unequip() -> void:
	visible = false
	_burst_remaining = 0
	_trigger_held_last = false
	_beam_wanted = false
	if _beam:
		_beam.deactivate()
