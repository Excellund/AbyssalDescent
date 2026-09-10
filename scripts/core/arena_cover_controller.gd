extends RefCounted
## Authored cover stays immutable. Room-local contact state only moves toward zero.

var revision: int = 0
var _layout: Array[Dictionary] = []
var _remaining: Dictionary = {}

func reset(layout: Array[Dictionary]) -> void:
	_layout = layout.duplicate(true)
	_remaining.clear()
	revision = 0
	for index in _layout.size():
		var contacts: Variant = _layout[index].get("break_contacts")
		if contacts is int and contacts == 3:
			_remaining[index + 1] = contacts

func has_brittle_cover() -> bool:
	return not _remaining.is_empty()

func is_present(id: int) -> bool:
	return id > 0 and id <= _layout.size() and int(_remaining.get(id, 1)) > 0

func contacts_left(id: int) -> int:
	return int(_remaining.get(id, -1))

func live_layout() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in _layout.size():
		var id := index + 1
		if not is_present(id):
			continue
		var entry := _layout[index].duplicate(true)
		if _remaining.has(id) and int(_remaining[id]) < int(entry.break_contacts):
			entry["contacts_left"] = int(_remaining[id])
		result.append(entry)
	return result

func rubble_layout() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in _remaining:
		if int(_remaining[id]) == 0:
			var entry := _layout[id - 1].duplicate(true)
			entry["contacts_left"] = 0
			result.append(entry)
	return result

func contact_candidates(origin: Vector2, direction: Vector2, shapes: Array[Dictionary]) -> Array[int]:
	var result: Array[int] = []
	for id: int in _remaining:
		if not is_present(id):
			continue
		var entry := _layout[id - 1]
		var center: Vector2 = entry.get("pos", Vector2.ZERO)
		var radius := float(entry.get("radius", 28.0))
		for shape in shapes:
			if _circle_in_strike(center, radius, origin, direction, shape):
				result.append(id)
				break # One Attack's melee and Wind shapes form one contact.
	return result

func apply_contact(id: int) -> bool:
	if not _remaining.has(id) or int(_remaining[id]) <= 0:
		return false
	_remaining[id] = int(_remaining[id]) - 1
	revision += 1
	return true

func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in _remaining:
		result.append({"id": id, "left": int(_remaining[id])})
	return result

func apply_snapshot(incoming_revision: int, entries: Array) -> bool:
	if incoming_revision <= revision or entries.size() != _remaining.size() or entries.is_empty():
		return false
	var next := {}
	var spent := 0
	for value in entries:
		if not (value is Dictionary) or not (value.get("id") is int) or not (value.get("left") is int):
			return false
		var id: int = value.id
		var left: int = value.left
		if not _remaining.has(id) or next.has(id) or left < 0 or left > int(_remaining[id]):
			return false
		next[id] = left
		spent += int(_layout[id - 1].break_contacts) - left
	if spent != incoming_revision:
		return false
	# Validate the whole state before changing any geometry. Higher revisions
	# cannot repair a damaged column or resurrect a destroyed one.
	_remaining = next
	revision = incoming_revision
	return true

static func _circle_in_strike(center: Vector2, radius: float, origin: Vector2, direction: Vector2, shape: Dictionary) -> bool:
	var offset := center - origin
	var distance := offset.length()
	if distance > float(shape.range) + radius:
		return false
	# Match the existing Razor Wind center exclusion at its hollow inner range.
	var inner := float(shape.get("inner", 0.0))
	if inner > 0.0 and distance <= inner:
		return false
	if distance <= 0.000001:
		return true
	var angular_grace := asin(clampf(radius / distance, 0.0, 1.0))
	return absf(direction.angle_to(offset / distance)) <= deg_to_rad(float(shape.arc_degrees) * 0.5) + angular_grace
