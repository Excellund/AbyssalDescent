extends Node

signal back_to_main_menu_requested
signal retry_run_requested

const RUN_RESULTS_SCREEN_SCRIPT := preload("res://scripts/ui/run_summary/run_results_screen.gd")

var _results_screen

func show_defeat(room_label: String = "", depth: int = 0, run_summary: Dictionary = {}, allow_retry_run: bool = true) -> void:
	if _results_screen == null:
		_results_screen = RUN_RESULTS_SCREEN_SCRIPT.new()
		add_child(_results_screen)
		_results_screen.return_to_main_menu_requested.connect(func() -> void:
			back_to_main_menu_requested.emit()
		)
		_results_screen.retry_run_requested.connect(func() -> void:
			retry_run_requested.emit()
		)
	var summary := run_summary.duplicate(true)
	if int(summary.get("max_depth", 0)) <= 0:
		summary["max_depth"] = maxi(0, depth)
	if String(summary.get("death_event", {}).get("room_label", "")).is_empty() and not room_label.strip_edges().is_empty():
		summary["death_event"] = {
			"room_label": room_label
		}
	var death_label := String(summary.get("death_event", {}).get("room_label", room_label)).strip_edges()
	var subtitle := "Your run ended in %s. Regroup and descend again." % death_label if not death_label.is_empty() else "Your run ended. Regroup and descend again."
	_results_screen.show_result("Defeat", subtitle, summary, true, allow_retry_run)

func is_open() -> bool:
	return _results_screen != null and bool(_results_screen.is_open())
