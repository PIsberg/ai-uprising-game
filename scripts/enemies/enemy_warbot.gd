class_name EnemyWarbot
extends EnemyAndroid
## A stout bipedal war-bot built on the imported "Robot" chassis. Twin arm-cannons
## are welded over its hands, and its screen is a MOOD face: a green happy face
## while it idles/patrols, snapping to a red angry face the instant it spots you and
## engages. Reuses the android rifleman AI (walk / flank / dodge / burst-fire).

# Face overlay sits on the chest screen, covering the model's built-in face
# (forward is -Z). Tunable.
const FACE_Y := 1.5
const FACE_Z := -0.52
# Hand/cannon offsets (mirrored on X). Pushed forward so the cannons read as
# held weapons jutting past the forearms.
const HAND_X := 0.6
const HAND_Y := 1.08
const HAND_Z := -0.42

var _happy: Node3D
var _angry: Node3D
var _angry_now: bool = false

func _ready() -> void:
	super._ready()
	# A sturdier mid-tier grunt than the android.
	max_health = 150.0
	move_speed = 4.6
	turn_speed = 7.5
	attack_range = 24.0
	preferred_range = 11.0
	score_value = 185
	hp.max_health = max_health
	hp.current_health = max_health
	_build_weapons()
	_build_face()

func _emissive(c: Color, energy: float = 3.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material) -> void:
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	b.mesh = bm
	b.material_override = mat
	b.position = pos
	b.rotation = Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	parent.add_child(b)

## Twin arm-cannons welded over the hands (barrels point forward, -Z).
func _build_weapons() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.16, 0.17, 0.2)
	metal.metallic = 0.85
	metal.roughness = 0.35
	var glow := _emissive(Color(1.0, 0.5, 0.12), 2.2)
	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(HAND_X * sx, HAND_Y, HAND_Z)
		add_child(arm)
		_box(arm, Vector3(0.32, 0.32, 0.4), Vector3(0, 0, 0.1), Vector3.ZERO, metal) # housing at hand
		_box(arm, Vector3(0.12, 0.12, 0.5), Vector3(0, -0.16, -0.2), Vector3.ZERO, metal) # under-barrel rail
		var barrel := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1; cm.bottom_radius = 0.15; cm.height = 0.8; cm.radial_segments = 12
		barrel.mesh = cm
		barrel.material_override = metal
		barrel.rotation.x = deg_to_rad(90.0) # cylinder Y-axis -> forward (-Z)
		barrel.position = Vector3(0, 0, -0.4)
		arm.add_child(barrel)
		var tip := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1; sm.height = 0.2
		tip.mesh = sm
		tip.material_override = glow
		tip.position = Vector3(0, 0, -0.82)
		arm.add_child(tip)

## Two faces on the screen — a green happy one and a red angry one — toggled by
## combat state. Built from emissive blocks; forward is -Z so they sit on the face.
func _build_face() -> void:
	var green := _emissive(Color(0.3, 1.0, 0.4), 4.0)
	var red := _emissive(Color(1.0, 0.2, 0.16), 4.5)
	# A near-black panel masks the model's painted-on face so only ours shows.
	var panel := StandardMaterial3D.new()
	panel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.albedo_color = Color(0.015, 0.018, 0.025)
	_happy = Node3D.new()
	_happy.position = Vector3(0, FACE_Y, FACE_Z)
	add_child(_happy)
	_box(_happy, Vector3(0.44, 0.54, 0.02), Vector3(0, 0, 0.01), Vector3.ZERO, panel)
	# Happy: round eyes + an upward smile.
	_box(_happy, Vector3(0.11, 0.16, 0.02), Vector3(-0.11, 0.08, 0), Vector3.ZERO, green)
	_box(_happy, Vector3(0.11, 0.16, 0.02), Vector3(0.11, 0.08, 0), Vector3.ZERO, green)
	_box(_happy, Vector3(0.16, 0.05, 0.02), Vector3(0, -0.15, 0), Vector3.ZERO, green)
	_box(_happy, Vector3(0.09, 0.05, 0.02), Vector3(-0.15, -0.1, 0), Vector3(0, 0, 40), green)
	_box(_happy, Vector3(0.09, 0.05, 0.02), Vector3(0.15, -0.1, 0), Vector3(0, 0, -40), green)
	# Angry: slanted brows, narrowed eyes, a downturned frown.
	_angry = Node3D.new()
	_angry.position = Vector3(0, FACE_Y, FACE_Z)
	add_child(_angry)
	_box(_angry, Vector3(0.44, 0.54, 0.02), Vector3(0, 0, 0.01), Vector3.ZERO, panel)
	_box(_angry, Vector3(0.18, 0.06, 0.02), Vector3(-0.12, 0.14, 0), Vector3(0, 0, -26), red)
	_box(_angry, Vector3(0.18, 0.06, 0.02), Vector3(0.12, 0.14, 0), Vector3(0, 0, 26), red)
	_box(_angry, Vector3(0.12, 0.08, 0.02), Vector3(-0.11, 0.02, 0), Vector3(0, 0, -20), red)
	_box(_angry, Vector3(0.12, 0.08, 0.02), Vector3(0.11, 0.02, 0), Vector3(0, 0, 20), red)
	_box(_angry, Vector3(0.16, 0.05, 0.02), Vector3(0, -0.16, 0), Vector3.ZERO, red)
	_box(_angry, Vector3(0.09, 0.05, 0.02), Vector3(-0.15, -0.11, 0), Vector3(0, 0, -40), red)
	_box(_angry, Vector3(0.09, 0.05, 0.02), Vector3(0.15, -0.11, 0), Vector3(0, 0, 40), red)
	_angry.visible = false

## Happy until it engages — angry the moment it's alerted / chasing / attacking.
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var hostile := state == State.ALERT or state == State.CHASE or state == State.ATTACK
	if hostile != _angry_now:
		_angry_now = hostile
		if _happy:
			_happy.visible = not hostile
		if _angry:
			_angry.visible = hostile
