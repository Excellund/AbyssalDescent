extends SceneTree

const TRACKER := preload("res://scripts/core/run_summary_tracker.gd")
const RECORDER := preload("res://scripts/core/run_summary_recorder.gd")
const FACTS := preload("res://scripts/ui/run_summary/run_result_facts.gd")
const SCREEN := preload("res://scripts/ui/run_summary/run_results_screen.gd")
const HISTORY := preload("res://scripts/core/run_history_store.gd")
const HISTORY_PANEL := preload("res://scripts/ui/run_history/run_history_panel.gd")

class SummaryWorld extends Node:
	var current_player_profile: RefCounted = null
	var submitted: Dictionary = {}
	func _resolve_local_peer_id() -> int:
		return 2
	func _get_run_context() -> Node:
		return null
	func _enqueue_leaderboard_submission(value: Dictionary) -> void:
		submitted = value.duplicate(true)
var checks := 0
var failures: Array[String] = []
var viewport: SubViewport
var screen: SCREEN

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _settle() -> void:
	for _frame in 4:
		await process_frame

func fixture_summary() -> Dictionary:
	return {
		"reached_act": 3, "max_depth": 20, "duration_seconds": 842,
		"character_name": "Hexweaver", "difficulty_label": "Harbinger",
		"defeated_boss_ids": ["warden", "sovereign"],
		"stats": {"bosses_defeated": 2, "damage_dealt_total": 12456, "damage_taken_total": 185, "enemies_killed": 187},
		"build_summary": {
			"arcana": [{"id": "static_wake", "name": "Static Wake", "stacks": 3}, {"id": "storm_crown", "name": "Storm Crown", "stacks": 2}, {"id": "aegis_field", "name": "Aegis Pulse", "stacks": 1}],
			"boons": [{"id": "heavy_blow", "name": "Heavy Blow", "stacks": 3}, {"id": "heartstone", "name": "Heartstone", "stacks": 2}],
			"boss_rewards": [{"id": "sovereigns_double", "name": "Sovereign's Double", "stacks": 1}]
		},
		"unlocks": ["Oath Complete: Untouched by the Warden", "Catalyst Unlocked: Prismatic Arcana"],
		"reward_timeline": [{"depth": 0, "label": "Static Wake"}, {"depth": 3, "label": "Storm Crown"}, {"depth": 8, "label": "Sovereign's Double"}]
	}

func _prepare_screen() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	screen = SCREEN.new()
	viewport.add_child(screen)

func _check_layout(size: Vector2i) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(size))
	check(bounds.grow(1.0).encloses(screen._card.get_global_rect()), "Result card fits %s" % size)
	check(screen._card.get_global_rect().grow(1.0).encloses(screen._action_buttons.get_global_rect()), "Result actions remain inside card at %s" % size)
	check(screen._content_scroll.size.y >= 140.0, "Build remains visible below header at %s" % size)
	check(screen._title_label.get_global_rect().end.y <= screen._content_scroll.get_global_rect().position.y, "Act/depth remains above content")
	check(screen._build_panel.get_index() < screen._reward_panel.get_index() and screen._reward_panel.get_index() < screen._stats_panel.get_index(), "Build and progression precede supporting totals")
	for label: Label in [screen._title_label, screen._boss_label, screen._subtitle_label, screen._meta_label]:
		if label.visible:
			check(label.size.x <= screen._card.size.x and screen._card.get_global_rect().grow(1.0).encloses(label.get_global_rect()), "Header text fits card at %s: %s" % [size, label.text])

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	var tracker := TRACKER.new()
	tracker.reset_for_run({})
	check(tracker.reached_act == 1, "New run starts with recorded act one")
	tracker.record_act_entry(2)
	tracker.record_act_entry(1)
	tracker.record_act_entry(9)
	check(tracker.reached_act == 2, "Entered act only advances within campaign range")
	tracker.record_boss_defeat("sovereign")
	tracker.record_boss_defeat("warden")
	tracker.record_boss_defeat("warden")
	tracker.record_boss_defeat("unknown")
	check(tracker.defeated_boss_ids == ["sovereign", "warden"], "Only real canonical boss IDs are retained in recorded order without duplicates")
	check(tracker.bosses_defeated == 4, "Existing boss count semantics remain unchanged")
	var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(tracker.build_checkpoint()))
	var restored := TRACKER.new()
	restored.reset_for_run({})
	restored.restore_checkpoint(checkpoint)
	check(restored.reached_act == 2 and restored.defeated_boss_ids == ["sovereign", "warden"], "Checkpoint roundtrip retains identity facts, including JSON numbers")
	var summary: Dictionary = restored.build_summary({"max_depth": 12})
	check(summary.get("reached_act") == 2 and summary.get("defeated_boss_ids") == ["sovereign", "warden"], "Final summary exposes only recorded act and victories")
	restored.restore_checkpoint({"bosses_defeated": 2})
	summary = restored.build_summary({"max_depth": 20})
	check(not summary.has("reached_act") and not summary.has("defeated_boss_ids"), "Legacy checkpoint does not invent act or named victories from counts/depth")
	restored.record_act_entry(3)
	restored.record_boss_defeat("lacuna")
	check(restored.build_summary({}).defeated_boss_ids == ["lacuna"], "Legacy continuation records only newly observed boss identity")
	var recorder := RECORDER.new(null)
	recorder.run_summary_tracker.reset_for_run({})
	recorder.record_act_entry(2)
	check(recorder.run_summary_tracker.reached_act == 2, "Recorder exposes explicit room-entry API")
	recorder.restore_tracker_items_from_snapshot({})
	check(recorder.run_summary_tracker.reached_act == 0 and recorder.run_summary_tracker.defeated_boss_ids.is_empty(), "Legacy snapshot with no checkpoint clears new-run identity defaults")
	var legacy_summary: Dictionary = recorder.run_summary_tracker.build_summary({"max_depth": 15})
	check(legacy_summary.get("full_run_tracking_complete") == false and legacy_summary.stats.bosses_defeated == 0, "Real legacy restore preserves explicit incomplete history alongside reset counters")
	check(FACTS.boss_line(legacy_summary).is_empty(), "Legacy resume cannot advertise the reset zero as a complete run's boss total")
	recorder.run_summary_tracker.record_boss_defeat("lacuna")
	legacy_summary = recorder.run_summary_tracker.build_summary({"max_depth": 20})
	check(legacy_summary.stats.bosses_defeated == 1 and FACTS.boss_line(legacy_summary) == "Defeated: Lacuna", "Legacy continuation retains the observed boss name without promoting partial count to a run total")
	var legacy_checkpoint: Dictionary = JSON.parse_string(JSON.stringify(recorder.run_summary_tracker.build_checkpoint()))
	recorder.restore_tracker_items_from_snapshot({"tracker_checkpoint": legacy_checkpoint})
	check(FACTS.has_partial_history(recorder.run_summary_tracker.build_summary({})), "Later checkpoint roundtrip cannot erase the missing earlier history")
	check(FACTS.headline({"max_depth": 15}, "Defeat") == "Depth 15", "Legacy header never derives act from depth")
	check(FACTS.boss_line({"stats": {"bosses_defeated": 2}}) == "Bosses defeated · 2", "Legacy boss count never implies particular boss names")
	check(not FACTS.has_partial_history({}) and not FACTS.has_partial_history({"full_run_tracking_complete": "false"}), "Only an explicit boolean false marks partial history")
	check(FACTS.headline({}, "Defeat") == "Defeat" and FACTS.boss_line({}) == "" and FACTS.metadata({}) == "", "Missing data never appears as invented zeros, difficulty, duration or identity")
	check(FACTS.headline({"max_depth": 2.5, "reached_act": "3"}, "Defeat") == "Defeat", "Invalid identity facts are omitted")
	var json_summary: Dictionary = JSON.parse_string(JSON.stringify(fixture_summary()))
	check(FACTS.headline(json_summary, "Defeat") == "Act III · Depth 20", "History JSON numbers retain headline")
	check(FACTS.boss_line(json_summary).contains("Warden · Sovereign") and not FACTS.boss_line(json_summary).contains("Lacuna"), "Boss line includes only recorded identities")
	_test_peer_summary_flow()
	await _test_history_outcome_presentation()
	_prepare_screen()
	for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		screen.show_result("Defeat", "Run ended in Apex Breakwater.", json_summary, true)
		await _settle()
		# Finish entrance scale before measuring containment.
		screen._appearance_tween.custom_step(1.0)
		await _settle()
		_check_layout(size)
	check(screen._stats_panel._grid.get_child_count() == 4, "Recorded JSON totals remain available")
	screen.show_result("Defeat", "", legacy_summary, true)
	await _settle()
	check(screen._boss_label.text == "Defeated: Lacuna" and screen._stats_panel._title.text == "Stats since resuming", "Result screen qualifies partial statistics and retains the actual observed boss")
	screen.show_result("Defeat", "", {"max_depth": 3, "stats": {"bosses_defeated": 0}}, true, false)
	await _settle()
	check(screen._stats_panel._title.text == "Run Stats", "Reusing the result screen restores the ordinary heading for complete history")
	check(screen._stats_panel._grid.get_child_count() == 1, "Missing legacy totals do not become zero-valued cards")
	check(not screen._action_buttons._retry_button.visible, "Existing retry availability remains respected")
	check(not screen._build_panel.visible and not screen._reward_panel.visible, "Unavailable legacy build/progression are omitted")
	await _test_timeline_availability_reuse()
	var old_tween := screen._appearance_tween
	screen.show_result("Victory", "The descent is complete.", fixture_summary())
	check(not old_tween.is_valid(), "Reopening results cancels prior entrance tween")
	var screen_id := screen.get_instance_id()
	viewport.queue_free()
	await _settle()
	check(not is_instance_id_valid(screen_id), "Result owner and viewport connection retire during animation")
	print("[OK] Run result identity: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_history_outcome_presentation() -> void:
	var cases := [
		{"outcome": "clear", "label": "Victory", "marker": "\u2713 ", "color": Color(0.52, 0.88, 0.62, 1.0)},
		{"outcome": "death", "label": "Defeat", "marker": "\u2717 ", "color": Color(0.90, 0.46, 0.46, 1.0)},
		{"outcome": "abandon", "label": "Abandoned"},
		{"outcome": "host_left", "label": "Host disconnected"},
		{"outcome": "menu_exit", "label": "Returned to menu"},
		{"outcome": "quit", "label": "Exited game"},
		{"outcome": "future_outcome", "label": "Run ended"},
		{"outcome": "", "label": "Run ended"},
		{"label": "Run ended"},
	]
	HISTORY.clear_all()
	for i in range(cases.size() - 1, -1, -1):
		var record := fixture_summary()
		record["run_id"] = "history-outcome-%d" % i
		record["character_name"] = "Veilstrider"
		record["is_multiplayer"] = true
		record["player_count"] = 2
		if cases[i].has("outcome"):
			record["outcome"] = cases[i].outcome
		check(HISTORY.append(record), "History case persists through the actual JSON store: %d" % i)
	var before_hash := FileAccess.get_sha256(HISTORY.STORAGE_PATH)
	var panel := HISTORY_PANEL.new()
	root.add_child(panel)
	panel.size = Vector2(960, 720)
	panel._build_ui(null)
	panel.populate()
	await _settle()
	for i in range(cases.size()):
		var expected: Dictionary = cases[i]
		panel._row_buttons[i].pressed.emit()
		await _settle()
		var row: VBoxContainer = panel._row_buttons[i].get_child(0)
		var top: Label = row.get_child(0)
		var heading: Label = panel._detail_content.get_child(0)
		var neutral := not expected.has("marker")
		var color: Color = expected.get("color", Color(0.68, 0.78, 0.90, 1.0))
		check(heading.text == expected.label + " — Veilstrider", "Selected history detail reports its actual recorded outcome: %d" % i)
		check(top.get_theme_color("font_color") == color and heading.get_theme_color("font_color") == color, "List/detail agree on victory, defeat or neutral color: %d" % i)
		check(top.text == expected.get("marker", "\u00b7 ") + "Veilstrider  —  Co-op 2P", "History preserves character/co-op text with the correct outcome marker: %d" % i)
		check(row.get_child_count() == (3 if neutral else 2) and panel._row_buttons[i].custom_minimum_size.y == (78.0 if neutral else 58.0), "Only neutral outcomes add a distinct status line: %d" % i)
		if neutral:
			check(row.get_child(2).text == expected.label and row.get_child(2).get_theme_color("font_color") == color, "Neutral list status agrees with detail without claiming defeat: %d" % i)
		else:
			check(row.get_child(1).text == "Harbinger  ·  Depth 20  ·  14:02", "Victory/death supporting row text stays unchanged: %d" % i)
	check(FileAccess.get_sha256(HISTORY.STORAGE_PATH) == before_hash, "Viewing/selecting every outcome leaves serialized outcomes, stats and progression bytes unchanged")
	panel.populate()
	await _settle()
	check(panel._selected_index == 0 and panel._detail_content.get_child(0).text == "Victory — Veilstrider", "Reopening history returns to the latest record after neutral selection")
	panel.queue_free()
	await _settle()
	HISTORY.clear_all()

func _test_timeline_availability_reuse() -> void:
	check(not screen._action_buttons._timeline_button.visible and not screen._reward_panel._timeline_section.visible, "Missing legacy timeline offers no unavailable action or empty section")
	screen._toggle_timeline()
	check(screen._timeline_visible, "Unavailable timeline cannot change the retained toggle preference")
	var actions: Array[String] = []
	screen.return_to_main_menu_requested.connect(func(): actions.append("menu"))
	screen.retry_run_requested.connect(func(): actions.append("retry"))
	screen._input_delay_left = 0.1
	screen._action_buttons.get_child(0).pressed.emit()
	check(actions.is_empty(), "Menu keeps its existing input guard with the timeline action absent")
	screen._input_delay_left = 0.0
	screen._action_buttons.get_child(0).pressed.emit()
	check(actions == ["menu"], "Return to menu still works without a timeline or retry action")
	screen.show_result("Victory", "", fixture_summary())
	await _settle()
	check(screen._action_buttons._timeline_button.visible and screen._action_buttons._timeline_button.text == "Hide Timeline" and screen._reward_panel._timeline_section.visible, "Reusing an empty result with populated history restores its expanded timeline action")
	check(screen._action_buttons._retry_button.visible, "Populated reuse restores permitted retry independently of timeline availability")
	screen._input_delay_left = 0.0
	screen._action_buttons._retry_button.pressed.emit()
	check(actions == ["menu", "retry"], "Retry still forwards the normal result action after screen reuse")
	screen._action_buttons._timeline_button.pressed.emit()
	check(not screen._timeline_visible and not screen._reward_panel._timeline_section.visible and screen._action_buttons._timeline_button.text == "Build Timeline", "Populated timeline button hides entries and updates its label")
	screen.show_result("Victory", "", {"unlocks": ["Unlocked Bearing: Delver"], "reward_timeline": []})
	await _settle()
	check(screen._reward_panel.visible and not screen._reward_panel._timeline_section.visible and not screen._action_buttons._timeline_button.visible, "Empty timeline preserves available progression while omitting its action and section")
	screen._toggle_timeline()
	screen.show_result("Victory", "", fixture_summary())
	await _settle()
	check(screen._action_buttons._timeline_button.visible and screen._action_buttons._timeline_button.text == "Build Timeline" and not screen._reward_panel._timeline_section.visible, "Populated reuse restores the previously collapsed preference after an empty result")
	screen._action_buttons._timeline_button.pressed.emit()
	check(screen._timeline_visible and screen._reward_panel._timeline_section.visible and screen._action_buttons._timeline_button.text == "Hide Timeline", "Restored timeline action can reveal recorded entries again")

func _test_peer_summary_flow() -> void:
	var host_tracker := TRACKER.new()
	host_tracker.reset_for_run({"game_version": "dev-result-identity"})
	host_tracker.record_act_entry(3)
	host_tracker.record_boss_defeat("warden")
	host_tracker.record_boss_defeat("sovereign")
	var host_summary := host_tracker.build_summary({"run_id": "identity-host", "max_depth": 20, "outcome": "death"})
	# The reliable outcome carries a Variant dictionary, not a reconstructed
	# per-peer model. Exercise that serialization before the real receiver helpers.
	var received: Dictionary = bytes_to_var(var_to_bytes(host_summary))
	var world := SummaryWorld.new()
	var recorder := RECORDER.new(world)
	recorder._run_is_debug = true
	recorder.run_summary_tracker.reset_for_run({"game_version": "dev-result-identity"})
	var local := recorder.summary_with_local_peer_stats(received, {2: {"bosses_defeated": 2, "damage_dealt_total": 37}})
	local = recorder.summary_with_local_peer_overrides(local, {2: {"character_name": "Riftlancer", "build_summary": {"arcana": []}, "boss_no_hit_ids": []}})
	check(local.get("reached_act") == 3 and local.get("defeated_boss_ids") == ["warden", "sovereign"], "Peer statistics/build replacement preserves shared act and actual victories")
	check(local.stats.damage_dealt_total == 37 and host_summary.stats.damage_dealt_total == 0, "Peer totals remain separate without mutating host results")
	MultiplayerSessionManager.session_connected = false
	MultiplayerSessionManager.is_host_peer = false
	recorder.finalize_synced_run_summary_for_joiner(local, "death")
	check(recorder.latest_run_summary.get("reached_act") == 3 and recorder.latest_run_summary.get("defeated_boss_ids") == ["warden", "sovereign"], "Joiner finalization retains host-recorded act/boss facts despite local tracker defaults")
	var records := HISTORY.load_all()
	var found := false
	for item: Dictionary in records:
		if item.get("run_id") == "identity-host-p2":
			found = FACTS.headline(item, "Defeat") == "Act III · Depth 20" and item.get("defeated_boss_ids") == ["warden", "sovereign"]
	check(found, "Joiner local JSON history roundtrip preserves result identity")
	world.free()
