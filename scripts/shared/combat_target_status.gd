extends Node2D
## Enemy-owned gameplay state. Sources expire independently; Dread and fractional
## damage belong to the target and disappear with that enemy or room.

const REGISTRY := preload("res://scripts/shared/combat_interaction_registry.gd")
const BODY_GEOMETRY := preload("res://scripts/enemy_launch_state.gd")
const MAX_MARKS := 32
const MAX_OWNERS := 4
const MAX_REMAINDERS := 128
# Append sources: their indices are serialized in the compact network packet.
const MARK_SOURCES := ["wraithstep", "eclipse_mark", "dread_resonance", "cross_stitch", "stormbrand", "null_corridor"]

var marks: Dictionary = {}
var dread: Dictionary = {}
var _remainders: Dictionary = {}
var _last_dread_actions: Dictionary = {}
var _run: String = ""
var _room: int = -1
var _revision: int = 0
var _received_revision: int = 0
var _fraction_generation: int = 0
var _had_status: bool = false

func _ready() -> void:
	add_to_group("shared_combat_status")
	z_index = 1
	_refresh_identity()

func _refresh_identity() -> void:
	var run := REGISTRY.current_run()
	var room := REGISTRY.current_room()
	if run != _run or room != _room:
		clear()
		_run = run
		_room = room
		_received_revision = 0

func _physics_process(delta: float) -> void:
	var target := get_parent()
	if get_tree().paused or not is_instance_valid(target) or not target.is_physics_processing():
		return
	advance(delta)

func advance(delta: float) -> void:
	_refresh_identity()
	var target := get_parent()
	if is_instance_valid(target) and target.has_method("get_current_health") and int(target.get_current_health()) <= 0:
		clear()
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	for key in marks.keys():
		var entry: Dictionary = marks[key]
		entry.left = maxf(0.0, float(entry.left) - delta)
		if entry.left <= 0.0:
			marks.erase(key)
	queue_redraw()

func clear() -> void:
	marks.clear()
	dread.clear()
	_remainders.clear()
	_last_dread_actions.clear()
	_revision += 1
	_fraction_generation += 1
	queue_redraw()

func cancel_owner(owner: int) -> void:
	for key in marks.keys():
		if int(marks[key].owner) == owner:
			marks.erase(key)
	dread.erase(owner)
	_last_dread_actions.erase(owner)
	for key: String in _remainders.keys():
		if key.begins_with("%d:" % owner):
			_remainders.erase(key)
	_fraction_generation += 1
	queue_redraw()

func apply_mark(owner: int, source: String, ratio: float, duration: float) -> bool:
	_refresh_identity()
	if owner <= 0 or source not in MARK_SOURCES or not is_finite(ratio) or not is_finite(duration) or ratio <= 0.0 or duration <= 0.0:
		return false
	var key := "%d:%s" % [owner, source]
	if not marks.has(key) and marks.size() >= MAX_MARKS:
		return false
	var owners: Dictionary = {}
	for entry: Dictionary in marks.values():
		owners[int(entry.owner)] = true
	if not owners.has(owner) and owners.size() >= MAX_OWNERS:
		return false
	# Reapplying this source replaces only its own window. Other sources retain
	# their actual potency and expiry, including stronger shorter windows.
	marks[key] = {"owner": owner, "source": source, "ratio": ratio, "left": duration}
	_had_status = true
	queue_redraw()
	return true

func snapshot(owner: int) -> Dictionary:
	_refresh_identity()
	var ratio := 0.0
	for entry: Dictionary in marks.values():
		if float(entry.left) > 0.0:
			ratio = maxf(ratio, float(entry.ratio))
	return {"mark_ratio": ratio, "dread_stacks": int(dread.get(owner, 0))}

func add_dread(owner: int, cap: int, action: Dictionary) -> int:
	_refresh_identity()
	if owner <= 0 or cap <= 0 or (not dread.has(owner) and dread.size() >= MAX_OWNERS):
		return 0
	var identity := "%d:%d" % [int(action.get("epoch", 0)), int(action.get("seq", 0))]
	if _last_dread_actions.get(owner) == identity:
		return int(dread.get(owner, 0))
	_last_dread_actions[owner] = identity
	dread[owner] = mini(cap, int(dread.get(owner, 0)) + 1)
	_had_status = true
	queue_redraw()
	return int(dread[owner])

func prepare_damage(owner: int, source: String, amount: float, round_down: bool = false) -> Dictionary:
	_refresh_identity()
	if not is_finite(amount) or amount < 0.0:
		return {}
	var key := "%d:%s" % [owner, source]
	if not _remainders.has(key) and _remainders.size() >= MAX_REMAINDERS:
		return {"amount": int(floor(amount + 0.000000001) if round_down else round(amount)), "key": "", "generation": _fraction_generation, "remainder": 0.0}
	var accumulated := amount + float(_remainders.get(key, 0.0))
	var result := maxi(0, int(floor(accumulated + 0.000000001) if round_down else round(accumulated)))
	return {"amount": result, "key": key, "generation": _fraction_generation, "remainder": maxf(0.0, accumulated - float(result)) if round_down else accumulated - float(result)}

func commit_damage(prepared: Dictionary) -> void:
	if int(prepared.get("generation", -1)) == _fraction_generation and not String(prepared.get("key", "")).is_empty():
		_remainders[prepared.key] = float(prepared.remainder)

func network_state() -> Dictionary:
	_refresh_identity()
	_revision += 1
	var mark_records: Array = []
	for entry: Dictionary in marks.values():
		mark_records.append([int(entry.owner), String(entry.source), float(entry.ratio), float(entry.left)])
	var dread_records: Array = []
	for owner: int in dread.keys():
		dread_records.append([owner, int(dread[owner])])
	return {"run": _run, "r": _room, "q": _revision, "m": mark_records, "d": dread_records}

func network_packet() -> PackedByteArray:
	if not _had_status:
		return PackedByteArray()
	var state := network_state()
	var run_bytes := _run.to_utf8_buffer()
	if run_bytes.size() > 128:
		return PackedByteArray()
	var packet := PackedByteArray()
	packet.resize(20 + run_bytes.size() + state.m.size() * 13 + state.d.size() * 5)
	packet.encode_s64(0, int(state.q))
	packet.encode_s64(8, _room)
	packet.encode_u16(16, run_bytes.size())
	packet[18] = state.m.size()
	packet[19] = state.d.size()
	var offset := 20
	for value: int in run_bytes:
		packet[offset] = value
		offset += 1
	for entry: Array in state.m:
		packet.encode_s32(offset, int(entry[0]))
		packet[offset + 4] = MARK_SOURCES.find(String(entry[1]))
		packet.encode_float(offset + 5, float(entry[2]))
		packet.encode_float(offset + 9, float(entry[3]))
		offset += 13
	for entry: Array in state.d:
		packet.encode_s32(offset, int(entry[0]))
		packet[offset + 4] = int(entry[1])
		offset += 5
	return packet

func apply_network_packet(packet: PackedByteArray) -> bool:
	if packet.size() < 20:
		return false
	var run_size := packet.decode_u16(16)
	var mark_count := int(packet[18])
	var dread_count := int(packet[19])
	if run_size > 128 or mark_count > MAX_MARKS or dread_count > MAX_OWNERS or packet.size() != 20 + run_size + mark_count * 13 + dread_count * 5:
		return false
	var state := {"run": packet.slice(20, 20 + run_size).get_string_from_utf8(), "r": packet.decode_s64(8), "q": packet.decode_s64(0), "m": [], "d": []}
	var offset := 20 + run_size
	for index in range(mark_count):
		var source_index := int(packet[offset + 4])
		if source_index >= MARK_SOURCES.size():
			return false
		state.m.append([packet.decode_s32(offset), MARK_SOURCES[source_index], packet.decode_float(offset + 5), packet.decode_float(offset + 9)])
		offset += 13
	for index in range(dread_count):
		state.d.append([packet.decode_s32(offset), int(packet[offset + 4])])
		offset += 5
	return apply_network_state(state)

func apply_network_state(payload: Dictionary) -> bool:
	_refresh_identity()
	if payload.get("run") != _run or payload.get("r") != _room or not (payload.get("q") is int) or int(payload.q) <= _received_revision:
		return false
	if not (payload.get("m") is Array) or not (payload.get("d") is Array) or payload.m.size() > MAX_MARKS or payload.d.size() > MAX_OWNERS:
		return false
	var next_marks: Dictionary = {}
	var next_dread: Dictionary = {}
	for entry: Variant in payload.m:
		if not (entry is Array) or entry.size() != 4 or not (entry[0] is int) or int(entry[0]) <= 0 or entry[1] not in MARK_SOURCES:
			return false
		if not _number(entry[2]) or not _number(entry[3]) or float(entry[2]) <= 0.0 or float(entry[2]) > 1.0 or float(entry[3]) <= 0.0 or float(entry[3]) > 30.0:
			return false
		var key := "%d:%s" % [entry[0], entry[1]]
		if next_marks.has(key):
			return false
		next_marks[key] = {"owner": entry[0], "source": entry[1], "ratio": float(entry[2]), "left": float(entry[3])}
	for entry: Variant in payload.d:
		if not (entry is Array) or entry.size() != 2 or not (entry[0] is int) or not (entry[1] is int) or int(entry[0]) <= 0 or int(entry[1]) < 0 or int(entry[1]) > 15 or next_dread.has(entry[0]):
			return false
		next_dread[entry[0]] = entry[1]
	marks = next_marks
	dread = next_dread
	_received_revision = int(payload.q)
	queue_redraw()
	return true

func _draw() -> void:
	var strongest := 0.0
	for entry: Dictionary in marks.values():
		strongest = maxf(strongest, float(entry.ratio))
	if strongest <= 0.0:
		return
	var stacks := 0
	for count: int in dread.values():
		stacks = maxi(stacks, count)
	var radius := marker_radius()
	var intensity := minf(1.0, float(stacks) / 15.0)
	var color := Color(0.87, 0.68, 0.93).lerp(Color(0.98, 0.84, 1.0), intensity * 0.65)
	var edge := 8.5 + intensity * 1.5
	# Open diamond corners identify vulnerability without covering the body or
	# sharing the circular language of Slow, lightning and enemy warnings.
	for index in range(4):
		var angle := float(index) * PI * 0.5
		var direction := Vector2.from_angle(angle)
		var tangent := direction.orthogonal()
		var tip := direction * radius
		var corner := PackedVector2Array([tip - direction * edge - tangent * edge, tip, tip - direction * edge + tangent * edge])
		draw_polyline(corner, Color(0.07, 0.03, 0.10, 0.96), 5.5, true)
		draw_polyline(corner, color, 2.6 + intensity * 0.4, true)

func marker_radius() -> float:
	var target := get_parent() as CollisionObject2D
	return maxf(24.0, BODY_GEOMETRY.body_radius(target) + 11.0) if is_instance_valid(target) else 24.0

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
