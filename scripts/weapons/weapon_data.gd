class_name WeaponData
extends Resource

enum FireMode { SEMI, AUTO, BURST, BEAM } ## BEAM: continuous ray while held — damage ticks at fire_rate, 1 ammo per tick.
enum DamageType { HITSCAN, PROJECTILE }
## Secondary fire (V / mouse thumb). CHARGE: hold to charge a boosted accurate
## shot (3 ammo). VOLLEY: instant tight 3-round burst (3 ammo). SLUG: collapse
## all pellets into one accurate heavy slug (shotguns).
enum AltMode { NONE, CHARGE, VOLLEY, SLUG }

@export var display_name: String = "Weapon"
@export var fire_mode: FireMode = FireMode.SEMI
@export var damage_type: DamageType = DamageType.HITSCAN
@export var alt_mode: AltMode = AltMode.NONE

@export_group("Damage / Fire")
@export var damage: float = 20.0
@export var fire_rate: float = 6.0
@export var burst_count: int = 3
@export var range_m: float = 60.0
@export var spread_deg: float = 1.2
@export var aim_spread_mult: float = 0.35
@export var pellets: int = 1
@export var headshot_mult: float = 2.0
@export var pierce: int = 0 ## Hitscan only: extra enemies the shot punches through (0 = stops at first).

@export_group("Effective Range")
## Per-weapon range identity — the heart of "use the right tool for the range".
## Inside [opt_min, opt_max] the weapon does full damage; closer than opt_min it
## scales toward close_mult (0 m), farther than opt_max it scales toward far_mult
## (at range_m). Close shredders set a low far_mult; long-range guns set a low
## close_mult. Heavy/AoE weapons leave range_falloff off and stay range-agnostic.
@export var range_falloff: bool = false ## When false the weapon does flat damage at any range (AoE/heavy).
@export var opt_min: float = 0.0   ## Closest distance still at full damage.
@export var opt_max: float = 60.0  ## Farthest distance still at full damage.
@export var close_mult: float = 1.0 ## Damage multiplier at point-blank (<1 = penalized up close).
@export var far_mult: float = 1.0   ## Damage multiplier out at range_m (<1 = penalized at distance).

@export_group("Recoil")
@export var recoil_pitch: float = 0.9
@export var recoil_yaw: float = 0.3
@export var recoil_recovery: float = 9.0

@export_group("Ammo")
@export var mag_size: int = 18
@export var reserve_max: int = 180
@export var reload_time: float = 1.6

@export_group("Projectile (when PROJECTILE)")
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 60.0
@export var splash_radius: float = 0.0
@export var splash_damage: float = 0.0

@export_group("Feel")
@export var muzzle_flash_scene: PackedScene
@export var impact_scene: PackedScene
@export var tracer_scene: PackedScene
@export var tracer_color: Color = Color(1.0, 0.85, 0.5) ## Tint + glow of the round's tracer.
@export var energy_beam_fx: bool = false ## Hitscan only: draw a thick lingering laser beam (muzzle→hit) with end blooms, on top of the tracer. For lasers/railguns.
@export var arc_fx: bool = false ## Adds jagged electric arcs to the energy beam (Tesla/Arc weapons). Implies an energy beam.
@export var fire_sound: AudioStream
@export var reload_sound: AudioStream
@export var empty_sound: AudioStream
@export var sound_id: String = "" ## Looked up in SoundSynth.streams when fire_sound is null. Suffixes _reload, _empty resolved automatically.
@export var has_pump_action: bool = false ## If true, viewmodel "Pump" node cycles after each shot
@export var slide_kick: float = 0.025 ## Distance the "Slide" node travels backward on fire
@export var pump_throw: float = 0.09 ## Distance the "Pump" node travels backward when cycling
@export var viewmodel_color: Color = Color(0.6, 0.65, 0.7)

@export_group("ADS Feel")
@export var ads_position_offset: Vector3 = Vector3(-0.25, 0.08, 0.1) ## Offset added to hip WeaponHolder position when aiming
@export var ads_fov: float = 58.0 ## Target Camera FOV when aiming this weapon

