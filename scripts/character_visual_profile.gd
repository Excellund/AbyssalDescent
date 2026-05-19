extends RefCounted

class_name CharacterVisualProfile

var body_color: Color = Color()
var core_color: Color = Color()
var glow_color: Color = Color()
var speed_arc_color: Color = Color()
var dash_phase_color: Color = Color()
var dash_streak_color: Color = Color()

func _init(source: Dictionary = {}):
	body_color = source.get("body_color", Color())
	core_color = source.get("core_color", Color())
	glow_color = source.get("glow_color", Color())
	speed_arc_color = source.get("speed_arc_color", Color())
	dash_phase_color = source.get("dash_phase_color", Color())
	dash_streak_color = source.get("dash_streak_color", Color())

func duplicate() -> CharacterVisualProfile:
	var copy = CharacterVisualProfile.new()
	copy.body_color = body_color
	copy.core_color = core_color
	copy.glow_color = glow_color
	copy.speed_arc_color = speed_arc_color
	copy.dash_phase_color = dash_phase_color
	copy.dash_streak_color = dash_streak_color
	return copy

func apply_color_variant(hue_shift: float, value_shift: float) -> void:
	body_color = _shift_color_hsv(body_color, hue_shift, value_shift)
	core_color = _shift_color_hsv(core_color, hue_shift, value_shift)
	glow_color = _shift_color_hsv(glow_color, hue_shift, value_shift)
	speed_arc_color = _shift_color_hsv(speed_arc_color, hue_shift, value_shift)
	dash_phase_color = _shift_color_hsv(dash_phase_color, hue_shift, value_shift)
	dash_streak_color = _shift_color_hsv(dash_streak_color, hue_shift, value_shift)

func _shift_color_hsv(source_color: Color, hue_shift: float, value_shift: float) -> Color:
	var hue: float = fposmod(source_color.h + hue_shift, 1.0)
	var saturation: float = source_color.s
	var value: float = clampf(source_color.v + value_shift, 0.0, 1.0)
	return Color.from_hsv(hue, saturation, value, source_color.a)
