extends RefCounted
class_name RunSummaryTracker

const RUN_SUMMARY_MODEL := preload("res://scripts/core/run_summary_model.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")
const PROVENANCE := preload("res://scripts/core/run_provenance.gd")
const TELEMETRY := preload("res://scripts/run_telemetry_store.gd")
const CATALYST_REGISTRY := preload("res://scripts/progression/catalyst_registry.gd")

var started_at_unix: int = 0
var started_at_msec: int = 0
var character_id: String = ""
var character_name: String = ""
var difficulty_tier: int = 0
var difficulty_label: String = "Pilgrim"
var game_version: String = "dev"
var _runtime_game_version: String = "dev"
var run_provenance: Dictionary = {}
var _expected_provenance_peers: Dictionary = {}
var _received_provenance_peers: Dictionary = {}
var leaderboard_patch_key: String = "dev"
var player_uuid: String = ""
var player_name: String = ""
var is_multiplayer: bool = false
var player_count: int = 1

var total_damage_dealt: int = 0
var total_damage_taken: int = 0
var enemies_killed: int = 0
var bosses_defeated: int = 0
var reached_act: int = 0
var defeated_boss_ids: Array[String] = []

var boon_items: Dictionary = {}
var arcana_items: Dictionary = {}
var boss_reward_items: Dictionary = {}
var reward_timeline: Array[Dictionary] = []
var unlocks: Array[String] = []

## Endgame chase: shared encounter facts, local actions and frozen run setup.
var ascension_rank: int = 0
var ascension_tracking_complete: bool = true
var ascension_loadout: Array[String] = []
var equipped_catalyst_ids: Array[String] = []
var boss_no_hit_ids: Array[String] = []
var hold_full_control_achieved: bool = false
var rest_count: int = 0
var primary_attacks_fired: int = 0
var dashes_performed: int = 0
var dash_tracking_complete: bool = true
## -1 means unknown history; a later difficulty change cannot certify it.
var oath_min_difficulty_tier: int = -1
var oath_difficulty_verified: bool = false
var catalyst_tracking_complete: bool = false
var full_run_tracking_complete: bool = true
var _bosses_with_damage_taken: Dictionary = {}
var _active_boss_id: String = ""
var _active_boss_peer_ids: Array[int] = []
var _active_boss_damaged_peers: Dictionary = {}
var _boss_no_hit_ids_by_peer: Dictionary = {}

func reset_for_run(run_seed: Dictionary) -> void:
	started_at_unix = int(run_seed.get("started_at_unix", Time.get_unix_time_from_system()))
	started_at_msec = int(run_seed.get("started_at_msec", Time.get_ticks_msec()))
	character_id = String(run_seed.get("character_id", "unknown")).strip_edges().to_lower()
	character_name = String(run_seed.get("character_name", character_id.capitalize())).strip_edges()
	oath_min_difficulty_tier = _validated_oath_tier(run_seed.get("difficulty_tier"))
	difficulty_tier = oath_min_difficulty_tier
	oath_difficulty_verified = oath_min_difficulty_tier == BEARING_ENUMS.BearingTier.FORSWORN
	difficulty_label = String(run_seed.get("difficulty_label", "Pilgrim")).strip_edges()
	game_version = String(run_seed.get("game_version", "dev")).strip_edges()
	_runtime_game_version = game_version
	run_provenance = PROVENANCE.start(game_version, bool(run_seed.get("is_debug", false)))
	_expected_provenance_peers.clear()
	_received_provenance_peers.clear()
	leaderboard_patch_key = String(run_seed.get("leaderboard_patch_key", game_version)).strip_edges()
	player_uuid = String(run_seed.get("player_uuid", "")).strip_edges().to_lower()
	player_name = String(run_seed.get("player_name", "")).strip_edges()
	is_multiplayer = bool(run_seed.get("is_multiplayer", false))
	player_count = maxi(1, int(run_seed.get("player_count", 1)))
	total_damage_dealt = 0
	total_damage_taken = 0
	enemies_killed = 0
	bosses_defeated = 0
	reached_act = 1
	defeated_boss_ids.clear()
	boon_items.clear()
	arcana_items.clear()
	boss_reward_items.clear()
	reward_timeline.clear()
	unlocks.clear()
	ascension_rank = int(run_seed.get("ascension_rank", 0))
	ascension_tracking_complete = bool(run_seed.get("ascension_tracking_complete", true))
	if difficulty_tier != BEARING_ENUMS.BearingTier.FORSWORN:
		ascension_rank = 0
	var loadout_raw: Variant = run_seed.get("ascension_loadout", [])
	ascension_loadout.clear()
	if loadout_raw is Array and difficulty_tier == BEARING_ENUMS.BearingTier.FORSWORN:
		for entry in loadout_raw:
			ascension_loadout.append(String(entry))
	var catalysts_raw: Variant = run_seed.get("equipped_catalyst_ids", [])
	catalyst_tracking_complete = run_seed.has("equipped_catalyst_ids") and _valid_catalyst_ids(catalysts_raw)
	equipped_catalyst_ids.clear()
	if catalysts_raw is Array:
		for entry in catalysts_raw:
			equipped_catalyst_ids.append(String(entry))
	boss_no_hit_ids.clear()
	hold_full_control_achieved = false
	rest_count = 0
	primary_attacks_fired = 0
	dashes_performed = 0
	dash_tracking_complete = true
	full_run_tracking_complete = true
	_bosses_with_damage_taken.clear()
	_active_boss_id = ""
	_active_boss_peer_ids.clear()
	_active_boss_damaged_peers.clear()
	_boss_no_hit_ids_by_peer.clear()

func record_damage_dealt(amount: int) -> void:
	total_damage_dealt += maxi(0, amount)

func record_damage_taken(amount: int, peer_id: int = 0) -> void:
	total_damage_taken += maxi(0, amount)
	if amount > 0 and not _active_boss_id.is_empty():
		_bosses_with_damage_taken[_active_boss_id] = true
		_active_boss_damaged_peers[peer_id] = true

func record_enemy_kill() -> void:
	enemies_killed += 1

func record_boss_defeat(_boss_id: String = "") -> void:
	bosses_defeated += 1
	var id: String = String(_boss_id).strip_edges().to_lower()
	if id.is_empty():
		id = _active_boss_id
	if id in ["warden", "sovereign", "lacuna"] and not defeated_boss_ids.has(id):
		defeated_boss_ids.append(id)
	# A defeat without a matching engagement is not evidence of a clean fight.
	if not id.is_empty() and id == _active_boss_id and not _bosses_with_damage_taken.has(id):
		if not boss_no_hit_ids.has(id):
			boss_no_hit_ids.append(id)
	if not id.is_empty() and id == _active_boss_id:
		for peer_id in _active_boss_peer_ids:
			if _active_boss_damaged_peers.has(peer_id):
				continue
			var peer_ids: Array = _boss_no_hit_ids_by_peer.get(peer_id, [])
			if not peer_ids.has(id):
				peer_ids.append(id)
			_boss_no_hit_ids_by_peer[peer_id] = peer_ids
	end_boss_engagement()

func record_act_entry(act: int) -> void:
	if act >= 1 and act <= 3:
		reached_act = maxi(reached_act, act)

func restore_descent_facts(checkpoint: Dictionary) -> void:
	# Old checkpoints did not store act/boss identity. Do not reconstruct them
	# from depth or a victory count: debug starts and partial resumes can differ.
	reached_act = 0
	var saved_act: Variant = checkpoint.get("reached_act")
	if (saved_act is int or saved_act is float) and saved_act >= 1 and saved_act <= 3 and float(saved_act) == floor(float(saved_act)):
		reached_act = int(saved_act)
	defeated_boss_ids.clear()
	var saved_bosses: Variant = checkpoint.get("defeated_boss_ids", [])
	if saved_bosses is Array:
		for id in saved_bosses:
			if id is String and id in ["warden", "sovereign", "lacuna"] and not defeated_boss_ids.has(id):
				defeated_boss_ids.append(id)

## Boss fight bracketing: boss enemy id is opened on engage, closed on defeat/death.
func begin_boss_engagement(boss_id: String, participating_peer_ids: Array = [0]) -> void:
	_active_boss_id = String(boss_id).strip_edges().to_lower()
	_bosses_with_damage_taken.erase(_active_boss_id)
	_active_boss_peer_ids.clear()
	_active_boss_damaged_peers.clear()
	for peer_id in participating_peer_ids:
		if not _active_boss_peer_ids.has(int(peer_id)):
			_active_boss_peer_ids.append(int(peer_id))

func end_boss_engagement() -> void:
	_active_boss_id = ""
	_active_boss_peer_ids.clear()
	_active_boss_damaged_peers.clear()

func get_boss_no_hit_ids_for_peer(peer_id: int) -> Array:
	return (_boss_no_hit_ids_by_peer.get(peer_id, []) as Array).duplicate()

## Doorway saves preserve the evidence for whole-run Oaths, not just the build.
func build_checkpoint() -> Dictionary:
	return {
		"run_provenance": resolved_run_provenance(),
		"total_damage_dealt": total_damage_dealt,
		"total_damage_taken": total_damage_taken,
		"enemies_killed": enemies_killed,
		"bosses_defeated": bosses_defeated,
		"reached_act": reached_act,
		"defeated_boss_ids": defeated_boss_ids.duplicate(),
		"boss_no_hit_ids": boss_no_hit_ids.duplicate(),
		"hold_full_control_achieved": hold_full_control_achieved,
		"rest_count": rest_count,
		"primary_attacks_fired": primary_attacks_fired,
		"dashes_performed": dashes_performed,
		"dash_tracking_complete": dash_tracking_complete,
		"oath_min_difficulty_tier": oath_min_difficulty_tier,
		"oath_difficulty_verified": oath_difficulty_verified,
		"oath_start_difficulty_tier": difficulty_tier,
		"catalyst_tracking_complete": catalyst_tracking_complete,
		"equipped_catalyst_ids": equipped_catalyst_ids.duplicate(),
		"full_run_tracking_complete": full_run_tracking_complete,
		"ascension_tracking_complete": ascension_tracking_complete,
		"reward_timeline": reward_timeline.duplicate(true),
	}

func restore_checkpoint(checkpoint: Dictionary) -> void:
	restore_descent_facts(checkpoint)
	restore_run_provenance(checkpoint.get("run_provenance"))
	total_damage_dealt = maxi(0, int(checkpoint.get("total_damage_dealt", 0)))
	total_damage_taken = maxi(0, int(checkpoint.get("total_damage_taken", 0)))
	enemies_killed = maxi(0, int(checkpoint.get("enemies_killed", 0)))
	bosses_defeated = maxi(0, int(checkpoint.get("bosses_defeated", 0)))
	boss_no_hit_ids.clear()
	for id in checkpoint.get("boss_no_hit_ids", []):
		boss_no_hit_ids.append(String(id))
	hold_full_control_achieved = bool(checkpoint.get("hold_full_control_achieved", false))
	rest_count = maxi(0, int(checkpoint.get("rest_count", 0)))
	primary_attacks_fired = maxi(0, int(checkpoint.get("primary_attacks_fired", 0)))
	# Earlier saves have no Dash evidence. Unknown history must never become
	# a zero-Dash run, without invalidating unrelated tracked achievements.
	var saved_dashes: Variant = checkpoint.get("dashes_performed")
	var valid_dashes: bool = (saved_dashes is int or saved_dashes is float) and is_finite(float(saved_dashes)) and float(saved_dashes) >= 0.0 and float(saved_dashes) == floor(float(saved_dashes))
	dashes_performed = int(saved_dashes) if valid_dashes else 0
	var saved_dash_tracking: Variant = checkpoint.get("dash_tracking_complete")
	dash_tracking_complete = valid_dashes and saved_dash_tracking is bool and saved_dash_tracking
	var saved_difficulty: Dictionary = {
		"difficulty_tier": checkpoint.get("oath_start_difficulty_tier"),
		"oath_difficulty_verified": checkpoint.get("oath_difficulty_verified"),
	}
	if checkpoint.has("oath_min_difficulty_tier"):
		saved_difficulty["oath_min_difficulty_tier"] = checkpoint.oath_min_difficulty_tier
	oath_min_difficulty_tier = mini(oath_min_difficulty_tier, _oath_minimum_from_summary(saved_difficulty))
	oath_difficulty_verified = oath_min_difficulty_tier == BEARING_ENUMS.BearingTier.FORSWORN
	var saved_catalysts: Variant = checkpoint.get("equipped_catalyst_ids")
	var saved_catalyst_tracking: Variant = checkpoint.get("catalyst_tracking_complete")
	catalyst_tracking_complete = catalyst_tracking_complete and _valid_catalyst_ids(saved_catalysts) and saved_catalysts == equipped_catalyst_ids and saved_catalyst_tracking is bool and saved_catalyst_tracking
	full_run_tracking_complete = bool(checkpoint.get("full_run_tracking_complete", true))
	ascension_tracking_complete = ascension_tracking_complete and bool(checkpoint.get("ascension_tracking_complete", true))
	reward_timeline.clear()
	for entry in checkpoint.get("reward_timeline", []):
		if entry is Dictionary:
			reward_timeline.append((entry as Dictionary).duplicate(true))

func restore_run_provenance(saved: Variant) -> void:
	run_provenance = PROVENANCE.restore(saved, _runtime_game_version)
	game_version = String(run_provenance.origin_version) if run_provenance.origin_known else "unknown"
	leaderboard_patch_key = TELEMETRY.leaderboard_patch_key_from_version(game_version)

## Keep missing announcements out of the live evidence: a delayed valid peer
## may still arrive. Only a saved/final copy treats unknown participation as unknown.
func expect_peer_provenance(peer_id: int) -> void:
	if peer_id > 0:
		_expected_provenance_peers[peer_id] = true

func record_peer_provenance(peer_id: int, provenance: Dictionary) -> void:
	if not _expected_provenance_peers.has(peer_id):
		return
	_received_provenance_peers[peer_id] = true
	run_provenance = PROVENANCE.merge(run_provenance, provenance)

func resolved_run_provenance() -> Dictionary:
	for peer_id in _expected_provenance_peers:
		if not _received_provenance_peers.has(peer_id):
			return PROVENANCE.merge(run_provenance, null)
	return run_provenance.duplicate(true)

func record_hold_full_control() -> void:
	hold_full_control_achieved = true

func record_primary_attack_fired() -> void:
	primary_attacks_fired += 1

func record_normal_dash_started() -> void:
	dashes_performed += 1

func record_difficulty_applied(tier: int) -> void:
	# Neither a harder Bearing nor resuming can erase an easier/unknown segment.
	oath_min_difficulty_tier = mini(oath_min_difficulty_tier, _validated_oath_tier(tier))
	oath_difficulty_verified = oath_min_difficulty_tier == BEARING_ENUMS.BearingTier.FORSWORN

static func _validated_oath_tier(raw: Variant) -> int:
	if not (raw is int or raw is float) or not is_finite(float(raw)):
		return -1
	if raw < 0 or raw > BEARING_ENUMS.BearingTier.FORSWORN or float(raw) != floor(float(raw)):
		return -1
	return int(raw)

static func _oath_minimum_from_summary(summary: Dictionary) -> int:
	var actual_tier: int = _validated_oath_tier(summary.get("difficulty_tier"))
	if summary.has("oath_min_difficulty_tier"):
		return mini(actual_tier, _validated_oath_tier(summary.oath_min_difficulty_tier))
	# The previous format only certified whole runs on Forsworn. A missing
	# minimum on an easier run is unknown history, not evidence for that tier.
	var legacy_proof: Variant = summary.get("oath_difficulty_verified")
	if actual_tier == BEARING_ENUMS.BearingTier.FORSWORN and legacy_proof is bool and legacy_proof:
		return actual_tier
	return -1

static func _is_forsworn_evidence(raw: Variant) -> bool:
	return _validated_oath_tier(raw) == BEARING_ENUMS.BearingTier.FORSWORN

static func _valid_catalyst_ids(raw: Variant) -> bool:
	if not (raw is Array) or raw.size() > CATALYST_REGISTRY.get_slot_limit():
		return false
	var seen: Array[String] = []
	for entry in raw:
		if not (entry is String) or not CATALYST_REGISTRY.has_catalyst(entry) or seen.has(entry):
			return false
		seen.append(entry)
	return true

func record_unlock(unlock_label: String) -> void:
	var label := unlock_label.strip_edges()
	if label.is_empty():
		return
	if unlocks.has(label):
		return
	unlocks.append(label)

func record_reward_choice(choice: Dictionary, mode: int, depth: int, unix_time: int = 0) -> void:
	if choice.is_empty():
		return
	var item_id := String(choice.get("id", "")).strip_edges().to_lower()
	var item_name := String(choice.get("name", item_id)).strip_edges()
	if item_id.is_empty() or item_name.is_empty():
		return
	var category := _category_for_mode(mode)
	var container := _container_for_category(category)
	var existing := container.get(item_id, {}) as Dictionary
	if existing.is_empty():
		container[item_id] = RUN_SUMMARY_MODEL.create_build_item(item_id, item_name, category, 1)
	else:
		existing["stacks"] = int(existing.get("stacks", 1)) + 1
		container[item_id] = existing
	var event_unix := unix_time
	if event_unix <= 0:
		event_unix = int(Time.get_unix_time_from_system())
	reward_timeline.append(RUN_SUMMARY_MODEL.create_timeline_entry(depth, mode, item_name, category, event_unix))

func record_rest_visit(depth: int, unix_time: int = 0) -> void:
	rest_count += 1
	var event_unix := unix_time
	if event_unix <= 0:
		event_unix = int(Time.get_unix_time_from_system())
	reward_timeline.append(RUN_SUMMARY_MODEL.create_timeline_entry(depth, ENUMS.RewardMode.NONE, RUN_SUMMARY_MODEL.REST_TIMELINE_LABEL, RUN_SUMMARY_MODEL.CATEGORY_REST, event_unix))

func build_summary(final_state: Dictionary) -> Dictionary:
	var ended_at_unix := int(final_state.get("ended_at_unix", Time.get_unix_time_from_system()))
	var duration_seconds := int(final_state.get("duration_seconds", 0))
	if duration_seconds <= 0:
		duration_seconds = maxi(0, ended_at_unix - started_at_unix)
	var summary := RUN_SUMMARY_MODEL.create_summary({
		"run_id": String(final_state.get("run_id", "")),
		"outcome": String(final_state.get("outcome", "unknown")),
		"character_id": character_id,
		"character_name": character_name,
		"difficulty_tier": difficulty_tier,
		"difficulty_label": difficulty_label,
		"max_depth": int(final_state.get("max_depth", 0)),
		"rooms_cleared": int(final_state.get("rooms_cleared", 0)),
		"duration_seconds": duration_seconds,
		"started_at_unix": started_at_unix,
		"ended_at_unix": ended_at_unix,
		"game_version": game_version,
		"run_provenance": resolved_run_provenance(),
		"leaderboard_patch_key": leaderboard_patch_key,
		"player_uuid": player_uuid,
		"player_name": player_name,
		"is_multiplayer": is_multiplayer,
		"player_count": player_count,
		"death_event": (final_state.get("death_event", {}) as Dictionary).duplicate(true),
		"stats": RUN_SUMMARY_MODEL.create_stats(total_damage_dealt, total_damage_taken, enemies_killed, bosses_defeated),
		"build_summary": {
			"boons": _flatten_items(boon_items),
			"arcana": _flatten_items(arcana_items),
			"boss_rewards": _flatten_items(boss_reward_items),
		},
		"reward_timeline": reward_timeline.duplicate(true),
		"unlocks": unlocks.duplicate(),
		"timestamp_text": _format_timestamp(ended_at_unix),
	})
	summary["ascension_rank"] = ascension_rank
	summary["ascension_tracking_complete"] = ascension_tracking_complete
	summary["ascension_loadout"] = ascension_loadout.duplicate()
	summary["equipped_catalyst_ids"] = equipped_catalyst_ids.duplicate()
	summary["boss_no_hit_ids"] = boss_no_hit_ids.duplicate()
	summary["hold_full_control_achieved"] = hold_full_control_achieved
	summary["rest_count"] = rest_count
	summary["primary_attacks_fired"] = primary_attacks_fired
	summary["dashes_performed"] = dashes_performed
	summary["dash_tracking_complete"] = dash_tracking_complete
	summary["oath_min_difficulty_tier"] = oath_min_difficulty_tier
	summary["oath_difficulty_verified"] = oath_difficulty_verified
	summary["catalyst_tracking_complete"] = catalyst_tracking_complete
	summary["full_run_tracking_complete"] = full_run_tracking_complete
	if reached_act > 0:
		summary["reached_act"] = reached_act
	if not defeated_boss_ids.is_empty():
		summary["defeated_boss_ids"] = defeated_boss_ids.duplicate()
	return summary

func _category_for_mode(mode: int) -> String:
	if mode == ENUMS.RewardMode.BOSS:
		return RUN_SUMMARY_MODEL.CATEGORY_BOSS_REWARD
	if mode == ENUMS.RewardMode.ARCANA:
		return RUN_SUMMARY_MODEL.CATEGORY_ARCANA
	return RUN_SUMMARY_MODEL.CATEGORY_BOON

func _container_for_category(category: String) -> Dictionary:
	match category:
		RUN_SUMMARY_MODEL.CATEGORY_BOSS_REWARD:
			return boss_reward_items
		RUN_SUMMARY_MODEL.CATEGORY_ARCANA:
			return arcana_items
		_:
			return boon_items

func _flatten_items(container: Dictionary) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for item_id in container.keys():
		values.append((container[item_id] as Dictionary).duplicate(true))
	values.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")).to_lower() < String(b.get("name", "")).to_lower()
	)
	return values

func _format_timestamp(unix_time: int) -> String:
	if unix_time <= 0:
		return ""
	var dt := Time.get_datetime_dict_from_unix_time(unix_time)
	var year := int(dt.get("year", 0))
	var month := int(dt.get("month", 0))
	var day := int(dt.get("day", 0))
	var hour := int(dt.get("hour", 0))
	var minute := int(dt.get("minute", 0))
	return "%04d-%02d-%02d %02d:%02d" % [year, month, day, hour, minute]
