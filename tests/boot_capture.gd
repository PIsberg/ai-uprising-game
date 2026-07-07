extends Node
## Parented to /root so it survives change_scene. Screenshots the start flow.
var _shots: Array = [0.4, 1.2, 2.5, 4.5, 7.0]
var _i: int = 0
var _acc: float = 0.0
func _process(delta: float) -> void:
	_acc += delta
	if _i < _shots.size() and _acc >= float(_shots[_i]):
		var cur: Node = get_tree().current_scene
		var nm: String = String(cur.name) if cur != null else "<none>"
		print("CAP t=%.1f scene=%s" % [_acc, nm])
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/boot_%d.png" % _i)
		_i += 1
		if _i >= _shots.size():
			get_tree().quit()
