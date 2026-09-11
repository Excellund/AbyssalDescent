extends Node

signal back_to_main_menu_requested
signal retry_run_requested

const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const BOSS_CATALOGUE := preload("res://scripts/shared/boss_catalogue.gd")
const RUN_RESULTS_SCREEN_SCRIPT := preload("res://scripts/ui/run_summary/run_results_screen.gd")

var _results_screen

func show_victory(_rooms_cleared: int, unlocked_tier: int = -1, run_summary: Dictionary = {}, allow_retry_run: bool = true) -> void:
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
	_results_screen.show_result("Victory", get_victory_subtitle(summary), summary, false, allow_retry_run)

static func get_victory_subtitle(summary: Dictionary) -> String:
	const FALLBACK := "The descent is complete."
	var defeated_ids: Variant = summary.get("defeated_boss_ids", [])
	if not defeated_ids is Array:
		return FALLBACK
	var final_boss_id := ""
	for value: Variant in defeated_ids:
		if not value is String or BOSS_CATALOGUE.stage_for_id(value) != 3:
			continue
		# An ambiguous or legacy record must not invent who spoke.
		if not final_boss_id.is_empty() and final_boss_id != value:
			return FALLBACK
		final_boss_id = value
	var line: String = BOSS_CATALOGUE.get_defeat_line(final_boss_id)
	if line.is_empty():
		return FALLBACK
	return "%s: \"%s\"" % [String(BOSS_CATALOGUE.NAMES[final_boss_id]), line]

func is_open() -> bool:
	return _results_screen != null and bool(_results_screen.is_open())

func set_retry_label(text: String) -> void:
	if _results_screen != null:
		_results_screen.set_retry_label(text)

func set_retry_disabled(disabled: bool) -> void:
	if _results_screen != null:
		_results_screen.set_retry_disabled(disabled)

func set_checkpoint_notice(message: String) -> void:
	if _results_screen != null:
		_results_screen.set_checkpoint_notice(message)
