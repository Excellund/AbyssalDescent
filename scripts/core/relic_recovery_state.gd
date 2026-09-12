extends RefCounted
## Small authoritative carrying state. Call advance only on the host; replicas
## consume bounded snapshots and render them without claiming pickups.

const RELIC_COUNT := 3
const PICKUP_RADIUS := 36.0
const RECEIVER_RADIUS := 68.0

var relics: Array[Dictionary] = []
var receiver := Vector2.ZERO
var completed := false

func reset() -> void:
	relics.clear()
	receiver = Vector2.ZERO
	completed = false

func begin(positions: Array, receiver_position: Vector2 = Vector2.ZERO) -> void:
	reset()
	receiver = receiver_position
	for index in mini(RELIC_COUNT, positions.size()):
		var position: Vector2 = positions[index]
		relics.append({"id": index, "position": position, "carrier_id": 0, "delivered": false, "awakened": false})

func delivered_count() -> int:
	var total := 0
	for relic in relics:
		if bool(relic.delivered):
			total += 1
	return total

func carrier_has_relic(player_id: int) -> bool:
	if player_id <= 0:
		return false
	for relic in relics:
		if int(relic.carrier_id) == player_id and not bool(relic.delivered):
			return true
	return false

## Roster entries contain stable player ID, reachable world position and living
## eligibility. Last observed positions remain available after a disconnect.
func advance(roster: Array[Dictionary]) -> Dictionary:
	var result := {"first_pickups": 0, "deposits": 0, "drops": 0, "completed": false}
	if completed or relics.size() != RELIC_COUNT:
		return result
	var players := {}
	for entry in roster:
		var id := int(entry.get("id", 0))
		if id > 0 and entry.get("position") is Vector2:
			players[id] = entry
	# Resolve existing carriers first, freeing their slot on deposit or defeat.
	for relic in relics:
		if bool(relic.delivered) or int(relic.carrier_id) <= 0:
			continue
		var carrier: Dictionary = players.get(int(relic.carrier_id), {})
		if not carrier.is_empty():
			relic.position = carrier.position
		if carrier.is_empty() or not bool(carrier.get("living", false)):
			relic.carrier_id = 0
			result.drops += 1
		elif (relic.position as Vector2).distance_to(receiver) <= RECEIVER_RADIUS:
			_deposit(relic)
			result.deposits += 1
	# Each relic is assigned once; closest eligible player wins, then lowest ID.
	for relic in relics:
		if bool(relic.delivered) or int(relic.carrier_id) > 0:
			continue
		var chosen_id := 0
		var chosen_distance := INF
		for id: int in players:
			var candidate: Dictionary = players[id]
			if not bool(candidate.get("living", false)) or carrier_has_relic(id):
				continue
			var distance := (candidate.position as Vector2).distance_to(relic.position)
			if distance > PICKUP_RADIUS:
				continue
			if distance < chosen_distance or (is_equal_approx(distance, chosen_distance) and (chosen_id == 0 or id < chosen_id)):
				chosen_id = id
				chosen_distance = distance
		if chosen_id == 0:
			continue
		relic.carrier_id = chosen_id
		relic.position = players[chosen_id].position
		if not bool(relic.awakened):
			relic.awakened = true
			result.first_pickups += 1
		if (relic.position as Vector2).distance_to(receiver) <= RECEIVER_RADIUS:
			_deposit(relic)
			result.deposits += 1
	if delivered_count() == RELIC_COUNT:
		completed = true
		result.completed = true
	return result

func _deposit(relic: Dictionary) -> void:
	relic.delivered = true
	relic.carrier_id = 0
	relic.position = receiver

func snapshot() -> Dictionary:
	return {"receiver": receiver, "relics": relics.duplicate(true), "completed": completed}

## Invalid/legacy data clears this objective's display instead of retaining
## cargo from a previous room. The ordered room envelope lives in World.
func apply_snapshot(value: Variant) -> void:
	reset()
	if not (value is Dictionary):
		return
	var raw_relics: Variant = value.get("relics", [])
	var raw_receiver: Variant = value.get("receiver", Vector2.ZERO)
	if not (raw_relics is Array) or raw_relics.size() != RELIC_COUNT or not (raw_receiver is Vector2) or not raw_receiver.is_finite():
		return
	var seen_carriers := {}
	for index in RELIC_COUNT:
		var raw: Variant = raw_relics[index]
		if not (raw is Dictionary) or int(raw.get("id", -1)) != index:
			reset()
			return
		var position: Variant = raw.get("position")
		if not (position is Vector2) or not position.is_finite():
			reset()
			return
		var delivered := bool(raw.get("delivered", false))
		var carrier_id := maxi(0, int(raw.get("carrier_id", 0))) if not delivered else 0
		if carrier_id > 0 and seen_carriers.has(carrier_id):
			reset()
			return
		if carrier_id > 0:
			seen_carriers[carrier_id] = true
		relics.append({"id": index, "position": position, "carrier_id": carrier_id, "delivered": delivered, "awakened": bool(raw.get("awakened", false))})
	receiver = raw_receiver
	completed = delivered_count() == RELIC_COUNT
