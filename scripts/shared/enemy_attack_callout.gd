extends RefCounted
## A move name follows its owner, using the owner's existing replicated state.
## No timers, combat events or extra network messages are owned by this view.

const FONT_SIZE := 18
# Original Kilnheart / Glass Weaver presentation, preserved in
# d3a82a2:enemy_boss_alternative.gd:517: centered warm lettering, no plate.
const TEXT_COLOR := Color(1.0, 0.89, 0.74)

static func layout(owner: Node2D, text: String, baseline_y: float) -> Dictionary:
	var viewport := owner.get_viewport()
	var canvas := owner.get_global_transform_with_canvas()
	var stretch := maxf(0.1, viewport.get_stretch_transform().get_scale().x)
	var font_size := maxi(FONT_SIZE, ceili(float(FONT_SIZE) / stretch))
	var font := ThemeDB.fallback_font
	var lines := text.split("\n")
	var width := 0.0
	for line in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var line_height := font.get_height(font_size)
	var padding := 5.0 / stretch
	var extent := Vector2(width + padding * 2.0, line_height * lines.size() + padding * 2.0)
	var anchor := canvas * Vector2(0.0, baseline_y)
	# Keep the historical lettering readable on every silhouette: a fixed
	# screen-space gap above the real health bar, independent of body size/zoom.
	var health_bar := owner.get("health_bar") as Control
	if is_instance_valid(health_bar) and health_bar.is_visible_in_tree():
		var bar_rect: Rect2 = health_bar.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, health_bar.size)
		anchor = Vector2(bar_rect.get_center().x, bar_rect.position.y - 8.0 / stretch)
	var position := anchor - Vector2(extent.x * 0.5, extent.y)
	var bounds := viewport.get_visible_rect().grow(-8.0 / stretch)
	# At the upper edge place the callout beneath its owner instead of clipping it.
	if position.y < bounds.position.y:
		position.y = (canvas * Vector2(0.0, 65.0)).y
	position.x = clampf(position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - extent.x))
	position.y = clampf(position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - extent.y))
	var rectangle := Rect2(position, extent)
	var hud := owner.get_tree().get_first_node_in_group("attack_callout_hud")
	if is_instance_valid(hud):
		rectangle = avoid_hud(rectangle, bounds, hud.call("get_attack_callout_exclusion_rects"), padding)
	return {"rect": rectangle, "font_size": font_size, "padding": padding, "line_height": line_height, "lines": lines}

static func avoid_hud(preferred: Rect2, bounds: Rect2, occupied: Array, gap: float) -> Rect2:
	if not _overlaps(preferred, occupied, gap):
		return preferred
	var xs := [preferred.position.x]
	var ys := [preferred.position.y]
	for obstacle: Rect2 in occupied:
		xs.append(clampf(obstacle.position.x - preferred.size.x - gap, bounds.position.x, bounds.end.x - preferred.size.x))
		xs.append(clampf(obstacle.end.x + gap, bounds.position.x, bounds.end.x - preferred.size.x))
		ys.append(clampf(obstacle.position.y - preferred.size.y - gap, bounds.position.y, bounds.end.y - preferred.size.y))
		ys.append(clampf(obstacle.end.y + gap, bounds.position.y, bounds.end.y - preferred.size.y))
	var best := preferred
	var best_distance := INF
	for x: float in xs:
		for y: float in ys:
			var candidate := Rect2(Vector2(x, y), preferred.size)
			var distance := candidate.position.distance_squared_to(preferred.position)
			if distance < best_distance and bounds.encloses(candidate) and not _overlaps(candidate, occupied, gap):
				best = candidate
				best_distance = distance
	return best

static func _overlaps(rectangle: Rect2, occupied: Array, gap: float) -> bool:
	for obstacle: Rect2 in occupied:
		if rectangle.intersects(obstacle.grow(gap * 0.95)):
			return true
	return false

static func draw_callout(owner: Node2D, text: String, baseline_y: float) -> void:
	if text.is_empty() or owner.is_queued_for_deletion() or bool(owner.call("is_spawn_transporting")) or int(owner.call("get_current_health")) <= 0:
		return
	var info := layout(owner, text, baseline_y)
	var rect: Rect2 = info["rect"]
	var font_size: int = info["font_size"]
	var font := ThemeDB.fallback_font
	# Cancel world zoom while drawing text so larger arenas retain readable names.
	owner.draw_set_transform_matrix(owner.get_global_transform_with_canvas().affine_inverse())
	var baseline := rect.position.y + float(info["padding"]) + font.get_ascent(font_size)
	for line in info["lines"]:
		var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		owner.draw_string(font, Vector2(rect.get_center().x - width * 0.5, baseline), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)
		baseline += float(info["line_height"])
	owner.draw_set_transform_matrix(Transform2D.IDENTITY)
