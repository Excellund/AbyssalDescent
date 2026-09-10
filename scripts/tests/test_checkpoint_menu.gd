extends SceneTree
## Real menu controls and RunContext delegation; only storage I/O and scene
## replacement are intercepted. Every checkpoint remains inside this fixture.
const MENU := preload("res://scripts/menu_controller.gd")
const STORE := preload("res://scripts/core/active_run_checkpoint_store.gd")
const META := preload("res://scripts/meta_progress_store.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const AUDIO := preload("res://scripts/tests/fixture_audio_retirement.gd")

class FaultStore extends "res://scripts/core/active_run_checkpoint_store.gd":
	var deny_read: bool = false
	var deny_clear: bool = false
	func _open_file(path: String, mode: int) -> FileAccess:
		if deny_read and mode == FileAccess.READ and path == save_path:
			return null
		if deny_clear and mode == FileAccess.WRITE:
			return null
		return super._open_file(path, mode)
	func _remove_file(path: String) -> bool:
		return false if deny_clear else super._remove_file(path)

class FixtureMenu extends "res://scripts/menu_controller.gd":
	var scene_entries: int = 0
	var checkpoint_before_clear: Dictionary = {}
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_build_ui()
		_apply_menu_layout()
		_consume_checkpoint_menu_error()
		set_process(false)
	func _change_to_gameplay_scene() -> void:
		scene_entries += 1
	func _clear_saved_run() -> bool:
		if not checkpoint_before_clear.is_empty():
			# Model a checkpoint appearing after the primary-button presence probe.
			var file := FileAccess.open(RunContext._active_run_save_path(), FileAccess.WRITE)
			file.store_var({"version": 1, "snapshot": checkpoint_before_clear.duplicate(true)})
			file.close()
			checkpoint_before_clear.clear()
		return super._clear_saved_run()

var checks: int = 0
var failures: Array[String] = []
var retirement := AUDIO.new()
var menu: FixtureMenu
var store: FaultStore
var previous_store: STORE
var snapshot := {"version": 1, "marker": "menu-checkpoint", "rooms_cleared": 7, "room_depth": 8, "run_mode": ENUMS.RunMode.STANDARD}

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _prepare_menu() -> void:
	node_added.connect(retirement.observe_node)
	RunContext.telemetry_upload_enabled = false
	RunContext.meta_progress_profile = META._get_default_profile()
	RunContext.current_difficulty_tier = 1
	RunContext.selected_character_id = "bastion"
	RunContext.clear_resume_saved_run_request()
	previous_store = RunContext.active_run_checkpoint_store
	store = FaultStore.new()
	RunContext.active_run_checkpoint_store = store
	check(RunContext.clear_active_run(), "Fixture begins with no active checkpoint")
	menu = FixtureMenu.new()
	root.add_child(menu)
	current_scene = menu

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	_prepare_menu()
	await _test_normal_and_read_failure()
	await _test_invalid_and_discard()
	await _test_new_run_clear_failure()
	await _test_handoff_and_coop()
	await _release_menu()
	print("[OK] Checkpoint menu: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_normal_and_read_failure() -> void:
	check(menu.primary_run_button.text == "Begin Descent" and not menu.checkpoint_status_label.visible and not menu.checkpoint_discard_button.visible, "Normal menu retains its original primary action and no error controls")
	RunContext.run_mode = ENUMS.RunMode.ENDLESS
	menu.primary_run_button.pressed.emit()
	await _settle()
	check(menu.character_selector_panel.visible and menu.scene_entries == 0 and RunContext.run_mode == ENUMS.RunMode.STANDARD, "Successful Begin opens normal character selection before entering gameplay")
	menu._show_root_panel(false)
	check(RunContext.save_active_run(snapshot), "Real store publishes a supported checkpoint")
	var save_hash := FileAccess.get_sha256(RunContext._active_run_save_path())
	menu._refresh_primary_run_button()
	check(menu.primary_run_button.text == "Resume Descent", "Supported checkpoint offers Resume")
	menu.primary_run_button.pressed.emit()
	check(menu.scene_entries == 1 and RunContext.consume_resume_saved_run_request(), "Validated Resume requests one real scene entry and a one-use resume request")
	check(FileAccess.get_sha256(RunContext._active_run_save_path()) == save_hash, "Successful Resume preserves checkpoint bytes")
	store.deny_read = true
	menu._refresh_primary_run_button()
	check(menu.primary_run_button.text == "Resume Descent", "An unreadable primary remains a resume candidate")
	RunContext.run_mode = ENUMS.RunMode.ENDLESS
	menu.primary_run_button.pressed.emit()
	check(menu.scene_entries == 1 and not RunContext.consume_resume_saved_run_request() and RunContext.run_mode == ENUMS.RunMode.ENDLESS, "Failed Resume enters no scene, sets no request and preserves run mode")
	check(menu.root_panel.visible and not menu.character_selector_panel.visible and menu.primary_run_button.text == "Retry Resume", "Failed Resume stays on the root menu with a truthful retry action")
	check(FileAccess.get_sha256(RunContext._active_run_save_path()) == save_hash and menu.checkpoint_status_label.visible, "Read failure leaves checkpoint bytes and visible recovery text")
	for size in [Vector2i(960, 720), Vector2i(1280, 720)]:
		await _check_error_layout(size)
	store.deny_read = false
	menu.primary_run_button.pressed.emit()
	check(menu.scene_entries == 2 and RunContext.consume_resume_saved_run_request() and not menu.checkpoint_status_label.visible, "Retry Resume succeeds after storage recovers and removes the old error")

func _write_primary_record(payload: Dictionary) -> void:
	var file := FileAccess.open(RunContext._active_run_save_path(), FileAccess.WRITE)
	file.store_var(payload)
	file.close()

func _test_invalid_and_discard() -> void:
	for version in [1, 999]:
		_write_primary_record({"version": version, "snapshot": [] if version == 1 else snapshot})
		var save_hash := FileAccess.get_sha256(RunContext._active_run_save_path())
		menu._clear_checkpoint_error()
		check(menu.primary_run_button.text == "Resume Descent", "Invalid/future-format checkpoint cannot become an automatic fresh start")
		menu.primary_run_button.pressed.emit()
		check(menu.scene_entries == 2 and menu.checkpoint_discard_button.visible and not RunContext.consume_resume_saved_run_request(), "Invalid/future-format Resume offers an explicit discard escape without starting a game")
		check(FileAccess.get_sha256(RunContext._active_run_save_path()) == save_hash, "Failed validation preserves the original checkpoint bytes")
	store.deny_clear = true
	var before_discard_hash := FileAccess.get_sha256(RunContext._active_run_save_path())
	RunContext.request_resume_saved_run()
	menu.checkpoint_discard_button.pressed.emit()
	check(menu.scene_entries == 2 and menu.checkpoint_discard_button.visible and FileAccess.get_sha256(RunContext._active_run_save_path()) == before_discard_hash, "Failed explicit discard stays on the menu with its checkpoint byte-for-byte intact")
	check(RunContext.consume_resume_saved_run_request(), "Failed clear does not discard an existing resume request")
	check(menu.checkpoint_status_label.text.contains("Could not discard") and menu.checkpoint_discard_button.has_focus(), "Failed discard reports its own action and retains keyboard retry focus")
	store.deny_clear = false
	menu.checkpoint_discard_button.pressed.emit()
	check(not RunContext.has_saved_run() and menu.primary_run_button.text == "Begin Descent" and not menu.checkpoint_discard_button.visible, "Successful explicit discard restores the normal Begin action")
	check(menu.scene_entries == 2 and not menu.character_selector_panel.visible, "Discard does not unexpectedly start a fresh descent")
	# A save can disappear after the menu displayed Resume; keep that click's intent.
	menu._on_continue_pressed()
	check(menu.scene_entries == 2 and menu.primary_run_button.text == "Retry Resume" and menu.checkpoint_status_label.text.contains("unavailable"), "A requested missing checkpoint cannot fall through to new-game selection")
	menu._clear_checkpoint_error()

func _test_new_run_clear_failure() -> void:
	store.deny_clear = true
	menu.checkpoint_before_clear = snapshot.duplicate(true)
	RunContext.run_mode = ENUMS.RunMode.ENDLESS
	menu.primary_run_button.pressed.emit()
	check(menu.scene_entries == 2 and not menu.character_selector_panel.visible and RunContext.run_mode == ENUMS.RunMode.ENDLESS, "A failed clear between presence probe and Begin preserves menu and run mode")
	check(menu.primary_run_button.text == "Retry Begin Descent" and not menu.checkpoint_discard_button.visible, "Begin retry preserves the requested action instead of silently switching to Resume")
	store.deny_clear = false
	menu.primary_run_button.pressed.emit()
	await _settle()
	check(menu.character_selector_panel.visible and RunContext.run_mode == ENUMS.RunMode.STANDARD and not RunContext.has_saved_run(), "Retry Begin only opens selection after durable clear succeeds")
	menu._show_root_panel(false)
	check(RunContext.save_active_run(snapshot), "Real checkpoint restored before Endless clear test")
	store.deny_clear = true
	menu._on_endless_pressed()
	check(menu.scene_entries == 2 and RunContext.run_mode == ENUMS.RunMode.STANDARD and menu.primary_run_button.text == "Retry Endless Descent", "Failed Endless clear preserves the selected mode and creates no gameplay scene")
	store.deny_clear = false
	menu.primary_run_button.pressed.emit()
	check(menu.scene_entries == 3 and RunContext.run_mode == ENUMS.RunMode.ENDLESS and not RunContext.has_saved_run(), "Retry Endless clears first and enters the requested mode exactly once")

func _test_handoff_and_coop() -> void:
	RunContext.set_meta("checkpoint_menu_error", "Could not resume this checkpoint. Try again.")
	menu._consume_checkpoint_menu_error()
	check(not RunContext.has_meta("checkpoint_menu_error") and menu.checkpoint_status_label.visible and menu.primary_run_button.text == "Retry Resume", "World failure handoff is consumed once into the existing menu")
	check(RunContext.save_active_run(snapshot), "Suspended solo checkpoint exists before opening co-op menu")
	var save_hash := FileAccess.get_sha256(RunContext._active_run_save_path())
	store.deny_read = true
	store.deny_clear = true
	RunContext.request_resume_saved_run()
	menu._on_multiplayer_pressed()
	await _settle()
	check(menu.multiplayer_panel.visible and menu.scene_entries == 3, "Checkpoint failure does not block the existing Multiplayer menu")
	check(FileAccess.get_sha256(RunContext._active_run_save_path()) == save_hash, "Opening Multiplayer never clears or rewrites the suspended solo checkpoint")
	check(RunContext.consume_resume_saved_run_request(), "Opening Multiplayer preserves the separate solo resume request")
	store.deny_read = false
	store.deny_clear = false
	menu._show_root_panel(false)
	# A readable primary is valid even when retiring its recovery file fails.
	var backup := FileAccess.open(RunContext._active_run_save_path() + ".bak", FileAccess.WRITE)
	backup.store_var({"version": 1, "snapshot": {"marker": "older"}})
	backup.close()
	store.deny_clear = true
	menu._clear_checkpoint_error()
	menu.primary_run_button.pressed.emit()
	check(menu.scene_entries == 4 and RunContext.consume_resume_saved_run_request() and RunContext.get_active_run_status() == STORE.CLEANUP_FAILED, "Validated primary still resumes when only recovery cleanup fails")
	check(FileAccess.get_sha256(RunContext._active_run_save_path()) == save_hash, "Cleanup warning does not replace the validated primary")
	store.deny_clear = false

func _check_error_layout(viewport_size: Vector2i) -> void:
	root.size = viewport_size
	root.content_scale_size = viewport_size
	await _settle()
	menu._apply_menu_layout()
	await _settle()
	var label := menu.checkpoint_status_label
	check(label.visible and label.get_line_count() == label.get_visible_line_count(), "Full checkpoint message is visible at " + str(viewport_size))
	check(menu.root_panel.get_global_rect().encloses(label.get_global_rect()) and Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(menu.root_panel.get_global_rect()), "Checkpoint error and menu fit the viewport at " + str(viewport_size))
	check(menu.primary_run_button.get_global_rect().end.y <= label.get_global_rect().position.y and label.get_global_rect().end.y <= menu.checkpoint_discard_button.get_global_rect().position.y, "Retry, message and discard do not overlap at " + str(viewport_size))
	check(menu.primary_run_button.has_focus() and not label.text.contains("user://") and not label.text.contains(".save"), "Error keeps actionable focus and avoids raw storage details")
	for action: Control in menu.root_actions.get_children():
		if action.visible:
			check(menu.root_panel.get_global_rect().encloses(action.get_global_rect()) and Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(action.get_global_rect()), "Every visible menu action remains available at %s: %s" % [viewport_size, action.get_class()])

func _release_menu() -> void:
	store.deny_read = false
	store.deny_clear = false
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	RunContext.active_run_checkpoint_store = previous_store
	current_scene = null
	menu.queue_free()
	await _settle()
	check(await retirement.wait_until_retired(self), "Menu fixture releases all native audio")
