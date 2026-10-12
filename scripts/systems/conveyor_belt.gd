class_name ConveyorBelt
# @lat: [[level-system#Conveyor Belts]]
extends StaticBody3D
## A factory conveyor: a flat belt that carries anything standing on it along
## `dir` at `speed`, the player and robots alike. It never moves itself:
## StaticBody3D.constant_linear_velocity hands its speed to every body that
## stands on it (CharacterBody3D adds the floor's velocity in move_and_slide).
## A slab 6 cm proud of the floor, side rails in hazard stripes, chevrons
## scrolling the way it runs. Def key `conveyors` (level_builder
## `_build_conveyors`). tests/conveyor_probe.

@export var size: Vector2 = Vector2(12.0, 3.0) ## Footprint (x by z) in metres.
@export var dir: Vector2 = Vector2(1.0, 0.0)   ## Direction on the ground plane (x, z).
@export var speed: float = 3.0                 ## m/s

const THICK := 0.06
const RAIL := 0.12

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var d := Vector3(dir.x, 0.0, dir.y).normalized()
	constant_linear_velocity = d * speed
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, THICK, size.y)
	cs.shape = box
	cs.position = Vector3.UP * THICK * 0.5
	add_child(cs)
	var belt := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	belt.mesh = bm
	belt.position = cs.position
	var mat := ShaderMaterial.new()
	mat.shader = _belt_shader()
	mat.set_shader_parameter("flow", Vector2(d.x, d.z) * speed)
	belt.material_override = mat
	add_child(belt)
	var rail := StandardMaterial3D.new()
	rail.albedo_color = Color(0.9, 0.62, 0.08)
	rail.roughness = 0.6
	# Rails along the belt's two long sides (visual: walk on and off freely).
	var long_x := size.x >= size.y
	for s: float in [-1.0, 1.0]:
		var r := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(size.x, 0.1, RAIL) if long_x else Vector3(RAIL, 0.1, size.y)
		r.mesh = rm
		r.material_override = rail
		r.position = Vector3(0, 0.05, s * (size.y * 0.5 + RAIL * 0.5)) if long_x \
			else Vector3(s * (size.x * 0.5 + RAIL * 0.5), 0.05, 0)
		add_child(r)

static var _shader: Shader
static func _belt_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type spatial;
uniform vec2 flow = vec2(3.0, 0.0);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 d = normalize(flow);
	float along = dot(wp.xz, d) - TIME * length(flow);
	float across = abs(dot(wp.xz, vec2(-d.y, d.x)));
	// Chevrons pointing downstream over dark rubber slats.
	float chev = fract((along + across * 0.6) * 0.5);
	float slat = step(0.85, fract(along * 2.0));
	vec3 col = vec3(0.07, 0.07, 0.075) + slat * 0.05;
	col = mix(col, vec3(0.95, 0.66, 0.08), step(0.82, chev) * 0.85);
	ALBEDO = col;
	ROUGHNESS = 0.8;
}
"""
	return _shader
