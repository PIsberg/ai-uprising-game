class_name ConvoyRide
extends Node3D
## The HIGHWAY BREAKOUT ride: a commandeered flatbed hauler that drives itself
## down the highway while the player fights off pursuit from its deck. The
## truck is an AnimatableBody3D (sync_to_physics) so the player rides it like
## a moving platform; waves of flyers and runners spawn around it as it rolls.

@export var speed: float = 5.5           ## cruise speed, m/s (toward -Z)
@export var start_z: float = 170.0
@export var end_z: float = -170.0
@export var wave_interval: float = 11.0

## Ranged-leaning on purpose: the deck used to fill up with melee flyers
## perma-hugging the player (a mosh pit, not a chase). Raptor (flying gunner) and
## the ground Gunner (ranged trooper — it needs LOS, not a boarding path) now carry
## most waves; seeker/dog (the true melee/kamikaze pressure) are the exception,
## not the norm. Breaker (melee flyer) keeps its 2 slots — it now peels off
## between hits instead of camping in your face (see EnemyDrone.standoff).
const WAVES: Array = [
	["drone", "drone", "raptor"],
	["raptor", "drone", "gunner"],
	["dog", "gunner", "raptor", "seeker"],
	["raptor", "raptor", "breaker"],
	["gunner", "drone", "raptor", "mender"],
	["seeker", "raptor", "raptor", "brute"],
	["mech", "drone", "raptor", "seeker"],
	["brute", "breaker", "raptor", "drone"],
]
const SCENES := {
	"drone": preload("res://scenes/enemies/drone.tscn"),
	"raptor": preload("res://scenes/enemies/raptor.tscn"),
	"dog": preload("res://scenes/enemies/dog.tscn"),
	"seeker": preload("res://scenes/enemies/seeker.tscn"),
	"breaker": preload("res://scenes/enemies/breaker.tscn"),
	"mender": preload("res://scenes/enemies/mender.tscn"),
	"brute": preload("res://scenes/enemies/brute.tscn"),
	"mech": preload("res://scenes/enemies/mech.tscn"),
	"gunner": preload("res://scenes/enemies/gunner.tscn"),
	"android": preload("res://scenes/enemies/android.tscn"),
	"gunslinger": preload("res://scenes/enemies/gunslinger.tscn"),
}

# --- Set pieces: pursuit gun-trucks, chase swarms, zipline demo platforms ---
## Flyer pack that hounds the truck as it nears each demo platform. Shooting it
## down gun-by-gun is possible but slow — the intended play is to ride the rear
## zip pad to the platform, bait the swarm in (they chase YOU), blow the bomb,
## and zip back aboard.
const SWARM := ["drone", "drone", "drone", "seeker", "seeker", "raptor", "drone", "seeker", "raptor", "drone"]
const PLATFORM_ZS := [66.0, -78.0] ## clear of streetlight posts (z≡-200+28k) and gantries
const SWARM_LEAD := 45.0   ## swarm appears this far before the truck passes its platform
const ZIP_RANGE := 50.0    ## rear pad arms while a live platform is this close
const BOMB_RADIUS := 30.0
const BOMB_DAMAGE := 520.0
## Rider crews for the drive-by gun-trucks (ranged robots that hold the bed).
const PURSUIT_RIDERS := [["gunner", "android"], ["gunslinger", "gunner"], ["android", "gunner", "android"]]

var _truck: AnimatableBody3D
var _t: float = 0.0
var _wave_t: float = 6.0 # first wave shortly after rollout
var _wave_i: int = 0
var _arrived: bool = false
var _truck_anchor: Node3D          ## return-trip zipline target, rides the tail deck
var _platforms: Array[Dictionary] = []
var _pad_cd: float = 0.0           ## shared zip-pad debounce
var _vehicles: Array[Dictionary] = []
var _vehicle_timer: float = 14.0
var _vehicle_i: int = 0

func _ready() -> void:
	_build_truck()
	_build_highway_scenery()
	_build_bomb_platforms()
	_board_player.call_deferred()

func _build_truck() -> void:
	_truck = AnimatableBody3D.new()
	_truck.sync_to_physics = true
	_truck.collision_layer = 1
	_truck.collision_mask = 0
	add_child(_truck)
	_truck.global_position = Vector3(0, 0, start_z)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.30, 0.33, 0.38)
	metal.metallic = 0.7
	metal.roughness = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.15, 0.17)
	dark.metallic = 0.5
	dark.roughness = 0.6
	var mk := func(center: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		mi.position = center
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = center
		_truck.add_child(mi)
		_truck.add_child(cs)
	# Flatbed deck + low rail ring (keeps the player aboard) + cab up front.
	mk.call(Vector3(0, 1.0, 0), Vector3(5.6, 0.5, 11.0), metal)          # deck
	mk.call(Vector3(0, 1.75, -6.0), Vector3(5.6, 1.0, 1.0), dark)        # front rail/cab back
	mk.call(Vector3(0, 1.6, 5.75), Vector3(5.6, 0.7, 0.5), dark)         # tail rail
	mk.call(Vector3(-3.0, 1.6, 0), Vector3(0.4, 0.7, 12.0), dark)        # left rail
	mk.call(Vector3(3.0, 1.6, 0), Vector3(0.4, 0.7, 12.0), dark)         # right rail
	mk.call(Vector3(0, 2.6, -7.6), Vector3(5.0, 2.6, 2.4), metal)        # cab block
	
	# Cargo cover boxes on the flatbed for cover:
	mk.call(Vector3(-1.7, 1.8, -1.8), Vector3(1.3, 1.1, 1.3), dark)      # front-left cover
	mk.call(Vector3(1.7, 1.9, 2.2), Vector3(1.4, 1.3, 1.4), metal)       # back-right cover
	mk.call(Vector3(0, 1.75, 4.2), Vector3(1.1, 1.0, 1.1), dark)         # back-center cover
	# Roofed nook over the front-left quadrant: EVERY pursuer on this ride is
	# an elevated flyer shooting DOWN, so the low cargo boxes never actually
	# break their line of sight — deck fighters died to open-sky attrition in
	# every playtest. One canopy gives the deck a legitimate LOS shelter
	# (enemy _can_see raycasts hit it); flyers have to dive or flank to get an
	# angle in, which is exactly the duck-out-and-shoot rhythm the ride wants.
	# Underside at 3.38 leaves 2.1 m of headroom over the 1.25 deck.
	mk.call(Vector3(-1.55, 3.45, -2.6), Vector3(2.9, 0.14, 3.6), dark)   # canopy roof
	mk.call(Vector3(-0.25, 2.7, -4.3), Vector3(0.16, 1.4, 0.16), dark)   # front post
	mk.call(Vector3(-0.25, 2.7, -0.9), Vector3(0.16, 1.4, 0.16), dark)   # rear post

	# Zipline rig: the return-trip anchor floats above the tail so an incoming
	# zip drops the player onto the deck, and the rear pad launches outbound
	# rides to the nearest demo platform.
	_truck_anchor = Node3D.new()
	_truck_anchor.name = "ZipAnchor"
	_truck.add_child(_truck_anchor)
	_truck_anchor.position = Vector3(0, 3.2, 2.6) # inboard of the tail so the drop lands mid-deck
	var tpad := _make_pad(_truck, Vector3(0, 1.85, 5.0), Color(0.35, 0.9, 1.0))
	tpad.body_entered.connect(_on_truck_pad)

	# Wheels: six dark cylinders (visual only).
	for wz in [-4.5, 0.0, 4.5]:
		for sx in [-2.6, 2.6]:
			var wheel := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.75
			cm.bottom_radius = 0.75
			cm.height = 0.5
			cm.material = dark
			wheel.mesh = cm
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(sx, 0.75, wz)
			_truck.add_child(wheel)
	# Headlights + a warm cab light so the rig reads alive at night.
	for sx in [-1.8, 1.8]:
		var hl := SpotLight3D.new()
		hl.light_color = Color(1.0, 0.95, 0.8)
		hl.light_energy = 3.0
		hl.spot_range = 30.0
		hl.spot_angle = 30.0
		hl.position = Vector3(sx, 1.6, -8.8)
		hl.rotation.x = -0.08
		hl.rotation.y = PI
		_truck.add_child(hl)

func _build_highway_scenery() -> void:
	var light_color := Color(1.0, 0.62, 0.22) # Amber sodium highway glow
	var metal_color := Color(0.22, 0.24, 0.28)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = metal_color
	post_mat.metallic = 0.8
	post_mat.roughness = 0.35
	
	var barrier_mat := StandardMaterial3D.new()
	barrier_mat.albedo_color = Color(0.3, 0.3, 0.3)
	barrier_mat.roughness = 0.9
	
	# Shared emissive lamp-head material — the glowing fixture is what makes a
	# streetlight read as lit at night (the OmniLight itself is invisible).
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = light_color
	lamp_mat.emission_enabled = true
	lamp_mat.emission = light_color
	lamp_mat.emission_energy_multiplier = 3.5
	
	for z in range(int(end_z) - 30, int(start_z) + 30, 28):
		for side in [-10.5, 10.5]:
			# Streetlight Post
			var post := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.08
			pm.bottom_radius = 0.12
			pm.height = 7.5
			pm.material = post_mat
			post.mesh = pm
			post.position = Vector3(side, 3.75, z)
			add_child(post)
			
			# Streetlight Arm — reaches from the post toward the roadway.
			var toward_road := 1.0 if side < 0 else -1.0
			var arm := MeshInstance3D.new()
			var am := BoxMesh.new()
			am.size = Vector3(2.6, 0.16, 0.16)
			am.material = post_mat
			arm.mesh = am
			arm.position = Vector3(side + 1.3 * toward_road, 7.5, z)
			add_child(arm)
			
			# Streetlight Light Source — hangs off the arm tip, over the lanes.
			var light := OmniLight3D.new()
			light.light_color = light_color
			light.light_energy = 2.4
			light.omni_range = 16.0
			light.position = Vector3(side + 2.6 * toward_road, 7.2, z)
			add_child(light)
			
			# Lamp head at the arm tip, just above the light source.
			var lamp := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.55, 0.14, 0.32)
			lm.material = lamp_mat
			lamp.mesh = lm
			lamp.position = Vector3(side + 2.45 * toward_road, 7.42, z)
			add_child(lamp)
			
			# Concrete Jersey Barrier along sides
			var barrier := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.6, 0.9, 5.0)
			bm.material = barrier_mat
			barrier.mesh = bm
			barrier.position = Vector3(side * 0.88, 0.45, z + randf_range(-1.0, 1.0))
			barrier.rotation.y = randf_range(-0.06, 0.06)
			add_child(barrier)
			
	# Spawn a few overhead highway sign gantries for scale
	for gz in [120.0, 30.0, -60.0, -140.0]:
		# Left pillar
		var p1 := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.16
		pm.bottom_radius = 0.16
		pm.height = 9.5
		pm.material = post_mat
		p1.mesh = pm
		p1.position = Vector3(-11.0, 4.75, gz)
		add_child(p1)
		
		# Right pillar
		var p2 := MeshInstance3D.new()
		p2.mesh = pm
		p2.position = Vector3(11.0, 4.75, gz)
		add_child(p2)
		
		# Crossbeam
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(22.0, 0.4, 0.4)
		bm.material = post_mat
		beam.mesh = bm
		beam.position = Vector3(0, 9.5, gz)
		add_child(beam)
		
		# Sign board
		var board := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(7.0, 2.0, 0.15)
		var board_mat := StandardMaterial3D.new()
		board_mat.albedo_color = Color(0.08, 0.26, 0.14) # Highway Green
		board_mat.roughness = 0.75
		bmesh.material = board_mat
		board.mesh = bmesh
		board.position = Vector3(-2.2, 8.2, gz)
		add_child(board)

# --- shared builders ---

## Box mesh + matching collision shape under `parent`, at a local offset.
func _mk_box(parent: Node, center: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = center
	parent.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = center
	parent.add_child(cs)

## Glowing floor pad the player steps onto to trigger something (zip / detonate).
## Area only — the collision box is tall enough to catch the player capsule.
func _make_pad(parent: Node, pos: Vector3, color: Color) -> Area3D:
	var pad := Area3D.new()
	pad.collision_layer = 64
	pad.collision_mask = 2
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.5, 1.4, 1.5)
	cs.shape = bs
	pad.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 0.08, 1.5)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.2
	bm.material = m
	mi.mesh = bm
	mi.position = Vector3(0, -0.62, 0)
	pad.add_child(mi)
	parent.add_child(pad)
	pad.position = pos
	return pad

# --- demolition platforms (zipline destinations) ---

func _build_bomb_platforms() -> void:
	for z in PLATFORM_ZS:
		_build_bomb_platform(float(z))

## Elevated roadside demo rig: legs + deck + rails, a mega-bomb, a red
## detonator pad and a cyan return pad. The truck's rear pad zips you here.
func _build_bomb_platform(z: float) -> void:
	var root := StaticBody3D.new()
	root.collision_layer = 1
	root.collision_mask = 0
	add_child(root)
	root.global_position = Vector3(10.4, 0, z)
	var deck_y := 6.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.22, 0.27)
	mat.metallic = 0.75
	mat.roughness = 0.4
	for lx in [-2.4, 2.4]:
		for lz in [-2.4, 2.4]:
			_mk_box(root, Vector3(lx, deck_y * 0.5, lz), Vector3(0.35, deck_y, 0.35), mat)
	_mk_box(root, Vector3(0, deck_y + 0.15, 0), Vector3(6.0, 0.3, 6.0), mat)
	# Low guard rails (jumpable) so a slam or seeker pop doesn't dump you off.
	_mk_box(root, Vector3(0, deck_y + 0.55, -2.9), Vector3(6.0, 0.5, 0.2), mat)
	_mk_box(root, Vector3(0, deck_y + 0.55, 2.9), Vector3(6.0, 0.5, 0.2), mat)
	_mk_box(root, Vector3(-2.9, deck_y + 0.55, 0), Vector3(0.2, 0.5, 5.8), mat)
	_mk_box(root, Vector3(2.9, deck_y + 0.55, 0), Vector3(0.2, 0.5, 5.8), mat)
	# The mega-bomb: fat dark sphere with a hot warning band + pulsing light.
	var bomb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.12, 0.12, 0.14)
	bmat.metallic = 0.9
	bmat.roughness = 0.3
	sm.material = bmat
	bomb.mesh = sm
	bomb.position = Vector3(0.9, deck_y + 1.25, 1.6)
	root.add_child(bomb)
	var band := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.98
	tm.outer_radius = 1.12
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(1.0, 0.25, 0.1)
	wmat.emission_enabled = true
	wmat.emission = Color(1.0, 0.25, 0.1)
	wmat.emission_energy_multiplier = 3.0
	tm.material = wmat
	band.mesh = tm
	band.position = bomb.position
	root.add_child(band)
	var blight := OmniLight3D.new()
	blight.light_color = Color(1.0, 0.3, 0.12)
	blight.light_energy = 2.0
	blight.omni_range = 9.0
	blight.position = bomb.position + Vector3(0, 1.2, 0)
	root.add_child(blight)
	var p := {
		"z": z, "root": root, "bomb": bomb, "band": band, "light": blight,
		"anchor": null, "spent": false, "swarmed": false,
	}
	# Zip anchor floats over the road-side half of the deck. Arrival carry
	# drifts the player ~2 m along the cable direction (from the road, +x),
	# so the LANDING zone is deck centre — both pads sit in far corners well
	# clear of it, or a drop-in would trigger them instantly.
	var anchor := Node3D.new()
	anchor.name = "ZipAnchor"
	root.add_child(anchor)
	anchor.position = Vector3(-1.6, deck_y + 2.2, 0.4)
	p["anchor"] = anchor
	var det := _make_pad(root, Vector3(2.35, deck_y + 1.0, -2.35), Color(1.0, 0.25, 0.1))
	det.body_entered.connect(_on_detonator.bind(p))
	var ret := _make_pad(root, Vector3(-2.35, deck_y + 1.0, 2.35), Color(0.35, 0.9, 1.0))
	ret.body_entered.connect(_on_return_pad)
	_platforms.append(p)

# --- zip pads ---

func _nearest_live_platform() -> Dictionary:
	var best := {}
	var bd := ZIP_RANGE
	for p in _platforms:
		if p["spent"]:
			continue
		var d: float = absf(float(p["z"]) - _truck.global_position.z)
		if d <= bd:
			bd = d
			best = p
	return best

func _on_truck_pad(body: Node3D) -> void:
	if _pad_cd > 0.0 or not body.is_in_group("player"):
		return
	var p := _nearest_live_platform()
	if p.is_empty():
		_pad_cd = 2.0
		_toast("NO DEMO PLATFORM IN RANGE")
		return
	_pad_cd = 3.0
	if body.has_method("zipline_to"):
		body.call_deferred("zipline_to", p["anchor"])

func _on_return_pad(body: Node3D) -> void:
	if _pad_cd > 0.0 or not body.is_in_group("player"):
		return
	_pad_cd = 3.0
	if body.has_method("zipline_to"):
		body.call_deferred("zipline_to", _truck_anchor)

# --- the boom ---

func _on_detonator(body: Node3D, p: Dictionary) -> void:
	if p["spent"] or not body.is_in_group("player"):
		return
	p["spent"] = true
	_detonate(p)

func _detonate(p: Dictionary) -> void:
	# Short arming beep-flash so the boom reads as triggered, not random.
	var band: MeshInstance3D = p["band"]
	if is_instance_valid(band) and band.mesh and band.mesh.material:
		band.mesh.material.emission_energy_multiplier = 9.0
	AudioBus.play_synth_at("impact_metal", (p["bomb"] as Node3D).global_position, -2.0, 2.2)
	await get_tree().create_timer(0.55).timeout
	if not is_inside_tree() or not is_instance_valid(p["bomb"]):
		return
	var pos: Vector3 = (p["bomb"] as Node3D).global_position
	(p["bomb"] as Node3D).visible = false
	(p["band"] as Node3D).visible = false
	(p["light"] as Node3D).visible = false
	_explode_at(pos, BOMB_RADIUS, BOMB_DAMAGE)
	var hud := get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("_overlord_say"):
		hud._overlord_say("MY SWARM! You will regret every bolt of that scrap.")

## Big fireball (reuses the grenade explosion FX, scaled) + AOE damage to
## enemies only. Credited to the player so kills pay score and hit feedback.
func _explode_at(pos: Vector3, radius: float, damage: float) -> void:
	var fx := preload("res://scenes/fx/grenade_explosion.tscn").instantiate() as Node3D
	get_tree().current_scene.add_child(fx)
	fx.global_position = pos
	fx.scale = Vector3.ONE * clampf(radius / 8.0, 1.0, 4.0)
	ScorchDecal.spawn(get_tree().current_scene, pos, clampf(radius * 0.25, 2.0, 6.0))
	var player := get_tree().get_first_node_in_group("player")
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	q.shape = s
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = 0b100 # enemy layer only — tuned as a swarm-killer
	var hits := get_world_3d().direct_space_state.intersect_shape(q, 64)
	# Collect the victims (nearest first) instead of damaging them all in the same
	# frame. A mega-bomb into the swarm can kill ~18 robots at once, and every death
	# spawns its own explosion FX + positional death sound — 18 of those plus the
	# bomb's own fireball and a 64-body physics query in ONE frame spiked hard
	# enough to underrun the WASAPI audio device and drop ALL sound for the rest of
	# the run. Ripple the damage out over successive frames so the deaths (and their
	# FX/sounds) spread across ~0.2 s — visually still a single blast, but no frame
	# ever carries the whole flood at once.
	var victims: Array = []
	var seen := {}
	for h in hits:
		var c: Object = h.get("collider")
		if c == null or seen.has(c):
			continue
		seen[c] = true
		var n := c as Node3D
		if n == null:
			continue
		var d = n.get_node_or_null("Damageable")
		if d == null:
			continue
		var falloff := clampf(1.0 - pos.distance_to(n.global_position) / radius, 0.3, 1.0)
		victims.append({"d": d, "amt": damage * falloff, "dist": pos.distance_to(n.global_position)})
	victims.sort_custom(func(a, b): return a["dist"] < b["dist"]) # inner ring dies first — reads as an outward blast wave
	# Batch on a real-time cadence (not per-frame): at a low framerate a per-frame
	# stagger still bunches the whole flood into one long frame, which is exactly
	# the stall that drops the audio device. A short wall-clock gap between batches
	# keeps each frame's FX/sound spawn small regardless of framerate.
	const PER_BATCH := 3
	const BATCH_GAP := 0.05
	var i := 0
	while i < victims.size():
		for _j in range(PER_BATCH):
			if i >= victims.size():
				break
			var v = victims[i]
			i += 1
			if is_instance_valid(v["d"]):
				v["d"].apply_damage(v["amt"], player, false, pos)
		if i < victims.size():
			await get_tree().create_timer(BATCH_GAP).timeout
			if not is_inside_tree():
				return

func _toast(text: String) -> void:
	var pl := get_tree().get_first_node_in_group("player")
	if pl and pl.has_method("notify_pickup"):
		pl.notify_pickup(text)

# --- chase swarm ---

## Dense flyer pack spawned behind the truck. Flyers home on the player
## directly (no navmesh), so zipping to a platform drags them into the bomb.
## Each swarm remembers its platform (meta "convoy_swarm") so leftovers can
## disperse once that bomb window closes — see _disperse_swarms.
##
## The pack arrives in TWO pulses (front half at SWARM_LEAD, back half 12 s
## later) instead of ten at once: the single drop stacked with waves and
## gun-truck crews into a spike that killed every deck-fighting playtest run
## right in this window. Blowing the demo charge before the second pulse
## CANCELS it — the intended zip-and-bomb play now removes the whole swarm,
## and standing your ground meets five at a time instead of ten.
const SWARM_PULSE := 5
const SWARM_PULSE_GAP := 12.0

func _spawn_swarm(platform_z: float, pack: Array) -> void:
	var tz: float = _truck.global_position.z
	for i in pack.size():
		var scene: PackedScene = SCENES.get(pack[i])
		if scene == null:
			continue
		var e := scene.instantiate() as Node3D
		e.position = Vector3(randf_range(-8.0, 8.0), randf_range(2.0, 5.0), tz + randf_range(14.0, 30.0))
		e.set_meta("convoy_swarm", platform_z)
		get_tree().current_scene.add_child(e)

## Deck resupply riding the flatbed: a medkit + ammo box drop in with each
## swarm. Playtest bot runs died at min_hp<10 fighting deck-only — the swarm
## is DESIGNED to be baited into the platform bomb, but standing your ground
## must stay viable, and a 60 s firefight needs somewhere to breathe. Parented
## to the truck so they ride with the player; spots picked clear of the cargo
## cover boxes and the rear zip pad.
const RESUPPLY_SPOTS := [Vector3(-1.8, 1.7, 3.8), Vector3(1.0, 1.7, -3.8)]

func _drop_resupply() -> void:
	var kinds := ["health", "ammo"]
	for i in kinds.size():
		var scene: PackedScene = load("res://scenes/pickups/%s.tscn" % ("health_pack" if kinds[i] == "health" else "ammo_box"))
		if scene == null:
			continue
		var pk := scene.instantiate() as Node3D
		_truck.add_child(pk)
		pk.position = RESUPPLY_SPOTS[i]

## The swarm's job is to be lured into the demo charge. Once its platform is
## behind the truck (or already blown), any leftovers would otherwise chase
## the deck FOREVER — playtest: 20 simultaneous pursuers by the second swarm,
## deck-only runs died to the pile-up, not to any one fight. Let the pack lose
## interest instead: while more than 3 of a closed swarm remain, peel off the
## flyer FURTHEST from the player every couple of seconds (reads as the swarm
## breaking off into the night, and the survivors stay dangerous).
var _disperse_t: float = 0.0

func _disperse_swarms(delta: float) -> void:
	_disperse_t -= delta
	if _disperse_t > 0.0:
		return
	_disperse_t = 2.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	for p in _platforms:
		if not p["swarmed"]:
			continue
		var closed: bool = p["spent"] or _truck.global_position.z < float(p["z"]) - 12.0
		if not closed:
			continue
		var pack: Array[Node3D] = []
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is Node3D and (e as Node).get_meta("convoy_swarm", 1e9) == float(p["z"]):
				if e is EnemyBase and (e as EnemyBase).state == EnemyBase.State.DEAD:
					continue
				pack.append(e)
		if pack.size() <= 3:
			continue
		var furthest: Node3D = null
		var fd := -1.0
		for e in pack:
			var d := player.global_position.distance_to(e.global_position)
			if d > fd:
				fd = d
				furthest = e
		if furthest:
			furthest.queue_free()

# --- pursuit gun-trucks ---

## Enemy flatbed that overtakes from behind, pulls alongside in the next lane
## with a ranged crew firing from its bed, and floors it away if ignored.
## Wipe the crew and the driverless rig blows up on the spot.
func _spawn_pursuit_vehicle() -> void:
	var side := -6.6 if _vehicle_i % 2 == 0 else 6.6
	var crew: Array = PURSUIT_RIDERS[_vehicle_i % PURSUIT_RIDERS.size()]
	_vehicle_i += 1
	var v := AnimatableBody3D.new()
	v.sync_to_physics = true
	v.collision_layer = 1
	v.collision_mask = 0
	add_child(v)
	v.global_position = Vector3(side, 0, _truck.global_position.z + 42.0)
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.24, 0.1, 0.1)
	hull.metallic = 0.7
	hull.roughness = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	dark.roughness = 0.6
	_mk_box(v, Vector3(0, 0.85, 0), Vector3(3.4, 0.4, 6.5), hull)   # bed
	_mk_box(v, Vector3(0, 1.5, -2.7), Vector3(3.0, 1.0, 1.4), dark) # cab
	for wz in [-2.2, 2.2]:
		for sx in [-1.6, 1.6]:
			var wheel := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.55
			cm.bottom_radius = 0.55
			cm.height = 0.4
			cm.material = dark
			wheel.mesh = cm
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(sx, 0.55, wz)
			v.add_child(wheel)
	# Hostile red running light so it reads as machine-driven at a glance.
	var rl := OmniLight3D.new()
	rl.light_color = Color(1.0, 0.2, 0.1)
	rl.light_energy = 1.6
	rl.omni_range = 7.0
	rl.position = Vector3(0, 2.0, -2.7)
	v.add_child(rl)
	var riders: Array = []
	for j in crew.size():
		var scene: PackedScene = SCENES.get(crew[j])
		if scene == null:
			continue
		var e := scene.instantiate() as Node3D
		e.position = v.global_position + Vector3(randf_range(-0.7, 0.7), 1.5, -1.6 + j * 1.7)
		get_tree().current_scene.add_child(e)
		riders.append(e)
	_vehicles.append({"body": v, "riders": riders, "age": 0.0, "done": false})
	_toast("PURSUIT GUN-TRUCK INBOUND — TAKE OUT THE CREW")

func _update_vehicles(delta: float) -> void:
	for v in _vehicles:
		if v["done"]:
			continue
		var body: AnimatableBody3D = v["body"]
		if not is_instance_valid(body):
			v["done"] = true
			continue
		v["age"] = float(v["age"]) + delta
		var alive := 0
		for r in v["riders"]:
			if is_instance_valid(r):
				var hp = r.get("hp")
				if hp and hp.is_alive():
					alive += 1
		if alive == 0:
			# Crew wiped: the driverless rig cooks off in a fireball, and its
			# supplies land on the deck. Playtest runs that handled every wave
			# still bled out at ~60 s on two medkits — clearing a gun-truck is
			# the ride's most deliberate play, so it pays out the third.
			v["done"] = true
			_explode_at(body.global_position + Vector3(0, 1.0, 0), 7.0, 140.0)
			body.queue_free()
			_drop_resupply()
			_toast("WRECK SALVAGE — SUPPLIES ON THE DECK")
			continue
		var dz: float = body.global_position.z - _truck.global_position.z
		var spd: float = speed
		if float(v["age"]) > 26.0:
			spd = speed + 6.5 # disengage: floor it up the road and vanish
			if dz < -70.0:
				v["done"] = true
				for r in v["riders"]:
					if is_instance_valid(r):
						(r as Node).queue_free()
				body.queue_free()
				continue
		elif dz > 1.5:
			spd = speed + 3.2 # closing from behind
		body.global_position.z -= spd * delta

## Ground chasers with no path onto the moving flatbed (dog, gunner, mender,
## and any gun-truck crew whose ride already died) just fall further and further
## behind the truck instead of ever catching up — left to accumulate they'd
## litter the highway with pursuit that can no longer matter. Boarders ride the
## truck's own frame (they stay within a few metres of it) and flyers are fast
## enough to keep pace, so this only ever catches units that are truly stragglers.
const STRAGGLER_DIST := 60.0
var _straggler_t: float = 3.0

func _cull_stragglers(delta: float) -> void:
	_straggler_t -= delta
	if _straggler_t > 0.0:
		return
	_straggler_t = 2.0
	var tz: float = _truck.global_position.z
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if e is EnemyBase and (e as EnemyBase).state == EnemyBase.State.DEAD:
			continue # already dying its own death (fall/topple/explosion) — let it finish
		if (e as Node3D).global_position.z - tz > STRAGGLER_DIST:
			e.queue_free()

func _board_player() -> void:
	await get_tree().create_timer(0.6).timeout
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		p.global_position = _truck.global_position + Vector3(0, 1.8, 1.0)
		var dmg := p.get_node_or_null("Damageable")
		if dmg and dmg.has_signal("died"):
			dmg.died.connect(_on_player_died)
	# Opening beats: the ride explains itself before the first wave lands —
	# the persistent objective line alone is easy to miss while being dropped
	# onto a truck that's already rolling.
	_toast("PURSUIT INBOUND — HOLD THE DECK TO THE INTERCHANGE")
	get_tree().create_timer(7.5).timeout.connect(func():
		if not _arrived:
			_toast("REAR ZIP PAD FIRES WHEN A DEMO PLATFORM IS IN RANGE"))

## A checkpoint respawn drops the player back onto a deck the pursuit never
## left — world state is deliberately NOT reset (see GameState), so a mid-ride
## death put you back at partial HP inside 13+ live pursuers and playtests
## death-spiralled (three more deaths inside ten seconds). The pack losing the
## trail while the screen is dark is the fair version: on death, thin pursuit
## down to the four nearest so the comeback is a fight, not a grinder.
func _on_player_died(_source: Node) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var live: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as EnemyBase).state != EnemyBase.State.DEAD:
			live.append(e)
	live.sort_custom(func(a, b) -> bool:
		return player.global_position.distance_to((a as Node3D).global_position) \
			< player.global_position.distance_to((b as Node3D).global_position))
	for i in range(4, live.size()):
		(live[i] as Node).queue_free()
	GameState.start_attack_grace(2.5) # same opening-seconds fairness as a fresh level

func _physics_process(delta: float) -> void:
	_pad_cd = maxf(0.0, _pad_cd - delta) # pads stay usable even at the terminus
	if _arrived:
		_wind_down_pursuit(delta)
		_update_checkpoint() # deaths at the terminus still respawn on the deck
		return
	_t += delta
	# Ease off the line, cruise, ease into the terminus.
	var z: float = _truck.global_position.z
	var spd := speed
	if _t < 3.0:
		spd = speed * (_t / 3.0)
	elif z < end_z + 20.0:
		spd = maxf(1.2, speed * (z - end_z) / 20.0)
	_truck.global_position.z = maxf(end_z, z - spd * delta)
	if _truck.global_position.z <= end_z + 0.05:
		_arrived = true
		_toast("INTERCHANGE REACHED — PURSUIT BREAKING OFF")
		# The portal sits off the roadside (visible from the deck, but a first-
		# timer's instinct is to walk out over the cab): say the quiet part.
		get_tree().create_timer(3.0).timeout.connect(func():
			_toast("HOP THE RAIL — EXTRACTION PORTAL AT THE ROADSIDE"))
		return
	# Pursuit waves, spawned around the rolling truck — but never into an
	# already-packed sky. Waves land every 11 s no matter what, so a swarm
	# (10 flyers, its own set-piece) stacking with two waves and a gun-truck
	# crew peaked playtests at 20 live pursuers; a competent deck fighter died
	# seconds short of the terminus every run. Holding the NEXT wave while
	# live pursuit is high keeps the pace for players who clear fast and
	# relieves exactly the pile-up that killed the ones who don't.
	_wave_t -= delta
	if _wave_t <= 0.0:
		if _live_pursuit() >= WAVE_HOLD_AT:
			_wave_t = 3.0 # re-check shortly; the wave arrives once the sky thins
		else:
			_wave_t = wave_interval
			_spawn_wave()
	# Chase swarms: unleashed as the truck runs up on each demo platform, so
	# the bomb is in reach right when the sky fills with pursuit.
	for p in _platforms:
		if not p["swarmed"] and _truck.global_position.z < float(p["z"]) + SWARM_LEAD:
			p["swarmed"] = true
			p["pulse2"] = SWARM_PULSE_GAP
			_spawn_swarm(float(p["z"]), SWARM.slice(0, SWARM_PULSE))
			_drop_resupply()
			_toast("SWARM INBOUND — REAR ZIP PAD ARMED, RIDE IT TO THE DEMO CHARGE")
		elif p.has("pulse2"):
			p["pulse2"] = float(p["pulse2"]) - delta
			if float(p["pulse2"]) <= 0.0:
				p.erase("pulse2")
				# The demo charge already went off? The rest of the swarm never
				# launches — bombing the pack is meant to END this set piece.
				if not p["spent"]:
					_spawn_swarm(float(p["z"]), SWARM.slice(SWARM_PULSE))
					_toast("SWARM REINFORCEMENTS INBOUND")
	# Drive-by gun-trucks (three per run, alternating lanes).
	_vehicle_timer -= delta
	if _vehicle_timer <= 0.0 and _vehicle_i < 3:
		_vehicle_timer = 20.0
		_spawn_pursuit_vehicle()
	_update_vehicles(delta)
	_cull_stragglers(delta)
	_disperse_swarms(delta)
	_update_checkpoint()

## Terminus wind-down: the ride ends but its leftovers used to keep coming —
## fifteen pursuers camped the parked deck and a respawn's 1.5 s grace fed the
## player straight back into the pile (playtest died 3× AT the interchange
## after surviving the whole ride). "Survive to the interchange" means arrival
## is the resolution: the pack breaks off, furthest flyer first, one every
## 0.4 s — close threats stay dangerous for a beat, then the sky clears.
var _wind_t: float = 0.0

func _wind_down_pursuit(delta: float) -> void:
	_wind_t -= delta
	if _wind_t > 0.0:
		return
	_wind_t = 0.4
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var furthest: Node3D = null
	var fd := -1.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is EnemyBase):
			continue
		if (e as EnemyBase).state == EnemyBase.State.DEAD:
			continue
		var d := player.global_position.distance_to((e as Node3D).global_position)
		if d > fd:
			fd = d
			furthest = e
	if furthest:
		furthest.queue_free()

## Mid-ride checkpoints. The convoy's only task is "survive", which completes
## at the very END — so the generic task-completion checkpoint never fires
## mid-ride and every death replayed the whole set piece. Snapshot once the
## ride is rolling and again as each platform set-piece closes. The generic
## snapshot pins an ABSOLUTE position, which on this level is an empty stretch
## of highway by the time a death respawns — keep it pinned to the deck so a
## respawn always lands back aboard the rolling truck.
var _cp_started: bool = false

func _update_checkpoint() -> void:
	if not _cp_started and _t > 4.0:
		_cp_started = true
		GameState.set_checkpoint()
	for p in _platforms:
		if p["swarmed"] and not p.has("cp_done") \
			and (p["spent"] or _truck.global_position.z < float(p["z"]) - 12.0):
			p["cp_done"] = true
			GameState.set_checkpoint()
	if GameState.has_checkpoint():
		GameState.checkpoint["position"] = _truck.global_position + Vector3(0, 2.0, 0.5)

## Live-pursuit ceiling: at or above this, the next wave holds (see the
## note in _physics_process). Tuned against the playtest bot — 8 keeps two
## waves' worth of pressure in the air without the swarm-stack death spiral.
const WAVE_HOLD_AT := 8

func _live_pursuit() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as EnemyBase).hp and (e as EnemyBase).hp.is_alive():
			n += 1
	return n

## Heavies too slow to chase a 5.5 m/s truck from the roadside — they drop
## straight onto the deck as boarders instead, forcing close-quarters fights
## around the cargo cover boxes.
const BOARDERS := ["brute", "mech"]

func _spawn_wave() -> void:
	var wave: Array = WAVES[_wave_i % WAVES.size()]
	_wave_i += 1
	var tz: float = _truck.global_position.z
	for i in wave.size():
		var scene: PackedScene = SCENES.get(wave[i])
		if scene == null:
			continue
		var e := scene.instantiate() as Node3D
		if wave[i] in BOARDERS:
			# Deck boarding drop: released above the front half of the bed so
			# the truck's forward travel during the fall lands them mid-deck.
			# Kept to the RIGHT side (x > 0): the canopy roofs the front-left
			# quadrant, and a melee boarder released over it lands ON the roof
			# where it can never reach anyone (convoy_probe caught a brute
			# standing at rel y=3.5 — canopy-top height).
			e.position = _truck.global_position \
				+ Vector3(randf_range(0.3, 1.8), 3.0, randf_range(-4.4, -1.4))
		else:
			var side := -1.0 if i % 2 == 0 else 1.0
			# Flank spawns slightly behind the truck so pursuit reads as a chase.
			e.position = Vector3(side * randf_range(9.0, 14.0), 0.6, tz + randf_range(4.0, 16.0))
		# The breaker is the one true melee FLYER on this ride — it can actually
		# reach the deck and hover there. Force standoff so it harries (dive in,
		# hammer, peel off) instead of parking on top of the player forever.
		if wave[i] == "breaker" and "standoff" in e:
			e.standoff = true
		get_tree().current_scene.add_child(e)
