extends SceneTree

const FIXTURES := preload("res://scripts/tests/test_catalyst_runtime.gd")
const ASCENSION := preload("res://scripts/progression/ascension_modifier_registry.gd")
const DIFFICULTY := preload("res://scripts/difficulty_config.gd")
const META := preload("res://scripts/meta_progress_store.gd")
const RECORDER := preload("res://scripts/core/run_summary_recorder.gd")
const TRACKER := preload("res://scripts/core/run_summary_tracker.gd")
const EVALUATOR := preload("res://scripts/progression/oaths_evaluator.gd")
const PANEL := preload("res://scripts/ui/ascension/ascension_panel.gd")
const LOBBY := preload("res://scripts/lobby_controller.gd")
const LEADERBOARD := preload("res://scripts/core/leaderboard_entry_model.gd")
const ROUTES := preload("res://scripts/core/encounter_route_controller.gd")
const FLOW := preload("res://scripts/encounter_flow_system.gd")
const DEPTH := preload("res://scripts/core/room_depth_bookkeeper.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const LOADOUT := ["hardened_foes", "thinned_choices", "relentless_tide"]
const ENCOUNTERS := ["skirmish", "crossfire", "blitz", "onslaught", "fortress", "suppression", "vanguard", "ambush", "gauntlet"]

class TestSession extends Node:
	func is_host() -> bool:
		return false

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	_test_resolvers_and_bootstrap()
	_test_checkpoint_and_retry()
	_test_progression_guards()
	await _test_menu_and_lobby()
	print("Ascension regression tests: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _make_world(menu_tier: int, host_tier: int = -1, host_loadout: Array = LOADOUT) -> FIXTURES.TestWorld:
	var world := FIXTURES.TestWorld.new()
	world.context = FIXTURES.TestContext.new()
	var context := world.context
	context.meta_progress_profile = META._get_default_profile()
	META.unlock_character_tier(context.meta_progress_profile, "bastion", 3)
	META.record_forsworn_clear(context.meta_progress_profile, "bastion")
	META.set_ascension_loadout(context.meta_progress_profile, "bastion", LOADOUT)
	context.current_difficulty_tier = menu_tier
	world.is_multiplayer = host_tier >= 0
	if world.is_multiplayer:
		context.set_multiplayer_session("ascension-test", false)
		context.set_multiplayer_difficulty_tier(host_tier)
		context.set_peer_character_selection(2, "bastion")
		context.set_active_ascension_loadout(host_loadout, host_tier)
	root.add_child(world)
	world.player = FIXTURES.TestPlayer.new()
	world.add_child(world.player)
	world.party.append(world.player)
	world.difficulty_provider = FIXTURES.PROVIDER.new(world)
	world.room_depth_bookkeeper = DEPTH.new(world)
	world.encounter_flow_system = FLOW.new()
	world.add_child(world.encounter_flow_system)
	world.encounter_route_controller = ROUTES.new()
	world.encounter_route_controller.set_encounter_flow_system(world.encounter_flow_system)
	world._prepare_run_loadout()
	world._setup_encounter_profile_builder_system()
	world.enemy_spawner = FIXTURES.TestSpawner.new()
	world.add_child(world.enemy_spawner)
	world._apply_difficulty_tier_bonuses(world.current_difficulty_tier, false)
	world.reward_selection_ui = FIXTURES.REWARD_UI.new()
	world.add_child(world.reward_selection_ui)
	world._configure_reward_selection_loadout()
	world.hud = FIXTURES.TestHud.new()
	world.add_child(world.hud)
	world.run_summary_recorder = RECORDER.new(world)
	world.run_summary_recorder.reset_summary_tracker()
	return world

func _free_world(world: FIXTURES.TestWorld) -> void:
	if world.difficulty_provider._multiplayer_config != null:
		world.difficulty_provider._multiplayer_config.free()
	world.encounter_profile_builder.multiplayer_difficulty_config.free()
	world.context.free()
	world.free()

func _test_resolvers_and_bootstrap() -> void:
	_check(ASCENSION.normalize_loadout(3, [" hardened_foes ", "unknown", "hardened_foes"]) == ["hardened_foes"], "Effective modifiers must be recognized, trimmed and unique")
	for tier in range(4):
		var config := DIFFICULTY.get_tier_config_with_ascension(tier, LOADOUT)
		_check(int(config["ascension_rank"]) == (5 if tier == 3 else 0), "Direct resolver rank uses Forsworn only: %d" % tier)
		if tier < 3:
			var base := DIFFICULTY.get_tier_config(tier)
			for key in base:
				_check(config[key] == base[key], "Lower-tier base config is unchanged: %d/%s" % [tier, key])
		for coop in [false, true]:
			var world := _make_world(0 if tier == 3 else 3, tier) if coop else _make_world(tier)
			var expected: Array = LOADOUT if tier == 3 else []
			_check(world.current_difficulty_tier == tier and world.encounter_profile_builder.current_difficulty_tier == tier, "World and encounter builder use actual solo/host tier: %d/%s" % [tier, coop])
			_check(world.context.get_active_ascension_loadout() == expected, "Active loadout follows actual solo/host tier: %d/%s" % [tier, coop])
			_check(world.context.get_saved_ascension_loadout("bastion") == LOADOUT, "Lower Bearings preserve saved Forsworn preferences")
			_check(world.reward_selection_ui.boon_choice_count == world.boon_choice_count - (1 if tier == 3 else 0), "Thinned Choices applies only on Forsworn")
			_check(is_equal_approx(world.enemy_spawner.ascension_enemy_health_mult, 1.25 if tier == 3 else 1.0), "Enemy-health modifier agrees with reward and encounter configuration")
			_check(world.run_summary_recorder.run_summary_tracker.ascension_rank == (5 if tier == 3 else 0), "Run summary rank agrees with gameplay")
			for encounter in ENCOUNTERS:
				var profile := world.encounter_profile_builder.build_debug_encounter_profile(encounter, 5)
				_check(not profile.is_empty(), "Encounter remains available: %d/%s/%s" % [tier, coop, encounter])
				_check(world.encounter_profile_builder.get_ascension_rank() == (5 if tier == 3 else 0), "Encounter modifier rank remains tier-correct: %s" % encounter)
			world.encounter_profile_builder.set_difficulty_tier(0)
			world.encounter_profile_builder.set_ascension_loadout(LOADOUT)
			_check(world.encounter_profile_builder.get_ascension_loadout().is_empty() and world.encounter_profile_builder.get_ascension_payload().is_empty(), "Direct builder writes cannot enable lower-tier Ascension")
			_free_world(world)
	var empty_party := _make_world(3, 3, [])
	_check(empty_party.context.get_active_ascension_loadout().is_empty() and empty_party.encounter_profile_builder.get_ascension_rank() == 0, "Explicit empty host loadout never falls back to joiner's saved modifiers")
	_free_world(empty_party)
	var character_switch := _make_world(3)
	character_switch.context.begin_ascension_run("hexweaver", 3)
	_check(character_switch.context.get_active_ascension_loadout().is_empty(), "A new character never inherits another character's active modifiers")
	_free_world(character_switch)

func _test_checkpoint_and_retry() -> void:
	var world := _make_world(3)
	var context := world.context
	world.player.set_max_health_and_current(world.player.get_max_health(), 37)
	var saved := world._build_active_run_snapshot()
	_check(saved["active_ascension_loadout"] == LOADOUT and saved["ascension_tracking_complete"], "New checkpoint records exact Ascension setup and evidence")
	META.set_ascension_loadout(context.meta_progress_profile, "bastion", ["glass_descent"])
	context.current_difficulty_tier = 0
	context.set_active_ascension_loadout([], 0)
	_check(world._apply_active_run_snapshot(saved), "Forsworn checkpoint resumes after a menu tier/loadout change")
	_check(context.get_active_ascension_loadout() == LOADOUT and world.current_difficulty_tier == 3, "Resume restores saved modifiers and saved tier")
	_check(world.player.get_current_health() == 37, "Ascension restore preserves saved health")
	_check(world.reward_selection_ui.boon_choice_count == world.boon_choice_count - 1, "Resume reconfigures reward choices from saved modifiers")
	world.run_summary_recorder.reset_summary_tracker()
	_check(world.run_summary_recorder.run_summary_tracker.ascension_rank == 5, "Resumed summary uses restored modifiers")
	context.request_run_retry(world.current_character_id, world.current_difficulty_tier)
	context.selected_character_id = "hexweaver"
	world._prepare_run_loadout()
	_check(world.current_character_id == "bastion" and world.current_difficulty_tier == 3 and context.get_active_ascension_loadout() == LOADOUT, "Retry keeps completed run tier, character and Ascension after menu changes")
	_check(context.selected_character_id == "hexweaver" and context.current_difficulty_tier == 0, "Retry does not rewrite menu preferences")
	_check(context.consume_run_retry().is_empty(), "Retry configuration is consumed once")
	saved["active_ascension_loadout"] = []
	_check(world._apply_active_run_snapshot(saved), "Empty Ascension checkpoint resumes")
	_check(context.get_active_ascension_loadout().is_empty() and world.encounter_profile_builder.get_ascension_rank() == 0, "Explicit saved empty loadout never falls back to menu preferences")
	saved["current_difficulty_tier"] = 0
	saved["active_ascension_loadout"] = LOADOUT
	saved["room_depth"] = int(DIFFICULTY.get_tier_config(0)["encounter_count_before_boss"]) - 1
	saved["rooms_cleared"] = saved["room_depth"]
	saved["door_options"] = [{"label": "Stale Ascension", "profile": {"chasers": 9999}}]
	_check(world._apply_active_run_snapshot(saved), "Stale lower-tier Ascension checkpoint remains playable")
	_check(context.get_active_ascension_loadout().is_empty() and world.reward_selection_ui.boon_choice_count == world.boon_choice_count, "Lower-tier checkpoint strips every Ascension effect")
	_check(world.door_options.size() == 2 and world.door_options != saved["door_options"], "Resume rebuilds precomputed lower-tier doors instead of retaining leaked profiles")
	_check(world.rooms_cleared == saved["rooms_cleared"] and world.room_depth == saved["room_depth"] and world.player.get_current_health() == 37, "Door repair preserves run progress and health")
	var rest_found := false
	for door in world.door_options:
		rest_found = rest_found or CONTRACTS.door_option_kind_id(door) == CONTRACTS.DOOR_KIND_REST
	_check(rest_found, "Regenerated lower-tier pre-boss route restores its Rest option")
	var clean_save := world._build_active_run_snapshot()
	_check(world._apply_active_run_snapshot(clean_save), "Corrected lower-tier save resumes")
	_check(world.door_options == clean_save["door_options"], "New known-empty lower-tier saves keep exact doorway choices")
	saved["boss_unlocked"] = true
	saved.erase("active_ascension_loadout")
	_check(world._apply_active_run_snapshot(saved), "Legacy lower-tier boss checkpoint resumes")
	_check(world.door_options.size() == 1 and CONTRACTS.door_option_kind_id(world.door_options[0]) == CONTRACTS.DOOR_KIND_BOSS, "Door repair preserves boss readiness")
	saved["boss_unlocked"] = false
	saved.erase("active_ascension_loadout")
	saved.erase("ascension_tracking_complete")
	saved["current_difficulty_tier"] = 3
	_check(world._apply_active_run_snapshot(saved), "Legacy Forsworn checkpoint remains playable")
	_check(context.get_active_ascension_loadout() == ["glass_descent"] and not context.ascension_tracking_complete, "Legacy Forsworn preserves old fallback without inventing original modifier evidence")
	world.run_summary_recorder.reset_summary_tracker()
	world.run_summary_recorder.restore_tracker_items_from_snapshot(saved)
	_check(not world.run_summary_recorder.run_summary_tracker.ascension_tracking_complete, "Older tracker checkpoint cannot restore missing Ascension evidence")
	var re_saved := world._build_active_run_snapshot()
	_check(not re_saved["ascension_tracking_complete"], "Re-saving a legacy run retains incomplete Ascension evidence")
	context.set_active_ascension_loadout([], 0)
	world._apply_active_run_snapshot(re_saved)
	_check(not context.ascension_tracking_complete, "Repeated resume cannot make legacy history eligible")
	context.request_run_retry("bastion", 3)
	world._prepare_run_loadout()
	_check(context.ascension_tracking_complete, "A fresh retry starts with complete modifier evidence")
	_free_world(world)

func _test_progression_guards() -> void:
	for tier in [-1, 0, 1, 2, 3]:
		for complete in [false, true]:
			var world := _make_world(0)
			var summary := {"outcome": "clear", "character_id": "bastion", "difficulty_tier": tier, "oath_min_difficulty_tier": tier, "ascension_rank": 10, "ascension_tracking_complete": complete}
			var completed: Array = EVALUATOR.evaluate_run(summary, world.context.meta_progress_profile).get("completed_oath_ids", [])
			var eligible: bool = tier == 3 and complete
			_check(completed.has("ascension_rank_10") == eligible, "Oath award independently requires Forsworn and modifier evidence: %d/%s" % [tier, complete])
			world.run_summary_recorder._apply_endgame_chase_progress(summary)
			_check((META.get_ascension_highest_rank(world.context.meta_progress_profile, "bastion") == 10) == eligible, "Highest-rank persistence independently requires Forsworn and evidence")
			_free_world(world)
	var tracker := TRACKER.new()
	tracker.reset_for_run({"difficulty_tier": 0, "ascension_rank": 10, "ascension_loadout": LOADOUT})
	var summary := tracker.build_summary({"outcome": "clear"})
	_check(summary["ascension_rank"] == 0 and summary["ascension_loadout"].is_empty(), "Summary drops stale lower-tier rank and modifiers")
	var joiner := _make_world(3, 0)
	joiner.run_summary_recorder.finalize_synced_run_summary_for_joiner({"run_id": "ascension-stale-host", "outcome": "clear", "character_id": "bastion", "difficulty_tier": 3, "ascension_rank": 10, "ascension_loadout": LOADOUT}, "clear")
	_check(joiner.run_summary_recorder.latest_run_summary["difficulty_tier"] == 0 and joiner.run_summary_recorder.latest_run_summary["ascension_rank"] == 0, "Joined summary trusts its established lobby setup over stale outcome rank/tier")
	_check(META.get_ascension_highest_rank(joiner.context.meta_progress_profile, "bastion") == 0 and not META.is_oath_completed(joiner.context.meta_progress_profile, "ascension_rank_1"), "Stale co-op result cannot persist Ascension progress")
	_free_world(joiner)
	var lower_summary := {"difficulty_tier": 0, "ascension_rank": 10, "ascension_loadout": LOADOUT}
	var normalized := LEADERBOARD.normalize_run_summary(lower_summary)
	_check(normalized["ascension_rank"] == 0 and normalized["ascension_loadout"].is_empty(), "Leaderboard submission normalization removes lower-tier Ascension")
	_check(LEADERBOARD.normalize_server_entry(lower_summary)["ascension_rank"] == 0, "Historical lower-tier server row cannot display an Ascension rank")

func _test_menu_and_lobby() -> void:
	var context := root.get_node("RunContext")
	context.meta_progress_profile = META._get_default_profile()
	META.record_forsworn_clear(context.meta_progress_profile, "bastion")
	META.set_ascension_loadout(context.meta_progress_profile, "bastion", LOADOUT)
	context.set_active_ascension_loadout([], 0)
	var panel := PANEL.new()
	root.add_child(panel)
	panel._build_ui(root)
	panel.set_character_id("bastion")
	panel.set_oaths_only_mode(true)
	panel.populate()
	_check(context.get_active_ascension_loadout().is_empty(), "Opening Oaths does not activate saved modifiers")
	panel.set_oaths_only_mode(false)
	panel.set_setup_bearing(0)
	panel._toggle_modifier("hardened_foes")
	_check(META.get_ascension_loadout(context.meta_progress_profile, "bastion") == LOADOUT, "Lower-tier setup cannot toggle Ascension")
	panel.set_setup_bearing(3)
	panel.populate()
	_check(context.get_active_ascension_loadout().is_empty(), "Browsing Forsworn setup does not modify an active run")
	panel.free()
	var lobby := LOBBY.new()
	lobby.ascension_info_label = Label.new()
	lobby.difficulty_selector = OptionButton.new()
	lobby.status_label = Label.new()
	lobby.multiplayer_session_manager = TestSession.new()
	for tier in range(4):
		lobby.difficulty_selector.add_item(str(tier), tier)
	lobby.selected_difficulty_tier = 3
	lobby._apply_ascension_loadout(LOADOUT)
	_check(lobby.selected_ascension_loadout == LOADOUT and lobby.ascension_info_label.visible, "Forsworn lobby receives host modifiers")
	lobby._apply_difficulty_selection(0)
	_check(lobby.selected_ascension_loadout.is_empty() and not lobby.ascension_info_label.visible, "Lobby difficulty downgrade clears effective rank and hides Ascension")
	lobby._apply_ascension_loadout(LOADOUT)
	_check(lobby.selected_ascension_loadout.is_empty(), "Late/stale Ascension broadcast cannot enable a lower-tier lobby")
	lobby._apply_difficulty_selection(3)
	lobby._apply_ascension_loadout([])
	_check(lobby.selected_ascension_loadout.is_empty(), "Empty host broadcast remains empty on Forsworn")
	lobby.ascension_info_label.free()
	lobby.difficulty_selector.free()
	lobby.status_label.free()
	lobby.multiplayer_session_manager.free()
	lobby.free()
	await process_frame
