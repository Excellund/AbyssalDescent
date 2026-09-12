extends SceneTree

const QUERY := preload("res://scripts/core/run_history_query.gd")
const PANEL := preload("res://scripts/ui/run_history/run_history_panel.gd")
const STORE := preload("res://scripts/core/run_history_store.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

static func records() -> Array:
	return [
		{"run_id": "a", "outcome": "clear", "character_name": "Veilstrider", "difficulty_label": "Harbinger",
			"max_depth": 30, "duration_seconds": 1820,
			"build_summary": {"arcana": [{"name": "Static Wake", "stacks": 2}]},
			"reward_timeline": [{"label": "Heartstone", "depth": 0, "category": "boon"},
				{"label": "Static Wake", "depth": 2, "category": "arcana"},
				{"label": "Rest Site", "depth": 4, "category": "rest"},
				{"label": "Static Wake", "depth": 6, "category": "arcana"}]},
		{"run_id": "b", "outcome": "death", "character_name": "Effigy Keeper", "difficulty_label": "Pilgrim",
			"player_count": 2, "build_summary": {"boss_rewards": [{"name": "Oathbreaker"}]},
			"damage_recap": {"version": 1, "peer_id": 2, "ending_health": 0, "ending_on_damage": true,
				"entries": [{"source": "enemy_ability", "ability": "archer_projectile", "health_before": 35,
					"health_after": 22, "elapsed_seconds": 180, "room_depth": 7},
					{"source": "enemy_ability", "ability": "pyre_death_field", "health_before": 22,
					"health_after": 0, "elapsed_seconds": 183, "room_depth": 7}]}},
		{"run_id": "c", "outcome": "host_left", "character_name": "Bastion", "is_multiplayer": true},
		{"run_id": "d", "character_name": "Voidfire", "reward_timeline": [null, 9, {"label": ""}, {"label": "Heartstone"}]},
	]

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	var data := records()
	var before := data.duplicate(true)
	check(QUERY.filter_records(data, "clear") == [data[0]], "Outcome filtering retains the recorded victories")
	check(QUERY.filter_records(data, "death", "coop") == [data[1]], "Outcome and mode filters combine")
	check(QUERY.filter_records(data, "all", "coop") == [data[1], data[2]], "Party count and explicit co-op both identify co-op")
	check(QUERY.filter_records(data, "all", "solo") == [data[0], data[3]], "Legacy records default to solo")
	check(QUERY.filter_records(data, "other") == [data[2], data[3]], "Unknown and disconnected outcomes are other endings, not defeats")
	check(QUERY.filter_records(data, "clear", "coop").is_empty(), "Crossed filters have a truthful empty result")
	check(QUERY.filter_records(data + [null, "bad", 7]).size() == 4, "Malformed top-level records are ignored")
	var journey := QUERY.journey(data[0])
	check(journey.size() == 4 and journey[1].label == journey[3].label and journey[2].label == "Rest Site", "Journey retains starting rewards, repeated upgrades and rests in recorded order")
	check(journey[0].depth == 0, "Known starting rewards retain their recorded depth zero")
	check(QUERY.journey(data[1]).is_empty(), "Legacy record does not invent build decisions")
	check(QUERY.journey(data[3]) == [{"label": "Heartstone", "depth": -1, "category": ""}], "Malformed journey entries are skipped and missing depth remains unknown")
	check(QUERY.journey({"reward_timeline": [{"label": "Unknown", "depth": -3}, {"label": "Malformed", "depth": "bad"}]}).all(func(entry: Dictionary) -> bool: return entry.depth == -1), "Invalid depths cannot masquerade as a known starting reward")
	check(QUERY.journey({"reward_timeline": "bad"}).is_empty(), "Wrong-shaped timeline is tolerated")
	journey[0].label = "edited view"
	check(data == before, "Read-only filtering and journey projection never mutate source records")
	STORE.clear_all()
	for i in range(data.size() - 1, -1, -1):
		STORE.append(data[i])
	var saved := STORE.load_all()
	var panel := PANEL.new()
	panel.size = Vector2(1000, 650)
	root.add_child(panel)
	panel._build_ui(null)
	panel.populate()
	await process_frame
	check(panel._records.size() == 4 and panel._selected_index == 0, "History initially opens all records with first selected")
	check(panel.find_children("*", "LineEdit", true, false).is_empty(), "History has no search input")
	panel._row_buttons[1].pressed.emit()
	panel._mode_filter.select(2)
	panel._mode_filter.item_selected.emit(2)
	check(panel._records.size() == 2 and panel._records[0].run_id == "b", "Native mode signal filters displayed runs")
	panel._outcome_filter.select(1)
	panel._outcome_filter.item_selected.emit(1)
	check(panel._records.is_empty() and panel._empty_label.visible and panel._count_label.text == "0 of 4 recorded runs", "Empty native filter clears detail and shows reset guidance")
	check(panel._detail_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Empty results do not retain a stale detail scrollbar")
	panel._reset_filters()
	panel._row_buttons[1].pressed.emit()
	panel._mode_filter.select(2)
	panel._mode_filter.item_selected.emit(2)
	check(panel._records.size() == 2 and panel._selected_index == 0 and panel._records[0].run_id == "b", "Filter preserves selected run when it remains visible")
	panel._reset_filters()
	check(panel._records.size() == 4 and panel._records[panel._selected_index].run_id == "b", "Reset restores rows while retaining selection")
	panel._row_buttons[0].pressed.emit()
	var labels: Array[String] = []
	for node in panel._detail_content.find_children("*", "Label", true, false):
		labels.append(node.text)
	check(labels.has("Build journey") and labels.has("Depth 4  ·  Rest Site") and labels.has("Depth 6  ·  Static Wake"), "Actual detail panel displays the ordered build journey")
	check(labels.has("Depth 0  ·  Heartstone"), "Actual starting reward is shown at known depth zero")
	check(STORE.load_all() == saved, "UI filtering never edits or removes persisted history")
	panel._row_buttons[1].pressed.emit()
	var recap_nodes := panel._detail_content.find_children("*", "Label", true, false)
	var has_final_damage := false
	for label: Label in recap_nodes:
		has_final_damage = has_final_damage or label.text == "Final · Pyre · death field · 22 HP lost"
	check(has_final_damage, "History shows the persisted local final damage through the shared recap view")
	panel.populate()
	check(panel._selected_index == 0, "Reopening history returns to the newest matching record")
	panel.queue_free()
	await process_frame
	print("Run history archive: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
