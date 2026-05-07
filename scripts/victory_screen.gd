extends Node

signal back_to_main_menu_requested
signal retry_run_requested

const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const RUN_RESULTS_SCREEN_SCRIPT := preload("res://scripts/ui/run_summary/run_results_screen.gd")

var _results_screen

func show_victory(_rooms_cleared: int, unlocked_tier: int = -1, run_summary: Dictionary = {}) -> void:
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
	if unlocked_tier >= 0:
		var unlock_config := DIFFICULTY_CONFIG.get_tier_config(unlocked_tier)
		var unlock_name := String(unlock_config.get("name", "Unknown"))
		var unlocks := summary.get("unlocks", []) as Array
		var unlock_text := "Unlocked Bearing: %s" % unlock_name
		if not unlocks.has(unlock_text):
			unlocks.append(unlock_text)
		summary["unlocks"] = unlocks
	_results_screen.show_result("Victory", "Lacuna is defeated. The way back is clear.", summary, false)

func is_open() -> bool:
	return _results_screen != null and bool(_results_screen.is_open())
