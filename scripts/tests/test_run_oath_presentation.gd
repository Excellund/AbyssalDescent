extends SceneTree

const PRESENTATION := preload("res://scripts/progression/run_oath_presentation.gd")
const REGISTRY := preload("res://scripts/progression/oaths_registry.gd")
const EVALUATOR := preload("res://scripts/progression/oaths_evaluator.gd")
const TRACKER := preload("res://scripts/core/run_summary_tracker.gd")
const RECORDER := preload("res://scripts/core/run_summary_recorder.gd")
const META := preload("res://scripts/meta_progress_store.gd")
const ROSTER := preload("res://scripts/core/player_roster_helpers.gd")

class TestContext extends Node:
	var meta_progress_profile: Dictionary = META._get_default_profile()
	var saves := 0
	func save_meta_progress() -> bool:
		saves += 1
		return true

class TestPlayer extends "res://scripts/player.gd":
	func _init() -> void:
		health_state = HEALTH_STATE_SCRIPT.new()
		add_child(health_state)
	func _is_local_control_owner() -> bool:
		return is_local_player
	func get_trial_power_stack_count(id: String) -> int:
		return 2 if id == "static_wake" else 0
	func get_upgrade_stack_count(_id: String) -> int:
		return 0

class TestWorld extends Node:
	var context := TestContext.new()
	var is_multiplayer := false
	var peer_id := 1
	var owned: Node
	var power_registry_instance: Node
	func _get_run_context() -> Node:
		return context
	func _resolve_local_peer_id() -> int:
		return peer_id
	func _find_local_owned_player_node() -> Node:
		return ROSTER.find_local_owned_player_node([owned] if is_instance_valid(owned) else [])

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)

func _seed(tier: int = 3) -> Dictionary:
	return {"difficulty_tier": tier, "character_id": "bastion", "character_name": "Bastion", "difficulty_label": REGISTRY._bearing_label(tier), "equipped_catalyst_ids": [], "ascension_tracking_complete": true, "ascension_rank": 10, "ascension_loadout": ["glass_descent", "pilgrims_burden"]}

func _summary(tier: int = 3) -> Dictionary:
	var tracker := TRACKER.new()
	tracker.reset_for_run(_seed(tier))
	var summary := tracker.build_summary({"outcome": "in_progress", "duration_seconds": 120})
	summary.build_summary.arcana = [{"id": "static_wake", "stacks": 2}]
	return summary

func _rows(summary: Dictionary, evidence: Dictionary = {}) -> Array[Dictionary]:
	return PRESENTATION.presentation(summary, META._get_default_profile(), evidence)

func _row(rows: Array, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.id == id:
			return row
	_check(false, "Missing Oath row: " + id)
	return {}

func _state(summary: Dictionary, id: String, expected: String, message: String, evidence: Dictionary = {}) -> void:
	var row := _row(_rows(summary, evidence), id)
	_check(row.get("state") == expected, "%s: expected %s, got %s (%s)" % [message, expected, row.get("state"), row.get("detail")])

func _run() -> void:
	_test_evaluator_parity()
	_test_relevance_and_earned()
	_test_irreversible_facts()
	_test_future_and_missing_evidence()
	_test_joiner_authority()
	_test_progress_text()
	_test_purity()
	await _test_recorder_adapter()
	if _failures.is_empty():
		print("[OK] Current-run Oath projection: %d checks" % _checks)
	quit(0 if _failures.is_empty() else 1)

func _test_evaluator_parity() -> void:
	for tier in range(4):
		for milestones in [false, true]:
			for outcome in ["in_progress", "clear"]:
				var summary := _summary(tier)
				summary.outcome = outcome
				if milestones:
					summary.boss_no_hit_ids = ["warden", "sovereign", "lacuna"]
					summary.hold_full_control_achieved = true
				var actual: Array = EVALUATOR.evaluate_run(summary, META._get_default_profile()).completed_oath_ids
				var projected := summary.duplicate(true)
				projected.outcome = "clear"
				var on_clear: Array = EVALUATOR.evaluate_run(projected, META._get_default_profile()).completed_oath_ids
				for row: Dictionary in _rows(summary):
					_check((row.state == "achieved") == actual.has(row.id), "Achieved state agrees with award evaluator: %s tier%d" % [row.id, tier])
					_check((row.state == "on_track" or row.state == "achieved") == on_clear.has(row.id), "Positive projection agrees with clear evaluator: %s tier%d" % [row.id, tier])

func _test_relevance_and_earned() -> void:
	var rows := _rows(_summary(0))
	var relevant := 0
	for row: Dictionary in rows:
		if row.relevant:
			relevant += 1
	_check(relevant == 5, "Pilgrim Bastion sees four Journey attempts and one exact clear")
	_check(not _row(rows, "clear_hexweaver_pilgrim").relevant, "Other vessels stay outside current attempts")
	_check(not _row(rows, "clear_bastion_delver").relevant, "Exact Bearing clears cannot substitute")
	_check(not _row(rows, "forsworn_grounded").relevant, "Higher-Bearing requirements are not attempts on Pilgrim")
	var summary := _summary()
	summary.ascension_rank = 1
	summary.ascension_loadout = ["barren_road"]
	summary.equipped_catalyst_ids = ["extra_arcana_slot"]
	rows = _rows(summary)
	_check(not _row(rows, "ascension_rank_3").relevant, "Insufficient launch rank is not relevant")
	_check(_row(rows, "ascension_rank_1").relevant, "Matching launch rank remains relevant")
	_check(not _row(rows, "forsworn_glass_pilgrimage").relevant, "Wrong launch modifiers are not relevant")
	_check(not _row(rows, "unassisted_ascension").relevant, "Equipped launch Catalyst excludes Unassisted")
	var profile := META._get_default_profile()
	for id in ["warden_no_hit", "unbroken_line", "singular_focus", "the_unbroken_march", "forsworn_unassisted"]:
		META.mark_oath_completed(profile, id)
	rows = PRESENTATION.presentation(_summary(), profile)
	for id in REGISTRY.JOURNEY_OATH_IDS:
		_check(_row(rows, id).state == "earned", "Equivalent historical completion remains earned: " + id)
	_check(_row(rows, "unassisted_ascension").state == "on_track", "Retired easier Unassisted does not substitute for new challenge")
	summary = _summary()
	summary.is_debug = true
	_state(summary, "forsworn_grounded", "unavailable", "Debug run cannot imply eligibility")
	rows = PRESENTATION.presentation(summary, profile)
	_check(_row(rows, "forsworn_warden_no_hit").state == "earned", "A debug run does not erase profile completion")

func _test_irreversible_facts() -> void:
	var cases := {
		"forsworn_closed_fist": {"primary_attacks_fired": 1},
		"forsworn_grounded": {"dashes_performed": 1},
		"forsworn_unbroken_march": {"rest_count": 1},
		"forsworn_glass_pilgrimage": {"rest_count": 1},
		"forsworn_flawless_run": {"stats": {"damage_taken_total": 1}},
		"forsworn_against_the_clock": {"duration_seconds": 480},
		"forsworn_singular_focus": {"build_summary": {"arcana": [{"id": "static_wake", "stacks": 1}, {"id": "shatterwake", "stacks": 1}]}},
	}
	for id: String in cases:
		var summary := _summary()
		summary.merge(cases[id], true)
		var row := _row(_rows(summary), id)
		_check(row.state == "broken" and row.relevant, "Known violated attempt remains visible: " + id)
		summary.full_run_tracking_complete = false
		_state(summary, id, "broken", "Unknown older history cannot erase a known violation")
	var summary := _summary()
	summary.duration_seconds = 479
	_state(summary, "forsworn_against_the_clock", "on_track", "Time threshold remains strictly under eight minutes")
	summary.oath_min_difficulty_tier = 1
	_state(summary, "forsworn_flawless_run", "broken", "A known easier segment cannot be promoted by current Forsworn")
	_state(summary, "forsworn_grounded", "on_track", "Delver history still qualifies for Delver challenge")
	var tracker := TRACKER.new()
	tracker.reset_for_run(_seed())
	tracker.record_damage_taken(7)
	tracker.record_damage_recap_health(0, 123)
	tracker.record_damage_recap_health(0, 130)
	_state(tracker.build_summary({"outcome": "in_progress"}), "forsworn_flawless_run", "broken", "Healing does not clear total damage taken")

func _test_future_and_missing_evidence() -> void:
	var summary := _summary()
	summary.build_summary.arcana = []
	_state(summary, "forsworn_singular_focus", "pending", "Zero Arcana can still become one")
	summary.build_summary.arcana = [{"id": "static_wake", "stacks": 1}, {"id": "static_wake", "stacks": 3}]
	_state(summary, "forsworn_singular_focus", "on_track", "Repeated build entries and upgrades count one distinct Arcana")
	summary.boss_no_hit_ids = []
	summary.defeated_boss_ids = ["warden"]
	_state(summary, "forsworn_warden_no_hit", "pending", "Missing successful boss evidence does not infer permanent impossibility")
	_state(summary, "forsworn_unbroken_line", "pending", "Another Hold encounter may still qualify")
	summary.boss_no_hit_ids = ["warden", "warden", "sovereign"]
	var crowns := _row(_rows(summary), "forsworn_three_crowns_no_hit")
	_check(crowns.state == "pending" and crowns.current == 2 and crowns.target == 3, "Crowns progress counts distinct required bosses")
	summary.outcome = "death"
	_state(summary, "forsworn_warden_no_hit", "achieved", "Recorded encounter success survives defeat")
	_state(summary, "forsworn_grounded", "unavailable", "An ended run is not an in-progress clear attempt")
	summary = _summary()
	summary.full_run_tracking_complete = false
	for id in ["forsworn_grounded", "forsworn_closed_fist", "forsworn_unbroken_march", "forsworn_flawless_run", "forsworn_singular_focus", "forsworn_against_the_clock"]:
		var row := _row(_rows(summary), id)
		_check(row.state == "unverified" and not row.has("current"), "Legacy zero is not certified whole-run progress: " + id)
	summary.boss_no_hit_ids = ["warden"]
	_state(summary, "forsworn_warden_no_hit", "achieved", "Any-Bearing encounter remains useful after older history")
	summary = _summary()
	summary.oath_min_difficulty_tier = -1
	_state(summary, "forsworn_grounded", "unverified", "Unknown minimum Bearing is not an impossible challenge claim")
	_state(summary, "forsworn_unbroken_march", "on_track", "Any-Bearing whole-run proof remains independently valid")
	summary.erase("oath_min_difficulty_tier")
	summary.oath_difficulty_verified = true
	_state(summary, "forsworn_grounded", "on_track", "Explicit legacy Forsworn evidence still qualifies")
	summary = _summary()
	summary.dash_tracking_complete = false
	_state(summary, "forsworn_grounded", "unverified", "Absent earlier Dash proof is explicit")
	summary = _summary()
	summary.catalyst_tracking_complete = false
	_state(summary, "unassisted_ascension", "unverified", "Unknown Catalyst setup cannot become no Catalysts")
	summary = _summary()
	summary.ascension_tracking_complete = false
	_state(summary, "ascension_rank_1", "unverified", "Unknown Ascension setup cannot project a rank award")
	for malformed in [null, "0", -1, 0.5, INF, NAN]:
		summary = _summary()
		summary.dashes_performed = malformed
		_state(summary, "forsworn_grounded", "unverified", "Malformed Dash count is not zero or a known violation")
	summary = _summary()
	summary.build_summary.arcana = [{"id": "static_wake", "stacks": 0}]
	_state(summary, "forsworn_singular_focus", "unverified", "Malformed build evidence is not progress")
	summary = _summary()
	summary.erase("stats")
	_state(summary, "forsworn_flawless_run", "unverified", "Missing local damage is not aggregate or zero")

func _test_joiner_authority() -> void:
	var summary := _summary()
	summary.duration_seconds = 700
	summary.hold_full_control_achieved = true
	summary.boss_no_hit_ids = ["warden", "sovereign", "lacuna"]
	for id in ["forsworn_warden_no_hit", "forsworn_sovereign_no_hit", "forsworn_lacuna_no_hit", "forsworn_unbroken_line", "forsworn_three_crowns_no_hit", "forsworn_against_the_clock"]:
		var row := _row(_rows(summary, {"is_joiner": true}), id)
		_check(row.state == "unverified" and row.detail.contains("host") and not row.has("current"), "Joiner cannot certify host facts or time: " + id)
	summary.primary_attacks_fired = 1
	_state(summary, "forsworn_closed_fist", "broken", "Joiner still reads its own Attack use", {"is_joiner": true})
	_state(summary, "forsworn_grounded", "on_track", "Joiner still reads its own Dash evidence", {"is_joiner": true})

func _test_purity() -> void:
	var summary := _summary()
	var sparse := {"custom": {"preserve": [1, 2]}}
	var evidence := {"is_joiner": false}
	var before := var_to_bytes([summary, sparse, evidence])
	var rows := PRESENTATION.presentation(summary, sparse, evidence)
	_check(before == var_to_bytes([summary, sparse, evidence]), "Evaluation cannot initialize or mutate caller dictionaries")
	rows[0].label = "changed"
	_check(REGISTRY.get_definition(rows[0].id).label != "changed", "Rows do not alias registry definitions")
	var rows_again := PRESENTATION.presentation(summary, sparse, evidence)
	_check(rows_again[0].label != "changed", "Repeated reads have independent presentation data")
	_state(summary, "forsworn_grounded", "unverified", "Explicit missing profile cannot claim completion", {"profile_available": false})

func _test_progress_text() -> void:
	var summary := _summary()
	summary.primary_attacks_fired = 3
	summary.dashes_performed = 4
	summary.rest_count = 1
	summary.stats.damage_taken_total = 27
	summary.duration_seconds = 470
	summary.boss_no_hit_ids = ["warden", "sovereign"]
	var rows := _rows(summary)
	var expected := {
		"forsworn_closed_fist": "Attack actions: 3",
		"forsworn_grounded": "Dash uses: 4",
		"forsworn_unbroken_march": "Rest visits: 1",
		"forsworn_flawless_run": "Damage taken: 27",
		"forsworn_singular_focus": "Unique Arcana: 1 / 1",
		"forsworn_three_crowns_no_hit": "Qualifying bosses: 2 / 3",
		"forsworn_against_the_clock": "Elapsed: 7:50 (must be under 8:00)",
		"ascension_rank_3": "Ascension rank: 10 (requires 3+)",
	}
	for id: String in expected:
		_check(_row(rows, id).get("progress_text") == expected[id], "Precise presentation progress: " + id)
	summary = _summary()
	summary.full_run_tracking_complete = false
	_check(not _row(_rows(summary), "forsworn_grounded").has("progress_text"), "Unknown historical counters have no misleading zero progress text")
	summary.dashes_performed = 2
	_check(_row(_rows(summary), "forsworn_grounded").get("progress_text") == "Dash uses: 2 (recorded portion)", "Known post-Continue violation does not claim a complete historical count")
	_check(not _row(_rows(_summary(), {"is_joiner": true}), "forsworn_against_the_clock").has("progress_text"), "Joining timed row has no local-clock progress claim")

func _test_recorder_adapter() -> void:
	var world := TestWorld.new()
	var recorder := RECORDER.new(world)
	recorder.run_summary_tracker.reset_for_run(_seed())
	recorder.run_summary_tracker.started_at_unix -= 1000
	await create_timer(0.03).timeout
	recorder.run_started_at_msec = Time.get_ticks_msec()
	recorder.pause_run_timer()
	var snapshot: Dictionary = recorder.get_live_oath_presentation()
	_check(snapshot.elapsed_seconds == 0 and _row(snapshot.rows, "forsworn_against_the_clock").state == "on_track", "Paused live zero does not use a thousand-second wall-clock fallback")
	var checkpoint := {
		"tracker_checkpoint": recorder.run_summary_tracker.build_checkpoint(),
		"tracker_boon_items": {}, "tracker_arcana_items": {},
		"tracker_boss_reward_items": {}, "run_elapsed_seconds": 470,
	}
	recorder.restore_tracker_items_from_snapshot(checkpoint)
	snapshot = recorder.get_live_oath_presentation()
	_check(snapshot.elapsed_seconds == 470, "Continue adds previously recorded elapsed seconds")
	await create_timer(0.03).timeout
	_check(recorder.get_live_oath_presentation().elapsed_seconds == 470, "Open paused view does not advance recorded time")
	var profile_before := var_to_bytes(world.context.meta_progress_profile)
	var tracker_before := var_to_bytes(recorder.run_summary_tracker.build_checkpoint())
	var peer_before := var_to_bytes(recorder.get_stats_by_peer())
	for _i in range(3):
		recorder.get_live_oath_presentation()
	_check(profile_before == var_to_bytes(world.context.meta_progress_profile) and world.context.saves == 0, "Repeated live reads never save or mutate profile")
	_check(tracker_before == var_to_bytes(recorder.run_summary_tracker.build_checkpoint()) and peer_before == var_to_bytes(recorder.get_stats_by_peer()), "Repeated reads never change tracker or initialize peer ledgers")
	_check(recorder.latest_run_summary.is_empty() and not recorder.telemetry_run_finished, "Reading cannot finalize or create a persisted summary")
	world.is_multiplayer = true
	world.owned = TestPlayer.new()
	world.owned.player_id = 1
	recorder.run_summary_tracker.total_damage_taken = 99
	recorder.run_summary_tracker.begin_boss_engagement("warden", [1, 2])
	recorder.run_summary_tracker.record_damage_taken(9, 2)
	recorder.run_summary_tracker.record_boss_defeat("warden")
	recorder._summary_stats_by_peer = {"1": {"damage_taken_total": 0}, "2": {"damage_taken_total": 108}}
	var session_before := [MultiplayerSessionManager.session_connected, MultiplayerSessionManager.is_host_peer]
	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = true
	snapshot = recorder.get_live_oath_presentation()
	_check(_row(snapshot.rows, "forsworn_flawless_run").state == "on_track", "Host view uses its local zero damage, not injured teammate aggregate")
	_check(_row(snapshot.rows, "forsworn_warden_no_hit").state == "achieved", "Host uses untouched local peer boss map, not party no-hit")
	_check(_row(snapshot.rows, "forsworn_singular_focus").state == "on_track", "Co-op build projection uses the actual owned actor")
	world.peer_id = 2
	world.owned.player_id = 2
	MultiplayerSessionManager.is_host_peer = false
	snapshot = recorder.get_live_oath_presentation()
	_check(snapshot.is_joiner and _row(snapshot.rows, "forsworn_flawless_run").state == "broken", "Joiner uses its own positive damage")
	_check(_row(snapshot.rows, "forsworn_warden_no_hit").state == "unverified", "Joiner adapter cannot certify local replica boss data")
	world.peer_id = 3
	snapshot = recorder.get_live_oath_presentation()
	_check(_row(snapshot.rows, "forsworn_flawless_run").state == "unverified", "Missing peer ledger remains unknown")
	_check(_row(snapshot.rows, "forsworn_singular_focus").state == "unverified", "A different peer ID cannot supply local build evidence")
	world.owned.is_local_player = false
	_check(world._find_local_owned_player_node() == world.owned, "Production roster helper falls back to an alive ally without a local owner")
	snapshot = recorder.get_live_oath_presentation()
	_check(_row(snapshot.rows, "forsworn_singular_focus").state == "unverified", "An alive fallback ally cannot supply the missing owner's Arcana")
	world.owned.free()
	world.owned = null
	snapshot = recorder.get_live_oath_presentation()
	_check(_row(snapshot.rows, "forsworn_singular_focus").state == "unverified", "Missing owned actor cannot borrow an ally or create empty build evidence")
	MultiplayerSessionManager.session_connected = session_before[0]
	MultiplayerSessionManager.is_host_peer = session_before[1]
	world.is_multiplayer = false
	recorder.run_summary_tracker.reset_for_run(_seed())
	recorder.restore_tracker_items_from_snapshot({"tracker_boon_items": {}, "tracker_arcana_items": {}, "tracker_boss_reward_items": {}})
	snapshot = recorder.get_live_oath_presentation()
	_check(_row(snapshot.rows, "forsworn_grounded").state == "unverified" and _row(snapshot.rows, "forsworn_unbroken_march").state == "unverified", "Actual legacy Continue restoration leaves whole-run requirements unverified")
	recorder.run_summary_tracker.begin_boss_engagement("warden")
	recorder.run_summary_tracker.record_boss_defeat("warden")
	snapshot = recorder.get_live_oath_presentation()
	_check(_row(snapshot.rows, "forsworn_warden_no_hit").state == "achieved", "A newly recorded Any-Bearing encounter remains achievable after legacy Continue")
	world.context.free()
	world.free()
