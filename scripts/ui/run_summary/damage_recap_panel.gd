extends VBoxContainer

const RECAP := preload("res://scripts/core/damage_recap.gd")

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 7)

func set_summary(summary: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var view := RECAP.presentation(summary)
	visible = view.visible
	if not visible:
		return
	_add_label(view.title, 22, Color(1.0, 0.79, 0.72))
	_add_label(view.detail, 15, Color(0.68, 0.75, 0.84))
	for row in view.entries:
		var text := "%s · %d HP lost" % [row.label, row.health_lost]
		if row.is_final:
			text = "Final · " + text
		_add_label(text, 18, Color(1.0, 0.82, 0.76) if row.is_final else Color(0.88, 0.91, 0.96))
		_add_label(row.detail, 15, Color(0.68, 0.75, 0.84))

func _add_label(text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
