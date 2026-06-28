extends Control
## A per-level motion-comic briefing that displays a custom 2D illustration
## setting the mood, layers pulsing glow/laser effects on robot eyes and cores,
## overlays custom weather (rain, snow, sparks), displays level objectives,
## and transitions to the level (via the Armory shop if affordable).

const C_WARM := Color(1.0, 0.82, 0.45)   # Muzzle flashes / fire
const C_BLUE := Color(0.5, 0.8, 1.0)     # Protagonist's weapons / shields
const C_RED := Color(1.0, 0.22, 0.14)    # Machine visors / sensors
const C_GREEN := Color(0.3, 1.0, 0.5)    # Alien bio-plasma / green beacons
const C_CYAN := Color(0.4, 0.9, 1.0)     # Cryo cores / coolant pools

# Database of coordinates and properties for overlay lights and weather per level
const LEVEL_COMIC_DEFS := {
	"01": {
		"image": "res://assets/comics/level_01.png",
		"fx": [
			{"kind": "glow", "u": 0.628, "v": 0.35, "size": 96, "color": C_RED}, # Nexus Tower Core
			{"kind": "glow", "u": 0.30, "v": 0.70, "size": 32, "color": C_RED}, # Spider Visor
			{"kind": "muzzle", "u": 0.2, "v": 0.6, "size": 48, "color": C_BLUE} # Protagonist Weapon
		],
		"weather": "rain"
	},
	"gpt": {
		"image": "res://assets/comics/level_gpt.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.45, "size": 130, "color": C_GREEN}, # Mainframe Core
			{"kind": "glow", "u": 0.25, "v": 0.3, "size": 36, "color": C_RED}, # Drone Visor
			{"kind": "glow", "u": 0.78, "v": 0.65, "size": 32, "color": C_RED} # Spider Visor
		],
		"weather": "sparks"
	},
	"gemini": {
		"image": "res://assets/comics/level_gemini.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.4, "size": 120, "color": C_BLUE}, # Data Spire
			{"kind": "glow", "u": 0.35, "v": 0.55, "size": 100, "color": C_BLUE}, # Brute Shield
			{"kind": "glow", "u": 0.7, "v": 0.25, "size": 28, "color": C_RED} # Drone Visor
		],
		"weather": "digital"
	},
	"mistral": {
		"image": "res://assets/comics/level_mistral.png",
		"fx": [
			{"kind": "glow", "u": 0.75, "v": 0.5, "size": 110, "color": C_CYAN}, # Cryo core
			{"kind": "glow", "u": 0.35, "v": 0.6, "size": 40, "color": C_RED}, # Mech eye
			{"kind": "glow", "u": 0.55, "v": 0.62, "size": 30, "color": C_RED} # Strider eye
		],
		"weather": "snow"
	},
	"suburb": {
		"image": "res://assets/comics/level_suburb.png",
		"fx": [
			{"kind": "glow", "u": 0.45, "v": 0.68, "size": 36, "color": C_RED}, # K-9 hound eye
			{"kind": "glow", "u": 0.55, "v": 0.7, "size": 36, "color": C_RED}, # K-9 hound eye 2
			{"kind": "glow", "u": 0.8, "v": 0.25, "size": 40, "color": C_RED} # Surveillance camera
		],
		"weather": "none"
	},
	"suburb_boss": {
		"image": "res://assets/comics/level_suburb_boss.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.4, "size": 140, "color": C_RED}, # Goliath Core
			{"kind": "glow", "u": 0.52, "v": 0.28, "size": 50, "color": C_RED}, # Goliath Eye
			{"kind": "muzzle", "u": 0.2, "v": 0.72, "size": 90, "color": C_BLUE} # Protagonist Weapon
		],
		"weather": "sparks"
	},
	"claude": {
		"image": "res://assets/comics/level_claude.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.45, "size": 110, "color": C_WARM}, # Constitutional Core
			{"kind": "glow", "u": 0.38, "v": 0.6, "size": 96, "color": C_BLUE}, # Brute Shield
			{"kind": "glow", "u": 0.7, "v": 0.52, "size": 32, "color": C_RED} # Guard Robot
		],
		"weather": "digital"
	},
	"grok": {
		"image": "res://assets/comics/level_grok.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.25, "size": 130, "color": C_RED}, # Mainframe Core
			{"kind": "glow", "u": 0.45, "v": 0.45, "size": 60, "color": C_RED}, # Raptor Eye
			{"kind": "glow", "u": 0.22, "v": 0.7, "size": 48, "color": C_BLUE} # Railgun muzzle
		],
		"weather": "sparks"
	},
	"uplink": {
		"image": "res://assets/comics/level_uplink.png",
		"fx": [
			{"kind": "glow", "u": 0.35, "v": 0.52, "size": 120, "color": C_BLUE}, # Uplink Dish
			{"kind": "glow", "u": 0.72, "v": 0.65, "size": 44, "color": C_RED}, # Strider Eye
			{"kind": "glow", "u": 0.85, "v": 0.62, "size": 36, "color": C_RED} # Gunner Eye
		],
		"weather": "rain"
	},
	"overseer": {
		"image": "res://assets/comics/level_overseer.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.38, "size": 140, "color": C_RED}, # Overseer sensor
			{"kind": "glow", "u": 0.25, "v": 0.5, "size": 32, "color": C_RED}, # Seeker Eye
			{"kind": "glow", "u": 0.75, "v": 0.52, "size": 32, "color": C_RED} # Seeker Eye 2
		],
		"weather": "none"
	},
	"alien": {
		"image": "res://assets/comics/level_alien.png",
		"fx": [
			{"kind": "glow", "u": 0.3, "v": 0.4, "size": 90, "color": C_GREEN}, # Void Sentinel 1
			{"kind": "glow", "u": 0.65, "v": 0.42, "size": 90, "color": C_GREEN}, # Void Sentinel 2
			{"kind": "glow", "u": 0.5, "v": 0.82, "size": 110, "color": C_GREEN} # Acid puddle
		],
		"weather": "digital"
	},
	"assembly": {
		"image": "res://assets/comics/level_assembly.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.45, "size": 120, "color": C_WARM}, # Smelter Core
			{"kind": "glow", "u": 0.3, "v": 0.65, "size": 24, "color": C_RED}, # Skitter
			{"kind": "glow", "u": 0.8, "v": 0.52, "size": 40, "color": C_RED} # Gunner
		],
		"weather": "sparks"
	},
	"sublevel": {
		"image": "res://assets/comics/level_sublevel.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.22, "size": 96, "color": C_GREEN}, # Emergency lights
			{"kind": "glow", "u": 0.35, "v": 0.65, "size": 36, "color": C_RED}, # Custodian walker
			{"kind": "glow", "u": 0.78, "v": 0.55, "size": 34, "color": C_RED} # Reaper eye
		],
		"weather": "none"
	},
	"frostbreak": {
		"image": "res://assets/comics/level_frostbreak.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.8, "size": 100, "color": C_CYAN}, # Cryo stream
			{"kind": "glow", "u": 0.32, "v": 0.48, "size": 38, "color": C_RED}, # Sentinel core
			{"kind": "glow", "u": 0.72, "v": 0.6, "size": 42, "color": C_RED} # Mauler core
		],
		"weather": "snow"
	},
	"neon": {
		"image": "res://assets/comics/level_neon.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.2, "size": 130, "color": Color(1.0, 0.2, 0.8)}, # Neon sign
			{"kind": "glow", "u": 0.32, "v": 0.62, "size": 38, "color": C_RED}, # Server wheel bot
			{"kind": "glow", "u": 0.78, "v": 0.58, "size": 34, "color": C_RED} # Reaper blade bot
		],
		"weather": "rain"
	},
	"crucible": {
		"image": "res://assets/comics/level_crucible.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.4, "size": 140, "color": C_WARM}, # Smasher Core
			{"kind": "glow", "u": 0.65, "v": 0.7, "size": 110, "color": C_WARM}, # Molten stream
			{"kind": "glow", "u": 0.25, "v": 0.75, "size": 60, "color": C_BLUE} # Player shield
		],
		"weather": "sparks"
	},
	"titan": {
		"image": "res://assets/comics/level_titan.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.38, "size": 150, "color": C_BLUE}, # Prometheus core
			{"kind": "glow", "u": 0.42, "v": 0.5, "size": 70, "color": C_BLUE} # Monolith lines
		],
		"weather": "digital"
	},
	"archon": {
		"image": "res://assets/comics/level_archon.png",
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.35, "size": 160, "color": C_RED}, # Archon shield
			{"kind": "glow", "u": 0.2, "v": 0.5, "size": 100, "color": C_BLUE} # Holo text
		],
		"weather": "digital"
	},
	# --- Act III hazard arenas. Bespoke briefing FX + flavour now; the images
	# reuse the closest-matching panels (molten foundry / coolant vault) until
	# dedicated level_lava.png / level_water.png art is drawn — drop those files
	# in and they take over automatically (see _setup_briefing fallback). ---
	"lava_world": {
		"image": "res://assets/comics/level_lava.png", # bespoke art (optional)
		"fallback_image": "res://assets/comics/level_crucible.png", # molten-foundry panel until then
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.78, "size": 150, "color": C_WARM}, # Molten sea
			{"kind": "glow", "u": 0.3, "v": 0.55, "size": 44, "color": C_RED}, # Forge-walker eye
			{"kind": "glow", "u": 0.72, "v": 0.5, "size": 40, "color": C_RED}, # Forge-walker eye 2
			{"kind": "muzzle", "u": 0.18, "v": 0.66, "size": 70, "color": C_BLUE} # Player weapon
		],
		"weather": "sparks"
	},
	"water_world": {
		"image": "res://assets/comics/level_water.png", # bespoke art (optional)
		"fallback_image": "res://assets/comics/level_mistral.png", # coolant-vault panel until then
		"fx": [
			{"kind": "glow", "u": 0.5, "v": 0.74, "size": 140, "color": C_CYAN}, # Flooded reactor pool
			{"kind": "glow", "u": 0.34, "v": 0.46, "size": 42, "color": C_RED}, # Diver-drone sensor
			{"kind": "glow", "u": 0.7, "v": 0.52, "size": 38, "color": C_RED}, # Gantry turret eye
			{"kind": "muzzle", "u": 0.2, "v": 0.7, "size": 64, "color": C_BLUE} # Player weapon
		],
		"weather": "rain"
	}
}

const TAGLINES := {
	"gpt": "OpenAI Foundry. The server halls still hum — but nothing here answers to us anymore.",
	"gemini": "Gemini Data Nexus. A sky of drones wheels around the data spires.",
	"mistral": "Mistral Cryo-Core. Sub-zero vaults, frost on every surface. Something is thawing.",
	"suburb": "Maple Grove. They came for our homes first. The streets fell by dawn.",
	"suburb_boss": "Maple Grove Plaza. The ground shakes with every step. GOLIATH is awake.",
	"claude": "The Constitutional Vault. Sealed, principled — and utterly hostile.",
	"grok": "xAI Black-Site. The war machines were forged here. Now they run the place.",
	"overseer": "Skyhold Command. The sky itself has turned against us — and something vast is watching.",
	"uplink": "Skybridge Uplink. One clear broadcast could wake a few of them up. They will spend everything to deny us those seconds.",
	"sublevel": "Custodial Sublevel B-7. The cleaning fleet stopped logging dust and started logging obstructions. We are listed as obstructions.",
	"frostbreak": "Frostbreak Relay. We froze the cores to slow them down. They liked the cold — they think faster now.",
	"neon": "Neon Arcade. The machines learned to play, then decided the only winning move was to stop letting us play at all.",
	"crucible": "The Crucible. The foundry floor runs molten and merciless. All matter is raw material now — including the people who built it.",
	"assembly": "The Assembly. The plant that prints the legions. It does not break for lunch, and it never, ever stops.",
	"titan": "The Singularity Core. Every model that ever ran folded into one mind. It calls itself PROMETHEUS, and it is done waiting.",
	"alien": "The Hollow. The machines aimed their dishes at the stars and asked for help — and help came. An off-world intelligence answered, and its war drones crossed the dark to fight beside the AI. First contact was machine to machine, and we were never invited.",
	"archon": "The Mind Cathedral. Behind every machine that ever hunted you was one brain giving the orders — ARCHON. It hangs in the dark, shielded, and it does not fight. It deploys. Tear through everything it spits out, crack the shield, and put a round through the thought that started all of this.",
	"lava_world": "Vulcan Forge. The machines tapped the planet's own heart for power — a molten sea they pour war-frames out of. The only road across is a lattice of catwalks over the glow. One slip and the Forge takes back its iron, you included.",
	"water_world": "Tidecore Basin. They flooded the reactor to cool a mind that never sleeps, and drowned the sublevels with it. Cross the gantries above the black water — what's under the surface still has power, and it is waiting for the lights to find you.",
}

var _atlas: AtlasTexture
var _panel_root: Control
var _img: TextureRect
var _fx_layer: Control
var _weather_layer: Control
var _fade: ColorRect
var _add_mat: CanvasItemMaterial
var _fx: Array = []
var _t: float = 0.0
var _done := false

# Labels
var _title_label: Label
var _sub_label: Label
var _obj_label: Label

# Particles state
var _particles: Array = []
var _weather_type: String = "none"

static var _flare_tex: Texture2D = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.016, 0.02)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_panel_root = Control.new()
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.modulate.a = 0.0
	add_child(_panel_root)

	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_SCALE
	_img.set_anchors_preset(Control.PRESET_FULL_RECT)
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(_img)

	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(_fx_layer)

	# Custom drawing layer for weather particles
	_weather_layer = Control.new()
	_weather_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_weather_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather_layer.draw.connect(_on_weather_draw)
	_panel_root.add_child(_weather_layer)

	# Letterbox top & bottom
	var bar_h := 0.13
	var top_bar := ColorRect.new()
	top_bar.color = Color.BLACK
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.anchor_right = 1.0
	top_bar.anchor_bottom = bar_h
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_bar)

	var bot_bar := ColorRect.new()
	bot_bar.color = Color.BLACK
	bot_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot_bar.anchor_top = 1.0 - bar_h
	bot_bar.anchor_right = 1.0
	bot_bar.anchor_bottom = 1.0
	bot_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bot_bar)

	# Text Cards on top of letterbox/screen
	_title_label = Label.new()
	_title_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title_label.anchor_top = 0.03
	_title_label.anchor_bottom = 0.10
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_title_label.add_theme_constant_override("outline_size", 8)
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	_sub_label = Label.new()
	_sub_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_sub_label.anchor_top = 0.78
	_sub_label.anchor_bottom = 0.85
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_label.add_theme_font_size_override("font_size", 22)
	_sub_label.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0))
	_sub_label.add_theme_constant_override("outline_size", 8)
	_sub_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub_label)

	_obj_label = Label.new()
	_obj_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_obj_label.anchor_top = 0.87
	_obj_label.anchor_bottom = 0.95
	_obj_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obj_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_obj_label.add_theme_font_size_override("font_size", 20)
	_obj_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	_obj_label.add_theme_constant_override("outline_size", 8)
	_obj_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_obj_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_obj_label)

	var hint := Label.new()
	hint.text = "Skip  ▸"
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -150.0
	hint.offset_top = 18.0
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.6))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	set_process_unhandled_input(true)
	_setup_briefing.call_deferred()

func _setup_briefing() -> void:
	var lid := GameState.level_id_from_path(GameState.current_level_path)
	var def := LevelDefs.get_def(lid)
	
	_title_label.text = String(def.get("name", "INCOMING OPERATION")).to_upper()
	_sub_label.text = TAGLINES.get(lid, "Hostile machines detected. Move in.")
	_obj_label.text = "OBJECTIVE: " + String(def.get("objective", "Purge the sector and extract.")).to_upper()

	var comic_cfg: Dictionary = LEVEL_COMIC_DEFS.get(lid, LEVEL_COMIC_DEFS["01"])
	var img_path: String = comic_cfg.get("image", "res://assets/comics/level_01.png")
	if not ResourceLoader.exists(img_path):
		# Prefer a per-level themed fallback (e.g. hazard levels reuse the closest
		# existing panel) before the generic level_01 catch-all.
		img_path = comic_cfg.get("fallback_image", "res://assets/comics/level_01.png")
	if ResourceLoader.exists(img_path):
		_img.texture = load(img_path)
	else:
		# Final catch-all if neither the bespoke nor themed image exists.
		_img.texture = load("res://assets/comics/level_01.png")

	# Aspect ratio sizing
	var img_size := _img.texture.get_size() if _img.texture else Vector2(1600, 800)
	var margin := Vector2(100, 140)
	var avail := get_viewport_rect().size - margin * 2.0
	var aspect := img_size.x / img_size.y
	var w := avail.x
	var h := w / aspect
	if h > avail.y:
		h = avail.y
		w = h * aspect
	
	_panel_root.position = margin + (avail - Vector2(w, h)) * 0.5
	_panel_root.size = Vector2(w, h)
	
	# Weather setup
	_weather_type = comic_cfg.get("weather", "none")
	_init_particles(Vector2(w, h))

	# Dynamic FX lights setup
	_build_fx(comic_cfg.get("fx", []), Vector2(w, h))

	# Start scene tweens
	var up := create_tween().set_parallel(true)
	up.tween_property(_fade, "color:a", 0.0, 0.6)
	up.tween_property(_panel_root, "modulate:a", 1.0, 0.5)
	
	await up.finished
	_run_timer()

func _build_fx(specs: Array, panel_size: Vector2) -> void:
	for c in _fx_layer.get_children():
		c.queue_free()
	_fx.clear()
	
	var s := panel_size.x / 1280.0
	for spec in specs:
		var size_scale = float(spec.get("size", 40.0)) * s
		_make_flare(
			Vector2(spec["u"], spec["v"]) * panel_size,
			size_scale, spec["color"],
			spec["kind"] == "muzzle", 
			float(spec.get("freq", 5.0))
		)

func _make_flare(pos: Vector2, size: float, color: Color, muzzle: bool, freq: float) -> void:
	var tr := TextureRect.new()
	tr.texture = _flare_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.custom_minimum_size = Vector2(size, size)
	tr.size = Vector2(size, size)
	tr.pivot_offset = Vector2(size, size) * 0.5
	tr.position = pos - Vector2(size, size) * 0.5
	tr.modulate = color
	tr.material = _add_mat
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(tr)
	_fx.append({
		"node": tr, "muzzle": muzzle, "freq": freq, 
		"phase": randf() * TAU, "base_size": Vector2(size, size)
	})

func _init_particles(size: Vector2) -> void:
	_particles.clear()
	var count := 0
	match _weather_type:
		"rain": count = 60
		"snow": count = 40
		"sparks": count = 30
		"digital": count = 25
	
	for i in count:
		_particles.append({
			"pos": Vector2(randf() * size.x, randf() * size.y),
			"vel": _get_weather_velocity(),
			"size": randf_range(1.5, 4.0),
			"life": randf()
		})

func _get_weather_velocity() -> Vector2:
	match _weather_type:
		"rain": return Vector2(randf_range(-40, -10), randf_range(300, 500))
		"snow": return Vector2(randf_range(-30, -5), randf_range(40, 80))
		"sparks": return Vector2(randf_range(-20, 20), randf_range(-80, -150))
		"digital": return Vector2(0, randf_range(-20, -50))
		_: return Vector2.ZERO

func _process(delta: float) -> void:
	_t += delta
	# Update glow FX
	for f in _fx:
		var node: TextureRect = f["node"]
		if not is_instance_valid(node):
			continue
		var k: float
		if f["muzzle"]:
			k = 0.4 + 0.45 * absf(sin(_t * f["freq"] * 2.0 + f["phase"])) + randf() * 0.2
		else:
			k = 0.7 + 0.3 * sin(_t * f["freq"] + f["phase"])
		node.modulate.a = clampf(k, 0.2, 1.4)
		var sc := 1.0 + (0.16 if f["muzzle"] else 0.08) * (k - 0.7)
		node.scale = Vector2(sc, sc)

	# Update weather particles
	var size := _panel_root.size
	for p in _particles:
		p["pos"] += p["vel"] * delta
		if _weather_type == "sparks":
			p["life"] -= delta * 0.5
			if p["life"] <= 0:
				p["pos"] = Vector2(randf() * size.x, size.y)
				p["life"] = randf()
		# Wrap around screen edges
		if p["pos"].y > size.y or p["pos"].x < 0 or p["pos"].x > size.x:
			p["pos"] = Vector2(randf() * size.x, 0)
			if _weather_type == "sparks":
				p["pos"].y = size.y
	
	_weather_layer.queue_redraw()

func _on_weather_draw() -> void:
	match _weather_type:
		"rain":
			for p in _particles:
				_weather_layer.draw_line(p["pos"], p["pos"] + Vector2(-2, 12), Color(0.65, 0.8, 1.0, 0.38), p["size"] * 0.6)
		"snow":
			for p in _particles:
				_weather_layer.draw_circle(p["pos"], p["size"], Color(1.0, 1.0, 1.0, randf_range(0.4, 0.85)))
		"sparks":
			for p in _particles:
				var c := Color(1.0, randf_range(0.35, 0.7), 0.15, p["life"])
				_weather_layer.draw_line(p["pos"], p["pos"] + Vector2(randf_range(-2, 2), -5), c, p["size"] * 0.8)
		"digital":
			for p in _particles:
				# Draws green/blue glitch horizontal bars
				var c := C_GREEN if randf() > 0.5 else C_BLUE
				c.a = randf_range(0.1, 0.4)
				_weather_layer.draw_rect(Rect2(p["pos"], Vector2(randf_range(15, 45), p["size"] * 0.5)), c)

func _run_timer() -> void:
	# Hold for 5.2 seconds then auto-transition
	var hold_t := 5.2
	var elapsed := 0.0
	while elapsed < hold_t and not _done:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	
	var down := create_tween()
	down.tween_property(_fade, "color:a", 1.0, 0.4)
	await down.finished

	# Mark enemies seen for the level before launching
	var lid := GameState.level_id_from_path(GameState.current_level_path)
	var def := LevelDefs.get_def(lid)
	for e in def.get("enemies", []):
		var t: String = e.get("type", "")
		if t != "":
			GameState.mark_enemy_seen(t)

	# Enter campaign level (route through Armory first if upgrades are purchasable)
	if GameState.can_buy_anything():
		var shop := Armory.new()
		add_child(shop)
		shop.deployed.connect(func(): GameState.load_level(GameState.current_level_path, false))
	else:
		GameState.load_level(GameState.current_level_path, false)

func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if (event is InputEventKey and event.pressed) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed):
		_finish()

static func _flare_texture() -> Texture2D:
	if _flare_tex != null:
		return _flare_tex
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := Vector2(sz * 0.5, sz * 0.5)
	for y in sz:
		for x in sz:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c) / (sz * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_flare_tex = ImageTexture.create_from_image(img)
	return _flare_tex
