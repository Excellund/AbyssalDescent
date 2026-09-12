extends Panel
## Read-only view of the recorder's current-run Oath evidence.

const SCALED_FONT := preload("res://scripts/ui/scaled_ui_font.gd")
const STATE_LABELS := {
	"earned": "Already earned", "achieved": "Condition achieved",
	"on_track": "On track", "pending": "Still to do", "broken": "Ruled out this run",
	"unavailable": "Unavailable", "unverified": "Not yet verified",
}
signal back_requested

var provider: Callable
var heading: Label
var context_label: Label
var explanation: Label
var include_completed: CheckBox
var scroll: ScrollContainer
var rows_container: VBoxContainer
var back_button: Button
var shown_rows: Array[Dictionary] = []
var _snapshot: Dictionary = {}
var _refresh_elapsed: float = 0.0

func _ready() -> void:
	SCALED_FONT.apply_to(self)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111b29")
	style.border_color = Color("557b9e")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)
	var header := HBoxContainer.new()
	stack.add_child(header)
	heading = _label("Oaths This Run", 28)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(100, 40)
	back_button.add_theme_font_size_override("font_size", 18)
	back_button.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back_button)
	context_label = _label("", 18)
	stack.add_child(context_label)
	explanation = _label("", 16)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_theme_color_override("font_color", Color("a9bdd1"))
	stack.add_child(explanation)
	include_completed = CheckBox.new()
	include_completed.text = "Include already earned Oaths"
	include_completed.add_theme_font_size_override("font_size", 16)
	include_completed.add_theme_icon_override("unchecked", _checkbox_icon(false))
	include_completed.add_theme_icon_override("checked", _checkbox_icon(true))
	include_completed.toggled.connect(func(_included: bool) -> void: _update_rows(true))
	stack.add_child(include_completed)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	stack.add_child(scroll)
	rows_container = VBoxContainer.new()
	rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_container.add_theme_constant_override("separation", 10)
	scroll.add_child(rows_container)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not provider.is_valid():
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.5:
		_refresh_elapsed = 0.0
		refresh()

func refresh() -> void:
	if not is_node_ready():
		return
	var value: Variant = provider.call() if provider.is_valid() else {}
	populate(value if value is Dictionary else {})

func populate(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	if context_label == null:
		return
	var seconds := maxi(0, int(snapshot.get("elapsed_seconds", 0)))
	var time_label := "Local elapsed" if bool(snapshot.get("is_joiner", false)) else "Run time"
	context_label.text = "%s  ·  %s  ·  %s %d:%02d" % [snapshot.get("character_name", "Current vessel"), snapshot.get("difficulty_label", "Current Bearing"), time_label, seconds / 60, seconds % 60]
	explanation.text = "Goals available to this run's vessel and Bearing. On-track goals still require a clear. Oaths are recorded when the run ends."
	if bool(snapshot.get("is_joiner", false)):
		explanation.text += " The host confirms boss, Hold the Line and timed goals at run end."
	_update_rows()

func _update_rows(force: bool = false) -> void:
	var next_rows: Array[Dictionary] = []
	var source: Variant = _snapshot.get("rows", [])
	if source is Array:
		for row: Variant in source:
			if row is Dictionary and bool(row.get("relevant", false)) and (include_completed.button_pressed or row.get("state") != "earned"):
				next_rows.append(row.duplicate(true))
	# Empty rows can mean missing evidence, all earned, or another setup.
	# Their explanation must refresh even when the filtered row list is equal.
	if not force and not next_rows.is_empty() and next_rows == shown_rows and rows_container.get_child_count() > 0:
		return
	var old_scroll := scroll.scroll_vertical
	var focused_id := ""
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and rows_container.is_ancestor_of(focus):
		focused_id = String(focus.get_meta("oath_id", ""))
	for child in rows_container.get_children():
		rows_container.remove_child(child)
		child.queue_free()
	shown_rows = next_rows
	if shown_rows.is_empty():
		var empty_text := "No Oaths are available to this run's setup."
		if _snapshot.is_empty():
			empty_text = "No current-run evidence is available."
		elif source is Array and source.any(func(row: Variant) -> bool: return row is Dictionary and bool(row.get("relevant", false)) and row.get("state") == "earned"):
			empty_text = "All Oaths available to this setup are already earned."
		var empty := _label(empty_text, 18)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows_container.add_child(empty)
	for row in shown_rows:
		var card := _make_row(row)
		rows_container.add_child(card)
		if not focused_id.is_empty() and String(row.get("id", "")) == focused_id:
			card.grab_focus()
	# Container sorting happens after this update; keep the reader's position.
	scroll.set_deferred("scroll_vertical", old_scroll)

func _make_row(row: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.focus_mode = Control.FOCUS_ALL
	card.set_meta("oath_id", row.get("id", ""))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("192738")
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", style)
	# PanelContainer draws only its panel StyleBox; a "focus" override would
	# never appear. Keep layout/fill identical while making focus visible.
	var focus_style := style.duplicate() as StyleBoxFlat
	focus_style.border_color = Color("badfff")
	focus_style.set_border_width_all(2)
	card.focus_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", focus_style))
	card.focus_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", style))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	card.add_child(stack)
	var title := _label(String(row.get("label", "Oath")), 20)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(title)
	var state := String(row.get("state", "unverified"))
	var status := _label(String(STATE_LABELS.get(state, STATE_LABELS.unverified)), 16)
	status.add_theme_color_override("font_color", _state_color(state))
	stack.add_child(status)
	var description := _label(String(row.get("description", "")), 18)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(description)
	var progress_text := String(row.get("progress_text", ""))
	if not progress_text.is_empty():
		var progress := _label(progress_text, 16)
		progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(progress)
	var detail := _label(String(row.get("detail", "")), 16)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color", Color("aec2d5"))
	stack.add_child(detail)
	return card

static func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("ecf3fa"))
	return label

static func _checkbox_icon(checked: bool) -> ImageTexture:
	var tick := '<path d="M5 10l3 3 7-7" fill="none" stroke="#baffcf" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' if checked else ""
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect x="1" y="1" width="18" height="18" rx="3" fill="#192738" stroke="#a9bdd1" stroke-width="2"/>%s</svg>' % tick
	var icon := Image.new()
	icon.load_svg_from_string(svg)
	return ImageTexture.create_from_image(icon)

static func _state_color(state: String) -> Color:
	match state:
		"earned", "achieved": return Color("a5e5b9")
		"on_track": return Color("a5d9ff")
		"broken": return Color("ffbca0")
		_: return Color("d4c9a7")
