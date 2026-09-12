extends RefCounted
## Polarity belongs to the affected floor's contour, never a separate badge.
## All strokes sit inside the committed geometry; holes and lane gaps stay clear.

static func screen_unit(owner: Node2D) -> float:
	var canvas_scale := owner.get_global_transform_with_canvas().get_scale().abs().x
	var stretch := owner.get_viewport().get_stretch_transform().get_scale().abs().x
	return 1.0 / maxf(.1, canvas_scale * stretch)

static func tint(friendly: bool, warning: bool) -> Color:
	if friendly:
		return Color(.70, .96, .82) if warning else Color(.60, 1.0, .79)
	return Color(1.0, .74, .30) if warning else Color(1.0, .34, .23)

static func build_contours(geometry: Dictionary, friendly: bool, requested_unit: float = 1.0) -> Array[Dictionary]:
	var strokes: Array[Dictionary] = []
	if geometry.is_empty():
		return strokes
	var unit := clampf(requested_unit, .1, maxf(.1, _feature_width(geometry) / 18.0))
	if friendly:
		# A sector clipped by a wall may leave only a thin visible tip. Keep
		# both contours inside that tip instead of losing its helpful style.
		while unit > .1 and _paths(geometry, 6.5 * unit).is_empty():
			unit = maxf(.1, unit * .5)
		_add_paths(strokes, geometry, 4.0 * unit, 6.0 * unit, .15, "glow")
		_add_paths(strokes, geometry, 1.5 * unit, 2.0 * unit, 1.0, "rim")
		_add_paths(strokes, geometry, 6.5 * unit, 1.0 * unit, .65, "inner")
	else:
		_add_paths(strokes, geometry, 1.5 * unit, 2.0 * unit, 1.0, "rim")
		for path: PackedVector2Array in _paths(geometry, 2.0 * unit):
			var distance_left := 7.0 * unit
			for index in range(1, path.size()):
				var start := path[index - 1]
				var segment := path[index] - start
				var length := segment.length()
				if length <= .001:
					continue
				var tangent := segment / length
				while distance_left < length:
					var anchor := start + tangent * distance_left
					var inward := tangent.orthogonal()
					if not _contains(geometry, anchor + inward * 4.0 * unit):
						inward = -inward
					var end := anchor + inward * 5.5 * unit + tangent * 3.0 * unit
					if _stroke_inside(geometry, anchor, end, .85 * unit):
						strokes.append({"points": PackedVector2Array([anchor, end]), "width": 1.5 * unit, "alpha": .8, "role": "score"})
					distance_left += 13.0 * unit
				distance_left -= length
	return strokes

static func draw_contours(owner: Node2D, strokes: Array[Dictionary], color: Color, warning_progress: float = -1.0) -> void:
	for stroke: Dictionary in strokes:
		var line := Color(color, color.a * float(stroke.alpha))
		var timing_edge := warning_progress >= 0.0 and String(stroke.role) == "rim"
		owner.draw_polyline(stroke.points, Color(line, line.a * (.42 if timing_edge else 1.0)), float(stroke.width), true)
		if timing_edge:
			var remaining := _partial_path(stroke.points, warning_progress)
			if remaining.size() > 1:
				owner.draw_polyline(remaining, line, float(stroke.width), true)

static func _partial_path(points: PackedVector2Array, fraction: float) -> PackedVector2Array:
	var length := 0.0
	for index in range(1, points.size()):
		length += points[index - 1].distance_to(points[index])
	var left := length * clampf(fraction, 0.0, 1.0)
	var result := PackedVector2Array([points[0]])
	for index in range(1, points.size()):
		var segment := points[index - 1].distance_to(points[index])
		if left <= segment:
			result.append(points[index - 1].lerp(points[index], left / maxf(.001, segment)))
			break
		result.append(points[index])
		left -= segment
	return result

static func _add_paths(strokes: Array[Dictionary], geometry: Dictionary, inset: float, width: float, alpha: float, role: String) -> void:
	for points: PackedVector2Array in _paths(geometry, inset):
		if points.size() > 1:
			strokes.append({"points": points, "width": width, "alpha": alpha, "role": role})

static func _paths(geometry: Dictionary, inset: float) -> Array[PackedVector2Array]:
	var paths: Array[PackedVector2Array] = []
	var center: Vector2 = geometry.get("center", Vector2.ZERO)
	var kind := String(geometry.get("kind", ""))
	match kind:
		"circle":
			paths.append(_arc(center, maxf(.1, float(geometry.radius) - inset), 0.0, TAU))
		"rects":
			for rect: Rect2 in geometry.rects:
				var inner := rect.grow(-inset)
				if inner.has_area():
					paths.append(PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y), inner.position]))
		"annulus", "sector":
			var inner := float(geometry.inner) + inset
			var outer := float(geometry.outer) - inset
			var half_angle := float(geometry.get("half_angle", PI))
			if kind == "annulus" or half_angle >= PI - .001:
				paths.append(_arc(center, outer, 0.0, TAU))
				if float(geometry.inner) > 0.0:
					paths.append(_arc(center, inner, 0.0, TAU))
			else:
				var angle := float(geometry.angle)
				# Insets on each circular end meet the same inward-shifted radial
				# side. Joining these points cannot cut across the sector's hole.
				var outer_margin := asin(clampf(inset / outer, 0.0, 1.0))
				var inner_margin := asin(clampf(inset / inner, 0.0, 1.0))
				if inner_margin >= half_angle:
					return paths
				var loop := _arc(center, outer, angle - half_angle + outer_margin, angle + half_angle - outer_margin)
				loop.append_array(_arc(center, inner, angle + half_angle - inner_margin, angle - half_angle + inner_margin))
				loop.append(loop[0])
				paths.append(loop)
	var clipped: Array[PackedVector2Array] = []
	var bounds: Rect2 = geometry.get("bounds", Rect2(-Vector2.ONE * 10000.0, Vector2.ONE * 20000.0))
	bounds = bounds.grow(-inset)
	var frame := PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
	for path: PackedVector2Array in paths:
		clipped.append_array(Geometry2D.intersect_polyline_with_polygon(path, frame))
	return clipped

static func _arc(center: Vector2, radius: float, start: float, end: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments := clampi(ceili(absf(end - start) * radius / 10.0), 24, 256)
	for index in range(segments + 1):
		points.append(center + Vector2.from_angle(lerpf(start, end, float(index) / segments)) * radius)
	return points

static func _feature_width(geometry: Dictionary) -> float:
	match String(geometry.get("kind", "")):
		"circle":
			return float(geometry.radius)
		"annulus", "sector":
			return float(geometry.outer) - float(geometry.inner)
		"rects":
			var width := INF
			for rect: Rect2 in geometry.rects:
				width = minf(width, minf(rect.size.x, rect.size.y))
			return width
	return 1.0

static func _stroke_inside(geometry: Dictionary, start: Vector2, end: Vector2, radius: float) -> bool:
	for index in 5:
		var point := start.lerp(end, float(index) / 4.0)
		for offset in [Vector2.ZERO, Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			if not _contains(geometry, point + offset * radius):
				return false
	return true

static func _contains(geometry: Dictionary, point: Vector2) -> bool:
	var bounds: Rect2 = geometry.get("bounds", Rect2(-Vector2.ONE * 10000.0, Vector2.ONE * 20000.0))
	if not bounds.has_point(point):
		return false
	var offset := point - Vector2(geometry.get("center", Vector2.ZERO))
	var distance := offset.length()
	match String(geometry.get("kind", "")):
		"circle":
			return distance <= float(geometry.radius)
		"rects":
			for rect: Rect2 in geometry.rects:
				if rect.has_point(point):
					return true
		"annulus", "sector":
			if distance < float(geometry.inner) or distance > float(geometry.outer):
				return false
			return String(geometry.kind) == "annulus" or absf(wrapf(offset.angle() - float(geometry.angle), -PI, PI)) <= float(geometry.half_angle)
	return false
