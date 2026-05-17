extends RefCounted

const COLUMN_RADIUS := 28.0
const BOULDER_RADIUS := 36.0

## Returns true for room labels that must always be obstacle-free.
static func _obstacle_free(label: String) -> bool:
	if label == "Hold the Line" or label == "Tutorial":
		return true
	if label.begins_with("Trial ") or label.begins_with("Apex "):
		return true
	return false

## Maps encounter label to the set of layout templates eligible for selection.
## One template is chosen per room via the encounter RNG.
const _ENCOUNTER_POOL: Dictionary = {
	"Crossfire":       ["center_pair_h", "center_pair_v", "diagonal_slash", "boulder_pair_h"],
	"Onslaught":       ["scatter_3", "cross_4", "boulder_pair_h"],
	"Fortress":        ["cross_4", "quad_corners", "boulder_spread"],
	"Blitz":           ["diagonal_slash", "diagonal_backslash", "center_pair_h"],
	"Suppression":     ["quad_corners", "scatter_3", "boulder_pair_v"],
	"Vanguard":        ["center_pair_v", "diagonal_slash"],
	"Ambush":          ["scatter_3", "diagonal_backslash"],
	"Convergence":     ["cross_4", "center_pair_v", "boulder_pair_v"],
	"Gauntlet":        ["scatter_3", "quad_corners", "cross_4", "boulder_spread"],
	"Last Stand":      ["center_pair_h", "cross_4", "quad_corners", "boulder_pair_h"],
	"Cut the Signal":  ["scatter_3", "center_pair_h"],
	"Circuit Sweep":   ["scatter_3", "center_pair_h", "boulder_pair_h"],
	"Pulse Window":    ["scatter_3", "diagonal_slash", "boulder_pair_v"],
	"Intercept Run":   ["center_pair_v", "diagonal_backslash"],
	"Skirmish":        ["center_pair_h", "none"],
	"Pursuit":         ["none"],
}

## Returns the column positions for a named template (room-center-relative).
static func _resolve_positions(template_name: String) -> Array[Vector2]:
	match template_name:
		"center_pair_h":
			return [Vector2(-180.0, 0.0), Vector2(180.0, 0.0)]
		"center_pair_v":
			return [Vector2(0.0, -130.0), Vector2(0.0, 130.0)]
		"diagonal_slash":
			return [Vector2(-170.0, -120.0), Vector2(170.0, 120.0)]
		"diagonal_backslash":
			return [Vector2(170.0, -120.0), Vector2(-170.0, 120.0)]
		"cross_4":
			return [Vector2(-200.0, 0.0), Vector2(200.0, 0.0), Vector2(0.0, -145.0), Vector2(0.0, 145.0)]
		"quad_corners":
			return [Vector2(-220.0, -155.0), Vector2(220.0, -155.0), Vector2(-220.0, 155.0), Vector2(220.0, 155.0)]
		_:
			return []

## Primary API. Returns Array of {pos: Vector2, radius: float} dicts.
## Positions are in world space with the room centred at origin.
## Uses rng to pick a template and (for scatter_3) to place columns.
static func pick_layout(encounter_label: String, room_size: Vector2, rng: RandomNumberGenerator) -> Array[Dictionary]:
	if _obstacle_free(encounter_label):
		return []
	var pool: Array = _ENCOUNTER_POOL.get(encounter_label, []) as Array
	if pool.is_empty():
		return []
	var chosen: String = String(pool[rng.randi_range(0, pool.size() - 1)])
	if chosen == "none":
		return []
	if chosen == "scatter_3":
		return _generate_scatter(3, room_size, rng)
	if chosen.begins_with("boulder_"):
		return _resolve_boulder_template(chosen, room_size)
	var half_safe := room_size * 0.5 - Vector2.ONE * 90.0
	var out: Array[Dictionary] = []
	for pos in _resolve_positions(chosen):
		var clamped := Vector2(
			clampf(pos.x, -half_safe.x, half_safe.x),
			clampf(pos.y, -half_safe.y, half_safe.y)
		)
		out.append({"pos": clamped, "radius": COLUMN_RADIUS})
	return out

static func _resolve_boulder_template(template_name: String, room_size: Vector2) -> Array[Dictionary]:
	var half_safe := room_size * 0.5 - Vector2.ONE * 100.0
	var positions: Array[Vector2] = []
	match template_name:
		"boulder_pair_h":
			positions = [Vector2(-195.0, 0.0), Vector2(195.0, 0.0)]
		"boulder_pair_v":
			positions = [Vector2(0.0, -135.0), Vector2(0.0, 135.0)]
		"boulder_spread":
			positions = [Vector2(-160.0, -110.0), Vector2(160.0, -110.0), Vector2(0.0, 130.0)]
		_:
			return []
	var out: Array[Dictionary] = []
	for pos in positions:
		var clamped := Vector2(
			clampf(pos.x, -half_safe.x, half_safe.x),
			clampf(pos.y, -half_safe.y, half_safe.y)
		)
		out.append({"pos": clamped, "radius": BOULDER_RADIUS, "type": "boulder"})
	return out

static func _generate_scatter(count: int, room_size: Vector2, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var half_safe := room_size * 0.5 - Vector2.ONE * 90.0
	var min_center_dist := 100.0
	var min_spacing := 90.0
	for i in range(count):
		var placed := false
		for _attempt in range(60):
			var candidate := Vector2(
				rng.randf_range(-half_safe.x, half_safe.x),
				rng.randf_range(-half_safe.y, half_safe.y)
			)
			if candidate.length() < min_center_dist:
				continue
			var too_close := false
			for entry in out:
				if candidate.distance_to((entry as Dictionary).get("pos", Vector2.ZERO) as Vector2) < min_spacing:
					too_close = true
					break
			if not too_close:
				out.append({"pos": candidate, "radius": COLUMN_RADIUS})
				placed = true
				break
		if not placed:
			var angle := float(i) * (TAU / float(count))
			var fallback := Vector2(cos(angle), sin(angle)) * (min_center_dist + min_spacing * 0.7)
			out.append({"pos": fallback, "radius": COLUMN_RADIUS})
	return out
