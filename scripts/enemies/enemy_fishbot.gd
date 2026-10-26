class_name EnemyFishbot
extends EnemyDrone
## ANGLER UNIT — a robotic deep-sea fish that prowls the flooded basins: the
## one-eyed flyer dome (robot_flyer.glb) with glowing fins bolted on (tail,
## dorsal, two pectorals) and a trail of bubbles, on the drone's flight AI
## but faster, darting and fragile. It spits pressurised water bolts. Native
## to the water world.
##
## Swim rig (tests/fishbot_rig_probe). The fins hang under the model's Mesh
## node, so they bank and lean with the chassis instead of floating fixed
## beside it. The tail sweeps about its root in a beat that follows the swim:
## a lazy scull hanging still, fast wide strokes at speed, a thrash through a
## dart. The pectorals flutter in counter-phase and pitch with a climb or a
## descent like dive planes. The lander legs the flyer dome dangles trail
## behind it and kick with the beat (BoneSweepModifier on the hips and the
## feet), and go limp when it dies. The spit leaves the lens of the eye (the
## muzzle rides the Eye bone, which HeadTrack swivels onto you; it used to
## leave a point 0.7 m under the body), and every spit is followed by a
## tail-flick dart to the side, the next one the other way: hit and run.

const BEAT_IDLE := 6.0       ## rad/s of the tail beat hanging still (about 1 Hz)
const BEAT_SWIM := 19.0      ## at full speed (3 Hz)
const BEAT_DART := 30.0      ## through a dart
const BEAT_RATE := 40.0      ## rad/s^2 the beat changes
const TAIL_IDLE := 0.16      ## rad, the stroke's half-width hanging still
const TAIL_SWIM := 0.42
const TAIL_DART := 0.6
const AMP_RATE := 2.0        ## rad/s the stroke width changes
const PEC_FLAP := 0.3        ## the pectorals' flutter, as a share of the tail stroke
const PEC_PITCH := 0.08      ## rad per m/s of climb (a descent pitches them nose-down)
const PEC_PITCH_MAX := 0.45
const LEG_KICK := 0.2        ## rad about the hips with the beat, at full speed
const LEG_TRAIL := Vector3(0.35, -0.3, 0.9) ## where a swept leg points (right leg; the left mirrors x)
const DART_SPEED := 7.5      ## m/s sideways off a spit
const DART_TIME := 0.4       ## s the tail thrashes for

var _rig_ready := false
var _tail_e: Array = []
var _tail_hinge := Vector3.ZERO   ## body frame: the tail's front edge
var _pec_e: Array = []            ## PartRig entries, [right (+x), left]
var _pec_root: Array = []         ## body frame: each pectoral's edge at the body
var _pec_side: Array = []         ## +1 for the right (+x) fin, -1 for the left
var _sweep: BoneSweepModifier = null
var _legs: Array = []             ## the sides ("L", "R") with a hip and a foot bone
var _beat := 0.0
var _beat_rate := 0.0
var _amp := 0.0
var _tail := 0.0
var _pec_pitch := 0.0
var _dart_t := 0.0

func _ready() -> void:
	super._ready()
	# Fast, darting and fragile — a hit-and-run swimmer.
	max_health = 70.0
	move_speed = 7.4
	sight_range = 40.0
	attack_range = 20.0
	preferred_range = 10.0
	attack_cooldown = 0.55
	projectile_speed = 34.0
	projectile_damage = 12.0
	score_value = 110
	hover_amplitude = 0.5   # a deeper, fish-like undulation
	hover_freq = 2.6
	drops_loot = true       # a basin mini-elite leaves supplies (landed on the gantry)
	hp.max_health = max_health
	hp.current_health = max_health
	_build_fins()
	_sweep_legs()

## _process, not physics, so the codex preview (physics disabled) swims too.
func _process(delta: float) -> void:
	super._process(delta)
	_tick_rig(delta)

## The spit, then the dart: a tail-flick to the side (alternating), which the
## attack's own steering bleeds off over the next half second.
func _perform_attack() -> void:
	super._perform_attack()
	if target == null or not is_instance_valid(target):
		return
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() < 0.1:
		return
	velocity += to.normalized().cross(Vector3.UP) * _strafe_dir * DART_SPEED
	_strafe_dir = -_strafe_dir
	_strafe_change_timer = randf_range(1.0, 2.5)
	_dart_t = DART_TIME
	AudioBus.play_synth_at("drone_hum", global_position, 0.0, 2.3)

## Glowing blue fins (dorsal, swept tail, two pectorals) hung under the
## model's Mesh node, the one RobotModel banks and leans, placed in the body
## frame. The tail's hinge is its front edge; each pectoral's is the edge at
## the body.
func _build_fins() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.7, 1.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.75, 1.0)
	mat.emission_energy_multiplier = 1.9
	var mesh_node := get_node_or_null("Model/Mesh") as Node3D
	_fin("Dorsal", Vector3(0.03, 0.34, 0.26), Vector3(0.0, 0.92, 0.06), Vector3(16, 0, 0), mat, mesh_node)
	var tail := _fin("Tail", Vector3(0.03, 0.3, 0.42), Vector3(0.0, 0.6, 0.42), Vector3(46, 0, 0), mat, mesh_node)
	var pec_r := _fin("PectoralR", Vector3(0.34, 0.03, 0.22), Vector3(0.62, 0.42, 0.0), Vector3(0, 0, -30), mat, mesh_node)
	var pec_l := _fin("PectoralL", Vector3(0.34, 0.03, 0.22), Vector3(-0.62, 0.42, 0.0), Vector3(0, 0, 30), mat, mesh_node)
	if mesh_node == null:
		return # a chassis without the model keeps its fins still
	_tail_e = PartRig.entry(self, tail)
	_tail_hinge = AimedPart.band_mean(PartRig.body_points(self, tail), Vector3.FORWARD, 0.02)
	for p in [pec_r, pec_l]:
		var pts := PartRig.body_points(self, p)
		var side := signf(PartRig.mean(pts).x)
		_pec_e.append(PartRig.entry(self, p))
		_pec_root.append(AimedPart.band_mean(pts, Vector3.RIGHT * -side, 0.02))
		_pec_side.append(side)
	_rig_ready = true

## A box fin at `pos`/`rot_deg` in the body frame, under `parent` (the Mesh
## node, whatever its import scale and yaw) or, without one, the body.
func _fin(name: String, size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var fin := MeshInstance3D.new()
	fin.name = name
	var bm := BoxMesh.new()
	bm.size = size
	fin.mesh = bm
	fin.material_override = mat
	var in_body := Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))), pos)
	if parent == null:
		add_child(fin)
		fin.transform = in_body
		return fin
	parent.add_child(fin)
	fin.transform = parent.global_transform.affine_inverse() * global_transform * in_body
	return fin

## Trail the lander legs behind the body: each hip is turned so its leg
## (hip to foot, as the clip poses it that frame: the rest pose staggers
## the legs fore and aft, the idle clip splays them) points along
## LEG_TRAIL, and the foot and its pole target (separate root-level IK
## bones on this rig) swing about the same hip. The kick with the beat
## composes on top each tick.
func _sweep_legs() -> void:
	var sk := find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		return
	for side in ["L", "R"]:
		if sk.find_bone("Leg1." + side) >= 0 and sk.find_bone("Foot." + side) >= 0:
			_legs.append(side)
	if _legs.is_empty():
		return
	_sweep = BoneSweepModifier.new()
	_sweep.name = "LegSweep"
	_sweep.body = self
	sk.add_child(_sweep)
	_pose_legs(0.0)

func _pose_legs(kick: float) -> void:
	var k := Quaternion(Vector3.RIGHT, kick)
	for side in _legs:
		var dir := LEG_TRAIL * Vector3(1.0 if side == "R" else -1.0, 1.0, 1.0)
		_sweep.point("Leg1." + side, "Foot." + side, dir, k)
		_sweep.follow("Foot." + side, "Leg1." + side)
		_sweep.follow("PT." + side, "Leg1." + side) # no pole target on another rig: nothing registered

## Beat the tail, flutter and pitch the pectorals, kick the legs (see the
## class doc). The beat and the stroke follow the horizontal speed.
func _tick_rig(delta: float) -> void:
	if not _rig_ready:
		return
	var dead := state == State.DEAD or _dying
	var swim := clampf(Vector2(velocity.x, velocity.z).length() / maxf(move_speed, 0.1), 0.0, 1.0)
	_dart_t = maxf(_dart_t - delta, 0.0)
	var want_rate := 0.0
	var want_amp := 0.0
	if not dead:
		want_rate = BEAT_DART if _dart_t > 0.0 else lerpf(BEAT_IDLE, BEAT_SWIM, swim)
		want_amp = TAIL_DART if _dart_t > 0.0 else lerpf(TAIL_IDLE, TAIL_SWIM, swim)
	_beat_rate = move_toward(_beat_rate, want_rate, BEAT_RATE * delta)
	_amp = move_toward(_amp, want_amp, AMP_RATE * delta)
	_beat = fposmod(_beat + _beat_rate * delta, TAU)
	_tail = _amp * sin(_beat)
	PartRig.pose(_tail_e, PartRig.turn(_tail_hinge, Vector3.UP, _tail))
	var want_pitch := 0.0 if dead else clampf(velocity.y * PEC_PITCH, -PEC_PITCH_MAX, PEC_PITCH_MAX)
	_pec_pitch = move_toward(_pec_pitch, want_pitch, 3.0 * delta)
	var flap := _amp * PEC_FLAP * sin(_beat + PI * 0.5)
	for i in _pec_e.size():
		var root: Vector3 = _pec_root[i]
		PartRig.pose(_pec_e[i], PartRig.turn(root, Vector3.RIGHT, _pec_pitch) * PartRig.turn(root, Vector3.BACK, flap * float(_pec_side[i])))
	if _sweep:
		_sweep.weight = move_toward(_sweep.weight, 0.0 if dead else 1.0, 2.0 * delta)
		_pose_legs(LEG_KICK * sin(_beat) * (0.3 + 0.7 * swim))

## Override the drone's orange thruster trail with a slow rising stream of bubbles
## so it reads as swimming.
func _make_exhaust() -> void:
	var p := CPUParticles3D.new()
	p.amount = 16
	p.lifetime = 1.2
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 18.0
	p.gravity = Vector3(0, 0.8, 0) # bubbles drift up
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4)); curve.add_point(Vector2(0.5, 1.0)); curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.scale_amount_min = 0.4; p.scale_amount_max = 0.9
	var mesh := SphereMesh.new()
	mesh.radius = 0.05; mesh.height = 0.1; mesh.radial_segments = 6; mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.85, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.8, 1.0)
	mat.emission_energy_multiplier = 1.2
	mesh.material = mat
	p.mesh = mesh
	p.position = Vector3(0, 0.45, 0.4) # trail from behind the tail root
	add_child(p)
