extends PanelContainer
class_name LeaderboardEntryRow

var _rank_label: Label
var _bearing_label: Label
var _player_label: Label
var _character_label: Label
var _party_label: Label
var _patch_label: Label
var _time_label: Label
var _ended_label: Label

func _init() -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	_rank_label = _make_column(row, 56, HORIZONTAL_ALIGNMENT_CENTER)
	_bearing_label = _make_column(row, 90, HORIZONTAL_ALIGNMENT_LEFT)
	_player_label = _make_column(row, 160, HORIZONTAL_ALIGNMENT_LEFT)
	_character_label = _make_column(row, 120, HORIZONTAL_ALIGNMENT_LEFT)
	_party_label = _make_column(row, 64, HORIZONTAL_ALIGNMENT_CENTER)
	_patch_label = _make_column(row, 90, HORIZONTAL_ALIGNMENT_LEFT)
	_time_label = _make_column(row, 78, HORIZONTAL_ALIGNMENT_RIGHT)
	_ended_label = _make_column(row, 150, HORIZONTAL_ALIGNMENT_RIGHT)

func set_entry(entry: Dictionary, current_player_uuid: String) -> void:
	_rank_label.text = "#%d" % int(entry.get("rank", 0))
	_bearing_label.text = _bearing_label_for_tier(int(entry.get("difficulty_tier", 0)))
	_player_label.text = String(entry.get("player_name", "Player"))
	_character_label.text = String(entry.get("character_name", "Unknown"))
	var party_size := clampi(int(entry.get("player_count", 1)), 1, 4)
	_party_label.text = "Solo" if party_size <= 1 else "%dP" % party_size
	_patch_label.text = String(entry.get("leaderboard_patch_key", "dev"))
	_time_label.text = _format_duration(int(entry.get("duration_seconds", 0)))
	_ended_label.text = _format_timestamp(int(entry.get("ended_at_unix", 0)))
	var is_current := String(entry.get("player_uuid", "")).strip_edges().to_lower() == current_player_uuid.strip_edges().to_lower()
	_apply_row_style(is_current)

func _make_column(parent: HBoxContainer, min_width: float, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(min_width, 30.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.82, 0.92, 1.0, 0.94))
	parent.add_child(label)
	return label

func _apply_row_style(is_current: bool) -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	if is_current:
		style.bg_color = Color(0.22, 0.34, 0.50, 0.92)
		style.border_color = Color(1.0, 0.94, 0.66, 0.96)
	else:
		style.bg_color = Color(0.07, 0.11, 0.16, 0.84)
		style.border_color = Color(0.26, 0.42, 0.60, 0.58)
	add_theme_stylebox_override("panel", style)

func _bearing_label_for_tier(tier: int) -> String:
	match tier:
		0:
			return "Pilgrim"
		1:
			return "Delver"
		2:
			return "Harbinger"
		3:
			return "Forsworn"
		_:
			return "Pilgrim"

func _format_duration(total_seconds: int) -> String:
	var safe_total := maxi(0, total_seconds)
	var minutes := int(floor(float(safe_total) / 60.0))
	var seconds := safe_total % 60
	return "%02d:%02d" % [minutes, seconds]

func _format_timestamp(unix_time: int) -> String:
	if unix_time <= 0:
		return "-"
	var tz: Dictionary = Time.get_time_zone_from_system()
	var bias_minutes := int(tz.get("bias", 0))
	var dt := Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(dt.get("year", 0)),
		int(dt.get("month", 0)),
		int(dt.get("day", 0)),
		int(dt.get("hour", 0)),
		int(dt.get("minute", 0)),
	]
