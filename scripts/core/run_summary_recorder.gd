extends RefCounted

# Phase: world-generator-decomposition / Task: extract-run-summary-recorder
#
# Owns the per-run telemetry stream and run-summary aggregation that was
# previously scattered through world_generator.gd. The recorder reads
# context state from the host world generator (passed at construction)
# but owns all run-summary state and all calls to the persistent stores.

const RUN_SUMMARY_TRACKER_SCRIPT := preload("res://scripts/core/run_summary_tracker.gd")
const RUN_SUMMARY_MODEL_SCRIPT := preload("res://scripts/core/run_summary_model.gd")
const RUN_HISTORY_STORE_SCRIPT := preload("res://scripts/core/run_history_store.gd")
const RUN_TELEMETRY_STORE := preload("res://scripts/run_telemetry_store.gd")
const POWER_REGISTRY := preload("res://scripts/power_registry.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const BEARING_KEY_NORMALIZER := preload("res://scripts/shared/bearing_key_normalizer.gd")
const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")
const META_PROGRESS_STORE := preload("res://scripts/meta_progress_store.gd")
const OATHS_EVALUATOR := preload("res://scripts/progression/oaths_evaluator.gd")
const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const RUN_CONTEXT_SCRIPT := preload("res://scripts/run_context.gd")
const OBJECTIVE_MANAGER_SCRIPT := preload("res://scripts/objective_manager.gd")

const STAT_ATTRIBUTION_TRACE := false

var telemetry_run_id: String = ""
var telemetry_enabled: bool = false
var telemetry_run_finished: bool = false
var run_started_at_msec: int = 0
var latest_run_summary: Dictionary = {}
var run_summary_tracker

var _summary_last_player_health_by_peer: Dictionary = {}
var _summary_stats_by_peer: Dictionary = {}
var _summary_reward_timeline_by_peer: Dictionary = {}
var _latest_peer_summary_overrides: Dictionary = {}

var _world  # WorldGenerator back-reference for context reads.

func _init(world: Node) -> void:
	_world = world
	run_summary_tracker = RUN_SUMMARY_TRACKER_SCRIPT.new()


# --- queries -----------------------------------------------------------------

func can_record() -> bool:
	return telemetry_enabled and not telemetry_run_id.is_empty() and not telemetry_run_finished

func get_run_elapsed_seconds() -> int:
	if run_started_at_msec <= 0:
		return 0
	return maxi(0, int(round(float(Time.get_ticks_msec() - run_started_at_msec) / 1000.0)))

func get_active_boss_id() -> String:
	if _world.in_third_boss_room:
		return "lacuna"
	if _world.in_second_boss_room:
		return "sovereign"
	if _world.in_boss_room:
		return "warden"
	return ""

func get_stats_by_peer() -> Dictionary:
	return _summary_stats_by_peer

func get_latest_peer_summary_overrides() -> Dictionary:
	return _latest_peer_summary_overrides

func summary_category_for_mode(mode: int) -> String:
	if mode == ENUMS.RewardMode.BOSS:
		return RUN_SUMMARY_MODEL_SCRIPT.CATEGORY_BOSS_REWARD
	if mode == ENUMS.RewardMode.ARCANA:
		return RUN_SUMMARY_MODEL_SCRIPT.CATEGORY_ARCANA
	return RUN_SUMMARY_MODEL_SCRIPT.CATEGORY_BOON


# --- run lifecycle -----------------------------------------------------------

func mark_run_start() -> void:
	run_started_at_msec = Time.get_ticks_msec()
	latest_run_summary.clear()
	reset_summary_tracker()

func initialize(allow_collection: bool) -> void:
	telemetry_run_id = ""
	telemetry_enabled = allow_collection
	telemetry_run_finished = false
	latest_run_summary.clear()
	if not telemetry_enabled:
		return
	# In multiplayer, only the host should write telemetry to avoid file corruption races.
	if MultiplayerSessionManager.is_remote_replica():
		telemetry_enabled = false
		return
	var debug_settings: Node = _world.get_node_or_null("DebugSettings")
	if debug_settings != null and bool(debug_settings.get("stress_test_enabled")):
		telemetry_enabled = false
		return
	var run_context: Node = _world._get_run_context()
	var run_mode := int(ENUMS.RunMode.STANDARD)
	if run_context != null:
		var run_mode_value: Variant = run_context.get("run_mode")
		if run_mode_value != null:
			run_mode = int(run_mode_value)
	var run_seed := {
		"game_version": String(ProjectSettings.get_setting("application/config/version", "dev")).strip_edges(),
		"character_id": _world.current_character_id,
		"character_name": String(CHARACTER_REGISTRY.get_character(_world.current_character_id).get("name", String(_world.current_character_id).capitalize())),
		"difficulty_tier": _world.current_difficulty_tier,
		"run_mode": run_mode,
		"start_depth": _world.room_depth,
		"rooms_cleared": _world.rooms_cleared,
		"is_debug": false
	}
	if run_context != null:
		run_seed["player_uuid"] = String(run_context.get_profile_uuid())
		run_seed["player_name"] = String(run_context.get_profile_name_or_default())
	run_seed["leaderboard_patch_key"] = RUN_TELEMETRY_STORE.leaderboard_patch_key_from_version(String(run_seed.get("game_version", "")))
	telemetry_run_id = RUN_TELEMETRY_STORE.start_run(run_seed)

func reset_summary_tracker() -> void:
	if run_summary_tracker == null:
		run_summary_tracker = RUN_SUMMARY_TRACKER_SCRIPT.new()
	_summary_last_player_health_by_peer.clear()
	_summary_stats_by_peer.clear()
	_summary_reward_timeline_by_peer.clear()
	_latest_peer_summary_overrides.clear()
	var run_context: Node = _world._get_run_context()
	var game_version := String(ProjectSettings.get_setting("application/config/version", "dev")).strip_edges()
	if game_version.is_empty():
		game_version = "dev"
	var difficulty_label := String(DIFFICULTY_CONFIG.get_tier_config(_world.current_difficulty_tier).get("name", "Pilgrim"))
	var tracker_seed := {
		"started_at_unix": int(Time.get_unix_time_from_system()),
		"started_at_msec": int(Time.get_ticks_msec()),
		"character_id": _world.current_character_id,
		"character_name": String(CHARACTER_REGISTRY.get_character(_world.current_character_id).get("name", String(_world.current_character_id).capitalize())),
		"difficulty_tier": _world.current_difficulty_tier,
		"difficulty_label": difficulty_label,
		"game_version": game_version,
		"leaderboard_patch_key": RUN_TELEMETRY_STORE.leaderboard_patch_key_from_version(game_version),
		"is_multiplayer": _world.is_multiplayer,
		"player_count": _world.difficulty_provider.get_party_size(),
	}
	if run_context != null:
		tracker_seed["player_uuid"] = String(run_context.get_profile_uuid())
		tracker_seed["player_name"] = String(run_context.get_profile_name_or_default())
	if _world.current_player_profile != null and _world.current_player_profile.is_valid():
		tracker_seed["player_uuid"] = _world.current_player_profile.player_id
		tracker_seed["player_name"] = _world.current_player_profile.profile_name
	if run_context != null:
		var loadout: Array = run_context.get_active_ascension_loadout()
		tracker_seed["ascension_loadout"] = loadout
		var ASCENSION_REGISTRY := preload("res://scripts/progression/ascension_modifier_registry.gd")
		tracker_seed["ascension_rank"] = ASCENSION_REGISTRY.compute_loadout_rank(loadout)
		var character_id: String = String(_world.current_character_id).strip_edges().to_lower()
		var META_PROGRESS := preload("res://scripts/meta_progress_store.gd")
		tracker_seed["equipped_catalyst_ids"] = META_PROGRESS.get_equipped_catalyst_ids(run_context.meta_progress_profile, character_id)
	run_summary_tracker.reset_for_run(tracker_seed)
	for player_node in _world._get_multiplayer_player_nodes():
		var player := player_node as PLAYER_SCRIPT
		if not is_instance_valid(player):
			continue
		var peer_id: int = _world._get_player_network_id(player)
		var health_key := maxi(peer_id, 0)
		_summary_last_player_health_by_peer[health_key] = player.get_current_health()
		if peer_id <= 0:
			continue
		_set_peer_summary_stats(peer_id, _empty_peer_stats())
		_set_peer_reward_timeline(peer_id, [])

func mark_debug_mode() -> void:
	if MultiplayerSessionManager.is_remote_replica():
		telemetry_enabled = false
		return
	if telemetry_run_id.is_empty():
		telemetry_enabled = false
		return
	if telemetry_run_finished:
		telemetry_enabled = false
		return
	RUN_TELEMETRY_STORE.mark_run_debug(telemetry_run_id)
	RUN_TELEMETRY_STORE.finish_run(telemetry_run_id, "debug", {
		"max_depth": _world.room_depth,
		"rooms_cleared": _world.rooms_cleared
	})
	telemetry_enabled = false
	telemetry_run_finished = true

func finish_run(outcome: String, death_event: Dictionary = {}) -> void:
	var death_copy := death_event.duplicate(true)
	var close_fields := {
		"run_outcome": outcome
	}
	var active_boss_id := get_active_boss_id()
	if not active_boss_id.is_empty():
		close_fields["boss_id"] = active_boss_id
	close_active_room(close_fields)
	var active_powers: Dictionary = _world._get_active_player_powers()
	var build_ids: Array[String] = []
	for source_key in ["boons", "arcana", "boss_rewards"]:
		var ids := active_powers.get(source_key, []) as Array
		for id_variant in ids:
			var normalized_id := String(id_variant).strip_edges().to_lower()
			if normalized_id.is_empty():
				continue
			if not build_ids.has(normalized_id):
				build_ids.append(normalized_id)
	var summary := {
		"max_depth": _world.room_depth,
		"rooms_cleared": _world.rooms_cleared,
		"build_ids": build_ids
	}
	if not death_copy.is_empty():
		summary["death_event"] = death_copy
	if run_summary_tracker != null:
		run_summary_tracker.is_multiplayer = _world.is_multiplayer
		run_summary_tracker.player_count = _world.difficulty_provider.get_party_size()
		var tracker_summary: Dictionary = run_summary_tracker.build_summary({
			"run_id": telemetry_run_id,
			"outcome": outcome,
			"max_depth": _world.room_depth,
			"rooms_cleared": _world.rooms_cleared,
			"duration_seconds": get_run_elapsed_seconds(),
			"death_event": death_copy,
		})
		tracker_summary["build_ids"] = build_ids
		if _world.is_multiplayer:
			var local_peer_id: int = _world._resolve_local_peer_id()
			var local_peer_stats := _lookup_peer_dictionary(_summary_stats_by_peer, local_peer_id)
			if not local_peer_stats.is_empty():
				var merged_stats := (tracker_summary.get("stats", {}) as Dictionary).duplicate(true)
				for key_variant in local_peer_stats.keys():
					var stat_key := String(key_variant)
					merged_stats[stat_key] = int(local_peer_stats.get(key_variant, merged_stats.get(stat_key, 0)))
				tracker_summary["stats"] = merged_stats
		latest_run_summary = tracker_summary
		summary["stats"] = (tracker_summary.get("stats", {}) as Dictionary).duplicate(true)
		summary["build_summary"] = (tracker_summary.get("build_summary", {}) as Dictionary).duplicate(true)
		summary["reward_timeline"] = (tracker_summary.get("reward_timeline", []) as Array).duplicate(true)
		summary["unlocks"] = (tracker_summary.get("unlocks", []) as Array).duplicate(true)
		summary["duration_seconds"] = int(tracker_summary.get("duration_seconds", get_run_elapsed_seconds()))
		summary["timestamp_text"] = String(tracker_summary.get("timestamp_text", ""))
		_apply_endgame_chase_progress(latest_run_summary)
		summary["unlocks"] = (latest_run_summary.get("unlocks", []) as Array).duplicate(true)
	_latest_peer_summary_overrides = build_peer_summary_overrides()
	summary["is_multiplayer"] = _world.is_multiplayer
	summary["player_count"] = int(_world.difficulty_provider.get_party_size())
	if _world.is_multiplayer:
		summary["host_peer_id"] = int(_world._resolve_local_peer_id())
		summary["peers"] = build_peer_telemetry_entries()
	if not can_record():
		if not telemetry_run_finished:
			RUN_HISTORY_STORE_SCRIPT.append(latest_run_summary)
			_world._enqueue_leaderboard_submission(latest_run_summary)
			telemetry_run_finished = true
		return
	RUN_TELEMETRY_STORE.finish_run(telemetry_run_id, outcome, summary)
	latest_run_summary = RUN_TELEMETRY_STORE.build_run_summary(telemetry_run_id, latest_run_summary)
	RUN_HISTORY_STORE_SCRIPT.append(latest_run_summary)
	_world._enqueue_leaderboard_submission(latest_run_summary)
	telemetry_run_finished = true
	var run_context: Node = _world._get_run_context()
	if run_context != null:
		var upload_payload := RUN_TELEMETRY_STORE.build_upload_payload(telemetry_run_id)
		if not upload_payload.is_empty():
			run_context.enqueue_telemetry_payload(upload_payload)


# --- room/event recording ----------------------------------------------------

func close_active_room(extra_fields: Dictionary = {}) -> void:
	if not can_record():
		return
	var event_data := {
		"room_ended_at_unix": int(Time.get_unix_time_from_system())
	}
	for key_variant in extra_fields.keys():
		event_data[key_variant] = extra_fields[key_variant]
	RUN_TELEMETRY_STORE.finalize_last_room_entry(telemetry_run_id, event_data)

func record_room_entry(room_kind: String, profile: Dictionary) -> void:
	if not can_record():
		return
	var started_at_unix := int(Time.get_unix_time_from_system())
	var mutator_name := "none"
	var objective_kind := ""
	var bearing_label: String = _world.current_room_label
	var bearing_key := _bearing_key_from_label(bearing_label, room_kind)
	if not profile.is_empty():
		var mutator := ENCOUNTER_CONTRACTS.profile_enemy_mutator(profile)
		mutator_name = ENCOUNTER_CONTRACTS.mutator_name(mutator)
		if mutator_name.is_empty():
			mutator_name = "none"
		objective_kind = ENCOUNTER_CONTRACTS.profile_objective_kind(profile)
		bearing_label = ENCOUNTER_CONTRACTS.profile_label(profile)
		bearing_key = _bearing_key_from_profile(profile, room_kind)
	RUN_TELEMETRY_STORE.append_room_entry(telemetry_run_id, {
		"unix_time": started_at_unix,
		"room_started_at_unix": started_at_unix,
		"room_kind": room_kind,
		"room_label": _world.current_room_label,
		"bearing_key": bearing_key,
		"bearing_label": bearing_label,
		"enemy_mutator": mutator_name,
		"objective_kind": objective_kind,
		"room_depth": _world.room_depth,
		"rooms_cleared": _world.rooms_cleared
	})

func record_reward_choice(choice: Dictionary, mode: int, is_initial: bool) -> void:
	if not can_record():
		return
	var choice_id := String(choice.get("id", ""))
	var choice_name := String(choice.get("name", choice_id))
	if mode == ENUMS.RewardMode.MISSION:
		var mission_upgrade := choice.get("mission_upgrade", {}) as Dictionary
		if not mission_upgrade.is_empty():
			choice_id = String(mission_upgrade.get("id", choice_id))
			choice_name = String(mission_upgrade.get("name", choice_name))
	var event_data := {
		"unix_time": int(Time.get_unix_time_from_system()),
		"mode": mode,
		"choice_id": choice_id,
		"choice_name": choice_name,
		"is_initial": is_initial,
		"room_depth": _world.room_depth
	}
	if mode == ENUMS.RewardMode.BOSS:
		event_data["boss_id"] = _world.last_defeated_boss_id
	RUN_TELEMETRY_STORE.append_reward_choice(telemetry_run_id, event_data)

func record_reward_skip(mode: int, is_initial: bool, depth: int) -> void:
	if not can_record():
		return
	var event_data := {
		"unix_time": int(Time.get_unix_time_from_system()),
		"mode": mode,
		"choice_id": "",
		"choice_name": "skip",
		"is_initial": is_initial,
		"room_depth": depth,
		"skipped": true
	}
	RUN_TELEMETRY_STORE.append_reward_choice(telemetry_run_id, event_data)

func record_reward_offers(offers: Array[Dictionary], mode: int, is_initial: bool, stage: int) -> void:
	if not can_record():
		return
	if offers.is_empty():
		return
	var event_data := {
		"unix_time": int(Time.get_unix_time_from_system()),
		"mode": mode,
		"is_initial": is_initial,
		"stage": stage,
		"room_depth": _world.room_depth,
		"offers": offers.duplicate(true)
	}
	if mode == ENUMS.RewardMode.BOSS:
		event_data["boss_id"] = _world.last_defeated_boss_id
	RUN_TELEMETRY_STORE.append_reward_offers(telemetry_run_id, event_data)

func record_door_choice(choice: Dictionary) -> void:
	if not can_record():
		return
	var profile := ENCOUNTER_CONTRACTS.door_choice_profile(choice)
	var action_id := ENCOUNTER_CONTRACTS.door_choice_action_id(choice)
	var door_mutator := "none"
	var bearing_label := ENCOUNTER_CONTRACTS.profile_label(profile)
	var bearing_key := _bearing_key_from_profile(profile, "encounter")
	if action_id == ENUMS.EncounterAction.BOSS:
		if _world.second_boss_defeated:
			bearing_key = "lacuna"
			bearing_label = "Lacuna"
		elif _world.first_boss_defeated:
			bearing_key = "sovereign"
			bearing_label = "Sovereign"
		else:
			bearing_key = "warden"
			bearing_label = "Warden"
	elif action_id == ENUMS.EncounterAction.REST:
		bearing_key = "rest"
		bearing_label = "Rest Site"
	if not profile.is_empty():
		var mutator := ENCOUNTER_CONTRACTS.profile_enemy_mutator(profile)
		door_mutator = ENCOUNTER_CONTRACTS.mutator_name(mutator)
		if door_mutator.is_empty():
			door_mutator = "none"
	RUN_TELEMETRY_STORE.append_door_choice(telemetry_run_id, {
		"unix_time": int(Time.get_unix_time_from_system()),
		"action_id": action_id,
		"door_label": String(choice.get("label", "")),
		"reward_mode": ENCOUNTER_CONTRACTS.door_choice_reward_mode(choice),
		"encounter_label": ENCOUNTER_CONTRACTS.profile_label(profile),
		"bearing_key": bearing_key,
		"bearing_label": bearing_label,
		"enemy_mutator": door_mutator,
		"room_depth": _world.room_depth
	})

func record_player_damage_taken(raw_amount: int, final_amount: int, damage_context: Dictionary) -> void:
	if not can_record():
		return
	var context_copy := damage_context.duplicate(true)
	var current_bearing_key := _bearing_key_from_label(_world.current_room_label, "unknown")
	var objective_kind: String = ""
	if is_instance_valid(_world.objective_manager):
		objective_kind = String(_world.objective_manager.active_objective_kind)
	RUN_TELEMETRY_STORE.append_damage_event(telemetry_run_id, {
		"unix_time": int(context_copy.get("unix_time", Time.get_unix_time_from_system())),
		"source": String(context_copy.get("source", "unknown")),
		"ability": String(context_copy.get("ability", "unknown")),
		"raw_amount": raw_amount,
		"final_amount": final_amount,
		"health_before": int(context_copy.get("health_before", 0)),
		"health_after": int(context_copy.get("health_after", 0)),
		"room_label": _world.current_room_label,
		"bearing_key": current_bearing_key,
		"room_depth": _world.room_depth,
		"objective_kind": objective_kind,
		"active_enemies": _world.active_room_enemy_count,
		"difficulty_tier": _world.current_difficulty_tier,
		"character_id": _world.current_character_id
	})

func on_player_health_changed(current_health: int, _max_health: int, player_node: Node) -> void:
	if run_summary_tracker == null:
		return
	if not (player_node is Node2D):
		return
	var tracked_player := player_node as Node2D
	var peer_id: int = _world._get_player_network_id(tracked_player)
	var health_key := maxi(peer_id, 0)
	var last_health := int(_summary_last_player_health_by_peer.get(health_key, -1))
	if last_health < 0:
		_summary_last_player_health_by_peer[health_key] = current_health
		return
	var health_loss := last_health - current_health
	if health_loss > 0:
		run_summary_tracker.record_damage_taken(health_loss)
		if peer_id > 0:
			_add_peer_stat_delta(peer_id, "damage_taken_total", health_loss)
	_summary_last_player_health_by_peer[health_key] = current_health

func reconcile_damage_taken_to_player_health() -> void:
	if run_summary_tracker == null:
		return
	for player_node in _world._get_multiplayer_player_nodes():
		var player := player_node as PLAYER_SCRIPT
		if not is_instance_valid(player):
			continue
		var peer_id: int = _world._get_player_network_id(player)
		var health_key := maxi(peer_id, 0)
		var peer_current_health := player.get_current_health()
		var last_health := int(_summary_last_player_health_by_peer.get(health_key, -1))
		if last_health < 0:
			_summary_last_player_health_by_peer[health_key] = peer_current_health
			continue
		var peer_health_loss := last_health - peer_current_health
		if peer_health_loss > 0:
			run_summary_tracker.record_damage_taken(peer_health_loss)
			if peer_id > 0:
				_add_peer_stat_delta(peer_id, "damage_taken_total", peer_health_loss)
		_summary_last_player_health_by_peer[health_key] = peer_current_health

func build_death_event_snapshot() -> Dictionary:
	var death_event: Dictionary = {}
	for player_node in _world._get_multiplayer_player_nodes():
		var player := player_node as PLAYER_SCRIPT
		if not is_instance_valid(player):
			continue
		if not player.is_dead():
			continue
		death_event = player.get_last_damage_event().duplicate(true)
		if not death_event.is_empty():
			break
	if death_event.is_empty() and is_instance_valid(_world.player):
		death_event = _world.player.get_last_damage_event().duplicate(true)
	var objective_telemetry: Dictionary = {}
	var objective_manager := _world.objective_manager as OBJECTIVE_MANAGER_SCRIPT
	if is_instance_valid(objective_manager):
		objective_telemetry = objective_manager.get_telemetry_state()
	death_event["room_label"] = _world.current_room_label
	death_event["bearing_key"] = _bearing_key_from_label(_world.current_room_label, "unknown")
	death_event["room_depth"] = _world.room_depth
	death_event["objective_kind"] = String(objective_telemetry.get("objective_kind", ""))
	death_event["active_enemies"] = _world.active_room_enemy_count
	death_event["objective_player_inside"] = bool(objective_telemetry.get("objective_player_inside", false))
	death_event["objective_contested"] = bool(objective_telemetry.get("objective_contested", false))
	death_event["difficulty_tier"] = _world.current_difficulty_tier
	death_event["character_id"] = _world.current_character_id
	return death_event

func on_player_died_for_telemetry() -> void:
	reconcile_damage_taken_to_player_health()
	if not can_record():
		return
	if _world.is_multiplayer and _world._count_alive_players() > 0:
		return
	finish_run("death", build_death_event_snapshot())


# --- per-peer/tracker stats --------------------------------------------------

func record_enemy_kill_for_tracker() -> void:
	if run_summary_tracker == null:
		return
	run_summary_tracker.record_enemy_kill()

func record_damage_dealt(applied_amount: int, source_peer_id: int = 0) -> void:
	if run_summary_tracker == null:
		return
	run_summary_tracker.record_damage_dealt(applied_amount)
	if source_peer_id <= 0:
		return
	_add_peer_stat_delta(source_peer_id, "damage_dealt_total", maxi(0, applied_amount))

func record_peer_enemy_kill(peer_id: int) -> void:
	if peer_id <= 0:
		return
	_add_peer_stat_delta(peer_id, "enemies_killed", 1)
	if STAT_ATTRIBUTION_TRACE:
		print_debug("[StatAttribution][KillCredit] peer=%d kills=%d" % [peer_id, _get_peer_stat(peer_id, "enemies_killed")])

func record_boss_defeat(boss_id: String) -> void:
	if run_summary_tracker != null:
		run_summary_tracker.record_boss_defeat(boss_id)
	_record_boss_defeat_for_summary_peers()

func begin_boss_engagement_for_tracker(boss_id: String) -> void:
	if run_summary_tracker != null:
		run_summary_tracker.begin_boss_engagement(boss_id)

func record_hold_full_control_for_tracker() -> void:
	if run_summary_tracker != null:
		run_summary_tracker.record_hold_full_control()

func record_unlock(text: String) -> void:
	if run_summary_tracker == null:
		return
	run_summary_tracker.record_unlock(text)

func mark_full_clear_boss_credits(boss_total: int = 3) -> void:
	for peer_id_variant in _summary_stats_by_peer.keys():
		var peer_id := int(peer_id_variant)
		_set_peer_stat(peer_id, "bosses_defeated", boss_total)

func record_reward_choice_for_tracker(tracked_choice: Dictionary, mode: int, depth: int) -> void:
	if run_summary_tracker == null:
		return
	run_summary_tracker.record_reward_choice(tracked_choice, mode, depth)


# --- peer reward timeline ---------------------------------------------------

func record_peer_reward_timeline_choice(peer_id: int, choice: Dictionary, mode: int, depth: int, event_unix: int = 0) -> void:
	if peer_id <= 0:
		return
	if choice.is_empty():
		return
	var item_name := String(choice.get("name", choice.get("id", ""))).strip_edges()
	if item_name.is_empty():
		return
	var resolved_unix := event_unix
	if resolved_unix <= 0:
		resolved_unix = int(Time.get_unix_time_from_system())
	_append_peer_timeline_entry(peer_id, RUN_SUMMARY_MODEL_SCRIPT.create_timeline_entry(depth, mode, item_name, summary_category_for_mode(mode), resolved_unix))

func record_rest_visit(depth: int) -> void:
	var event_unix := int(Time.get_unix_time_from_system())
	if run_summary_tracker != null:
		run_summary_tracker.record_rest_visit(depth, event_unix)
	if not _world.is_multiplayer:
		return
	var rest_entry := RUN_SUMMARY_MODEL_SCRIPT.create_timeline_entry(depth, ENUMS.RewardMode.NONE, RUN_SUMMARY_MODEL_SCRIPT.REST_TIMELINE_LABEL, RUN_SUMMARY_MODEL_SCRIPT.CATEGORY_REST, event_unix)
	for peer_id_variant in _summary_reward_timeline_by_peer.keys():
		var peer_id := int(peer_id_variant)
		if peer_id <= 0:
			continue
		_append_peer_timeline_entry(peer_id, rest_entry.duplicate(true))


# --- summaries --------------------------------------------------------------

func build_peer_summary_overrides() -> Dictionary:
	var overrides := {}
	if not _world.is_multiplayer:
		return overrides
	for player_node in _world._get_multiplayer_player_nodes():
		var player := player_node as PLAYER_SCRIPT
		if not is_instance_valid(player):
			continue
		var peer_id: int = _world._get_player_network_id(player)
		if peer_id <= 0:
			continue
		var active_character := String(player.active_character_id).strip_edges().to_lower()
		if active_character.is_empty():
			active_character = _world.current_character_id
		var char_data := CHARACTER_REGISTRY.get_character(active_character)
		var character_name := String(char_data.get("name", active_character.capitalize()))
		var build_summary := build_summary_for_player(player)
		var timeline := _ensure_peer_reward_timeline(peer_id).duplicate(true)
		var build_ids: Array[String] = []
		for group_key in ["boons", "arcana", "boss_rewards"]:
			for item_variant in build_summary.get(group_key, []):
				var item := item_variant as Dictionary
				var item_id := String(item.get("id", "")).strip_edges().to_lower()
				if item_id.is_empty() or build_ids.has(item_id):
					continue
				build_ids.append(item_id)
		overrides[peer_id] = {
			"character_id": active_character,
			"character_name": character_name,
			"build_summary": build_summary,
			"reward_timeline": timeline,
			"build_ids": build_ids,
		}
	return overrides


func build_peer_telemetry_entries() -> Array:
	var entries: Array = []
	if not _world.is_multiplayer:
		return entries
	var run_context := _world._get_run_context() as RUN_CONTEXT_SCRIPT
	var host_peer_id := int(_world._resolve_local_peer_id())
	var seen_peer_ids: Dictionary = {}
	for player_node in _world._get_multiplayer_player_nodes():
		var player := player_node as PLAYER_SCRIPT
		if not is_instance_valid(player):
			continue
		var peer_id: int = _world._get_player_network_id(player)
		if peer_id <= 0 or seen_peer_ids.has(peer_id):
			continue
		seen_peer_ids[peer_id] = true
		var active_character := String(player.active_character_id).strip_edges().to_lower()
		if active_character.is_empty():
			active_character = _world.current_character_id
		var char_data := CHARACTER_REGISTRY.get_character(active_character)
		var character_name := String(char_data.get("name", active_character.capitalize()))
		var build_summary := build_summary_for_player(player)
		var timeline := _ensure_peer_reward_timeline(peer_id).duplicate(true)
		var stats := _ensure_peer_summary_stats(peer_id).duplicate(true)
		var build_ids: Array[String] = []
		for group_key in ["boons", "arcana", "boss_rewards"]:
			for item_variant in build_summary.get(group_key, []):
				var item := item_variant as Dictionary
				var item_id := String(item.get("id", "")).strip_edges().to_lower()
				if item_id.is_empty() or build_ids.has(item_id):
					continue
				build_ids.append(item_id)
		var peer_player_name := ""
		var peer_profile_uuid := ""
		if run_context != null:
			peer_player_name = String(run_context.get_peer_player_name(peer_id)).strip_edges()
			peer_profile_uuid = String(run_context.get_peer_profile_uuid(peer_id)).strip_edges().to_lower()
		if peer_id == host_peer_id and run_context != null:
			if peer_player_name.is_empty():
				peer_player_name = String(run_context.get_profile_name_or_default()).strip_edges()
			if peer_profile_uuid.is_empty():
				peer_profile_uuid = String(run_context.get_profile_uuid()).strip_edges().to_lower()
		if peer_player_name.is_empty():
			peer_player_name = "Player"
		entries.append({
			"peer_id": peer_id,
			"is_host": peer_id == host_peer_id,
			"player_name": peer_player_name,
			"player_uuid": peer_profile_uuid,
			"character_id": active_character,
			"character_name": character_name,
			"build_ids": build_ids,
			"build_summary": build_summary,
			"reward_timeline": timeline,
			"stats": stats,
		})
	entries.sort_custom(func(a, b):
		return int(a.get("peer_id", 0)) < int(b.get("peer_id", 0))
	)
	return entries

func build_summary_for_player(player_node: Node) -> Dictionary:
	var boons: Array[Dictionary] = []
	var arcana: Array[Dictionary] = []
	var boss_rewards: Array[Dictionary] = []
	var player := player_node as PLAYER_SCRIPT
	if not is_instance_valid(player):
		return {"boons": boons, "arcana": arcana, "boss_rewards": boss_rewards}
	for power_id_variant in POWER_REGISTRY.UPGRADE_BALANCE.keys():
		var power_id := String(power_id_variant)
		var stacks := player.get_upgrade_stack_count(power_id)
		if stacks <= 0:
			continue
		boons.append(RUN_SUMMARY_MODEL_SCRIPT.create_build_item(power_id, _resolve_power_display_name(power_id), RUN_SUMMARY_MODEL_SCRIPT.CATEGORY_BOON, stacks))
	for power_id_variant in POWER_REGISTRY.TRIAL_POWER_POOL_IDS:
		var power_id := String(power_id_variant)
		var stacks := player.get_trial_power_stack_count(power_id)
		if stacks <= 0:
			continue
		arcana.append(RUN_SUMMARY_MODEL_SCRIPT.create_build_item(power_id, _resolve_power_display_name(power_id), RUN_SUMMARY_MODEL_SCRIPT.CATEGORY_ARCANA, stacks))
	for power_id_variant in POWER_REGISTRY.BOSS_REWARD_BALANCE.keys():
		var power_id := String(power_id_variant)
		var stacks := player.get_upgrade_stack_count(power_id)
		if stacks <= 0:
			continue
		boss_rewards.append(RUN_SUMMARY_MODEL_SCRIPT.create_build_item(power_id, _resolve_power_display_name(power_id), RUN_SUMMARY_MODEL_SCRIPT.CATEGORY_BOSS_REWARD, stacks))
	boons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")).to_lower() < String(b.get("name", "")).to_lower()
	)
	arcana.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")).to_lower() < String(b.get("name", "")).to_lower()
	)
	boss_rewards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")).to_lower() < String(b.get("name", "")).to_lower()
	)
	return {
		"boons": boons,
		"arcana": arcana,
		"boss_rewards": boss_rewards,
	}

func summary_with_local_peer_stats(run_summary: Dictionary, stats_by_peer: Dictionary = {}) -> Dictionary:
	var summary := run_summary.duplicate(true)
	if stats_by_peer.is_empty():
		return summary
	var local_peer_id: int = _world._resolve_local_peer_id()
	if local_peer_id <= 0:
		return summary
	var local_stats := _lookup_peer_dictionary(stats_by_peer, local_peer_id)
	if local_stats.is_empty():
		return summary
	summary["stats"] = local_stats.duplicate(true)
	return summary

func summary_with_local_peer_overrides(run_summary: Dictionary, peer_summary_overrides: Dictionary = {}) -> Dictionary:
	var summary := run_summary.duplicate(true)
	if peer_summary_overrides.is_empty():
		return summary
	var local_peer_id: int = _world._resolve_local_peer_id()
	if local_peer_id <= 0:
		return summary
	var override := _lookup_peer_dictionary(peer_summary_overrides, local_peer_id)
	if override.is_empty():
		return summary
	for key in ["character_id", "character_name", "build_summary", "reward_timeline", "build_ids"]:
		if override.has(key):
			summary[key] = override.get(key)
	return summary

func finalize_synced_run_summary_for_joiner(synced_summary: Dictionary, outcome: String) -> void:
	if MultiplayerSessionManager.should_broadcast():
		return
	if telemetry_run_finished:
		return
	if synced_summary.is_empty():
		return
	var augmented := synced_summary.duplicate(true)
	if String(augmented.get("outcome", "")).strip_edges().is_empty():
		augmented["outcome"] = outcome
	var local_peer_id: int = _world._resolve_local_peer_id()
	var host_run_id := String(augmented.get("run_id", "")).strip_edges()
	if local_peer_id > 0 and not host_run_id.is_empty():
		augmented["run_id"] = "%s-p%d" % [host_run_id, local_peer_id]
	var run_context: Node = _world._get_run_context()
	if run_context != null:
		var local_uuid := String(run_context.get_profile_uuid()).strip_edges().to_lower()
		var local_name := String(run_context.get_profile_name_or_default()).strip_edges()
		if not local_uuid.is_empty():
			augmented["player_uuid"] = local_uuid
		if not local_name.is_empty():
			augmented["player_name"] = local_name
	if _world.current_player_profile != null and _world.current_player_profile.is_valid():
		augmented["player_uuid"] = _world.current_player_profile.player_id
		augmented["player_name"] = _world.current_player_profile.profile_name
	_apply_endgame_chase_progress(augmented)
	latest_run_summary = augmented
	RUN_HISTORY_STORE_SCRIPT.append(latest_run_summary)
	_world._enqueue_leaderboard_submission(latest_run_summary)
	telemetry_run_finished = true


# --- internals --------------------------------------------------------------

func _empty_peer_stats() -> Dictionary:
	return {
		"damage_dealt_total": 0,
		"damage_taken_total": 0,
		"enemies_killed": 0,
		"bosses_defeated": 0,
	}

func _ensure_peer_summary_stats(peer_id: int) -> Dictionary:
	if peer_id <= 0:
		return _empty_peer_stats()
	var stats := _lookup_peer_dictionary(_summary_stats_by_peer, peer_id)
	if stats.is_empty():
		stats = _empty_peer_stats()
		_set_peer_summary_stats(peer_id, stats)
	return stats

func _set_peer_summary_stats(peer_id: int, stats: Dictionary) -> void:
	if peer_id <= 0:
		return
	_summary_stats_by_peer[peer_id] = stats

func _get_peer_stat(peer_id: int, key: String) -> int:
	if peer_id <= 0:
		return 0
	var stats := _ensure_peer_summary_stats(peer_id)
	return int(stats.get(key, 0))

func _set_peer_stat(peer_id: int, key: String, value: int) -> void:
	if peer_id <= 0:
		return
	var stats := _ensure_peer_summary_stats(peer_id)
	stats[key] = value
	_set_peer_summary_stats(peer_id, stats)

func _add_peer_stat_delta(peer_id: int, key: String, delta: int) -> void:
	if peer_id <= 0 or delta == 0:
		return
	_set_peer_stat(peer_id, key, _get_peer_stat(peer_id, key) + delta)

func _ensure_peer_reward_timeline(peer_id: int) -> Array:
	if peer_id <= 0:
		return []
	var timeline := _lookup_peer_array(_summary_reward_timeline_by_peer, peer_id)
	if timeline.is_empty() and not _summary_reward_timeline_by_peer.has(peer_id):
		_set_peer_reward_timeline(peer_id, timeline)
	return timeline

func _set_peer_reward_timeline(peer_id: int, timeline: Array) -> void:
	if peer_id <= 0:
		return
	_summary_reward_timeline_by_peer[peer_id] = timeline

func _append_peer_timeline_entry(peer_id: int, entry: Dictionary) -> void:
	if peer_id <= 0 or entry.is_empty():
		return
	var timeline := _ensure_peer_reward_timeline(peer_id)
	timeline.append(entry)
	_set_peer_reward_timeline(peer_id, timeline)

func _lookup_peer_dictionary(source: Dictionary, peer_id: int) -> Dictionary:
	if peer_id <= 0 or source.is_empty():
		return {}
	var direct := source.get(peer_id, {}) as Dictionary
	if not direct.is_empty():
		return direct
	var as_string := source.get(str(peer_id), {}) as Dictionary
	if not as_string.is_empty():
		return as_string
	for key_variant in source.keys():
		if int(key_variant) != peer_id:
			continue
		var resolved := source.get(key_variant, {}) as Dictionary
		if not resolved.is_empty():
			return resolved
	return {}

func _lookup_peer_array(source: Dictionary, peer_id: int) -> Array:
	if peer_id <= 0 or source.is_empty():
		return []
	var direct: Variant = source.get(peer_id, null)
	if direct is Array:
		return direct as Array
	var as_string: Variant = source.get(str(peer_id), null)
	if as_string is Array:
		return as_string as Array
	for key_variant in source.keys():
		if int(key_variant) != peer_id:
			continue
		var resolved: Variant = source.get(key_variant, null)
		if resolved is Array:
			return resolved as Array
	return []

## Apply ascension clear records + oath completions + catalyst unlocks to the
## meta-progress profile based on the just-built run summary. Mutates
## `latest_run_summary["unlocks"]` to surface human-readable labels on the
## defeat/victory screen.
func _apply_endgame_chase_progress(run_summary: Dictionary) -> void:
	var run_context: Node = _world._get_run_context()
	if run_context == null:
		return
	var profile: Dictionary = run_context.meta_progress_profile
	if profile.is_empty():
		return
	var changed: bool = false
	var summary_unlocks: Array = run_summary.get("unlocks", []) as Array
	var outcome: String = String(run_summary.get("outcome", "")).to_lower()
	var is_clear: bool = outcome == "clear" or outcome == "victory" or outcome == "win"
	var character_id: String = String(run_summary.get("character_id", "")).strip_edges().to_lower()
	if is_clear and not character_id.is_empty():
		var rank: int = int(run_summary.get("ascension_rank", 0))
		if rank > 0:
			if META_PROGRESS_STORE.record_ascension_clear(profile, character_id, rank):
				changed = true
				summary_unlocks.append("Ascension Rank %d cleared" % rank)
	var results: Dictionary = OATHS_EVALUATOR.evaluate_run(run_summary, profile)
	if OATHS_EVALUATOR.apply_results_to_profile(profile, results):
		changed = true
	for label_variant in results.get("labels", []):
		summary_unlocks.append(String(label_variant))
	run_summary["unlocks"] = summary_unlocks
	if changed:
		run_context.save_meta_progress()

func _record_boss_defeat_for_summary_peers() -> void:
	var tracked_peer_ids: Dictionary = {}
	for peer_id_variant in _summary_stats_by_peer.keys():
		var peer_id := int(peer_id_variant)
		if peer_id > 0:
			tracked_peer_ids[peer_id] = true
	for player_node in _world._get_multiplayer_player_nodes():
		if not is_instance_valid(player_node):
			continue
		var peer_id: int = _world._get_player_network_id(player_node)
		if peer_id > 0:
			tracked_peer_ids[peer_id] = true
	for peer_id_variant in tracked_peer_ids.keys():
		var peer_id := int(peer_id_variant)
		_add_peer_stat_delta(peer_id, "bosses_defeated", 1)

func _bearing_key_from_label(label: String, fallback: String = "unknown") -> String:
	return BEARING_KEY_NORMALIZER.from_label(label, fallback)

func _bearing_key_from_profile(profile: Dictionary, fallback: String = "unknown") -> String:
	return BEARING_KEY_NORMALIZER.from_profile(profile, fallback)

func _resolve_power_display_name(power_id: String) -> String:
	var power_registry_instance := _world.power_registry_instance as POWER_REGISTRY
	if power_registry_instance != null:
		var resolved := String(power_registry_instance.get_power_display_name(power_id)).strip_edges()
		if not resolved.is_empty():
			return resolved
	var fallback := power_id.strip_edges().to_lower()
	return fallback.capitalize() if not fallback.is_empty() else power_id
