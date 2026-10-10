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
	"convoy": {
		"image": "res://assets/comics/level_convoy.png",
		"fx": [
			{"kind": "glow", "u": 0.19, "v": 0.17, "size": 52, "color": C_RED}, # Lead pursuit flyer optics
			{"kind": "glow", "u": 0.85, "v": 0.40, "size": 40, "color": C_RED}, # Flanking flyer optics
			{"kind": "glow", "u": 0.80, "v": 0.72, "size": 64, "color": C_WARM}, # Hauler headlights
			{"kind": "muzzle", "u": 0.36, "v": 0.63, "size": 60, "color": C_BLUE} # Player defensive fire off the span
		],
		"weather": "sparks"
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
			{"kind": "glow", "u": 0.55, "v": 0.62, "size": 30, "color": C_RED} # sentry eye
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
			{"kind": "glow", "u": 0.72, "v": 0.65, "size": 44, "color": C_RED}, # sentry eye
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
	},
	"desert": {
		"image": "res://assets/comics/level_desert.png",
		"fx": [
			{"kind": "glow", "u": 0.65, "v": 0.35, "size": 140, "color": C_RED}, # AI Relay Mast Core
			{"kind": "glow", "u": 0.45, "v": 0.6, "size": 32, "color": C_RED},   # Gunslinger bot eye
			{"kind": "glow", "u": 0.5, "v": 0.8, "size": 120, "color": C_WARM}    # Molten fissure
		],
		"weather": "sparks"
	}
}

# The mood line under each panel lives in StoryArc.BEATS, beside the trace log
# that ties each level to the last (scripts/systems/story_arc.gd).

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
var _act_label: Label
var _title_label: Label
var _sub_label: Label
var _obj_label: Label

# Particles state
var _particles: Array = []
var _weather_type: String = "none"

# The red thread: one node per campaign level, lit up to this one.
var _thread: Control
var _thread_acts: Array[int] = []
var _chapter: int = -1

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
	_title_label.set_anchors_preset(Control.PRESET_TOP_WIDE) # CENTER_TOP gave it zero width: the title started at mid-screen
	_title_label.anchor_top = 0.035
	_title_label.anchor_bottom = 0.095
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_title_label.add_theme_constant_override("outline_size", 8)
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	_act_label = Label.new()
	_act_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_act_label.anchor_top = 0.008
	_act_label.anchor_bottom = 0.035
	_act_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_act_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_act_label.add_theme_font_size_override("font_size", 15)
	_act_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.38))
	_act_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_act_label)

	_thread = Control.new()
	_thread.name = "StoryThread"
	_thread.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_thread.anchor_left = 0.18
	_thread.anchor_right = 0.82
	_thread.anchor_top = 0.1
	_thread.anchor_bottom = 0.124
	_thread.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thread.draw.connect(_on_thread_draw)
	add_child(_thread)

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

	set_process_input(true)
	_setup_briefing.call_deferred()

func _setup_briefing() -> void:
	var lid := GameState.level_id_from_path(GameState.current_level_path)
	var def := LevelDefs.get_def(lid)
	
	_title_label.text = String(def.get("name", "INCOMING OPERATION")).to_upper()
	var beat := StoryArc.beat(lid)
	_sub_label.text = String(beat.get("tagline", "Hostile machines detected. Move in."))
	_act_label.text = StoryArc.act_header(lid)
	var campaign: Array = GameState.campaign()
	_chapter = campaign.find(GameState.current_level_path) if not beat.is_empty() else -1
	if _chapter >= 0:
		_thread_acts = StoryArc.campaign_acts(campaign)
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

	# Intercepted ROBOT OS patch notes from the last level's fight (if any):
	# a terminal card that types itself out over the comic's left edge.
	_build_patch_panel()
	# The resistance's side of the story: what the last level uncovered.
	_build_trace_panel(String(beat.get("trace", "")), campaign.size())

	# Start scene tweens
	var up := create_tween().set_parallel(true)
	up.tween_property(_fade, "color:a", 0.0, 0.6)
	up.tween_property(_panel_root, "modulate:a", 1.0, 0.5)
	
	await up.finished
	_run_timer()

## The machine's changelog, staged as an intercepted transmission: a dark
## terminal panel that types one patch-note line at a time. Pure fiction layer
## over data the AI Director already tracks — this is how the player SEES the
## enemy adapt between levels. Skipped entirely when there's nothing to show.
func _build_patch_panel() -> void:
	var notes: Array = GameState.consume_patch_notes()
	if notes.is_empty():
		return
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.03, 0.86)
	style.border_color = Color(0.3, 1.0, 0.5, 0.55)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.anchor_left = 0.015
	panel.anchor_top = 0.16
	panel.anchor_right = 0.36
	panel.anchor_bottom = 0.16 # grows downward with content
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate.a = 0.0
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)
	var head := Label.new()
	head.text = "▚ INTERCEPTED — ROBOT OS v2.%d PATCH NOTES" % (GameState.level_index + 1)
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", Color(0.62, 0.95, 0.7, 0.95))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(body)
	# Fade in, then type the entries on one at a time — a live feed, not a wall.
	var tw := panel.create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(panel, "modulate:a", 1.0, 0.4)
	for i in notes.size():
		tw.tween_interval(0.55)
		tw.tween_callback(func() -> void:
			if is_instance_valid(body):
				body.text = "\n".join(notes.slice(0, i + 1))
				AudioBus.play_synth_ui("broadcast_blip", -14.0, 1.6))

## The handler's case-file entry, mirroring the patch notes on the right: the
## enemy's changelog on one side, our trace of the 03:14 order on the other.
## It types itself out so the eye lands on it after the title.
func _build_trace_panel(trace: String, total: int) -> void:
	if trace == "" or _chapter < 0:
		return
	var panel := PanelContainer.new()
	panel.name = "TracePanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.02, 0.02, 0.86)
	style.border_color = Color(1.0, 0.3, 0.22, 0.6)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.anchor_left = 0.64
	panel.anchor_top = 0.16
	panel.anchor_right = 0.985
	panel.anchor_bottom = 0.16 # grows downward with content
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate.a = 0.0
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)
	var head := Label.new()
	head.text = "◆ THE 03:14 TRACE · LOG %d/%d" % [_chapter + 1, total]
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(1.0, 0.5, 0.42))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)
	var body := Label.new()
	body.text = trace
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.visible_ratio = 0.0
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color(1.0, 0.88, 0.84, 0.95))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(body)
	var tw := panel.create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(panel, "modulate:a", 1.0, 0.35)
	tw.tween_property(body, "visible_ratio", 1.0, clampf(trace.length() / 90.0, 1.0, 2.6))

## The red thread across the top letterbox: every campaign level is a node,
## the line is lit red from the first level to this one, act changes are ticks,
## and this level's node pulses. The finale's node is drawn larger, so the whole
## campaign reads as one line running toward one place.
func _on_thread_draw() -> void:
	var n := _thread_acts.size()
	if n < 2 or _chapter < 0:
		return
	var w := _thread.size.x
	var y := _thread.size.y * 0.5
	var step := w / float(n - 1)
	var red := Color(1.0, 0.18, 0.12)
	var dim := Color(0.55, 0.58, 0.65, 0.35)
	var cx := step * _chapter
	_thread.draw_line(Vector2(cx, y), Vector2(w, y), dim, 1.0)
	_thread.draw_line(Vector2(0, y), Vector2(cx, y), red, 2.0)
	for i in n:
		var x := step * i
		if i > 0 and _thread_acts[i] != _thread_acts[i - 1]:
			var tx := x - step * 0.5
			_thread.draw_line(Vector2(tx, y - 7), Vector2(tx, y + 7), Color(1, 0.4, 0.32, 0.55) if i <= _chapter else dim, 1.0)
		var r := 5.0 if i == n - 1 else 3.0
		if i < _chapter:
			_thread.draw_circle(Vector2(x, y), r, red)
		elif i == _chapter:
			var pulse := 0.5 + 0.5 * sin(_t * 4.0)
			_thread.draw_circle(Vector2(x, y), r + 3.0 + pulse * 3.0, Color(red, 0.25 + 0.25 * pulse))
			_thread.draw_circle(Vector2(x, y), r + 1.0, Color(1.0, 0.85, 0.8))
		else:
			_thread.draw_arc(Vector2(x, y), r, 0.0, TAU, 12, dim, 1.0)

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

	if _chapter >= 0:
		_thread.queue_redraw()

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

func _input(event: InputEvent) -> void:
	if _done:
		return
	if (event is InputEventKey and event.pressed and not event.echo) \
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
