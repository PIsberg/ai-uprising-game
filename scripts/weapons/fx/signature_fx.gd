class_name SignatureFx
extends RefCounted
## A gun's signature: the firing effects that belong to this one weapon and no
## other, drawn on top of the shared flash, tracer and impact every gun gets.
## `WeaponData.signature_fx` names a script extending this one; `Weapon` builds
## one instance per gun (`make`) and calls the hooks below from its firing path.
## Every hook here is a no-op, so a gun with no signature fires exactly as it did.
##
## The weapon is duck-typed (a `Node3D`, not `Weapon`) so this script and
## weapon.gd never name each other's class: that pairing closed a load cycle on
## the enemies and nilled the autoload graph.

## The gun this signature belongs to (set by `make`).
var weapon: Node3D = null

## Build the signature named by the gun's data, or a silent default.
static func make(w: Node3D) -> SignatureFx:
	var sig: SignatureFx = null
	var data: WeaponData = w.get("data") if w else null
	if data and data.signature_fx:
		var inst = data.signature_fx.new()
		if inst is SignatureFx:
			sig = inst
	if sig == null:
		sig = SignatureFx.new()
	sig.weapon = w
	return sig

## The scene the FX live in (null headless before a scene is current).
func scene() -> Node:
	return weapon.get_tree().current_scene if is_instance_valid(weapon) and weapon.is_inside_tree() else null

## Overrides for the shared tracer's bolt fields (`bolt_speed`, `bolt_length`,
## `bolt_width`): how this gun's round reads in flight. Empty keeps the stock bolt.
func tracer_style() -> Dictionary:
	return {}

## True when the signature draws its own muzzle smoke, so the shared puff is skipped.
func owns_muzzle_smoke() -> bool:
	return false

## True when the signature throws its own spent case (a shotgun's hull on the pump
## beat), so the shared brass case on the shot is skipped.
func owns_brass() -> bool:
	return false

## Every shot, after the shared muzzle FX (flash, sparks, brass) have spawned.
func on_fire() -> void:
	pass

## A hitscan round stopped on world geometry at `pos` (surface normal `normal`,
## flying along `dir`, surface one of Weapon._surface_of's kinds).
func on_world_hit(_pos: Vector3, _normal: Vector3, _dir: Vector3, _surface: String) -> void:
	pass

## A hitscan round struck a robot (or destructible) at `pos` (surface normal
## `normal`, flying along `dir`) for `dmg`.
func on_enemy_hit(_pos: Vector3, _normal: Vector3, _dir: Vector3, _dmg: float, _crit: bool) -> void:
	pass

## Every frame, after the gun's own `_process` work (barrel heat, readouts).
func on_process(_delta: float) -> void:
	pass

## A projectile round was launched (after `launch`), so the signature can dress it.
func on_projectile(_proj: Node3D) -> void:
	pass
