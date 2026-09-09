extends RefCounted
## Arena perimeters constrain actor centers in WorldGenerator; they are not
## physics bodies. Motion powers use the same rectangle for first contact.

## Returns a fresh hit dictionary, or an empty dictionary for free travel.
## An outside start reports its clamped position separately from a swept hit.
static func sweep(start: Vector2, motion: Vector2, bounds: Rect2) -> Dictionary:
	if not bounds.has_area() or not start.is_finite() or not motion.is_finite():
		return {}
	var clamped := Vector2(clampf(start.x, bounds.position.x, bounds.end.x), clampf(start.y, bounds.position.y, bounds.end.y))
	if start != clamped:
		return {"fraction": 0.0, "position": clamped, "normal": (clamped - start).normalized(), "outside": true}
	var fraction := INF
	var normal := Vector2.ZERO
	for axis in range(2):
		if is_zero_approx(motion[axis]):
			continue
		var edge := bounds.end[axis] if motion[axis] > 0.0 else bounds.position[axis]
		var candidate := (edge - start[axis]) / motion[axis]
		if candidate < 0.0 or candidate > 1.0:
			continue
		var axis_normal := Vector2.ZERO
		axis_normal[axis] = -signf(motion[axis])
		if candidate < fraction and not is_equal_approx(candidate, fraction):
			fraction = candidate
			normal = axis_normal
		elif is_equal_approx(candidate, fraction):
			normal += axis_normal
	if not is_finite(fraction):
		return {}
	return {"fraction": fraction, "position": start + motion * fraction, "normal": normal.normalized(), "outside": false}
