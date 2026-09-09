extends SceneTree

const MODAL := preload("res://scripts/ui/profile/profile_name_entry_modal.gd")
const LEADERBOARD := preload("res://scripts/ui/leaderboard/leaderboard_panel.gd")

class ThemedStyle extends RefCounted:
	var last_button_id := 0
	func _make_panel_back_button() -> Button:
		var button := Button.new()
		button.text = "Themed Back"
		button.custom_minimum_size = Vector2(198, 53)
		last_button_id = button.get_instance_id()
		return button

class EmptyStyle extends RefCounted:
	func _make_panel_back_button() -> Variant:
		return null

var checks := 0
var failures: Array[String] = []
var back_count := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _run() -> void:
	var orphan_baseline := Node.get_orphan_node_ids().size()
	for error_when_freed in [false, true]:
		var modal := MODAL.new()
		root.add_child(modal)
		modal.show_prompt("Name", "Choose name", "FixturePilot", true)
		await _settle()
		var error_id := modal._error_label.get_instance_id()
		var stack := modal._name_input.get_parent() as VBoxContainer
		var clear_size := stack.get_combined_minimum_size()
		check(not modal._error_label.visible, "Clear error begins hidden")
		check(modal._error_label.get_parent() == stack, "Modal owns inactive error Label")
		modal.show_validation_error("Use three or more characters.")
		await _settle()
		var first_error_size := stack.get_combined_minimum_size()
		check(modal._error_label.visible and modal._error_label.text == "Use three or more characters.", "Real validation error appears with its text")
		check(modal._error_label.get_index() == stack.get_child_count() - 1 and stack.get_child(stack.get_child_count() - 2) is HBoxContainer, "Error retains original placement after action buttons")
		check(first_error_size.y > clear_size.y, "Visible validation error takes layout space")
		modal.clear_error()
		await _settle()
		check(not modal._error_label.visible and modal._error_label.text.is_empty(), "Clear hides and resets validation")
		check(stack.get_combined_minimum_size().is_equal_approx(clear_size), "Cleared error consumes exactly zero extra layout space")
		modal.show_validation_error("Use three or more characters.")
		await _settle()
		check(stack.get_combined_minimum_size().is_equal_approx(first_error_size), "Repeated error restores identical layout size")
		check(modal._error_label.get_instance_id() == error_id, "Error clear/show reuses the same owned Label")
		if not error_when_freed:
			modal.hide_prompt()
			await _settle()
		modal.queue_free()
		await _settle()
		check(not is_instance_id_valid(error_id), "Actual modal teardown frees hidden or visible error Label")
		check(Node.get_orphan_node_ids().size() == orphan_baseline, "Profile modal returns orphan count to baseline")
	for style in [null, ThemedStyle.new(), EmptyStyle.new()]:
		var board := LEADERBOARD.new()
		root.add_child(board)
		board._build_ui(style)
		board.back_pressed.connect(func(): back_count += 1)
		await _settle()
		var stack := board.get_child(0).get_child(0)
		var button := stack.get_child(stack.get_child_count() - 1) as Button
		check(button != null and button.get_parent() == stack, "Leaderboard owns final Back button")
		if style is ThemedStyle:
			check(button.get_instance_id() == style.last_button_id and button.text == "Themed Back" and button.custom_minimum_size == Vector2(198, 53), "Themed Back preserves actual provided Button and styling")
		else:
			check(button.text == "Back" and button.custom_minimum_size == Vector2(180, 46), "Null or unsupported theme uses original fallback Back")
		var previous_back_count := back_count
		button.pressed.emit()
		check(back_count == previous_back_count + 1, "Back button emits the production Back event once")
		var button_id := button.get_instance_id()
		board.queue_free()
		await _settle()
		check(not is_instance_id_valid(button_id), "Leaderboard teardown frees final themed/fallback Button")
		check(Node.get_orphan_node_ids().size() == orphan_baseline, "Leaderboard creates no abandoned fallback Button")
	print("[MenuHelperOwnership] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
