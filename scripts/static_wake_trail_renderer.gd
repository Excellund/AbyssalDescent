extends Node2D
## A single max-coverage draw keeps intersecting ribbons at the same brightness.
## Radius is the damage radius throughout life; only opacity fades at the end.

const MAX_SEGMENTS := 64
const FADE_TIME := 0.35
const SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;
uniform int segment_count = 0;
uniform vec4 segments[64];
uniform vec2 radii_fades[64];
uniform float static_time = 0.0;
varying vec2 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
float cell_hash(vec2 cell) {
    return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}
float line_distance(vec2 point, vec2 a, vec2 b) {
    vec2 ab = b - a;
    return length(point - a - ab * clamp(dot(point - a, ab) / max(dot(ab, ab), 0.00001), 0.0, 1.0));
}
float static_distance(vec2 point) {
    // One spatial pattern for the whole union. Segment count, age and overlap
    // cannot add another spark or refresh an animation allowance.
    vec2 cell_size = vec2(58.0, 46.0);
    vec2 cell = floor(point / cell_size);
    float phase = floor(static_time * 10.0 + cell_hash(cell) * 7.0);
    vec2 phase_cell = cell + vec2(phase * 0.37, phase * 1.17);
    float seed = cell_hash(phase_cell);
    if (seed < 0.28) {
        return 1000.0;
    }
    float bend = cell_hash(phase_cell + vec2(8.3, 2.7));
    float kink = cell_hash(phase_cell + vec2(1.9, 7.1));
    vec2 jitter = (vec2(bend, kink) - vec2(0.5)) * vec2(12.0, 8.0);
    vec2 local = mod(point, cell_size) - cell_size * 0.5 - jitter;
    float angle = cell_hash(phase_cell + vec2(19.0)) * 6.2831853;
    local = vec2(dot(local, vec2(cos(angle), sin(angle))), dot(local, vec2(-sin(angle), cos(angle))));
    vec2 a = vec2(-14.0, seed * 4.0 - 2.0);
    vec2 b = vec2(-7.0, bend * 8.0 - 4.0);
    vec2 c = vec2(-2.0, kink * 10.0 - 5.0);
    vec2 d = vec2(4.0, -1.0 - bend * 4.0);
    vec2 e = vec2(13.0, seed * 4.0);
    float distance_to_spark = min(line_distance(local, a, b), line_distance(local, b, c));
    distance_to_spark = min(distance_to_spark, line_distance(local, c, d));
    distance_to_spark = min(distance_to_spark, line_distance(local, d, e));
    if (seed > 0.72) {
        distance_to_spark = min(distance_to_spark, line_distance(local, c, c + vec2(4.0, 6.0)));
    }
    return distance_to_spark;
}
void fragment() {
    float fill = 0.0;
    float union_distance = 1000000.0;
    float boundary_fade = 0.0;
    for (int i = 0; i < segment_count; i++) {
        vec2 a = segments[i].xy;
        vec2 b = segments[i].zw;
        vec2 ab = b - a;
        float along = clamp(dot(world_position - a, ab) / max(dot(ab, ab), 0.00001), 0.0, 1.0);
        float distance_to_path = length(world_position - a - ab * along);
        float radius = radii_fades[i].x;
        float fade = radii_fades[i].y;
        float coverage = 1.0 - smoothstep(radius - 0.75, radius, distance_to_path);
        fill = max(fill, coverage * fade);
        float signed_distance = distance_to_path - radius;
        if (signed_distance < union_distance) {
            union_distance = signed_distance;
            boundary_fade = fade;
        }
    }
    // Max coverage prevents overlap from multiplying opacity.
    float edge = (1.0 - smoothstep(-0.75, 0.0, union_distance)) * smoothstep(-1.8, -1.0, union_distance) * boundary_fade;
    float core = 0.0;
    float halo = 0.0;
    if (fill > 0.0) {
        float spark_distance = static_distance(world_position);
        core = 1.0 - smoothstep(0.40, 1.20, spark_distance);
        halo = (1.0 - smoothstep(1.20, 3.8, spark_distance)) * 0.24;
    }
    // Steady pale-gold footprint, locally crackling white-yellow filaments.
    // Clip every layer by coverage and fade; only the union's outside has a rim.
    float alpha = max(max(fill * 0.075, edge * 0.40), fill * max(core * 0.94, halo));
    vec3 color = mix(vec3(0.97, 0.94, 0.54), vec3(1.0, 1.0, 0.91), max(edge * 0.6, core));
    COLOR = vec4(color, alpha);
}
"""

static var _shared_shader: Shader
var _bounds := Rect2()
var _segments: Array[Dictionary] = []
var _shader_material: ShaderMaterial
var _visual_time := 0.0

func _ready() -> void:
	_ensure_material()

func _process(delta: float) -> void:
	if _segments.is_empty() or not is_finite(delta) or delta <= 0.0:
		return
	_visual_time = fmod(_visual_time + delta, 1024.0)
	_shader_material.set_shader_parameter("static_time", _visual_time)

func _ensure_material() -> void:
	if _shader_material != null:
		return
	if _shared_shader == null:
		_shared_shader = Shader.new()
		_shared_shader.code = SHADER_CODE
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = _shared_shader
	material = _shader_material

func set_ribbons(snapshot: Dictionary) -> void:
	_ensure_material()
	_segments.clear()
	var vectors := PackedVector4Array()
	var values := PackedVector2Array()
	_bounds = Rect2()
	for entry in snapshot.get("segments", []):
		if not (entry is Dictionary) or _segments.size() >= MAX_SEGMENTS:
			continue
		var start: Vector2 = entry.get("a", Vector2.INF)
		var finish: Vector2 = entry.get("b", Vector2.INF)
		var radius := float(entry.get("radius", 0.0))
		var left := float(entry.get("left", 0.0))
		if not start.is_finite() or not finish.is_finite() or not is_finite(radius) or radius <= 0.0 or not is_finite(left) or left <= 0.0:
			continue
		var segment_bounds := Rect2(start, Vector2.ZERO).expand(finish).grow(radius)
		_bounds = segment_bounds if _segments.is_empty() else _bounds.merge(segment_bounds)
		_segments.append(entry.duplicate())
		vectors.append(Vector4(start.x, start.y, finish.x, finish.y))
		values.append(Vector2(radius, clampf(left / FADE_TIME, 0.0, 1.0)))
	vectors.resize(MAX_SEGMENTS)
	values.resize(MAX_SEGMENTS)
	_shader_material.set_shader_parameter("segment_count", _segments.size())
	_shader_material.set_shader_parameter("segments", vectors)
	_shader_material.set_shader_parameter("radii_fades", values)
	queue_redraw()

func clear() -> void:
	set_ribbons({"segments": []})

func get_footprint_bounds() -> Rect2:
	return _bounds

func _draw() -> void:
	if not _segments.is_empty():
		draw_rect(_bounds, Color.WHITE)
