class_name CrawlerPounce
extends RefCounted
## The pounce posture of the two-legged disc walker (Enemy_Trilobite.gltf: a
## flat disc body on two digitigrade legs, clips Idle/Run/Attack/Look/
## Hanging), shared by the SPIDER and the SKITTER. Their scripts moved the
## chassis through the coil, the spring and the flight with nothing but an
## eye flare. Driven from `_process` with the phase the owner is in:
##  - "windup": the chassis squashes down into a coil (COIL_SQUASH, a
##    squash-and-stretch on the Model node) and tips nose-down (COIL_PITCH);
##  - "flight": a stretch at take-off (STRETCH for STRETCH_T), then the
##    Hanging clip (the legs dangle under the tilted disc) with the body
##    pitched along the arc, nose up rising and nose down falling;
##  - "ground": the landing squash (LAND_SQUASH for LAND_T) recovers, the
##    posture eases back to rest; the owner spikes `recoil` on the bite so
##    RobotModel plays the Attack clip (the disc tips onto it);
##  - "assess": the Look clip (the disc turns on the legs) through the
##    scuttle's freeze.
## The posture goes through EnemyBase.pose_squash / pose_pitch, which
## rig_frame() takes out like the other Model-node nudges.
## tests/crawler_pounce_probe.

const COIL_SQUASH := 0.72   ## Model y scale at the bottom of the coil
const COIL_PITCH := -0.22   ## rad, nose down
const COIL_RATE := 6.0      ## 1/s the coil deepens
const STRETCH := 1.18       ## y scale through the take-off
const STRETCH_T := 0.14     ## s
const STRETCH_RATE := 14.0  ## 1/s: out of the coil and up in a few frames
const LAND_SQUASH := 0.8
const LAND_T := 0.1
const RECOVER := 8.0        ## 1/s the squash and pitch recover
const ARC_PITCH := 0.7      ## share of the velocity's angle the body pitches by in flight
const ARC_MAX := 0.6        ## rad
const PITCH_RATE := 10.0    ## 1/s the pitch follows
const HANG_FROM := 1.0      ## s into the Hanging clip the flight starts (past its settle)

var body: EnemyBase
var _model: RobotModel
var phase := "ground"
var _t := 0.0
var _squash := 1.0
var _pitch := 0.0
var _landed := INF  ## s since the last landing

func _init(owner: EnemyBase) -> void:
	body = owner
	_model = owner.get_node_or_null("Model") as RobotModel

## Advance the posture for `want` ("ground", "windup", "flight", "assess").
func tick(delta: float, want: String) -> void:
	if body == null or not is_instance_valid(body):
		return
	if want != phase:
		_enter(want)
	_t += delta
	# Ask whether this frame is inside the landing before counting its time: a
	# frame of LAND_T or longer (under 10 fps) used to skip the squash outright.
	var landing := _landed < LAND_T
	_landed += delta
	var want_squash := 1.0
	var want_pitch := 0.0
	var rate := RECOVER
	match phase:
		"windup":
			want_squash = COIL_SQUASH
			want_pitch = COIL_PITCH
			rate = COIL_RATE
		"flight":
			if _t < STRETCH_T:
				want_squash = STRETCH
				rate = STRETCH_RATE
			var vh := Vector2(body.velocity.x, body.velocity.z).length()
			want_pitch = clampf(atan2(body.velocity.y, maxf(vh, 0.1)) * ARC_PITCH, -ARC_MAX, ARC_MAX)
		"ground":
			if landing:
				want_squash = LAND_SQUASH
	_squash = move_toward(_squash, want_squash, rate * delta)
	_pitch = move_toward(_pitch, want_pitch, PITCH_RATE * delta)
	body.pose_squash = _squash
	body.pose_pitch = _pitch

func _enter(want: String) -> void:
	var was := phase
	phase = want
	_t = 0.0
	if _model == null:
		return
	if was == "assess" or was == "flight":
		_model.release_hold()
	match want:
		"flight":
			_model.play_oneshot("Hanging", 0.08, 1.0, HANG_FROM)
		"assess":
			_model.play_oneshot("Look", 0.15, 1.0, randf_range(0.3, 2.0))
		"ground":
			if was == "flight":
				_landed = 0.0
