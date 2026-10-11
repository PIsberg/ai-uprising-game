extends Node
## Dev probe: every campaign level opens on its own comic panel.
## (1) every campaign level has a LEVEL_COMIC_DEFS entry: without one the
##     briefing shows level 01's panel (GUARDRAILS and HIVEMIND did, 2026-10-11);
## (2) its briefing resolves to its own "image", or, for a level listed in
##     PENDING_ART, to its themed "fallback_image" and never to level 01's panel;
## (3) a PENDING_ART level whose art has landed fails, so the list can't go stale;
## (4) every FX anchor sits inside the panel (u, v in 0..1).
##   godot --headless --path . --audio-driver Dummy res://tests/comic_panel_probe.tscn

const Briefing := preload("res://scripts/cutscene/level_comic_briefing.gd")

## Levels whose own art is not drawn yet, each with the issue that tracks it.
const PENDING_ART := {}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	var defs: Dictionary = Briefing.LEVEL_COMIC_DEFS
	for path in GameState.CAMPAIGN:
		var lid := GameState.level_id_from_path(path)
		if not defs.has(lid):
			print("PANEL %s: no LEVEL_COMIC_DEFS entry, shows %s" % [lid, Briefing.panel_path(lid)])
			ok = false
			continue
		var cfg: Dictionary = defs[lid]
		var shown := Briefing.panel_path(lid)
		var own := String(cfg.get("image", ""))
		var want := own
		if PENDING_ART.has(lid):
			want = String(cfg.get("fallback_image", ""))
			if ResourceLoader.exists(own):
				print("PANEL %s: art landed at %s, drop it from PENDING_ART" % [lid, own])
				ok = false
		var good := shown == want and (lid == "01" or shown != Briefing.DEFAULT_PANEL)
		var anchors_in := true
		for fx in cfg.get("fx", []):
			var u: float = fx["u"]
			var v: float = fx["v"]
			anchors_in = anchors_in and u >= 0.0 and u <= 1.0 and v >= 0.0 and v <= 1.0
		if not good or not anchors_in:
			print("PANEL %s: shows %s want %s anchors_in=%s" % [lid, shown, want, anchors_in])
			ok = false
	print("PANELS: levels=%d pending=%s" % [GameState.CAMPAIGN.size(), PENDING_ART])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
