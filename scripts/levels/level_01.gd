extends Node3D

## Level bootstrap.
## The scene ships with an *unbaked* NavigationMesh (agent settings only, no
## polygons), so ground enemies had no path to follow and stood still. Baking
## at runtime from the static level colliders gives android/mech a navmesh to
## walk on without requiring a manual "Bake NavigationMesh" in the editor.

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var voxel_gi: VoxelGI = $VoxelGI

func _ready() -> void:
	# Defer one frame so all level geometry is settled in the tree, then bake
	# synchronously (the level is tiny). Enemies use a straight-line fallback
	# (see EnemyBase._move_toward) during the brief window before this finishes.
	_bake_navmesh.call_deferred()
	_bake_gi.call_deferred()
	GameState.apply_level_scaling(self) # difficulty: tune enemy/pickup counts
	AudioBus.play_music("music_techno")
	_setup_objectives()

## Bring the tutorial level onto the shared task framework: clear hostiles AND
## grab a keycard, then the gated Portal opens. Replaces the old single-purpose
## ExitObjective node with the same animated Portal the other levels use.
func _setup_objectives() -> void:
	GameState.reset_tasks()
	GameState.register_task("kill_all", "Eliminate all hostiles")
	GameState.register_task("key", "Recover the access keycard")

	var exit_pos := Vector3(22, 1.5, 22)
	var old := get_node_or_null("ExitObjective")
	if old:
		exit_pos = (old as Node3D).global_position
		old.queue_free()
	var portal := Portal.new()
	portal.objective_text = "Reach the extraction portal"
	portal.position = exit_pos
	add_child(portal)

	# A keycard along the route so the player learns the find-and-unlock loop.
	var key := Keycard.new()
	key.task_id = "key"
	key.position = Vector3(14, 0, 11.2)
	add_child(key)

func _bake_gi() -> void:
	# Real-time GI is High-quality only; the dummy/headless renderer can't bake.
	if voxel_gi == null:
		return
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs == null or not gs.has_method("is_high") or not gs.is_high():
		return
	if DisplayServer.get_name() != "headless":
		voxel_gi.bake.call_deferred()

func _bake_navmesh() -> void:
	if nav_region and nav_region.navigation_mesh and is_inside_tree():
		nav_region.bake_navigation_mesh(false)
