extends RefCounted
class_name RunSummaryModel

const CATEGORY_BOON := "boon"
const CATEGORY_ARCANA := "arcana"
const CATEGORY_BOSS_REWARD := "boss_reward"
const CATEGORY_REST := "rest"

const REST_TIMELINE_LABEL := "Rest Site"

const RARITY_COMMON := "common"
const RARITY_RARE := "rare"
const RARITY_EPIC := "epic"
const RARITY_LEGENDARY := "legendary"

static func rarity_for_category(category: String) -> String:
	match category:
		CATEGORY_BOSS_REWARD:
			return RARITY_LEGENDARY
		CATEGORY_ARCANA:
			return RARITY_EPIC
		CATEGORY_BOON:
			return RARITY_RARE
		_:
			return RARITY_COMMON

static func create_build_item(item_id: String, name: String, category: String, stacks: int, rarity: String = "") -> Dictionary:
	var resolved_rarity := rarity.strip_edges().to_lower()
	if resolved_rarity.is_empty():
		resolved_rarity = rarity_for_category(category)
	return {
		"id": item_id.strip_edges().to_lower(),
		"name": name.strip_edges(),
		"category": category,
		"stacks": maxi(1, stacks),
		"rarity": resolved_rarity,
	}

static func create_timeline_entry(depth: int, mode: int, label: String, category: String, unix_time: int) -> Dictionary:
	return {
		"depth": maxi(0, depth),
		"mode": mode,
		"label": label.strip_edges(),
		"category": category,
		"unix_time": maxi(0, unix_time),
	}

static func create_stats(damage_dealt_total: int, damage_taken_total: int, enemies_killed: int, bosses_defeated: int) -> Dictionary:
	return {
		"damage_dealt_total": maxi(0, damage_dealt_total),
		"damage_taken_total": maxi(0, damage_taken_total),
		"enemies_killed": maxi(0, enemies_killed),
		"bosses_defeated": maxi(0, bosses_defeated),
	}

static func create_summary(payload: Dictionary) -> Dictionary:
	var summary := payload.duplicate(true)
	if not summary.has("stats"):
		summary["stats"] = create_stats(0, 0, 0, 0)
	if not summary.has("build_summary"):
		summary["build_summary"] = {
			"boons": [],
			"arcana": [],
			"boss_rewards": [],
		}
	if not summary.has("reward_timeline"):
		summary["reward_timeline"] = []
	if not summary.has("unlocks"):
		summary["unlocks"] = []
	return summary
