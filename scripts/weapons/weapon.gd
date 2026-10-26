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
	return data.damage * GameState.upgrade_mult("damage") * GameState.damage_mult() * GameState.rampage_damage_mult() * GameState.adrenaline_damage_mult() * GameState.directive_damage_mult() * _alt_boost \
		* AIDirector.countermeasure_mult(data.display_name) # the overlord patched against your crutch gun

## Effective fire rate — OVERDRIVE and a high kill-streak RAMPAGE both crank it up
## so cooldowns shorten across all fire modes (semi/auto/burst/beam).
func eff_fire_rate() -> float:
	return data.fire_rate * GameState.fire_rate_mult() * GameState.rampage_fire_mult() * GameState.adrenaline_fire_mult()

func eff_mag_size() -> int:
	return int(round(data.mag_size * GameState.upgrade_mult("mag")))

func eff_reload_time() -> float:
	return data.reload_time * GameState.upgrade_reload_mult()

## Damage scale for a target at `dist` metres, from this weapon's range identity.
## 1.0 inside the optimal band; ramps to close_mult below opt_min and to far_mult
## beyond opt_max. Range-agnostic weapons (range_falloff off) always return 1.0.
func _range_mult(dist: float) -> float:
	if data == null or not data.range_falloff:
		return 1.0
	if dist <= data.opt_min:
		var t := 1.0 if data.opt_min <= 0.0 else clampf(dist / data.opt_min, 0.0, 1.0)
		return lerpf(data.close_mult, 1.0, t)
	if dist >= data.opt_max:
		var span := maxf(0.001, data.range_m - data.opt_max)
		var t := clampf((dist - data.opt_max) / span, 0.0, 1.0)
		return lerpf(1.0, data.far_mult, t)
	return 1.0

## True when the weapon is bone dry — no mag, no reserve, not mid-reload — so the
## manager can quick-draw a loaded backup instead of letting you click on empty.
func is_fully_dry() -> bool:
	return mag <= 0 and reserve <= 0 and not _reloading

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
var _slide_node: Node3D
var _pump_node: Node3D

# Continuous-beam (FireMode.BEAM) state: the visual updates every frame while
# the trigger is held; damage/ammo tick at data.fire_rate.
var _beam: ElectricBeam
var _beam_wanted: bool = false
var _beam_tick: float = 0.0
var _beam_pop: int = 0

# Spread bloom: sustained fire opens the cone toward spread_deg * bloom_max_mult;
# letting off the trigger bleeds it back down. _since_shot also arms the cold
# first-shot accuracy bonus.
var _bloom: float = 0.0
var _since_shot: float = 999.0

# Barrel heat: rises with every shot, bleeds off when you stop. The muzzle tip
# glows from a dull ember to a fierce orange as you mag-dump.
var _heat: float = 0.0
var _heat_glow: MeshInstance3D = null
var _heat_mat: StandardMaterial3D = null
var _heat_light: OmniLight3D = null

# Shared worn-metal roughness map for every real gun model — built once, reused.
static var _metal_rough_tex: NoiseTexture2D = null
static var _metal_grain_tex: NoiseTexture2D = null

## Fitted weapon mod (GameState.weapon_mods, keyed by this gun's scene path), read
## once when the gun is built for a level; WeaponMods runs it on every hit.
var mod_id: String = ""
var mod_last_proc_ms: int = -100000
var mod_override_ms: int = -100000
## A SALVAGE gun (WeaponManager.take_salvage): one magazine, no reserve, tossed
## when dry; ammo pickups skip it.
var salvage: bool = false
## The gloved hands holding this gun (ViewmodelHands), on every imported model.
var hands: ViewmodelHands = null
## This gun's firing signature (WeaponData.signature_fx), a silent default when it has none.
var _sig: SignatureFx = SignatureFx.new()
var mod_bank: float = 0.0 ## hit damage since the last ARC/RICOCHET proc (WeaponMods._bank)

func get_active_shooter() -> Node:
	return _active_shooter

func _ready() -> void:
	mod_id = GameState.mod_for(scene_file_path)
	if viewmodel == null:
		viewmodel = get_node_or_null("Viewmodel")
	if muzzle == null and viewmodel:
		muzzle = viewmodel.get_node_or_null("Muzzle")
	if viewmodel:
		_viewmodel_home = viewmodel.position
		_slide_node = viewmodel.get_node_or_null("Slide") as Node3D
		_pump_node = viewmodel.get_node_or_null("Pump") as Node3D
		if _slide_node:
			_slide_home = _slide_node.position
		if _pump_node:
			_pump_home = _pump_node.position
	if data:
		mag = eff_mag_size()
		reserve = data.reserve_max
		ammo_changed.emit(mag, reserve)
	_sig = SignatureFx.make(self)
	if not _apply_real_model():
		_bevel_viewmodel()
	_build_heat_glow()
	_build_ammo_readout()
	_build_energy_cell()
	GameState.rampage_changed.connect(_on_rampage_changed)
	_on_rampage_changed(GameState.rampage_tier, "")

# ---------- RAMPAGE charge ----------
## The gun charges up with the kill streak: at each RAMPAGE tier its tracers and
## muzzle flash take the tier's colour (GameState.RAMPAGE_COLORS, the banner's),
## the flash grows RAMPAGE_FLASH_GROW per tier, and a pulsing rim in that colour
## lights the viewmodel. A broken streak puts it all back.
## Covered by tests/weapon_rampage_probe.
const RAMPAGE_RIM: ShaderMaterial = preload("res://assets/materials/rampage_rim.tres")
const RAMPAGE_FLASH_GROW := 0.25

## The colour this gun's shots are drawn in right now.
func shot_color() -> Color:
	var t: int = GameState.rampage_tier
	if t <= 0 or data == null:
		return data.tracer_color if data else Color.WHITE
	return GameState.RAMPAGE_COLORS[clampi(t - 1, 0, GameState.RAMPAGE_COLORS.size() - 1)]

func _on_rampage_changed(tier: int, _name: String) -> void:
	if tier > 0:
		RAMPAGE_RIM.set_shader_parameter("color", shot_color())
	for mi in rim_meshes():
		(mi as MeshInstance3D).material_overlay = RAMPAGE_RIM if tier > 0 else null

## The viewmodel's own meshes: everything but the muzzle's (flashes, heat glow)
## and the hands holding it (gloves don't glow with the streak).
func rim_meshes() -> Array:
	if viewmodel == null:
		return []
	return viewmodel.find_children("*", "MeshInstance3D", true, false).filter(
			func(m: Node) -> bool: return (muzzle == null or not (muzzle == m or muzzle.is_ancestor_of(m))) 					and (hands == null or not hands.is_ancestor_of(m)))

## Imported gun models (Kenney "Blaster Kit", CC0) keyed by weapon scene name.
## `len` is the wanted barrel-to-stock length in metres (the GLB is uniformly
## scaled to it), `tint` multiplies the kit's white-plastic albedo so each gun
## reads as gunmetal with the weapon's energy-color identity.
const REAL_MODELS := {
	"pistol":     {"glb": "res://assets/models/weapons/blaster-b.glb", "len": 0.42, "tint": Color(0.5, 0.52, 0.56)},
	"rifle":      {"glb": "res://assets/models/weapons/blaster-d.glb", "len": 0.78, "tint": Color(0.46, 0.48, 0.52)},
	"shotgun":    {"glb": "res://assets/models/weapons/blaster-a.glb", "len": 0.72, "tint": Color(0.52, 0.48, 0.44)},
	"plasma":     {"glb": "res://assets/models/weapons/blaster-l.glb", "len": 0.58, "tint": Color(0.44, 0.56, 0.46)},
	"gauss":      {"glb": "res://assets/models/weapons/blaster-e.glb", "len": 0.95, "tint": Color(0.44, 0.5, 0.6)},
	"tesla":      {"glb": "res://assets/models/weapons/blaster-o.glb", "len": 0.52, "tint": Color(0.42, 0.54, 0.58)},
	"arccoil":    {"glb": "res://assets/models/weapons/blaster-q.glb", "len": 0.68, "tint": Color(0.58, 0.5, 0.4)},
	"devastator": {"glb": "res://assets/models/weapons/blaster-p.glb", "len": 0.8, "tint": Color(0.56, 0.44, 0.42)},
	"swarm":       {"glb": "res://assets/models/weapons/blaster-n.glb", "len": 0.74, "tint": Color(0.62, 0.4, 0.3)},
	"tempest":     {"glb": "res://assets/models/weapons/blaster-i.glb", "len": 0.7, "tint": Color(0.42, 0.7, 0.86)},
	"omega":       {"glb": "res://assets/models/weapons/blaster-g.glb", "len": 1.0, "tint": Color(0.74, 0.58, 0.32)},
	"sniper":      {"glb": "res://assets/models/weapons/blaster-h.glb", "len": 1.22, "tint": Color(0.4, 0.48, 0.62)},
	"magnum":      {"glb": "res://assets/models/weapons/blaster-j.glb", "len": 0.42, "tint": Color(0.62, 0.5, 0.36)},
	"cascade":     {"glb": "res://assets/models/weapons/blaster-f.glb", "len": 0.7, "tint": Color(0.4, 0.56, 0.6)},
	# SALVAGE guns (Salvage.TABLE): torn off a robot, so dirtier, robot-coloured tints.
	"salvage_chaingun": {"glb": "res://assets/models/weapons/blaster-r.glb", "len": 0.86, "tint": Color(0.5, 0.36, 0.3)},
	"salvage_palm":     {"glb": "res://assets/models/weapons/blaster-m.glb", "len": 0.62, "tint": Color(0.36, 0.46, 0.56)},
}

## Swap the primitive viewmodel for the real imported gun model, auto-fitted:
## scaled to the configured length, pushed forward until its grip sits at
## ViewmodelHands.GRIP_Z, the Muzzle node moved to the new barrel tip, and
## gloved hands (`hands`) built on its grip and fore-end. The primitive parts are hidden (not
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
	_fit_box = AABB(model.position + aabb.position * s, aabb.size * s)
	# Hold it where the hands show: a grip parked right under the eye sits below
	# the bottom of the screen with the stock filling the corner, so push the gun
	# forward until its grip is ViewmodelHands.GRIP_Z ahead of the origin.
	var grip := ViewmodelHands.grip_points(ViewmodelHands.vertices(viewmodel, model), _fit_box)
	var push := minf(0.0, ViewmodelHands.GRIP_Z - (grip["grip"] as Vector3).z)
	model.position.z += push
	_fit_box.position.z += push
	grip["grip"] += Vector3(0, 0, push)
	grip["fore"] += Vector3(0, 0, push)
	# Barrel tip = front face of the fitted model, slightly proud of it.
	if muzzle:
		muzzle.position.z = _fit_box.position.z - 0.03
	# Realistic worn-gunmetal skin over the kit's flat plastic albedo. Surfaces
	# the kit painted saturated (grips, vents, sight dots) become emissive
	# accents in the weapon's energy colour instead — every gun carries its own
	# glow identity, readable in the rack and in the dark.
	var tint: Color = cfg["tint"]
	var accent: Color = data.tracer_color if data else Color(0.5, 0.8, 1.0)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m and m.albedo_color.s > 0.35 and m.albedo_color.v > 0.25:
				var am := _energy_accent_material(accent)
				_accent_mats.append(am)
				mi.set_surface_override_material(i, am)
			else:
				mi.set_surface_override_material(i, _gunmetal_material(m, tint))
	hands = ViewmodelHands.fit(viewmodel, grip, _fit_box, accent)
	return true

## Emissive accent for the kit's saturated detail surfaces: lit from within in
## the weapon's tracer colour, at an energy low enough to glow without blowing
## out to white under bloom.
func _energy_accent_material(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r * 0.4, col.g * 0.4, col.b * 0.4)
	mat.metallic = 0.4
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = ACCENT_ENERGY
	return mat

## A procedural worn-gunmetal PBR material. The Kenney kit ships flat white plastic
## with a single albedo per surface; multiplying by the weapon's `tint` and dropping
## the value gives dark machined metal, while a triplanar noise roughness map breaks
## the low-poly facets into brushed/worn micro-variation. Clearcoat adds an oiled
## sheen and the fresnel rim catches edge light so the silhouette reads as metal, not
## a toy. Each gun keeps its tint as the metal's hue identity.
func _gunmetal_material(src: BaseMaterial3D, tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var base := (src.albedo_color if src != null else Color.WHITE)
	# darkened(0.25): with no reflection probes indoors, metal reads by its
	# albedo — the old 0.4 drop left every gun a black silhouette at the range.
	mat.albedo_color = (base * tint).darkened(0.25)
	mat.metallic = 0.88
	mat.metallic_specular = 0.6
	# The noise map is ramped to 0.7..1, so this gives 0.36..0.52: worn, never a
	# mirror. A full 0..1 map put mirror-smooth spots beside matte ones and the
	# smooth ones reflected the level (green in the foundry): every gun read as
	# camouflage. tests/gun_finish_probe.
	mat.roughness = 0.52
	mat.roughness_texture = _gunmetal_rough()
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.uv1_triplanar = true                              # map noise without relying on kit UVs
	# Fine grain: big patches read as camo blotches up close on the viewmodel;
	# a tight scale reads as brushed/worn machining instead.
	mat.uv1_scale = Vector3(5.5, 5.5, 5.5)
	# Fine machining grain in the normals instead of the roughness.
	mat.normal_enabled = true
	mat.normal_texture = _gunmetal_grain()
	mat.normal_scale = 0.15
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.4
	mat.clearcoat_roughness = 0.2
	mat.rim_enabled = true
	mat.rim = 0.35
	mat.rim_tint = 0.4
	return mat

## Lazily build (once) the shared FastNoiseLite roughness texture for gun metal.
func _gunmetal_rough() -> NoiseTexture2D:
	if _metal_rough_tex == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.045
		noise.fractal_octaves = 4
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.noise = noise
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.7, 0.7, 0.7))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		tex.color_ramp = ramp
		_metal_rough_tex = tex
	return _metal_rough_tex

## Lazily build (once) the shared fine-grain normal map for gun metal: tight,
## low-amplitude noise that breaks up highlights like machining marks.
func _gunmetal_grain() -> NoiseTexture2D:
	if _metal_grain_tex == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.4
		noise.fractal_octaves = 2
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.as_normal_map = true
		tex.bump_strength = 2.0
		tex.noise = noise
		_metal_grain_tex = tex
	return _metal_grain_tex

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

## The fitted gun's box in viewmodel space (set by _apply_real_model; the
## primitive viewmodel's own box otherwise). The ammo readout hangs off it.
var _fit_box := AABB()
var _ammo_label: Label3D = null
const READOUT_LOW := 0.25 ## mag fraction at which the readout turns red and pulses
const READOUT_LOW_COLOR := Color(1.0, 0.22, 0.15)
const READOUT_REACH := 0.2 ## metres forward of the stock the readout sits, at most

## A holographic round counter on the gun's left flank, above its rear third,
## the side you see in your hands: rounds in the mag in the gun's own glow
## colour, red and pulsing at READOUT_LOW, "--" while reloading. The HUD's
## corner counter stays; this one is where your eyes already are.
func _build_ammo_readout() -> void:
	if viewmodel == null or data == null:
		return
	var box := _fit_box
	if box.size == Vector3.ZERO:
		box = _merged_aabb(viewmodel)
	_ammo_label = Label3D.new()
	_ammo_label.name = "AmmoReadout"
	_ammo_label.font_size = 64
	_ammo_label.pixel_size = 0.0005
	_ammo_label.outline_size = 10
	_ammo_label.outline_modulate = Color(0, 0, 0, 0.6)
	_ammo_label.shaded = false
	_ammo_label.double_sided = false
	_ammo_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Left flank, just proud of the top edge, a third of the way up from the
	# rear but never more than READOUT_REACH (on the 1.22 m Longshot a third
	# floated it out by the barrel); turned a little toward the eye, which sits
	# behind and to the left.
	_ammo_label.position = Vector3(box.position.x - 0.006, box.end.y + 0.012,
		box.end.z - minf(box.size.z * 0.32, READOUT_REACH))
	_ammo_label.rotation_degrees = Vector3(-12.0, -28.0, 0.0)
	viewmodel.add_child(_ammo_label)
	ammo_changed.connect(func(_m: int, _r: int) -> void: _refresh_readout())
	reload_started.connect(func(_w: Weapon) -> void: _refresh_readout())
	_refresh_readout()

func _refresh_readout() -> void:
	if _ammo_label == null:
		return
	var size := maxi(1, eff_mag_size())
	if _reloading or mag <= 0:
		_ammo_label.text = "--"
	else:
		_ammo_label.text = "%02d" % mag if size >= 10 else str(mag)
	_ammo_label.modulate = READOUT_LOW_COLOR if readout_low() else data.tracer_color.lerp(Color.WHITE, 0.25)

## True while the readout warns: the mag is at or under READOUT_LOW, or dry.
## Rounded up like the low-mag click in _fire_once, so a 3-round OMEGA warns
## on its last shot.
func readout_low() -> bool:
	return not _reloading and mag <= ceili(maxi(1, eff_mag_size()) * READOUT_LOW)

## Energy guns (reload_style CELL) carry their cell on the outside: a glowing
## strip in the gun's colour along the left flank, under the readout. None of
## the five energy models has a saturated surface for _apply_real_model to
## light, so without it a cell reload had nothing to drain.
func _build_energy_cell() -> void:
	if viewmodel == null or data == null or data.reload_style != WeaponData.ReloadStyle.CELL:
		return
	var box := _fit_box if _fit_box.size != Vector3.ZERO else _merged_aabb(viewmodel)
	var strip := MeshInstance3D.new()
	strip.name = "EnergyCell"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.008, 0.014, clampf(box.size.z * 0.4, 0.12, 0.3))
	var mat := _energy_accent_material(data.tracer_color)
	mat.emission_energy_multiplier = ACCENT_ENERGY
	bm.material = mat
	strip.mesh = bm
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strip.position = Vector3(box.position.x - 0.003, box.position.y + box.size.y * 0.62,
		box.end.z - 0.05 - bm.size.z * 0.5)
	viewmodel.add_child(strip)
	_accent_mats.append(mat)

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
	_sig.on_process(delta)
	if _ammo_label and readout_low():
		# Low-mag pulse: the warning breathes at 3 Hz instead of sitting still.
		_ammo_label.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.0094))
	_update_beam(delta)
	_since_shot += delta
	if _bloom > 0.0 and data and _since_shot > 0.1:
		_bloom = maxf(0.0, _bloom - data.bloom_recovery * delta)
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
			# Burst spent: hold the trigger off for burst_cooldown so the next
			# burst can't start nose-to-tail on the per-shot cooldown alone.
			if _burst_remaining <= 0 and data and data.burst_cooldown > 0.0:
				_cooldown = maxf(_cooldown, data.burst_cooldown)

func try_fire(trigger_down: bool, aiming: bool, camera: Camera3D, shooter: Node) -> void:
	var just_pressed := trigger_down and not _trigger_held_last
	_trigger_held_last = trigger_down
	# The finger on screen follows the trigger, dry clicks included; mid-reload
	# it stays off.
	if trigger_down and hands and not _reloading:
		hands.squeeze()
	if data and data.fire_mode == WeaponData.FireMode.BEAM:
		# Beam weapons don't use the shot/cooldown machinery: try_fire just
		# records intent + context; _update_beam() does the work each frame.
		_beam_wanted = trigger_down and not _reloading and mag > 0
		if _beam_wanted:
			_active_camera = camera
			_active_shooter = shooter
			_active_aiming = aiming
		elif just_pressed and mag <= 0 and not _reloading:
			if reserve > 0:
				start_reload()
			else:
				_play_empty()
		return
	if _reloading or _cooldown > 0.0 or data == null:
		return
	if mag <= 0:
		# Pulling the trigger on an empty mag reloads by itself when there are
		# rounds in reserve — dry-clicking mid-brawl because you forgot R is
		# friction, not challenge. (Playtest: died at first contact with 84
		# rounds in reserve and an empty pistol.) Truly dry guns still click;
		# the manager's auto-switch covers those.
		if trigger_down and reserve > 0:
			start_reload()
		elif just_pressed:
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
			# `_burst_remaining <= 0` gates re-arming MID-BURST. _fire_once only
			# sets a one-shot cooldown (1/fire_rate), but a burst takes
			# burst_count shots to play out — so a fast trigger finger could start
			# a fresh burst every 1/fire_rate seconds while the previous one was
			# still firing from _process, stacking them. Measured on the CL-3 Arc
			# Coil (tests/ttk_probe): 1224 DPS against a lone robot, ~3x its
			# intended rate and 5x the OMEGA ultimate. One burst per press.
			if just_pressed and _burst_remaining <= 0:
				# burst_count - 1: _fire_once below already lands round 1, so
				# queuing burst_count more fired burst_count+1 rounds per press.
				_burst_remaining = maxi(0, data.burst_count - 1)
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
	var spread := deg_to_rad(spread_now(_active_aiming, _active_shooter))
	if _alt_tight:
		spread = 0.0 # alt-fire shots are laser-accurate
	_register_spread_shot(_active_aiming)
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
	if not _sig.owns_brass():
		_eject_brass()
	if not _sig.owns_muzzle_smoke():
		_muzzle_smoke()
	_sig.on_fire()
	_play_fire_sound()
	_play_fire_anim()
	# Gamepad rumble: every trigger pull snaps the buzz motor; the thump motor
	# grows with the round's total heft, so a shotgun blast kicks the pad the
	# way a pistol tap doesn't.
	# A gun with a chest thump (fire_thump) thumps the pad too, and longer.
	Haptics.pulse(0.35, maxf(clampf(eff_damage() * float(data.pellets) / 140.0, 0.0, 0.85), data.fire_thump * 0.9),
		0.09 + 0.08 * data.fire_thump)
	fired.emit(self)

## The live cone half-angle in degrees: base spread opened by bloom and
## movement, tightened by ADS and a cold first shot. The HUD reticle reads this
## too, so the crosshair always shows the real cone.
func spread_now(aiming: bool, shooter: Node = null) -> float:
	if data == null:
		return 0.0
	var s := data.spread_deg
	if aiming:
		s *= data.aim_spread_mult
	s *= 1.0 + _bloom * (data.bloom_max_mult - 1.0)
	if shooter is CharacterBody3D:
		var body := shooter as CharacterBody3D
		var hspeed := Vector2(body.velocity.x, body.velocity.z).length()
		s *= lerpf(1.0, data.move_spread_mult, clampf(hspeed / 8.0, 0.0, 1.0))
		if not body.is_on_floor():
			s *= data.air_spread_mult
	if _since_shot >= data.first_shot_delay:
		s *= data.first_shot_mult
	return s

## Book-keeping per trigger pull: bloom the cone (ADS blooms at half rate — a
## braced gun climbs slower) and reset the first-shot clock.
func _register_spread_shot(aiming: bool) -> void:
	_since_shot = 0.0
	if data.bloom_per_shot > 0.0:
		_bloom = minf(1.0, _bloom + data.bloom_per_shot * (0.5 if aiming else 1.0))

## Deflect `dir` by up to max_angle: uniform azimuth around the shot line, with
## a center-weighted (linear) radial falloff. The rotation axis is built
## perpendicular to the shot so the sampled angle always lands in full — the old
## random-3D-axis rotation shrank and skewed the cone unpredictably.
func _scattered(dir: Vector3, max_angle: float) -> Vector3:
	if max_angle <= 0.0:
		return dir
	var ref := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var axis := dir.cross(ref).normalized().rotated(dir, randf() * TAU)
	return dir.rotated(axis, randf() * max_angle).normalized()

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
		var pitch := randf_range(0.7, 0.85) if surf == "dirt" else randf_range(0.9, 1.1)
		AudioBus.play_synth_at(_impact_sound_for(surf), hpos, -8.0, pitch)
		if dmg_node == null:
			_spawn_bullet_hole(hpos, hit.normal)
			_sig.on_world_hit(hpos, hit.normal, dir, surf)
		if dmg_node:
			var final_damage := eff_damage() * _range_mult(origin.distance_to(hpos))
			# Headshots — and the crit bonus + "headshot" callout — apply ONLY to
			# enemy robots (the is_headshot method is the enemy marker). Destructible
			# props/cover never grant a headshot no matter where you hit them.
			var is_head: bool = col.has_method("is_headshot") and col.is_headshot(hpos.y)
			## Weak-point core crit: only the LARGER of headshot/weak-point bonus
			## applies (no stacking a lucky head+core overlap into a double-dip).
			var weak_mult := 1.0
			if col.has_method("weakpoint_multiplier"):
				weak_mult = col.weakpoint_multiplier(hpos)
			var is_crit := is_head or weak_mult > 1.0
			final_damage *= maxf(data.headshot_mult if is_head else 1.0, weak_mult)
			if is_head:
				AudioBus.play_synth_at("headshot", hpos, -1.0, 1.0)
			# A killing headshot from a gun with no kill style of its own takes the head.
			var style := KillFx.DECAPITATE if is_head and data.kill_fx == KillFx.NONE else data.kill_fx
			KillFx.tag(dmg_node, style, data)
			# Prime before the hit lands, so the killing round detonates too. The
			# blast scales with the Armory damage track like the round does.
			if data.cascade_damage > 0.0:
				Cascade.prime(dmg_node.get_parent(), data.cascade_damage * eff_damage() / data.damage,
						data.cascade_radius, _active_shooter)
			dmg_node.apply_damage(final_damage, _active_shooter, is_crit)
			KillFx.untag(dmg_node)
			_enemy_hit_pop(hpos, is_crit, final_damage)
			_sig.on_enemy_hit(hpos, hit.normal, dir, final_damage, is_crit)
			if mod_id != "":
				# x matchup: a mod works off what the hit dealt after the armour-class table.
				WeaponMods.on_enemy_hit(self, dmg_node.get_parent(), hpos, final_damage * dmg_node.matchup)
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
			if mod_id != "":
				WeaponMods.on_world_hit(self, hpos, hit.normal, dir, eff_damage() * _range_mult(origin.distance_to(hpos)))
			break
	# Draw the visible round from the muzzle (not the eye) to where it landed, so
	# it reads as leaving the rifle and striking the target.
	var beam_from := muzzle.global_position if muzzle else origin
	_spawn_tracer(beam_from, end_point)
	# Energy weapons (railguns/lasers/arc guns) get a fat glowing bolt + end blooms
	# on top of the tracer — and arc guns get a jagged lightning overlay.
	if data.energy_beam_fx or data.arc_fx:
		_energy_beam_flash(beam_from, end_point)
	# Railguns ionize the air they cross: a coil of light hangs on the shot's path.
	if data.rail_trail and get_tree().current_scene:
		RailTrail.spawn(get_tree().current_scene, beam_from, end_point, shot_color())

## A bright expanding flash + light when a shot connects with an enemy, plus a
## burst of metal embers/debris that scales with how hard the hit landed.
func _enemy_hit_pop(pos: Vector3, is_head: bool, dmg: float = 10.0) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_spawn_debris(scene, pos, dmg, is_head)
	# The robot bleeds data: binary sprays back out of the wound (DataBleed).
	var back := Vector3.UP
	if is_instance_valid(_active_shooter) and _active_shooter is Node3D:
		back = (_active_shooter as Node3D).global_position - pos
	DataBleed.spill(scene, pos, back, DataBleed.hit_amount(dmg, is_head))
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
	# Spill light only if the global FX-light budget allows — the orb above is
	# self-lit (unshaded emissive), so over budget we simply skip the point light.
	var light: OmniLight3D = null
	if FXLights.take():
		light = OmniLight3D.new()
		light.light_color = col
		light.light_energy = GraphicsSettings.flash_energy(4.0) # accessibility: flash-intensity slider
		light.omni_range = 3.0
		orb.add_child(light)
		light.tree_exited.connect(FXLights.give)
	var tw := orb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "scale", Vector3.ONE * (2.4 if is_head else 1.8), 0.11)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.11)
	if light:
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
	if "kill_fx" in proj:
		proj.kill_fx = data.kill_fx
		proj.weapon_data = data
	if proj.has_method("launch"):
		proj.launch(dir * data.projectile_speed, _active_shooter, eff_damage(), data.splash_radius, data.splash_damage)
	_sig.on_projectile(proj)

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
	# The gun's signature may re-cut the bolt (a pistol cracks, a belt pulses):
	# asked once per round, since a signature may count rounds.
	var style := _sig.tracer_style()
	# Fly the round as a visible bolt from the muzzle to the impact point so the
	# player sees the shot travel and connect (damage stays instant hitscan; the
	# bolt is fast enough — 150 m/s — to stay snappy).
	if "bolt" in t:
		t.bolt = true
		t.bolt_speed = 150.0
		t.bolt_length = 2.2
		t.bolt_width = 1.5
		for k in style:
			if k != "color":
				t.set(k, style[k])
	if t.has_method("setup"):
		# A signature may recolour a round (a tracer belt's hot every-third), but a
		# RAMPAGE tier's colour wins: the streak is the streak's.
		var col: Color = shot_color()
		if GameState.rampage_tier <= 0 and style.has("color"):
			col = style["color"]
		t.setup(from, to, col)

## Persistent bullet scars on world geometry — delegates to the shared
## BulletMark utility (scripts/fx/bullet_mark.gd) so hitscan AND projectile
## impacts (projectile.gd) draw from ONE capped pool instead of two.
func _spawn_bullet_hole(pos: Vector3, normal: Vector3) -> void:
	BulletMark.spawn(get_tree().current_scene, pos, normal, data.damage_class if data else 0)

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
	if i.has_method("set_damage_class"):
		i.set_damage_class(data.damage_class)

## Continuous beam: raycast + redraw the lightning every frame while firing;
## damage and ammo tick at data.fire_rate (1 cell per tick).
func _update_beam(delta: float) -> void:
	if data == null or data.fire_mode != WeaponData.FireMode.BEAM:
		return
	if not _beam_wanted or _reloading or mag <= 0 or _active_camera == null or not visible:
		if is_instance_valid(_beam):
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
	# The beam's own voice per tick (tesla_fire), the old shared zap if it has none.
	AudioBus.play_synth_at(data.sound_id + "_fire" if data.sound_id != "" else "drone_shot", from, -9.0, randf_range(0.9, 1.15))
	if not hit.is_empty():
		var col := hit.collider as Node
		var dmg_node: Node = _find_damageable(col) if col else null
		if dmg_node:
			var beam_dmg := eff_damage() * _range_mult(origin.distance_to(hit.position))
			var weak_mult := 1.0
			if col.has_method("weakpoint_multiplier"):
				weak_mult = col.weakpoint_multiplier(hit.position)
			beam_dmg *= weak_mult
			KillFx.tag(dmg_node, data.kill_fx, data)
			dmg_node.apply_damage(beam_dmg, _active_shooter, weak_mult > 1.0)
			KillFx.untag(dmg_node)
			if mod_id != "":
				WeaponMods.on_enemy_hit(self, dmg_node.get_parent(), hit.position, beam_dmg * dmg_node.matchup)
			# Hit pop on every 4th tick — constant feedback without the FX spam.
			if _beam_pop % 4 == 0:
				_enemy_hit_pop(hit.position, weak_mult > 1.0, beam_dmg * 2.0)
		else:
			if mod_id != "":
				WeaponMods.on_world_hit(self, hit.position, hit.normal, dir, eff_damage() * _range_mult(origin.distance_to(hit.position)))
			if _beam_pop % 6 == 0:
				_spawn_impact(hit.position, hit.normal, _surface_of(col, false) if col else "concrete")
	fired.emit(self)

func _ensure_beam() -> void:
	if is_instance_valid(_beam):
		return
	# Parent the bolt to the WORLD scene, not the weapon. Every other effect
	# (tracers, energy flash, hit pops) lives in current_scene; the beam used to
	# hang off the weapon viewmodel, which couples it to that subtree's visibility
	# and could leave the lightning invisible in actual play. Keep it in the world.
	_beam = ElectricBeam.new()
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(_beam)
	if data:
		_beam.set_color(data.tracer_color)

## Classify a hit surface from collider groups (enemies/destructibles read metal).
## Static (no instance state used) so projectile.gd's world-hit path can share
## the exact same classification instead of duplicating it (Weapon._surface_of).
static func _surface_of(col: Node, is_enemy: bool) -> String:
	if is_enemy or col.is_in_group("surf_metal"):
		return "metal"
	if col.is_in_group("surf_wood"):
		return "wood"
	if col.is_in_group("surf_stone"):
		return "stone"
	if col.is_in_group("surf_dirt"):
		return "dirt"
	return "concrete"

## Pick the bullet-impact sound for a classified surface so each material reads
## distinctly (wood thocks, stone cracks, metal clinks). Dirt reuses the concrete
## thud at a lower pitch (set by the caller). Static for the same reason as
## _surface_of above — shared with projectile.gd.
const _IMPACT_SOUND := {
	"metal": "impact_metal", "wood": "impact_wood", "stone": "impact_stone",
	"concrete": "impact_concrete", "dirt": "impact_concrete",
}
static func _impact_sound_for(surf: String) -> String:
	return _IMPACT_SOUND.get(surf, "impact_concrete")

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
	# Per-weapon flash colour + size so each gun blasts distinctly.
	if "tint_color" in m:
		m.tint_color = shot_color()
		m.size_mult = data.muzzle_scale * (1.0 + RAMPAGE_FLASH_GROW * maxi(0, GameState.rampage_tier))
	if "along_bore" in m:
		m.along_bore = true # the Muzzle's -Z is the barrel
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
	var light: OmniLight3D = null
	if FXLights.take():
		light = OmniLight3D.new()
		light.light_color = col
		light.light_energy = GraphicsSettings.flash_energy(5.0) # accessibility: flash-intensity slider
		light.omni_range = 5.0
		orb.add_child(light)
		light.tree_exited.connect(FXLights.give)
	var tw := orb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "scale", Vector3.ONE * 1.7, 0.13)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.13)
	if light:
		tw.tween_property(light, "light_energy", 0.0, 0.13)
	tw.chain().tween_callback(orb.queue_free)

## ---------- energy / laser / arc beam flash (hitscan cosmetic) ----------

## A thick, short-lived laser bolt from the muzzle to the hit point for energy
## hitscan weapons: a fat additive glow tube wrapping a searing white-hot core,
## emissive blooms with lights at both ends, and (for arc weapons) a jagged
## lightning overlay. Purely cosmetic — damage is the instant hitscan above.
func _energy_beam_flash(from: Vector3, to: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var col := data.tracer_color
	# Bigger guns fire fatter, cooler beams: scale the beam presence by the weapon's
	# muzzle_scale (gauss 1.3, arccoil 1.15, ... the heavy energy guns read beefier).
	var ms: float = maxf(1.0, data.muzzle_scale)
	var root := Node3D.new()
	scene.add_child(root)
	# Wide soft halo → glow tube → bright white core: three concentric layers give
	# the bolt real girth and a hot centre instead of a thin line.
	root.add_child(_beam_tube(from, to, 0.20 * ms, Color(col.r, col.g, col.b, 0.16), col, 3.2))
	root.add_child(_beam_tube(from, to, 0.10 * ms, Color(col.r, col.g, col.b, 0.5), col, 6.5))
	root.add_child(_beam_tube(from, to, 0.03 * ms, Color(1, 1, 1, 0.95), col.lerp(Color.WHITE, 0.6), 14.0))
	# End blooms — an emissive orb + a light at the muzzle and at the impact (the
	# impact end punches bigger so the hit reads as the bolt biting in).
	var ends := {from: 0.13 * ms, to: 0.22 * ms}
	for end_pt in ends:
		var orb := _glow_orb(col, ends[end_pt])
		root.add_child(orb)
		orb.global_position = end_pt
		# Budgeted spill light (the glow orb is self-lit; skip the point light when
		# the FX-light budget is full). The fade loop below finds lights generically.
		if FXLights.take():
			var l := OmniLight3D.new()
			l.light_color = col
			l.light_energy = 5.0
			l.omni_range = 4.0
			orb.add_child(l)
			l.tree_exited.connect(FXLights.give)
	if data.arc_fx:
		_spawn_arc_overlay(root, from, to, col)
	# A shock-ring punched into the impact plane — the energy bolt's bite.
	var bolt_dir := (to - from)
	if bolt_dir.length() > 0.01:
		_spawn_impact_ring(to, bolt_dir.normalized(), col)
	# Fade the whole flash out fast (a snap, not a lingering beam).
	var tw := root.create_tween().set_parallel(true)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if m:
			tw.tween_property(m, "emission_energy_multiplier", 0.0, 0.14)
			tw.tween_property(m, "albedo_color:a", 0.0, 0.14)
	for li in root.find_children("*", "OmniLight3D", true, false):
		tw.tween_property(li, "light_energy", 0.0, 0.14)
	tw.chain().tween_callback(root.queue_free)

## A unit additive glow cylinder spanning exactly a→b (cylinder axis is +Y).
func _beam_tube(a: Vector3, b: Vector3, radius: float, albedo: Color, emission: Color, energy: float) -> MeshInstance3D:
	var d := b - a
	var l := maxf(0.001, d.length())
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = l
	cm.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dn := d / l
	var up := Vector3.UP if absf(dn.y) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(dn, up) * Basis(Vector3.RIGHT, PI * 0.5)
	mi.transform = Transform3D(basis, (a + b) * 0.5)
	return mi

## A small unshaded additive glow sphere (for the muzzle/impact blooms).
func _glow_orb(col: Color, r: float) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(col.r, col.g, col.b, 0.9)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 9.0
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## A one-shot jagged lightning polyline jittered off the muzzle→hit axis, sagging
## widest mid-beam — the electric snap for arc weapons. Fades with the rest.
func _spawn_arc_overlay(root: Node3D, from: Vector3, to: Vector3, col: Color) -> void:
	var d := to - from
	var dist := maxf(0.001, d.length())
	var dir := d / dist
	var segs := 7
	var prev := from
	for i in segs:
		var t := float(i + 1) / float(segs)
		var p := from + dir * (dist * t)
		if i < segs - 1:
			var amp := 0.16 * sin(PI * t) * minf(dist * 0.2, 1.0)
			p += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0 * amp
		root.add_child(_beam_tube(prev, p, 0.014, Color(1, 1, 1, 0.9), col.lerp(Color.WHITE, 0.4), 9.0))
		prev = p

## An additive ring that snaps out flat against the impact surface and fades — the
## shockwave of an energy bolt biting in. Detached so it outlives the flash. A
## thin band: the old 0.05-0.12 tube grown 6x read as a solid hexagon 0.7 m
## across on the wall, not a ring (tests/impact_class_probe).
func _spawn_impact_ring(at: Vector3, dir: Vector3, col: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.12
	tm.rings = 32
	tm.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(col.r, col.g, col.b, 0.9)
	mat.emission_enabled = true
	mat.emission = col.lerp(Color.WHITE, 0.3)
	mat.emission_energy_multiplier = 8.0
	tm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Torus lies in its local XZ plane (axis +Y); face it along the bolt so the ring
	# sits flat on the struck surface, lifted clear of it: the tube grows to 0.08 m
	# thick, so at 0.03 m half of it sank into the wall and only arcs showed.
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, PI * 0.5), at - dir * 0.1)
	scene.add_child(mi)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 4.0, 0.22).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.22)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	tw.chain().tween_callback(mi.queue_free)

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
	p.set_meta("shared_fx", "brass")
	get_tree().current_scene.add_child(p)
	p.global_position = global_position + cam.global_basis.x * 0.14 - cam.global_basis.y * 0.04
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)
	# The casing lands a beat later: a tiny pitched-up tink at the shooter's
	# feet, timing-jittered so an automatic burst scatters into a tinkle
	# instead of a metronome. The closure captures only the landing spot and
	# the AudioBus autoload, so it still fires if this weapon is freed mid-drop.
	var land := p.global_position - Vector3(0, 1.2, 0) + cam.global_basis.x * randf_range(0.3, 0.7)
	get_tree().create_timer(randf_range(0.55, 0.8)).timeout.connect(
		func() -> void: AudioBus.play_synth_at("brass_tink", land, -16.0, randf_range(0.85, 1.25)))

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
	p.set_meta("shared_fx", "muzzle_smoke")
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

## A thin air-pressure ring blown off the muzzle down the line of fire — only
## the heavy hitters (high recoil or splash rounds) earn it, so it reads as
## real blast force. It lives in the world and travels AWAY from the eye while
## it widens: it used to grow 6x where it spawned, 0.1 m off the muzzle, and
## covered half the view as an opaque donut (tests/muzzle_ring_probe).
const RING_START := 0.5 ## metres past the muzzle the ring forms
const RING_TRAVEL := 3.0 ## metres it flies down the line of fire
const RING_GROW := 3.0 ## final scale
const RING_TIME := 0.2

func _muzzle_shockwave() -> void:
	if muzzle == null:
		return
	if data.recoil_pitch < 1.8 and data.splash_radius <= 0.0:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var col := data.tracer_color
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.12
	tm.rings = 24
	tm.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(col.r, col.g, col.b, 0.45)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	tm.material = mat
	ring.mesh = tm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(ring)
	# Face it down the barrel: the torus axis (+Y) turned onto the shot line.
	var fwd := -muzzle.global_basis.z.normalized()
	var start := muzzle.global_position + fwd * RING_START
	ring.global_transform = Transform3D(Basis.looking_at(fwd) * Basis(Vector3.RIGHT, -PI * 0.5), start)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * RING_GROW, RING_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "global_position", start + fwd * RING_TRAVEL, RING_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, RING_TIME)
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
	# Layers that make a shot felt, not just heard: a sub-bass chest thump under
	# the heavy reports, and the action cycling a beat behind a cartridge gun's.
	if data.fire_thump > 0.0:
		AudioBus.play_synth_at("fire_thump", muzzle.global_position, lerpf(-16.0, -1.0, clampf(data.fire_thump, 0.0, 1.0)),
			randf_range(0.94, 1.04))
	if data.action_clack:
		var at := muzzle.global_position
		get_tree().create_timer(randf_range(0.045, 0.06)).timeout.connect(
			func() -> void: AudioBus.play_synth_at("action_clack", at, -13.0, randf_range(0.92, 1.08)))

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
	# The reload's beats carry its sounds (_reload_beat); an authored
	# reload_sound still plays over the top.
	if muzzle and data.reload_sound:
		AudioBus.play_at(data.reload_sound, muzzle.global_position)
	_play_reload_anim()
	reload_started.emit(self)

## Visual reload, one choreography per WeaponData.reload_style: the gun drops
## into a style pose, the beats play out (each a jolt of the gun, a sound and
## a reload_beat), then it comes back up. The whole timeline spans the reload
## time so it never outlives the timer.
##   MAG    unlatch and tug the mag out, slam a fresh one home, rack the action
##   SHELLS one thumbed-in shell per round actually loaded, then the pump
##   CELL   vent (steam, the glow strips drain dark), then recharge (whine, they refill)
##   TUBE   shoulder it, open the breech, shove the round in
## (Every real gun model hides the primitive Magazine node, so the old mag-drop
## animated nothing you could see: every reload was the same tilt.)
signal reload_beat(kind: String)
const RELOAD_POSES := [
	[Vector3(0.0, -0.03, 0.02), Vector3(-0.35, 0.1, 0.4)],     # MAG: tipped toward you
	[Vector3(0.01, -0.02, 0.03), Vector3(-0.2, -0.15, -0.55)],  # SHELLS: rolled, port up
	[Vector3(0.0, -0.04, 0.02), Vector3(-0.5, 0.0, 0.15)],      # CELL: nose down
	[Vector3(0.0, 0.03, 0.04), Vector3(0.15, -0.1, -0.3)],      # TUBE: shouldered
]
var _reload_tw: Tween = null
var _beat_tw: Tween = null
## The real model's emissive accent strips (built in _apply_real_model); a CELL
## reload drains and refills them.
var _accent_mats: Array[StandardMaterial3D] = []
const ACCENT_ENERGY := 1.4

## [time fraction, beat, jolt] for this reload: when each beat lands in the
## timeline and how hard it jerks the gun.
func reload_beats() -> Array:
	match data.reload_style:
		WeaponData.ReloadStyle.SHELLS:
			var n := clampi(mini(eff_mag_size() - mag, reserve), 1, 8)
			var out: Array = []
			for i in n:
				out.append([lerpf(0.22, 0.64, float(i) / maxf(1.0, float(n - 1))) if n > 1 else 0.4,
					"shell", Vector3(0.0, 0.015, -0.02)])
			out.append([0.74, "pump", Vector3(0.0, 0.0, 0.06)])
			return out
		WeaponData.ReloadStyle.CELL:
			return [[0.22, "vent", Vector3(0.0, 0.01, 0.015)], [0.58, "charge", Vector3(0.0, 0.012, -0.01)]]
		WeaponData.ReloadStyle.TUBE:
			return [[0.3, "breech", Vector3(0.0, 0.02, 0.03)], [0.6, "load", Vector3(0.0, 0.0, -0.05)]]
		_:
			return [[0.24, "mag_out", Vector3(0.0, -0.03, 0.0)], [0.55, "mag_in", Vector3(0.0, 0.035, 0.0)],
				[0.72, "rack", Vector3(0.0, 0.0, 0.045)]]

func _play_reload_anim() -> void:
	if viewmodel == null or data == null:
		return
	for tw in [_reload_tw, _beat_tw]:
		if tw and tw.is_valid():
			tw.kill()
	var t: float = maxf(0.6, eff_reload_time())
	var pose: Array = RELOAD_POSES[clampi(data.reload_style, 0, RELOAD_POSES.size() - 1)]
	var pos: Vector3 = _viewmodel_home + pose[0]
	_reload_tw = create_tween()
	_reload_tw.tween_property(viewmodel, "rotation", pose[1], t * 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reload_tw.parallel().tween_property(viewmodel, "position", pos, t * 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reload_tw.tween_interval(t * 0.66)
	_reload_tw.tween_property(viewmodel, "rotation", Vector3.ZERO, t * 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_reload_tw.parallel().tween_property(viewmodel, "position", _viewmodel_home, t * 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if hands:
		hands.support_on(0.0) # a restarted reload starts with the hand on the gun
	_beat_tw = create_tween()
	var at := 0.0
	for b: Array in reload_beats():
		_beat_tw.tween_interval(maxf(0.0, t * float(b[0]) - at))
		at = t * float(b[0])
		_beat_tw.tween_callback(_reload_beat.bind(String(b[1]), pos, b[2] as Vector3, t))

## One beat: jolt the gun off its reload pose and back, play its sound, tell
## anyone listening.
func _reload_beat(kind: String, pose_pos: Vector3, jolt: Vector3, t: float) -> void:
	if viewmodel and jolt != Vector3.ZERO:
		var jt := create_tween()
		jt.tween_property(viewmodel, "position", pose_pos + jolt, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		jt.tween_property(viewmodel, "position", pose_pos, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# The support hand goes for the new magazine, cell or round and brings it back.
	if hands:
		match kind:
			"mag_out", "vent", "breech":
				hands.support_off(0.14)
			"mag_in", "charge", "load":
				hands.support_on(0.16)
			"shell":
				hands.support_dip(0.2)
	var at := muzzle.global_position if muzzle else global_position
	match kind:
		"mag_out":
			AudioBus.play_synth_at("empty_click", at, -5.0, 0.6)
		"mag_in":
			AudioBus.play_synth_at("reload", at, -2.0, randf_range(0.95, 1.05))
		"rack":
			AudioBus.play_synth_at("action_clack", at, -6.0, 0.85)
		"shell":
			AudioBus.play_synth_at("empty_click", at, -8.0, randf_range(1.35, 1.6))
		"pump":
			AudioBus.play_synth_at("pump_action", at, -3.0)
		"vent":
			AudioBus.play_synth_at("vent_hiss", at, -6.0, randf_range(0.95, 1.05))
			_vent_steam()
			_tween_accents(0.08, t * 0.3)
		"charge":
			AudioBus.play_synth_at("charge", at, -6.0, 1.0)
			_tween_accents(ACCENT_ENERGY, t * 0.3)
		"breech":
			AudioBus.play_synth_at("impact_metal", at, -4.0, 0.55)
		"load":
			AudioBus.play_synth_at("reload", at, -2.0, 0.7)
	reload_beat.emit(kind)

## Drain (or refill) the gun's glow strips to `energy` over `secs`.
func _tween_accents(energy: float, secs: float) -> void:
	if _accent_mats.is_empty():
		return
	var tw := create_tween().set_parallel(true)
	for m in _accent_mats:
		tw.tween_property(m, "emission_energy_multiplier", energy, secs)

## A puff of white vapour off the muzzle as a cell vents.
func _vent_steam() -> void:
	if muzzle == null or get_tree().current_scene == null:
		return
	# Soft: a faint, many-sided puff whose alpha ramps in and out (the same
	# vertex-colour ramp as _muzzle_smoke). Opaque 6-sided spheres read as
	# white hexagons in front of the gun.
	var sm := SphereMesh.new()
	sm.radius = 0.025; sm.height = 0.05; sm.radial_segments = 12; sm.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	sm.material = mat
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(0.92, 0.95, 1.0, 0.0), Color(0.9, 0.93, 1.0, 0.16), Color(0.85, 0.88, 0.95, 0.0)])
	var p := CPUParticles3D.new()
	p.one_shot = true; p.emitting = true; p.amount = 18; p.lifetime = 0.9; p.explosiveness = 0.5
	p.local_coords = false
	p.mesh = sm
	p.color_ramp = ramp
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.3; p.initial_velocity_max = 0.8
	p.scale_amount_min = 0.8; p.scale_amount_max = 2.2
	get_tree().current_scene.add_child(p)
	p.global_position = muzzle.global_position
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

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
	if hands:
		hands.support_on(0.12) # however the beats fell, end on the gun
	ammo_changed.emit(mag, reserve)
	reload_finished.emit(self)
	_refresh_readout()

func add_ammo(amount: int) -> void:
	if salvage:
		return
	reserve = mini(data.reserve_max, reserve + amount)
	ammo_changed.emit(mag, reserve)

func on_equip() -> void:
	visible = true
	ammo_changed.emit(mag, reserve)
	# Quick-draw: the weapon snaps up from below into its home pose (the manager
	# blocks firing for the same beat, so the raise reads as the draw time).
	if viewmodel:
		viewmodel.position = _viewmodel_home + Vector3(0.04, -0.14, 0.05)
		var tw := create_tween()
		tw.tween_property(viewmodel, "position", _viewmodel_home, 0.34) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func on_unequip() -> void:
	visible = false
	_burst_remaining = 0
	_trigger_held_last = false
	_beam_wanted = false
	if is_instance_valid(_beam):
		_beam.deactivate()
	# Holster reload: top the mag back up in the background while it's stowed, over
	# the normal reload time. Coming back to a backup and swapping out again can't
	# hand you a fresh mag instantly — the reload has to actually finish first.
	if not _reloading and reserve > 0 and mag < eff_mag_size():
		start_reload()

## The beam bolt lives in the world scene (not under us), so free it ourselves
## when this weapon leaves the tree rather than leaking it.
func _exit_tree() -> void:
	if is_instance_valid(_beam):
		_beam.queue_free()
	_beam = null
