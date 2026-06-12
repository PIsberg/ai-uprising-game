class_name Pickup
extends Area3D

enum Kind { HEALTH, AMMO, WEAPON, OVERCLOCK }

@export var kind: Kind = Kind.HEALTH
@export var amount: int = 25
@export var weapon_scene: PackedScene ## Used when kind == WEAPON.

var _taken: bool = false
var _bob_phase: float = 0.0
@onready var _mesh: Node3D = get_node_or_null("Mesh")
@onready var _light: OmniLight3D = get_node_or_null("Light")
var _mesh_home_y: float = 0.0
var _light_base: float = 0.0

func _ready() -> void:
	collision_layer = 32
	collision_mask = 2
	add_to_group("pickup")
	body_entered.connect(_on_body_entered)
	_bob_phase = randf() * TAU
	if _mesh:
		_mesh_home_y = _mesh.position.y
	if _light:
		_light_base = _light.light_energy
	if kind == Kind.WEAPON and weapon_scene:
		_show_weapon_model()
	_add_blob_shadow()

## A soft dark disc under the pickup. Floating items otherwise read as pasted
## onto the floor — this grounds them for almost nothing.
func _add_blob_shadow() -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.32
	cm.height = 0.01
	cm.radial_segments = 14
	cm.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0.4)
	cm.material = mat
	disc.mesh = cm
	disc.position = Vector3(0, 0.025, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)

## Weapon pickups display the ACTUAL gun hovering inside the glow ring instead
## of the placeholder box: the real weapon scene is instanced (its _ready swaps
## in the imported model), turned side-on so its profile fills the ring, and
## auto-fitted from the same length table the viewmodel uses.
func _show_weapon_model() -> void:
	if _mesh == null or not _mesh is MeshInstance3D:
		return
	(_mesh as MeshInstance3D).mesh = null # drop the placeholder; the ring is a child and stays
	var inst := weapon_scene.instantiate() as Node3D
	# Display only: no heat/cooldown ticking, and tween-driven anims stay off.
	inst.process_mode = Node.PROCESS_MODE_DISABLED
	_mesh.add_child(inst)
	var vm := inst.get_node_or_null("Viewmodel") as Node3D
	if vm:
		vm.position = Vector3.ZERO # undo the first-person framing offset
	# Side-on inside the ring; fitted so long rifles don't poke through it.
	var key := weapon_scene.resource_path.get_file().get_basename()
	var cfg: Dictionary = Weapon.REAL_MODELS.get(key, {})
	var glen: float = cfg.get("len", 0.6)
	var s := minf(1.0, 0.7 / glen)
	inst.rotation.y = PI * 0.5
	inst.scale = Vector3.ONE * s
	# The fitted model spans z in [0.18 - len, 0.18] (rear parked at 0.18), so
	# shift the gun so its midpoint sits at the ring centre.
	var center := Vector3(0, 0.0, 0.18 - glen * 0.5)
	inst.position = -(Basis(Vector3.UP, inst.rotation.y) * center) * s

func _process(delta: float) -> void:
	rotate_y(delta * 1.2)
	_bob_phase += delta * 2.0
	if _mesh:
		_mesh.position.y = _mesh_home_y + sin(_bob_phase) * 0.12
	if _light:
		_light.light_energy = _light_base + sin(_bob_phase * 1.5) * _light_base * 0.3

func _on_body_entered(body: Node) -> void:
	if _taken or not body.is_in_group("player"):
		return
	match kind:
		Kind.HEALTH:
			var d := body.get_node_or_null("Damageable")
			if d == null or d.current_health >= d.max_health:
				return # don't waste a full-health pickup
			d.heal(amount)
			if body.has_method("notify_pickup"):
				body.notify_pickup("+%d HEALTH" % amount)
			AudioBus.play_synth_at("pickup_health", global_position, -2.0)
		Kind.AMMO:
			var wm := body.get_node_or_null("Head/Camera3D/WeaponHolder")
			if wm:
				# Top up every weapon's reserve, not just the equipped one.
				for w in wm.weapons:
					if w and w.has_method("add_ammo"):
						w.add_ammo(amount)
			var got_grenade := false
			if body.has_method("add_grenade"):
				body.add_grenade(1)
				got_grenade = true
			if body.has_method("notify_pickup"):
				body.notify_pickup("+%d AMMO" % amount + (" · +1 GRENADE" if got_grenade else ""))
			AudioBus.play_synth_at("pickup_ammo", global_position, -2.0)
		Kind.WEAPON:
			if weapon_scene == null:
				return
			var wm := body.get_node_or_null("Head/Camera3D/WeaponHolder")
			if wm and wm.has_method("add_weapon"):
				wm.add_weapon(weapon_scene, true) # equip the shiny new gun
				GameState.unlock_weapon(weapon_scene.resource_path)
			AudioBus.play_synth_at("pickup_health", global_position, 0.0, 0.7)
		Kind.OVERCLOCK:
			GameState.activate_overclock()
			if body.has_method("notify_pickup"):
				body.notify_pickup("⚡ OVERCLOCK — ×%d DAMAGE" % int(GameState.OVERCLOCK_MULT))
			# Triumphant sting: this is a run-the-table moment.
			AudioBus.play_synth_ui("victory", -8.0, 1.4)
	_taken = true
	queue_free()
