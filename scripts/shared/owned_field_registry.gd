extends RefCounted
## Gameplay membership only. Visual cues never register a damage Field.

const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")
const MAX_FIELDS := 64
const MAX_WAKE_SEGMENTS := 32
const SOURCES := ["static_wake", "sigil_chain_zone", "void_echo_zone", "null_corridor_deflect", "convergence_window"]

var _player: Node2D
var _clock := 0.0
var _identity := ""
var _epoch := 0
var _fields: Dictionary = {}
var _latest_serial: Dictionary = {}

func initialize(player: Node2D) -> void:
	_player = player
	clear()

func clear() -> void:
	_fields.clear()
	_latest_serial.clear()
	_epoch = 0
	_identity = _current_identity()

func advance(delta: float) -> void:
	if is_finite(delta) and delta > 0.0:
		_clock += delta
	_prune()

func _current_identity() -> String:
	return "%s:%d" % [INTERACTIONS.current_run(), INTERACTIONS.current_room()]

func _controller() -> Node:
	return _player.get("combat_interactions") as Node if is_instance_valid(_player) else null

func _authorized() -> bool:
	return is_instance_valid(_player) and not MultiplayerSessionManager.is_remote_replica()

func _prune() -> void:
	if _identity != _current_identity():
		clear()
	var controller := _controller()
	for key in _fields.keys():
		var field: Dictionary = _fields[key]
		if float(field.expires) <= _clock or controller == null or not controller.accepts_action(field.action):
			_retire(key)

func _retire(key: String) -> void:
	if not _fields.has(key):
		return
	_fields.erase(key)

func register_field(source: String, identity: String, geometry: Dictionary, action: Dictionary) -> bool:
	if not _authorized() or source not in SOURCES or identity.is_empty() or identity.length() > 96:
		return false
	_prune()
	var owner := int(_player.get("player_id"))
	if owner <= 0:
		owner = _player.get_multiplayer().get_unique_id() if MultiplayerSessionManager.is_session_connected() else 1
	var validated := INTERACTIONS.validate_action(INTERACTIONS.damage_context(action, source).interaction, owner)
	var controller := _controller()
	if validated.is_empty() or controller == null or not controller.accepts_action(validated):
		return false
	if _epoch != 0 and _epoch != int(validated.epoch):
		clear()
	_epoch = int(validated.epoch)
	var prefix := "%d:%d:" % [validated.epoch, validated.seq]
	if not identity.begins_with(prefix):
		return false
	var serial_text := identity.trim_prefix(prefix)
	if not serial_text.is_valid_int() or int(serial_text) <= 0:
		return false
	var serial := int(serial_text)
	var key := source + ":" + identity
	var remaining: Variant = geometry.get("remaining")
	if not _number(remaining) or float(remaining) < 0.0:
		return false
	if float(remaining) == 0.0:
		if not _fields.has(key):
			return false
		_retire(key)
		return true
	if not _fields.has(key) and serial <= int(_latest_serial.get(source, 0)):
		return false
	var limits := _source_limits(source)
	if limits.is_empty() or float(remaining) > float(limits.life) + 0.0001:
		return false
	var shape := _validated_geometry(geometry, limits)
	if shape.is_empty():
		return false
	var expires := _clock + float(remaining)
	if _fields.has(key):
		expires = minf(expires, float(_fields[key].expires))
	else:
		var cap := 2 if source == "static_wake" else (1 if source in ["void_echo_zone", "convergence_window"] else MAX_FIELDS)
		var source_keys: Array[String] = []
		for existing: String in _fields:
			if _fields[existing].source == source:
				source_keys.append(existing)
		while source_keys.size() >= cap:
			_retire(source_keys.pop_front())
		while _fields.size() >= MAX_FIELDS:
			_retire(String(_fields.keys()[0]))
	_latest_serial[source] = maxi(int(_latest_serial.get(source, 0)), serial)
	_fields[key] = {"source": source, "geometry": shape, "expires": expires, "action": validated.duplicate(true)}
	return true

func contains_point(point: Vector2) -> bool:
	if not _authorized() or not point.is_finite():
		return false
	_prune()
	for field: Dictionary in _fields.values():
		var shape: Dictionary = field.geometry
		match String(shape.shape):
			"circle", "moving_circle":
				var center: Vector2 = _player.global_position if shape.shape == "moving_circle" else shape.center
				if point.distance_squared_to(center) <= float(shape.radius) * float(shape.radius):
					return true
			"capsules":
				for segment: Dictionary in shape.segments:
					var closest := Geometry2D.get_closest_point_to_segment(point, segment.a, segment.b)
					if point.distance_squared_to(closest) <= float(shape.radius) * float(shape.radius):
						return true
			"rectangle":
				var axis: Vector2 = shape.end - shape.start
				var offset: Vector2 = point - shape.start
				var length_sq := axis.length_squared()
				var projection := offset.dot(axis)
				if projection >= 0.0 and projection <= length_sq and absf(offset.cross(axis)) <= float(shape.width) * 0.5 * sqrt(length_sq):
					return true
	return false

func _source_limits(source: String) -> Dictionary:
	match source:
		"static_wake":
			if bool(_player.get("reward_static_wake")):
				return {"shape": "capsules", "radius": maxf(8.0, _value("static_wake_trail_radius")), "life": _value("static_wake_lifetime")}
		"sigil_chain_zone":
			if bool(_player.get("reward_sigil_chain")):
				return {"shape": "circle", "radius": _value("sigil_chain_radius"), "life": 1.0}
		"void_echo_zone":
			var power := _value("void_echo_damage")
			if power > 0.0:
				return {"shape": "circle", "radius": clampf(54.0 + power * 0.6, 54.0, 110.0), "life": 2.4}
		"null_corridor_deflect":
			var strength := _value("null_corridor_strength")
			if strength > 0.0:
				return {"shape": "rectangle", "width": 32.0 + strength * 14.0, "life": 3.2 + strength * 0.8}
		"convergence_window":
			var ratio := _value("convergence_surge_damage_ratio")
			if ratio > 0.0:
				return {"shape": "moving_circle", "radius": clampf(92.0 + ratio * 120.0, 92.0, 250.0), "life": 1.2 + ratio * 1.8}
	return {}

func _validated_geometry(raw: Dictionary, limits: Dictionary) -> Dictionary:
	if not (raw.get("shape") is String):
		return {}
	var shape := String(raw.get("shape", ""))
	if shape != String(limits.shape):
		return {}
	if shape == "rectangle":
		if not _point(raw.get("start")) or not _point(raw.get("end")) or not _positive(raw.get("width")) or float(raw.width) > float(limits.width) + 0.0001:
			return {}
		var length := (raw.end as Vector2).distance_to(raw.start)
		if length <= 0.0 or length > _dash_reach() + 1.0:
			return {}
		return {"shape": shape, "start": raw.start, "end": raw.end, "width": float(raw.width)}
	if not _positive(raw.get("radius")) or float(raw.radius) > float(limits.radius) + 0.0001:
		return {}
	if shape in ["circle", "moving_circle"]:
		if not _point(raw.get("center")):
			return {}
		return {"shape": shape, "center": raw.center, "radius": float(raw.radius)}
	var segments: Variant = raw.get("segments")
	if not (segments is Array) or segments.is_empty() or segments.size() > MAX_WAKE_SEGMENTS:
		return {}
	var validated: Array[Dictionary] = []
	var traveled := 0.0
	for segment: Variant in segments:
		if not (segment is Dictionary) or not _point(segment.get("a")) or not _point(segment.get("b")):
			return {}
		traveled += (segment.a as Vector2).distance_to(segment.b)
		validated.append({"a": segment.a, "b": segment.b})
	if traveled > _dash_reach() + 1.0:
		return {}
	return {"shape": shape, "segments": validated, "radius": float(raw.radius)}

func _dash_reach() -> float:
	return _value("dash_distance") * (_value("void_dash_range_mult") if bool(_player.get("reward_void_dash")) else 1.0)

func _value(property: String) -> float:
	var value: Variant = _player.get(property)
	return float(value) if _number(value) else 0.0

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _positive(value: Variant) -> bool:
	return _number(value) and float(value) > 0.0

func _point(value: Variant) -> bool:
	return value is Vector2 and (value as Vector2).is_finite()
