extends Node
## Windowed probe for QualityBenchmark (scripts/ui/quality_benchmark.gd).
## Run windowed (NOT headless — it needs real GPU timings):
##   godot --path . res://tests/benchmark_probe.tscn
##
## Instantiates QualityBenchmark directly twice, prints the measured avg ms +
## tier each run, and asserts:
##   - each tier is in range 0..3 (LOW..ULTRA)
##   - the two runs agree within 1 tier (stability)
##   - GraphicsSettings.quality is untouched by the class itself (it never
##     calls set_quality — that's the caller's job, e.g. main_menu.gd)
##
## Like preset_probe.gd, this drives the real GraphicsSettings autoload, so we
## snapshot user://settings.cfg's raw bytes up front and restore them
## verbatim before any hard assertions run (restore-before-assert, not just
## restore-before-quit, so a failed assertion still leaves the dev's file
## untouched).

var _failures := 0
const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var had_file := FileAccess.file_exists(SETTINGS_PATH)
	var backup_bytes := PackedByteArray()
	if had_file:
		var rf := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		backup_bytes = rf.get_buffer(rf.get_length())
		rf.close()

	var quality_before := GraphicsSettings.quality

	var run1 := await _run_one()
	var run2 := await _run_one()

	# ---- restore the dev's real settings BEFORE any hard assertion ----
	if had_file:
		var wf := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		wf.store_buffer(backup_bytes)
		wf.close()
	else:
		var da := DirAccess.open("user://")
		if da and da.file_exists("settings.cfg"):
			da.remove("settings.cfg")
	GraphicsSettings._load_settings()

	print("RESULT run1: tier=%d (%s) avg=%.2fms" % [run1.tier, GraphicsSettings.LABELS[run1.tier], run1.avg])
	print("RESULT run2: tier=%d (%s) avg=%.2fms" % [run2.tier, GraphicsSettings.LABELS[run2.tier], run2.avg])

	_assert(run1.tier >= 0 and run1.tier <= 3, "run1 tier in range 0..3 (got %d)" % run1.tier)
	_assert(run2.tier >= 0 and run2.tier <= 3, "run2 tier in range 0..3 (got %d)" % run2.tier)
	_assert(absi(run1.tier - run2.tier) <= 1,
		"tiers stable across two runs, within 1 (run1=%d run2=%d)" % [run1.tier, run2.tier])
	_assert(GraphicsSettings.quality == quality_before,
		"QualityBenchmark alone never mutates GraphicsSettings.quality (still %s)" % GraphicsSettings.LABELS[GraphicsSettings.quality])

	print("=== %s ===" % ("ALL PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL"))
	get_tree().quit(0 if _failures == 0 else 1)

## Instantiates one QualityBenchmark run and returns {tier, avg} once it's
## reported in. QualityBenchmark frees itself right after emitting, but
## queue_free() defers to end-of-frame, so avg_ms is still readable in this
## same continuation.
func _run_one() -> Dictionary:
	var bench := QualityBenchmark.new()
	add_child(bench)
	var tier: int = await bench.finished
	return {"tier": tier, "avg": bench.avg_ms}

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: %s" % msg)
	else:
		print("FAIL: %s" % msg)
		_failures += 1
