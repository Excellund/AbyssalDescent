extends RefCounted
class_name PlayerCueSyncQueue

func copy_pending_events(pending_variant: Variant) -> Array[Dictionary]:
	var pending_events: Array[Dictionary] = []
	if pending_variant is Array:
		for entry in pending_variant:
			if entry is Dictionary:
				pending_events.append((entry as Dictionary).duplicate(true))
	return pending_events

func estimate_event_bytes(event_name: String, payload: Dictionary) -> int:
	return event_name.length() + var_to_str(payload).length() + 16

func can_fit_event(estimated_bytes: int, payload_budget_bytes: int) -> bool:
	return estimated_bytes <= payload_budget_bytes

func total_pending_bytes(pending_events: Array[Dictionary]) -> int:
	var pending_bytes := 0
	for existing_event in pending_events:
		pending_bytes += int(existing_event.get("estimated_bytes", 0))
	return pending_bytes

func requires_pre_flush(pending_events: Array[Dictionary], next_event_bytes: int, payload_budget_bytes: int) -> bool:
	if pending_events.is_empty():
		return false
	return total_pending_bytes(pending_events) + next_event_bytes > payload_budget_bytes

func build_event_entry(event_name: String, payload: Dictionary, reliable: bool, estimated_bytes: int) -> Dictionary:
	return {
		"event": event_name,
		"payload": payload,
		"reliable": reliable,
		"estimated_bytes": estimated_bytes
	}

func split_packets(pending_events: Array[Dictionary]) -> Dictionary:
	var unreliable_events: Array[Dictionary] = []
	var reliable_events: Array[Dictionary] = []
	var event_count := 0
	var estimated_bytes := 0
	for event_entry in pending_events:
		var event_name := String(event_entry.get("event", ""))
		var payload := event_entry.get("payload", {}) as Dictionary
		if event_name.is_empty() or payload.is_empty():
			continue
		var packet := {
			"event": event_name,
			"payload": payload
		}
		if bool(event_entry.get("reliable", false)):
			reliable_events.append(packet)
		else:
			unreliable_events.append(packet)
		event_count += 1
		estimated_bytes += int(event_entry.get("estimated_bytes", 0))
	return {
		"unreliable_events": unreliable_events,
		"reliable_events": reliable_events,
		"event_count": event_count,
		"estimated_bytes": estimated_bytes
	}
