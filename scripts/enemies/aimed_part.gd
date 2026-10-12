class_name AimedPart
extends RefCounted
## A rigid part of a static robot model (PartRig entries) that swings about a
## pivot to point its tip at a target: the ENFORCER's rifle, the GUNSLINGER's
## gun-arm. Engaged it eases onto the aim at `rate` (1/s); disengaged it eases
## back to its rest pose out of the last aim. All in the robot's body frame.

var entries: Array = []        ## PartRig entries that move together
var pivot := Vector3.ZERO      ## body frame, at rest
var tip := Vector3.ZERO        ## body frame, at rest
var rate := 5.0
var _w := 0.0
var _q := Quaternion.IDENTITY  ## rest pointing -> the last aim

func _init(parts: Array, pivot_at: Vector3, tip_at: Vector3, ease_rate: float = 5.0) -> void:
	entries = parts
	pivot = pivot_at
	tip = tip_at
	rate = ease_rate

## Advance one tick toward `aim_at` (world point, or null to keep the last
## aim) and pose the parts. Returns the tip's world position.
func tick(body: Node3D, aim_at: Variant, engaged: bool, delta: float) -> Vector3:
	_w = move_toward(_w, 1.0 if engaged else 0.0, rate * delta)
	if aim_at is Vector3:
		var aim: Vector3 = body.global_transform.basis.inverse() * ((aim_at as Vector3) - body.global_transform * pivot)
		if aim.length() > 0.01:
			_q = Quaternion((tip - pivot).normalized(), aim.normalized())
	var r := Basis(Quaternion.IDENTITY.slerp(_q, smoothstep(0.0, 1.0, _w)))
	var lay := Transform3D(r, pivot - r * pivot)
	for e in entries:
		PartRig.pose(e, lay)
	return body.global_transform * (pivot + r * (tip - pivot))

## Points within `band` m of the extreme of `pts` along `axis` (the top band
## of a hanging forearm, the far end of a barrel), averaged.
static func band_mean(pts: PackedVector3Array, axis: Vector3, band: float) -> Vector3:
	var hi := -INF
	for q in pts:
		hi = maxf(hi, q.dot(axis))
	var sel := PackedVector3Array()
	for q in pts:
		if q.dot(axis) > hi - band:
			sel.append(q)
	return PartRig.mean(sel)

## The vertices of `pts` farthest from `from` (within `band` m), averaged.
static func far_mean(pts: PackedVector3Array, from: Vector3, band: float) -> Vector3:
	var far := 0.0
	for q in pts:
		far = maxf(far, q.distance_to(from))
	var sel := PackedVector3Array()
	for q in pts:
		if q.distance_to(from) > far - band:
			sel.append(q)
	return PartRig.mean(sel)
