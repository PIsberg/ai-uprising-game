# @lat: [[weapons#Salvage]]
class_name Salvage
extends RefCounted
## SALVAGE guns: a heavy robot in TABLE drops its own arm weapon when it dies.
## Walking over the drop arms it at once for ONE magazine (WeaponManager
## .take_salvage: no reserve, no reload, ammo pickups skip it), then the empty gun
## is tossed out of the rack and your own gun comes back. It never joins the
## campaign arsenal (WEAPON_ORDER) and never carries into the next level.
##
## The drop rides on Damageable.died (EnemyBase._ready connects drop_from), so
## subclasses that override _on_died without super still drop. A robot that dies
## while hijacked fought for you; it drops too. Covered by tests/salvage_probe.
##
## Pickup is duck-typed here (SALVAGE_KIND, set()), never named: EnemyBase loads
## this class, and naming Pickup from robot code closes the same load cycle
## WeaponMods documents (pickup.gd fails with "Busy").

const LIFETIME := 25.0 ## seconds an untaken drop waits before it powers down
const BLINK_AT := 5.0  ## the drop blinks for its last seconds
const PICKUP := "res://scenes/pickups/weapon_pickup.tscn"
const SALVAGE_KIND := 6 ## Pickup.Kind.SALVAGE (salvage_probe pins the two together)

## codex_key -> the gun its chassis carries. `color` tints the drop's glow.
const TABLE := {
	"gunner": {"scene": "res://scenes/weapons/salvage_chaingun.tscn", "color": Color(1.0, 0.45, 0.25)},
	"mech": {"scene": "res://scenes/weapons/salvage_palm.tscn", "color": Color(0.55, 0.85, 1.0)},
}

## Damageable.died handler on every robot: drop its gun if it carries one.
static func drop_from(robot: Node) -> void:
	if not is_instance_valid(robot) or not robot.has_method("codex_key"):
		return
	var key: String = robot.codex_key()
	if not TABLE.has(key):
		return
	var at := (robot as Node3D).global_position
	var parent := robot.get_parent()
	if parent == null:
		return
	# Deferred: died fires inside apply_damage, mid physics query.
	(func() -> void:
		if is_instance_valid(parent):
			drop_at(parent, at, key)).call_deferred()

## Spawn `key`'s salvage pickup at `pos` under `parent`. Returns the pickup.
static func drop_at(parent: Node, pos: Vector3, key: String) -> Area3D:
	if not TABLE.has(key) or not is_instance_valid(parent):
		return null
	var p := (load(PICKUP) as PackedScene).instantiate() as Area3D
	p.set("kind", SALVAGE_KIND)
	p.set("weapon_scene", load(String(TABLE[key]["scene"])))
	parent.add_child(p)
	p.global_position = pos + Vector3.UP * 0.2
	var light := p.get_node_or_null("Light") as OmniLight3D
	if light:
		light.light_color = TABLE[key]["color"]
	var tree := p.get_tree()
	tree.create_timer(LIFETIME - BLINK_AT, false).timeout.connect(func() -> void:
		if is_instance_valid(p) and not p.get("_taken"):
			var tw := p.create_tween().set_loops(int(BLINK_AT / 0.25))
			tw.tween_callback(p.hide).set_delay(0.125)
			tw.tween_callback(p.show).set_delay(0.125))
	tree.create_timer(LIFETIME, false).timeout.connect(func() -> void:
		if is_instance_valid(p) and not p.get("_taken"):
			p.queue_free())
	return p
