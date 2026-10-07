extends SceneTree
## Headless stand-in for the editor's Profiler tab (#89). Launches a scene in a
## child Godot process with --remote-debug pointed at this one, switches on the
## engine's "servers" profiler (script functions, with native calls recorded, and
## the physics server's per-step breakdown), and prints where the time goes,
## averaged over the frames of a capture window.
##
## Runs headless, so it measures CPU work only; that is the open question in #89.
##   godot --headless --path . --script res://tools/remote_profile.gd -- \
##       scene=res://tests/enemy_cost_probe.tscn warmup=4 capture=3 top=25 \
##       args=types=android
## `args=` is passed through to the child after its own `--` (separate several with |).
##
## Protocol (core/debugger/remote_debugger_peer.cpp): every message is a u32
## little-endian byte length, then a Variant-encoded Array. Child -> us:
## [message, thread_id, data]; us -> child: [command, thread_id, data], where the
## thread id must be one the child has registered (its main thread: the id on
## its first message, set_pid), or the child drops the command silently.

const PORT := 6107

var _opts := {"scene": "res://tests/enemy_cost_probe.tscn", "warmup": "4", "capture": "3", "top": "25", "args": ""}
var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _buf := PackedByteArray()
var _pid := -1
var _sigs := {}            # signature id -> "path::line::function"
var _frames := 0
var _script := {}          # signature -> [self s summed, total s summed, calls summed]
var _servers := {}         # "server/function" -> seconds summed
var _sums := {"frame": 0.0, "process": 0.0, "physics": 0.0, "physics_frame": 0.0, "script": 0.0}
var _t0 := 0.0
var _armed := false
var _child_done := false
var _seen := {}
var _main_thread := -1
var _phys_samples: Array[float] = []
var _hot := {}             # signature -> self s summed over frames whose physics tick > hot= ms
var _hot_frames := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			_opts[kv[0]] = kv[1]
	if _server.listen(PORT, "127.0.0.1") != OK:
		push_error("remote_profile: cannot listen on %d" % PORT)
		quit(2)
		return
	var child_args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--audio-driver", "Dummy",
		"--remote-debug", "tcp://127.0.0.1:%d" % PORT, _opts["scene"]]
	if _opts["args"] != "":
		child_args.append("--")
		child_args.append_array(_opts["args"].split("|"))
	_pid = OS.create_process(OS.get_executable_path(), child_args)
	print("remote_profile: child pid %d running %s" % [_pid, _opts["scene"]])
	_t0 = Time.get_ticks_msec() / 1000.0

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0 - _t0
	if _peer == null:
		if _server.is_connection_available():
			_peer = _server.take_connection()
			_peer.set_no_delay(true)
			print("remote_profile: child connected after %.1f s; warmup counts from here" % now)
			_t0 = Time.get_ticks_msec() / 1000.0
		elif now > 60.0:
			push_error("remote_profile: child never connected")
			return _finish(2)
		return false
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_child_done = true
		return _finish(0)
	var n := _peer.get_available_bytes()
	if n > 0:
		var got := _peer.get_partial_data(n)
		if got[0] == OK:
			_buf.append_array(got[1])
	_drain()
	var warmup := float(_opts["warmup"])
	if not _armed and now >= warmup and _main_thread >= 0:
		_armed = true
		_send("profiler:servers", [true, [int(_opts["top"]) * 4, true]])
		print("remote_profile: profiling for %s s" % _opts["capture"])
	if _armed and now >= warmup + float(_opts["capture"]):
		_send("profiler:servers", [false])
		return _finish(0)
	return false

func _send(cmd: String, data: Array) -> void:
	var body := var_to_bytes([cmd, _main_thread, data])
	var head := PackedByteArray()
	head.resize(4)
	head.encode_u32(0, body.size())
	_peer.put_data(head + body)

func _drain() -> void:
	while _buf.size() >= 4:
		var size := _buf.decode_u32(0)
		if _buf.size() < 4 + size:
			return
		var msg = bytes_to_var(_buf.slice(4, 4 + size))
		_buf = _buf.slice(4 + size)
		if msg is Array and msg.size() == 3:
			if _main_thread < 0:
				_main_thread = int(msg[1])
			_handle(String(msg[0]), msg[2])

func _handle(name: String, data: Array) -> void:
	_seen[name] = _seen.get(name, 0) + 1
	match name:
		"servers:function_signature":
			_sigs[int(data[1])] = String(data[0])
		"servers:profile_frame":
			_frame(data)
		"output":
			# [strings, types]: echo the child's own prints so its report lines
			# land next to the profile they were measured under.
			for line in data[0]:
				print("  child> %s" % String(line).strip_edges())
		"debug_enter":
			print("remote_profile: child hit a script error, continuing: %s" % str(data))
			_send("continue", [])
		"error":
			if _seen[name] <= 3:
				print("remote_profile: child error: %s" % str(data).left(300))

func _frame(a: Array) -> void:
	_frames += 1
	_sums["frame"] += a[1]
	_sums["process"] += a[2]
	_sums["physics"] += a[3]
	_sums["physics_frame"] += a[4]
	_sums["script"] += a[5]
	if float(a[3]) > 0.0:
		_phys_samples.append(float(a[3]) * 1000.0)
	var hot := float(a[3]) * 1000.0 > float(_opts.get("hot", "3"))
	if hot:
		_hot_frames += 1
	var i := 7
	for _s in int(a[6]):
		var server := String(a[i])
		var sub := int(a[i + 1])
		i += 2
		for k in range(0, sub, 2):
			var key := "%s/%s" % [server, a[i + k]]
			_servers[key] = _servers.get(key, 0.0) + float(a[i + k + 1])
		i += sub
	var count := int(a[i])
	i += 1
	for k in range(0, count, 5):
		var sig: String = _sigs.get(int(a[i + k]), "sig#%d" % int(a[i + k]))
		var row: Array = _script.get(sig, [0.0, 0.0, 0])
		row[0] += float(a[i + k + 2])
		row[1] += float(a[i + k + 3])
		row[2] += int(a[i + k + 1])
		_script[sig] = row
		if hot:
			_hot[sig] = _hot.get(sig, 0.0) + float(a[i + k + 2])

func _finish(code: int) -> bool:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_report()
	quit(code)
	return true

func _report() -> void:
	print("messages: ", _seen)
	if _frames == 0:
		print("remote_profile: no profile frames received")
		return
	var f := float(_frames)
	print("\n== %d frames; per-frame means (ms) ==" % _frames)
	for k in ["frame", "process", "physics", "physics_frame", "script"]:
		print("  %-14s %8.3f" % [k, _sums[k] / f * 1000.0])
	var ps := _phys_samples.duplicate()
	ps.sort()
	var pct := func(p: float) -> float: return ps[clampi(int(p * (ps.size() - 1)), 0, ps.size() - 1)]
	print("  physics tick (%d frames that ran one) percentiles p10" % ps.size() + " %.2f  p50 %.2f  p90 %.2f  p99 %.2f  max %.2f"
		% [pct.call(0.1), pct.call(0.5), pct.call(0.9), pct.call(0.99), ps[-1]])
	if _hot_frames > 0:
		print("\n== %d frames with a physics tick over %s ms: script self ms per such frame ==" % [_hot_frames, _opts.get("hot", "3")])
		var hk := _hot.keys()
		hk.sort_custom(func(x, y): return _hot[x] > _hot[y])
		for k in hk.slice(0, int(_opts["top"])):
			print("  %8.3f  %s" % [_hot[k] / _hot_frames * 1000.0, k])
	print("\n== physics/servers functions, ms per frame ==")
	var srv := _servers.keys()
	srv.sort_custom(func(x, y): return _servers[x] > _servers[y])
	for k in srv.slice(0, int(_opts["top"])):
		print("  %8.3f  %s" % [_servers[k] / f * 1000.0, k])
	print("\n== script functions (native calls included), ms per frame: self / total / calls ==")
	var keys := _script.keys()
	keys.sort_custom(func(x, y): return _script[x][0] > _script[y][0])
	for k in keys.slice(0, int(_opts["top"])):
		var r: Array = _script[k]
		print("  %8.3f %8.3f %7.1f  %s" % [r[0] / f * 1000.0, r[1] / f * 1000.0, r[2] / f, k])
