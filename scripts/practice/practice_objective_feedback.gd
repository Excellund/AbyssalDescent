extends Node
## The shared Mission runtime can report a banner without creating run rewards.
var arena: Node

func show_banner(title: String, subtitle: String = "", _color: Color = Color.WHITE) -> void:
	if is_instance_valid(arena):
		arena.detail = title + (" — " + subtitle if not subtitle.is_empty() else "")
