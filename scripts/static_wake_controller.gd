extends Node
## Normal-dash ribbons share one exposure clock per owner/enemy. Presentation
## replicas receive geometry only; accepted damage still uses the host route.

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const REGISTRY := preload("res://scripts/shared/combat_interaction_registry.gd")
const RENDERER := preload("res://scripts/static_wake_trail_renderer.gd")
const TICK_INTERVAL := 0.25
const DAMAGE_RATE := 6.0
const MAX_RIBBONS := 2
const MAX_SEGMENTS := 64
const STATE_INTERVAL := 0.10
const REMOTE_LEASE := 0.35

var player: Node2D
var renderer: Node2D
var ribbons: Array[Dictionary] = []
var _clock := 0.0
var _next_id := 0
var _drawing_id := 0
var _drawing_context: Dictionary = {}
var _targets: Dictionary = {}
var _positions: Dictionary = {}
var _generation := 0
var _sequence := 0
var _received_sequence := -1
var _state_left := 0.0
var _remote_lease := 0.0
var _assembly_sequence := -1
var _assembly_parts: Dictionary = {}
var _assembly_count := 0

func initialize(owner_player: Node2D) -> void:
	player = owner_player
	renderer = RENDERER.new()
	add_child(renderer)
	renderer.set_as_top_level(true)
	renderer.global_position = Vector2.ZERO
	renderer.z_as_relative = false
	renderer.z_index = -1
	set_physics_process(false)

func _is_owner() -> bool:
	return is_instance_valid(player) and bool(player._is_local_control_owner())

func _allowed() -> bool:
	return is_instance_valid(player) and bool(player._is_alive_state) and bool(player.combat_damage_enabled) and not bool(player.encounter_input_frozen) and not get_tree().paused

func begin_dash(context: Dictionary) -> void:
	end_dash()
	if not _allowed() or not _is_owner() or not bool(player.reward_static_wake):
		return
	_drawing_context = context.duplicate(true)
	# A successful dash with no traveled distance does not replace a live field.
	_drawing_id = -1
	_seed_enemy_positions()

func append_segment(start: Vector2, finish: Vector2) -> void:
	if _drawing_id == 0 or not _allowed() or not _is_owner() or not bool(player.reward_static_wake):
		return
	if not start.is_finite() or not finish.is_finite() or start.distance_squared_to(finish) <= 0.000001:
		return
	var ribbon: Dictionary = {}
	if _drawing_id == -1:
		_next_id += 1
		_drawing_id = _next_id
		var lifetime := float(player.static_wake_lifetime)
		var radius := float(player.static_wake_trail_radius)
		if not is_finite(lifetime) or not is_finite(radius) or lifetime <= 0.0 or radius <= 0.0:
			end_dash()
			return
		ribbon = {"id": _drawing_id, "born": _clock, "expires": _clock + lifetime, "lifetime": lifetime, "radius": maxf(8.0, radius), "context": _drawing_context.duplicate(true), "segments": []}
		ribbons.append(ribbon)
		if ribbons.size() > MAX_RIBBONS:
			ribbons.pop_front()
	else:
		for candidate: Dictionary in ribbons:
			if int(candidate["id"]) == _drawing_id:
				ribbon = candidate
				break
	if ribbon.is_empty() or float(ribbon["expires"]) <= _clock:
		end_dash()
		return
	var segments: Array = ribbon["segments"]
	# Normal dash travel is straight. Merge only an exact continuation; retain
	# real collision/clamp corners rather than drawing a chord through terrain.
	if not segments.is_empty():
		var previous: Dictionary = segments.back()
		var previous_step: Vector2 = previous["b"] - previous["a"]
		var next_step := finish - start
		if Vector2(previous["b"]).is_equal_approx(start) and absf(previous_step.cross(next_step)) <= 0.00001 and previous_step.dot(next_step) > 0.0:
			previous["b"] = finish
			_sync_renderer()
			return
	if segments.size() >= MAX_SEGMENTS / MAX_RIBBONS:
		end_dash()
		return
	segments.append({"a": start, "b": finish})
	_sync_renderer()
	_publish_state()

func end_dash() -> void:
	_drawing_id = 0
	_drawing_context.clear()

func cancel() -> void:
	_generation += 1
	end_dash()
	ribbons.clear()
	_targets.clear()
	_positions.clear()
	_remote_lease = 0.0
	_received_sequence = maxi(_received_sequence, _assembly_sequence)
	_assembly_parts.clear()
	_sync_renderer()
	if _is_owner():
		_publish_state(true)

func _seed_enemy_positions() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Node2D and is_instance_valid(node) and not node.is_queued_for_deletion():
			var id: int = node.get_instance_id()
			if not _positions.has(id):
				_positions[id] = {"ref": weakref(node), "position": node.global_position}

func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if not _allowed():
		if not ribbons.is_empty() or not _targets.is_empty() or _drawing_id != 0:
			cancel()
		return
	if not _is_owner():
		_remote_lease = maxf(0.0, _remote_lease - delta)
		_clock += delta
		if _remote_lease <= 0.0:
			ribbons.clear()
		_retire_ribbons()
		_sync_renderer()
		return
	if ribbons.is_empty() and _targets.is_empty() and _drawing_id == 0:
		_clock += delta
		return
	var begin := _clock
	var finish := begin + delta
	var generation := _generation
	var seen: Dictionary = {}
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Node2D) or not is_instance_valid(node) or node.is_queued_for_deletion() or DAMAGEABLE._read_target_health(node) <= 0:
			continue
		var enemy := node as Node2D
		var id := enemy.get_instance_id()
		seen[id] = true
		var position := enemy.global_position
		var old: Dictionary = _positions.get(id, {})
		var start: Vector2 = old.get("position", position)
		_positions[id] = {"ref": weakref(enemy), "position": position}
		if not start.is_finite() or not position.is_finite():
			continue
		var contacts := _contacts(start, position - start, begin, delta)
		if contacts.is_empty() and not _targets.has(id):
			continue
		var state: Dictionary = _targets.get(id, {})
		if state.is_empty():
			state = {"ref": weakref(enemy), "next": float(contacts.front()["from"]) + TICK_INTERVAL, "pending": 0.0, "fraction": 0.0, "qualified": false, "context": {}, "origin": position}
			_targets[id] = state
		var cursor := begin
		while float(state["next"]) <= finish + 0.000000001:
			cursor = _skip_empty_windows(state, contacts, cursor, finish)
			if float(state["next"]) > finish + 0.000000001:
				break
			var deadline := float(state["next"])
			_accrue(state, contacts, cursor, deadline)
			_settle(enemy, state)
			if generation != _generation or not _allowed():
				return
			state["next"] = deadline + TICK_INTERVAL
			cursor = deadline
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or DAMAGEABLE._read_target_health(enemy) <= 0:
				break
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and DAMAGEABLE._read_target_health(enemy) > 0:
			_accrue(state, contacts, cursor, finish)
	for id in _positions.keys():
		if not seen.has(id):
			_positions.erase(id)
			_targets.erase(id)
	_clock = finish
	_retire_ribbons()
	_sync_renderer()
	_state_left -= delta
	if _state_left <= 0.0 and not ribbons.is_empty():
		_publish_state()

## Retained fractional credit and cadence survive gaps, but an empty gap needs
## no per-window callback. This also bounds work after a very long stalled frame.
func _skip_empty_windows(state: Dictionary, contacts: Array[Dictionary], cursor: float, finish: float) -> float:
	if bool(state["qualified"]):
		return cursor
	var empty_until := finish
	for contact: Dictionary in contacts:
		if float(contact["to"]) > cursor:
			empty_until = minf(finish, maxf(cursor, float(contact["from"])))
			break
	var deadline := float(state["next"])
	if deadline <= empty_until + 0.000000001:
		var windows := int(floor((empty_until - deadline + 0.000000001) / TICK_INTERVAL)) + 1
		state["next"] = deadline + windows * TICK_INTERVAL
		return empty_until
	return cursor

func _retire_ribbons() -> void:
	for index in range(ribbons.size() - 1, -1, -1):
		if float(ribbons[index]["expires"]) <= _clock:
			if int(ribbons[index]["id"]) == _drawing_id:
				end_dash()
			ribbons.remove_at(index)

func _accrue(state: Dictionary, contacts: Array[Dictionary], start: float, finish: float) -> void:
	for contact: Dictionary in contacts:
		var duration := minf(finish, float(contact["to"])) - maxf(start, float(contact["from"]))
		if duration <= 0.0:
			continue
		state["pending"] = float(state["pending"]) + duration * maxf(0.0, float(player.static_wake_damage)) * DAMAGE_RATE
		if not bool(state["qualified"]):
			state["context"] = contact["context"]
			state["origin"] = contact["origin"]
		state["qualified"] = true

func _settle(enemy: Node2D, state: Dictionary) -> void:
	if not bool(state["qualified"]):
		return
	var value := float(state["fraction"]) + float(state["pending"])
	var base_amount := int(floor(value + 0.000000001))
	state["fraction"] = maxf(0.0, value - base_amount)
	state["pending"] = 0.0
	state["qualified"] = false
	var amount := int(player._apply_objective_mutator_damage_mult(base_amount)) if base_amount > 0 else 0
	var action: Dictionary = state["context"]
	# The host reads Snare eligibility before this tick applies its level3 Slow.
	var context: Dictionary = REGISTRY.damage_context(action, "static_wake", {"attack_origin": state["origin"], "hunters_snare_aoe_bonus": true})
	var generation := _generation
	var accepted := DAMAGEABLE.apply_damage(enemy, amount, context)
	if generation != _generation or not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or DAMAGEABLE._read_target_health(enemy) <= 0:
		return
	if amount == 0 and not accepted:
		return
	if int(player.static_wake_stacks) >= 3 and not enemy.is_slowed():
		DAMAGEABLE.apply_slow(enemy, 0.3 * float(player._global_slow_duration_mult()), 0.8, 0, action)

func _contacts(position: Vector2, step: Vector2, begin: float, delta: float) -> Array[Dictionary]:
	var spans: Array[Dictionary] = []
	var edges: Array[float] = []
	for ribbon: Dictionary in ribbons:
		var low := maxf(0.0, (float(ribbon["born"]) - begin) / delta)
		var high := minf(1.0, (float(ribbon["expires"]) - begin) / delta)
		if high <= low:
			continue
		for segment: Dictionary in ribbon["segments"]:
			for interval: PackedFloat64Array in capsule_contact_intervals(position, step, segment["a"], segment["b"], float(ribbon["radius"])):
				var left := maxf(low, interval[0])
				var right := minf(high, interval[1])
				if right <= left:
					continue
				spans.append({"from": left, "to": right, "ribbon": ribbon, "segment": segment})
				edges.append(left)
				edges.append(right)
	edges.sort()
	var result: Array[Dictionary] = []
	for index in range(edges.size() - 1):
		var low := edges[index]
		var high := edges[index + 1]
		if high <= low:
			continue
		var middle := (low + high) * 0.5
		for span: Dictionary in spans:
			if middle >= float(span["from"]) and middle <= float(span["to"]):
				var segment: Dictionary = span["segment"]
				var origin := Geometry2D.get_closest_point_to_segment(position + step * middle, segment["a"], segment["b"])
				result.append({"from": begin + low * delta, "to": begin + high * delta, "context": span["ribbon"]["context"], "origin": origin})
				break # Union coverage: an older contributing ribbon owns this interval.
	return result

## Exact moving-point/capsule intervals: two round caps plus the interior strip.
static func capsule_contact_intervals(position: Vector2, step: Vector2, start: Vector2, finish: Vector2, radius: float) -> Array[PackedFloat64Array]:
	var intervals: Array[PackedFloat64Array] = []
	var dx := float(step.x)
	var dy := float(step.y)
	var speed_squared := dx * dx + dy * dy
	for endpoint: Vector2 in [start, finish]:
		var x := float(position.x) - float(endpoint.x)
		var y := float(position.y) - float(endpoint.y)
		var c := x * x + y * y - radius * radius
		if speed_squared <= 0.0:
			if c <= 0.0:
				intervals.append(PackedFloat64Array([0.0, 1.0]))
			continue
		var b := 2.0 * (x * dx + y * dy)
		var discriminant := b * b - 4.0 * speed_squared * c
		if discriminant < 0.0:
			continue
		var root_value := sqrt(discriminant)
		var low := maxf(0.0, (-b - root_value) / (2.0 * speed_squared))
		var high := minf(1.0, (-b + root_value) / (2.0 * speed_squared))
		if high > low:
			intervals.append(PackedFloat64Array([low, high]))
	var ax := float(finish.x) - float(start.x)
	var ay := float(finish.y) - float(start.y)
	var length_squared := ax * ax + ay * ay
	if length_squared > 0.0:
		var px := float(position.x) - float(start.x)
		var py := float(position.y) - float(start.y)
		var interval := PackedFloat64Array([0.0, 1.0])
		interval = _clip_linear(interval, px * ax + py * ay, dx * ax + dy * ay, 0.0, length_squared)
		var width := radius * sqrt(length_squared)
		interval = _clip_linear(interval, px * ay - py * ax, dx * ay - dy * ax, -width, width)
		if interval[1] > interval[0]:
			intervals.append(interval)
	return intervals

static func _clip_linear(interval: PackedFloat64Array, value: float, slope: float, low: float, high: float) -> PackedFloat64Array:
	if interval[1] <= interval[0]:
		return interval
	if slope == 0.0:
		return interval if value >= low and value <= high else PackedFloat64Array([0.0, 0.0])
	var first := (low - value) / slope
	var last := (high - value) / slope
	return PackedFloat64Array([maxf(interval[0], minf(first, last)), minf(interval[1], maxf(first, last))])

func snapshot_visual() -> Dictionary:
	var segments: Array[Dictionary] = []
	for ribbon: Dictionary in ribbons:
		var left := maxf(0.0, float(ribbon["expires"]) - _clock)
		if left <= 0.0:
			continue
		for segment: Dictionary in ribbon["segments"]:
			segments.append({"a": segment["a"], "b": segment["b"], "radius": ribbon["radius"], "left": left, "lifetime": ribbon["lifetime"], "id": ribbon["id"]})
	return {"segments": segments}

func _sync_renderer() -> void:
	if is_instance_valid(renderer):
		renderer.set_ribbons(snapshot_visual())

func _room_id() -> int:
	return EnemyReplicationService._current_room_sync_id()

func _run_token() -> String:
	return GameStateReplicationService.get_current_run_sync_token()

func _publish_state(reliable: bool = false) -> void:
	_sequence += 1
	_state_left = STATE_INTERVAL
	var encoded: Array = []
	for segment: Dictionary in snapshot_visual()["segments"]:
		encoded.append([int(segment["id"]), int(round(float(segment["radius"]) * 100.0)), int(round(float(segment["lifetime"]) * 1000.0)), int(round(float(segment["left"]) * 1000.0)), PackedVector2Array([segment["a"], segment["b"]])])
	var count := maxi(1, int(ceil(float(encoded.size()) / 2.0)))
	for index in range(count):
		player._broadcast_cue_event("static_wake_state", {"q": _sequence, "r": _room_id(), "u": _run_token(), "i": index, "n": count, "s": encoded.slice(index * 2, index * 2 + 2)}, reliable)

func apply_visual_state(payload: Dictionary) -> void:
	for key in ["q", "r", "n", "i"]:
		if not (payload.get(key) is int):
			return
	if not (payload.get("u") is String) or _is_owner() or not _allowed() or int(payload["r"]) != _room_id() or String(payload["u"]) != _run_token():
		return
	var sequence := int(payload.get("q", -1))
	var count := int(payload.get("n", 0))
	var index := int(payload.get("i", -1))
	var entries: Variant = payload.get("s")
	if sequence <= _received_sequence or sequence < _assembly_sequence or count < 1 or count > MAX_SEGMENTS / 2 or index < 0 or index >= count or not (entries is Array) or entries.size() > 2:
		return
	var valid: Array[Dictionary] = []
	for entry in entries:
		if not (entry is Array) or entry.size() != 5 or not (entry[4] is PackedVector2Array) or entry[4].size() != 2:
			return
		for field in range(4):
			if not (entry[field] is int):
				return
		var id := int(entry[0])
		var radius := float(entry[1]) * 0.01
		var lifetime := float(entry[2]) * 0.001
		var left := float(entry[3]) * 0.001
		var start: Vector2 = entry[4][0]
		var finish: Vector2 = entry[4][1]
		if id <= 0 or not is_finite(radius) or radius <= 0.0 or radius > 256.0 or not is_finite(lifetime) or lifetime <= 0.0 or lifetime > 15.0 or not is_finite(left) or left <= 0.0 or left > lifetime or not start.is_finite() or not finish.is_finite():
			return
		valid.append({"id": id, "radius": radius, "lifetime": lifetime, "left": left, "a": start, "b": finish})
	if sequence > _assembly_sequence:
		_assembly_sequence = sequence
		_assembly_count = count
		_assembly_parts.clear()
	if count != _assembly_count or _assembly_parts.has(index):
		return
	_assembly_parts[index] = valid
	if _assembly_parts.size() != count:
		return
	var incoming: Array[Dictionary] = []
	for part_index in range(count):
		for segment: Dictionary in _assembly_parts[part_index]:
			var found: Dictionary = {}
			for ribbon: Dictionary in incoming:
				if int(ribbon["id"]) == int(segment["id"]):
					found = ribbon
					break
			if found.is_empty():
				if incoming.size() >= MAX_RIBBONS:
					return
				found = {"id": segment["id"], "born": _clock, "expires": _clock + float(segment["left"]), "lifetime": segment["lifetime"], "radius": segment["radius"], "segments": []}
				incoming.append(found)
			found["segments"].append({"a": segment["a"], "b": segment["b"]})
	_received_sequence = sequence
	ribbons = incoming
	_remote_lease = REMOTE_LEASE
	_assembly_parts.clear()
	_sync_renderer()

func _process(delta: float) -> void:
	if not _is_owner():
		tick(delta)
