extends SceneTree; var test_val: Vector3 = Vector3.ZERO; func _init(): var tw = create_tween(); tw.tween_property(self, \
test_val\, Vector3(1,1,1), 1.0); await tw.finished; print(test_val); quit()
