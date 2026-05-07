extends RefCounted
class_name PlayerFeedbackDispatcher

## Dispatches player cue events (VFX/UI/audio cues) received over multiplayer.
## Peer-local events target owner-only handlers, while remote events target network handlers.
func apply_cue_events(player_node: Node, peer_id: int, local_peer_id: int, events: Array[Dictionary]) -> void:
	if events.is_empty():
		return
	if peer_id == local_peer_id:
		for event_entry in events:
			var event_name := String(event_entry.get("event", ""))
			var payload := event_entry.get("payload", {}) as Dictionary
			if event_name.is_empty() or payload.is_empty():
				continue
			player_node.apply_owner_feedback_event(event_name, payload)
		return
	for event_entry in events:
		var event_name := String(event_entry.get("event", ""))
		var payload := event_entry.get("payload", {}) as Dictionary
		if event_name.is_empty() or payload.is_empty():
			continue
		player_node.apply_network_feedback_event(event_name, payload)
