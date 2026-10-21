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
var _angry_mat: StandardMaterial3D
var _furious: bool = false ## Below the rage threshold it snaps to a heavier, faster barrage.
var _arms: Array[Node3D] = [] ## The two welded arm-cannons — cross-fire origins.

func _ready() -> void:
	super._ready()
	# A thick-armored bruiser grunt — bulkier and tankier than the android, and a
	# step slower for the weight.
	max_health = 200.0
	move_speed = 4.4
	turn_speed = 7.0
	attack_range = 24.0
	preferred_range = 11.0
	score_value = 210
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 2.0
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
		_arms.append(arm) # cross-fire shoots from these, not one imaginary chest gun
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
		# Muzzle lens recessed into the barrel mouth — a full glowing sphere out
		# on the tip read as a stray "orange ball" on the chassis (esp. in the
		# codex, where the bot idles on a pedestal).
		var tip := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.055; sm.height = 0.11
		tip.mesh = sm
		tip.material_override = glow
		tip.position = Vector3(0, 0, -0.78)
		arm.add_child(tip)

## Two faces on the screen — a green happy one and a red angry one — toggled by
## combat state. Built from emissive blocks; forward is -Z so they sit on the face.
func _build_face() -> void:
	var green := _emissive(Color(0.3, 1.0, 0.4), 4.0)
	var red := _emissive(Color(1.0, 0.2, 0.16), 4.5)
	_angry_mat = red # kept so the face can flare furious when it's wounded
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
	# Wounded rage: past 45% damage the mood face goes FURIOUS and it snaps to a
	# heavier, faster barrage — the mood screen finally cashed as a mechanic.
	if not _furious and state != State.DEAD and hp.current_health <= hp.max_health * 0.45:
		_furious = true
		burst_count = 8
		burst_interval = 0.06
		attack_cooldown = 1.0
		# The tantrum reads on the FIELD, not just the face: a furious surge
		# toward you plus a rally cry that pulls nearby allies onto you.
		if target and is_instance_valid(target):
			attack_lunge_speed = 13.0
			_attack_lunge()
			if target is Node3D:
				_alert_allies(14.0, target as Node3D)
		_speak("taunt", 0.9)
	if _furious and _angry and _angry.visible:
		var p := 1.0 + sin(_state_timer * 12.0) * 0.09 # a seething throb
		_angry.scale = Vector3(p, p, 1.0)
		if _angry_mat:
			_angry_mat.emission_energy_multiplier = 5.0 + sin(_state_timer * 12.0) * 2.5

## CROSS-FIRE: both welded arm-cannons fire together in a diverging V around
## the aim line (the android base fires one imaginary chest rifle). Standing
## dead still in the lane between the streams is (mostly) safe; strafing walks
## you across one — and FURIOUS narrows the V, squeezing that lane shut.
## Per-bolt damage is trimmed so two barrels ≈ the old single-gun burst.
##
## The V is authored in METRES at the target, not degrees: a fixed 6° V put
## each stream 1.15 m off the aim line at its 11 m preferred range — three
## times the player's 0.35 m capsule radius — so both barrels missed a still
## target every time and the warbot measured 0.4 DPS against the android's
## 13.5 (tests/threat_probe, 2026-09-11). Bracketing the body by a fixed
## half-width keeps the lane the same width at every range, and the base
## burst scatter is what makes standing still only *mostly* safe.
const CROSS_HALF_WIDTH_M := 0.45         ## each stream this far off the aim line, at the target
const CROSS_HALF_WIDTH_FURIOUS_M := 0.15 ## inside the capsule: the lane is gone

func _fire_one_shot() -> void:
	if target == null or _arms.size() < 2:
		super._fire_one_shot()
		return
	recoil = 1.0
	AudioBus.play_synth_at("drone_shot", global_position, -3.0, randf_range(0.88, 0.98))
	var half_w := CROSS_HALF_WIDTH_FURIOUS_M if _furious else CROSS_HALF_WIDTH_M
	var aim := target.global_position + Vector3.UP * 0.6
	for i in 2:
		var arm := _arms[i]
		var origin: Vector3 = arm.global_position - arm.global_basis.z * 0.8
		var dir := (aim - origin).normalized()
		# Convert the half-width at the target into this bolt's yaw offset.
		var v_rad := atan2(half_w, maxf(origin.distance_to(aim), 1.0))
		dir = dir.rotated(Vector3.UP, v_rad * (1.0 if i == 0 else -1.0))
		dir = scatter_aim(dir, burst_spread_deg)
		_cross_bolt(origin, dir)
		if muzzle_flash_scene:
			arm.add_child(muzzle_flash_scene.instantiate())

func _cross_bolt(origin: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 80.0)
	q.collision_mask = 0b0000011 # world + player
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var end_point := origin + dir * 80.0
	if not hit.is_empty():
		end_point = hit.position
		var col: Node = hit.collider
		var d: Node = col.get_node_or_null("Damageable") if col else null
		if d:
			d.apply_damage(hitscan_damage * 0.55, self)
	if tracer_scene:
		var t := tracer_scene.instantiate()
		get_tree().current_scene.add_child(t)
		if t.has_method("setup"):
			t.setup(origin, end_point)
