extends VBoxContainer
class_name RunStatsPanel

const STAT_CARD_SCRIPT := preload("res://scripts/ui/run_summary/stat_card.gd")
const RESULT_FACTS := preload("res://scripts/ui/run_summary/run_result_facts.gd")

var _grid: GridContainer
var _title: Label

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	_title = Label.new()
	_title.text = "Run Stats"
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0, 0.98))
	add_child(_title)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	add_child(_grid)

func set_stats(stats: Dictionary, partial_history: bool = false) -> void:
	_title.text = "Stats since resuming" if partial_history else "Run Stats"
	for child in _grid.get_children():
		child.queue_free()
	for entry in [
		["damage_dealt_total", "Damage Dealt", Color(0.54, 0.94, 0.78, 1.0)],
		["damage_taken_total", "Damage Taken", Color(1.0, 0.72, 0.64, 1.0)],
		["enemies_killed", "Enemies Killed", Color(0.76, 0.88, 1.0, 1.0)],
		["bosses_defeated", "Bosses Defeated", Color(1.0, 0.84, 0.58, 1.0)]
	]:
		if RESULT_FACTS.is_recorded_count(stats.get(entry[0])):
			_add_card(entry[1], _format_number(stats[entry[0]]), entry[2])

func _add_card(title: String, value: String, color: Color) -> void:
	var card = STAT_CARD_SCRIPT.new()
	card.set_stat(title, value, color)
	_grid.add_child(card)

func _format_number(value: int) -> String:
	var abs_value := maxi(0, value)
	var text := str(abs_value)
	var result := ""
	var index := 0
	for i in range(text.length() - 1, -1, -1):
		result = text.substr(i, 1) + result
		index += 1
		if i > 0 and index % 3 == 0:
			result = "," + result
	return result
