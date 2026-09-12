extends SceneTree

const HISTORY := preload("res://scripts/core/run_history_store.gd")
const FIXTURE := preload("res://scripts/tests/test_run_history_archive.gd")
const META := preload("res://scripts/meta_progress_store.gd")
const AUDIO := preload("res://scripts/tests/fixture_audio_retirement.gd")

class FixtureMenu extends "res://scripts/menu_controller.gd":
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		_build_ui()
		_apply_menu_layout()
		set_process(false)

var checks := 0
var failures: Array[String] = []
var retirement := AUDIO.new()

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func settle() -> void:
	for _i in range(8):
		await process_frame

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	RunContext.meta_progress_profile = META._get_default_profile()
	HISTORY.clear_all()
	var data := FIXTURE.records()
	for i in range(data.size() - 1, -1, -1):
		HISTORY.append(data[i])
	var viewport := root
	viewport.size = Vector2i(1280, 720)
	viewport.content_scale_size = Vector2i(2560, 1440)
	var menu := FixtureMenu.new()
	viewport.add_child(menu)
	await settle()
	menu._show_history_panel()
	await settle()
	var panel = menu.history_panel
	var folder := project_path.path_join("run_history_archive_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array[Dictionary] = []
	for size in [Vector2i(960, 720), Vector2i(1280, 720)]:
		viewport.size = size
		await settle()
		menu._apply_menu_layout()
		for state in ["all", "journey", "damage", "empty"]:
			panel._reset_filters()
			panel._row_buttons[0].pressed.emit()
			if state == "empty":
				panel._mode_filter.select(2)
				panel._mode_filter.item_selected.emit(2)
				panel._outcome_filter.select(1)
				panel._outcome_filter.item_selected.emit(1)
			elif state == "damage":
				panel._row_buttons[1].pressed.emit()
			await settle()
			if state == "journey":
				panel._detail_scroll.scroll_vertical = 99999
				await settle()
			elif state == "damage":
				for label: Label in panel._detail_content.find_children("*", "Label", true, false):
					if label.text == "Final · Pyre · death field · 22 HP lost":
						panel._detail_scroll.ensure_control_visible(label)
				await settle()
			var stretch := root.get_stretch_transform()
			check(Rect2(Vector2.ZERO, Vector2(size)).grow(1).encloses(stretch * panel.get_global_rect()), "Actual menu fits physical window %s: panel=%s, visible=%s, stretch=%s" % [size, stretch * panel.get_global_rect(), root.get_visible_rect(), stretch])
			check(panel._outcome_filter.get_theme_font_size("font_size") * panel.get_global_transform().get_scale().x * stretch.get_scale().x >= 14.0, "Filter text stays readable on production canvas")
			var filters: Control = panel._outcome_filter.get_parent()
			check(panel.get_global_rect().grow(1).encloses(filters.get_global_rect()), "Filters fit panel")
			for control: Control in filters.get_children():
				check(filters.get_global_rect().grow(1).encloses(control.get_global_rect()), "Filter control fits row")
				check(control.size.x >= control.get_combined_minimum_size().x, "Filter control respects its minimum width")
			check(panel.find_children("*", "LineEdit", true, false).is_empty(), "History has no search input")
			check(panel._detail_panel.get_global_rect().position.x >= (panel._list_container.get_parent() as Control).get_global_rect().end.x, "History columns do not overlap")
			if state == "journey":
				var visible_journey := false
				for label: Label in panel._detail_content.find_children("*", "Label", true, false):
					if label.text == "Depth 6  ·  Static Wake":
						visible_journey = panel._detail_scroll.get_global_rect().grow(1).encloses(label.get_global_rect())
				check(visible_journey, "Last build decision is reachable by scrolling")
			if state == "empty":
				check(panel._empty_label.visible and panel._row_buttons.is_empty(), "Empty filter result is visible and hides stale rows")
			await RenderingServer.frame_post_draw
			var filename := "%s_%d.png" % [state, size.x]
			check(viewport.get_texture().get_image().save_png(folder.path_join(filename)) == OK, "Captured " + filename)
			frames.append({"file": filename, "state": state, "size": [size.x, size.y]})
	menu.queue_free()
	await settle()
	check(await retirement.wait_until_retired(self), "Fixture audio retires")
	var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "frames": frames,
		"gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	print("Run history archive GPU: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
