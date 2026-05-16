extends RefCounted
class_name RunSummaryTracker

const RUN_SUMMARY_MODEL := preload("res://scripts/core/run_summary_model.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")

var started_at_unix: int = 0
var started_at_msec: int = 0
var character_id: String = ""
var character_name: String = ""
var difficulty_tier: int = 0
var difficulty_label: String = "Pilgrim"
var game_version: String = "dev"
var leaderboard_patch_key: String = "dev"
var player_uuid: String = ""
var player_name: String = ""
var is_multiplayer: bool = false
var player_count: int = 1

var total_damage_dealt: int = 0
var total_damage_taken: int = 0
var enemies_killed: int = 0
var bosses_defeated: int = 0

var boon_items: Dictionary = {}
var arcana_items: Dictionary = {}
var boss_reward_items: Dictionary = {}
var reward_timeline: Array[Dictionary] = []
var unlocks: Array[String] = []

## Endgame chase tracking (Ascension + Oaths). Host-tracked.
var ascension_rank: int = 0
var ascension_loadout: Array[String] = []
var equipped_catalyst_ids: Array[String] = []
var boss_no_hit_ids: Array[String] = []
var hold_full_control_achieved: bool = false
var rest_count: int = 0
var primary_attacks_fired: int = 0
var _bosses_with_damage_taken: Dictionary = {}
var _active_boss_id: String = ""

func reset_for_run(run_seed: Dictionary) -> void:
	started_at_unix = int(run_seed.get("started_at_unix", Time.get_unix_time_from_system()))
	started_at_msec = int(run_seed.get("started_at_msec", Time.get_ticks_msec()))
	character_id = String(run_seed.get("character_id", "unknown")).strip_edges().to_lower()
	character_name = String(run_seed.get("character_name", character_id.capitalize())).strip_edges()
	difficulty_tier = int(run_seed.get("difficulty_tier", 0))
	difficulty_label = String(run_seed.get("difficulty_label", "Pilgrim")).strip_edges()
	game_version = String(run_seed.get("game_version", "dev")).strip_edges()
	leaderboard_patch_key = String(run_seed.get("leaderboard_patch_key", game_version)).strip_edges()
	player_uuid = String(run_seed.get("player_uuid", "")).strip_edges().to_lower()
	player_name = String(run_seed.get("player_name", "")).strip_edges()
	is_multiplayer = bool(run_seed.get("is_multiplayer", false))
	player_count = maxi(1, int(run_seed.get("player_count", 1)))
	total_damage_dealt = 0
	total_damage_taken = 0
	enemies_killed = 0
	bosses_defeated = 0
	boon_items.clear()
	arcana_items.clear()
	boss_reward_items.clear()
	reward_timeline.clear()
	unlocks.clear()
	ascension_rank = int(run_seed.get("ascension_rank", 0))
	var loadout_raw: Variant = run_seed.get("ascension_loadout", [])
	ascension_loadout.clear()
	if loadout_raw is Array:
		for entry in loadout_raw:
			ascension_loadout.append(String(entry))
	var catalysts_raw: Variant = run_seed.get("equipped_catalyst_ids", [])
	equipped_catalyst_ids.clear()
	if catalysts_raw is Array:
		for entry in catalysts_raw:
			equipped_catalyst_ids.append(String(entry))
	boss_no_hit_ids.clear()
	hold_full_control_achieved = false
	rest_count = 0
	primary_attacks_fired = 0
	_bosses_with_damage_taken.clear()
	_active_boss_id = ""

func record_damage_dealt(amount: int) -> void:
	total_damage_dealt += maxi(0, amount)

func record_damage_taken(amount: int) -> void:
	total_damage_taken += maxi(0, amount)
	if amount > 0 and not _active_boss_id.is_empty():
		_bosses_with_damage_taken[_active_boss_id] = true

func record_enemy_kill() -> void:
	enemies_killed += 1

func record_boss_defeat(_boss_id: String = "") -> void:
	bosses_defeated += 1
	var id: String = String(_boss_id).strip_edges().to_lower()
	if id.is_empty():
		id = _active_boss_id
	if not id.is_empty() and not _bosses_with_damage_taken.has(id):
		if not boss_no_hit_ids.has(id):
			boss_no_hit_ids.append(id)
	_active_boss_id = ""

## Boss fight bracketing: boss enemy id is opened on engage, closed on defeat/death.
func begin_boss_engagement(boss_id: String) -> void:
	_active_boss_id = String(boss_id).strip_edges().to_lower()

func end_boss_engagement() -> void:
	_active_boss_id = ""

func record_hold_full_control() -> void:
	hold_full_control_achieved = true

func record_primary_attack_fired() -> void:
	primary_attacks_fired += 1

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
	summary["ascension_loadout"] = ascension_loadout.duplicate()
	summary["equipped_catalyst_ids"] = equipped_catalyst_ids.duplicate()
	summary["boss_no_hit_ids"] = boss_no_hit_ids.duplicate()
	summary["hold_full_control_achieved"] = hold_full_control_achieved
	summary["rest_count"] = rest_count
	summary["primary_attacks_fired"] = primary_attacks_fired
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
