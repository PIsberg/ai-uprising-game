class_name ZipLine
# @lat: [[level-system#Ziplines]]
extends Node3D
## A two-way zipline between two decks: a pylon at each end (`a`, `b`, world
## points on the decks) and a cable between their heads. Step into either
## station and the player's tether latches on and winches them along it to
## the other end (Player.zipline_to, the convoy's scripted ride); jump lets
## go mid-ride. The far station ignores the player until they step off it, so
## arriving never sends them straight back. Robots do not ride.
## Def key `ziplines` (level_builder `_build_ziplines`). tests/zipline_probe.

@export var a: Vector3 = Vector3.ZERO
@export var b: Vector3 = Vector3(10, 0, 0)

const STATION_RADIUS := 1.0
const ANCHOR_UP := 1.0   ## the ride ends at the anchor, this far over the deck
const PYLON_H := 3.0
const PLAYER_LAYER := 2

var _armed := [true, true]
var _anchors: Array[Node3D] = []

func _ready() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.2, 0.2, 0.22)
	steel.metallic = 0.8
	steel.roughness = 0.35
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.9, 0.62, 0.08)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.3, 0.9, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.3, 0.9, 1.0)
	glow.emission_energy_multiplier = 2.5
	var ends := [a, b]
	for i in 2:
		var p: Vector3 = ends[i]
		var o: Vector3 = ends[1 - i]
		var flat := Vector3(o.x - p.x, 0.0, o.z - p.z).normalized()
		# Pylon: a post set back behind the station, a crossarm with a pulley.
		var base := p - flat * 0.9
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, PYLON_H, 0.22)
		post.mesh = bm
		post.material_override = paint
		post.position = base + Vector3.UP * PYLON_H * 0.5
		add_child(post)
		var wheel := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.14
		tm.outer_radius = 0.24
		wheel.mesh = tm
		wheel.material_override = steel
		wheel.position = base + Vector3.UP * PYLON_H + flat * 0.25
		wheel.rotation = Vector3(0, atan2(flat.x, flat.z), PI * 0.5)
		add_child(wheel)
		# Station ring on the deck.
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = STATION_RADIUS - 0.12
		rm.outer_radius = STATION_RADIUS
		ring.mesh = rm
		ring.material_override = glow
		ring.scale = Vector3(1, 0.3, 1)
		ring.position = p + Vector3.UP * 0.05
		add_child(ring)
		var zone := Area3D.new()
		zone.collision_layer = 0
		zone.collision_mask = PLAYER_LAYER
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = STATION_RADIUS
		cyl.height = 2.4
		cs.shape = cyl
		cs.position = Vector3.UP * 1.2
		zone.add_child(cs)
		zone.position = p
		add_child(zone)
		zone.body_entered.connect(_on_enter.bind(i))
		zone.body_exited.connect(_on_exit.bind(i))
		var anchor := Node3D.new()
		anchor.position = p + Vector3.UP * ANCHOR_UP
		add_child(anchor)
		_anchors.append(anchor)
	# The cable, pylon head to pylon head.
	var fa := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var ha := a - fa * 0.9 + Vector3.UP * PYLON_H + fa * 0.25
	var hb := b + fa * 0.9 + Vector3.UP * PYLON_H - fa * 0.25
	var cable := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = ha.distance_to(hb)
	cable.mesh = cm
	# A faint glow so the line reads against a night sky from across the arena.
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.55, 0.85, 0.95)
	wire.metallic = 0.6
	wire.emission_enabled = true
	wire.emission = Color(0.3, 0.9, 1.0)
	wire.emission_energy_multiplier = 1.2
	cable.material_override = wire
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cable)
	# CylinderMesh runs along its local y: point y down the cable.
	var y := (hb - ha).normalized()
	var x := y.cross(Vector3.UP)
	x = x.normalized() if x.length() > 0.01 else Vector3.RIGHT
	cable.transform = Transform3D(Basis(x, y, x.cross(y)), (ha + hb) * 0.5)

func _on_enter(body: Node, station: int) -> void:
	if not body.is_in_group("player") or not body.has_method("zipline_to"):
		return
	if not _armed[station]:
		return
	_armed[1 - station] = false # arriving there must not send them back
	body.call_deferred("zipline_to", _anchors[1 - station])

func _on_exit(body: Node, station: int) -> void:
	if body.is_in_group("player"):
		_armed[station] = true
