extends RefCounted
## Fixture-only barrier for native audio playback retired by deleted scene owners.
## WeakRefs observe AudioServer cleanup without keeping playback or owner alive.
var _playbacks: Array[WeakRef] = []

func observe_node(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
		node.tree_exiting.connect(_capture_playback.bind(node))

func _capture_playback(node: Node) -> void:
	if bool(node.call("has_stream_playback")):
		_playbacks.append(weakref(node.call("get_stream_playback")))

func pending_count() -> int:
	var count := 0
	for playback_ref in _playbacks:
		if playback_ref.get_ref() != null:
			count += 1
	return count

func wait_until_retired(tree: SceneTree, timeout_seconds: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while pending_count() > 0:
		if Time.get_ticks_msec() >= deadline:
			return false
		await tree.process_frame
	return true
