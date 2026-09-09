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
varying vec2 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
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
    float alpha = max(fill * 0.17, edge * 0.48);
    COLOR = vec4(mix(vec3(0.22, 0.68, 0.90), vec3(0.64, 0.94, 1.0), edge), alpha);
}
"""

static var _shared_shader: Shader
var _bounds := Rect2()
var _segments: Array[Dictionary] = []
var _shader_material: ShaderMaterial

func _ready() -> void:
	_ensure_material()

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
