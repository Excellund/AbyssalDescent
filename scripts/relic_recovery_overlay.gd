extends RefCounted
## Presentation only; cargo ownership comes from the objective snapshot.
const RULES := preload("res://scripts/core/relic_recovery_state.gd")
const GOLD := Color(1.0, 0.79, 0.38, 0.95)
const MINT := Color(0.55, 1.0, 0.82, 0.98)

static func draw_recovery(canvas: Node2D, recovery: Dictionary) -> void:
	var receiver: Vector2 = recovery.get("receiver", Vector2.ZERO)
	var relics: Array = recovery.get("relics", [])
	var font := ThemeDB.fallback_font
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.003)
	canvas.draw_circle(receiver, RULES.RECEIVER_RADIUS, Color(0.12, 0.38, 0.30, 0.16))
	canvas.draw_arc(receiver, RULES.RECEIVER_RADIUS, 0.0, TAU, 64, Color(0.55, 1.0, 0.82, 0.8), 2.5)
	canvas.draw_arc(receiver, RULES.RECEIVER_RADIUS - 7.0, 0.0, TAU, 64, Color(0.55, 1.0, 0.82, 0.28), 1.0)
	_draw_label(canvas, font, receiver + Vector2(0.0, -RULES.RECEIVER_RADIUS - 12.0), "RECEIVER", MINT, 14)
	for index in RULES.RELIC_COUNT:
		var slot := receiver + Vector2((index - 1) * 22.0, 0.0)
		var delivered := index < relics.size() and bool(relics[index].get("delivered", false))
		_draw_relic(canvas, slot, 8.0, MINT if delivered else Color(0.55, 1.0, 0.82, 0.22))
	for relic: Dictionary in relics:
		if bool(relic.get("delivered", false)):
			continue
		var at: Vector2 = relic.get("position", Vector2.ZERO)
		if int(relic.get("carrier_id", 0)) > 0:
			var marker := at + Vector2(0.0, -48.0)
			canvas.draw_line(at + Vector2(0.0, -28.0), marker + Vector2(0.0, 10.0), Color(1.0, 0.79, 0.38, 0.8), 2.0)
			canvas.draw_circle(marker, 14.0, Color(0.08, 0.08, 0.1, 0.85))
			_draw_relic(canvas, marker, 10.0, GOLD)
		else:
			canvas.draw_circle(at, RULES.PICKUP_RADIUS, Color(0.55, 0.37, 0.10, 0.1))
			canvas.draw_arc(at, RULES.PICKUP_RADIUS, 0.0, TAU, 40, Color(1.0, 0.79, 0.38, 0.38 + pulse * 0.15), 1.5)
			canvas.draw_circle(at, 20.0, Color(0.06, 0.07, 0.1, 0.86))
			_draw_relic(canvas, at, 15.0, GOLD)
			_draw_label(canvas, font, at + Vector2(0.0, -45.0), "RELIC", GOLD, 13)

static func _draw_relic(canvas: Node2D, center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius * 0.68, 0), center + Vector2(0, radius), center + Vector2(-radius * 0.68, 0)])
	canvas.draw_colored_polygon(points, Color(color.r, color.g, color.b, color.a * 0.30))
	points.append(points[0])
	canvas.draw_polyline(points, color, 2.0, true)
	canvas.draw_line(center + Vector2(0, -radius * 0.65), center + Vector2(0, radius * 0.65), color, 1.0)

static func _draw_label(canvas: Node2D, font: Font, center: Vector2, label: String, color: Color, size: int) -> void:
	# Match existing move-callout scaling: world zoom locates the label, while
	# actual window stretch controls its font size. Narrow windows retain 13px.
	var transform := canvas.get_global_transform_with_canvas()
	var stretch := maxf(0.1, canvas.get_viewport().get_stretch_transform().get_scale().x)
	var font_size := maxi(size, ceili(float(size) / stretch))
	var at := transform * center
	var start := at - Vector2(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5, 0.0)
	canvas.draw_set_transform_matrix(transform.affine_inverse())
	canvas.draw_string_outline(font, start, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(2, ceili(2.0 / stretch)), Color(0.03, 0.04, 0.05, 0.92))
	canvas.draw_string(font, start, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
