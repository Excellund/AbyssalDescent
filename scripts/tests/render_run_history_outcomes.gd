extends SceneTree
## Actual Menu history panel, with only startup services suppressed. Records go
## through the normal isolated history store and native row selection signals.

const HISTORY := preload("res://scripts/core/run_history_store.gd")
const PANEL := preload("res://scripts/ui/run_history/run_history_panel.gd")
const META := preload("res://scripts/meta_progress_store.gd")
const AUDIO := preload("res://scripts/tests/fixture_audio_retirement.gd")
const CASES := [
	{"id": "abandon", "label": "Abandoned"},
	{"id": "clear", "label": "Victory"},
	{"id": "death", "label": "Defeat"},
	{"id": "host_left", "label": "Host disconnected"},
	{"id": "menu_exit", "label": "Returned to menu"},
	{"id": "quit", "label": "Exited game"},
	{"id": "future_boundary", "label": "Run ended"},
	{"id": "missing", "label": "Run ended"},
]

class FixtureMenu extends "res://scripts/menu_controller.gd":
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_build_ui()
		_apply_menu_layout()
		set_process(false)

var checks := 0
var failures: Array[String] = []
var retirement := AUDIO.new()
var viewport: SubViewport
var menu: FixtureMenu

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _settle(frame_count: int = 4) -> void:
	for _frame in range(frame_count):
		await process_frame

func _fixture_record(outcome: String) -> Dictionary:
	var record := {
		"run_id": "history-gpu-" + outcome, "outcome": outcome,
		"character_id": "veilstrider", "character_name": "Veilstrider",
		"difficulty_label": "Harbinger", "max_depth": 22,
		"rooms_cleared": 21, "duration_seconds": 1842,
		"is_multiplayer": true, "player_count": 4,
		"stats": {"enemies_killed": 187, "bosses_defeated": 2,
			"damage_dealt_total": 12456, "damage_taken_total": 185},
		"build_summary": {"arcana": [{"name": "Static Wake", "level": 3}],
			"boons": [{"name": "Heartstone", "level": 2}],
			"boss_rewards": [{"name": "Sovereign Double", "level": 1}]},
	}
	if outcome == "missing":
		record.erase("outcome")
	return record

func _rect_data(control: Control) -> Array:
	var rect := control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _check_layout(panel: PANEL, selected: Button, expected: Dictionary, size: Vector2i) -> void:
	var suffix := "%s at %s" % [expected.id, size]
	var list_scroll := panel._list_container.get_parent() as ScrollContainer
	var detail_scroll := panel._detail_content.get_parent() as ScrollContainer
	var headline := panel._detail_content.get_child(0) as Label
	check(Rect2(Vector2.ZERO, Vector2(size)).grow(1.0).encloses(panel.get_global_rect()), "Actual menu fits viewport: " + suffix)
	check(panel.get_global_rect().encloses(list_scroll.get_global_rect()) and panel.get_global_rect().encloses(panel._detail_panel.get_global_rect()), "Both history columns stay within menu: " + suffix)
	check(list_scroll.get_global_rect().end.x <= panel._detail_panel.get_global_rect().position.x, "List does not overlap detail: " + suffix)
	check(list_scroll.get_global_rect().grow(1.0).encloses(selected.get_global_rect()), "Selected native row is fully visible after scrolling: " + suffix)
	check(headline.text == String(expected.label) + " — Veilstrider", "Detail gives truthful outcome and character: " + suffix)
	check(detail_scroll.get_global_rect().grow(1.0).encloses(headline.get_global_rect()), "Complete detail heading fits its visible pane: " + suffix)
	check(headline.get_line_count() <= headline.get_visible_line_count(), "Detail heading displays every wrapped line: " + suffix)
	var row_labels := selected.find_children("*", "Label", true, false)
	var neutral := String(expected.id) not in ["clear", "death"]
	check(row_labels.size() == (3 if neutral else 2), "Outcome row keeps expected compact or neutral layout: " + suffix)
	var identity := row_labels[0] as Label
	check(identity.text.ends_with("Veilstrider  —  Co-op 4P"), "Longest character and co-op identity are retained: " + suffix)
	var expected_color := Color(0.68, 0.78, 0.90, 1.0)
	if expected.id == "clear":
		expected_color = Color(0.52, 0.88, 0.62, 1.0)
		check(identity.text.begins_with("✓ "), "Victory retains its check mark: " + suffix)
	elif expected.id == "death":
		expected_color = Color(0.90, 0.46, 0.46, 1.0)
		check(identity.text.begins_with("✗ "), "Defeat retains its cross: " + suffix)
	else:
		check(identity.text.begins_with("· ") and (row_labels[2] as Label).text == expected.label, "Neutral list row labels outcome without a defeat mark: " + suffix)
	check(identity.get_theme_color("font_color") == expected_color and headline.get_theme_color("font_color") == expected_color, "List and detail retain matching outcome colors: " + suffix)
	for node in row_labels:
		var label := node as Label
		check(selected.get_global_rect().grow(1.0).encloses(label.get_global_rect()), "Row label stays inside its button: %s / %s" % [suffix, label.text])
		var text_width := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size("font_size")).x
		check(text_width <= label.size.x + 1.0, "Row label fits without truncating identity or status: %s / %s" % [suffix, label.text])
	var mode_visible := false
	for node in panel._detail_content.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text == "Co-op (4 players)":
			mode_visible = detail_scroll.get_global_rect().grow(1.0).encloses(label.get_global_rect())
	check(mode_visible, "Co-op detail remains visible: " + suffix)
	var back: Button
	for node in panel.find_children("*", "Button", true, false):
		if (node as Button).text == "Back":
			back = node as Button
	check(back != null and panel.get_global_rect().grow(1.0).encloses(back.get_global_rect()) and not back.disabled, "Back remains fully visible and available: " + suffix)

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	RunContext.meta_progress_profile = META._get_default_profile()
	HISTORY.clear_all()
	for index in range(CASES.size() - 1, -1, -1):
		HISTORY.append(_fixture_record(String(CASES[index].id)))
	var records_before := HISTORY.load_all()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	menu = FixtureMenu.new()
	viewport.add_child(menu)
	await _settle()
	menu._show_history_panel()
	await _settle(30)
	var panel := menu.history_panel
	check(panel._row_buttons.size() == CASES.size() and not menu.root_panel.visible, "Actual Menu opens populated history from isolated records")
	var folder := project_path.path_join("run_history_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array[Dictionary] = []
	for size in [Vector2i(960, 720), Vector2i(1280, 720)]:
		viewport.size = size
		await _settle()
		menu._apply_menu_layout()
		await _settle()
		for index in range(CASES.size()):
			var expected: Dictionary = CASES[index]
			var selected: Button = panel._row_buttons[index]
			selected.pressed.emit()
			await _settle()
			var list_scroll := panel._list_container.get_parent() as ScrollContainer
			list_scroll.ensure_control_visible(selected)
			await _settle()
			_check_layout(panel, selected, expected, size)
			await RenderingServer.frame_post_draw
			var filename := "%s_%d.png" % [expected.id, size.x]
			var picture := viewport.get_texture().get_image()
			check(not picture.is_empty() and picture.save_png(folder.path_join(filename)) == OK, "Captured " + filename)
			frames.append({"file": filename, "size": [size.x, size.y], "outcome": expected.id,
				"label": expected.label, "panel_rect": _rect_data(panel), "row_rect": _rect_data(selected),
				"detail_rect": _rect_data(panel._detail_panel)})
	check(HISTORY.load_all() == records_before, "History rendering and selection never mutate persisted outcomes or summary fields")
	viewport.queue_free()
	await _settle()
	check(await retirement.wait_until_retired(self), "Fixture audio retires cleanly")
	var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "failures": failures, "checks": checks,
		"gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	print("[OK] History outcome frames: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
