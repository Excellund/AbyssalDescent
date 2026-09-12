extends RefCounted
## Counts learned sources, never proc strength, level investment or damage share.

const REGISTRY := preload("res://scripts/power_registry.gd")
const PASSIVES := preload("res://scripts/shared/character_passive_catalogue.gd")
const KEYWORDS := preload("res://scripts/shared/combat_keyword_catalogue.gd")
const ACTION_IDS := ["attack", "attack_hit", "dash", "kill", "recoil", "orbit"]

static func owned_levels(player: Node) -> Dictionary:
	var levels := {}
	if not is_instance_valid(player):
		return levels
	for id: String in REGISTRY.UPGRADE_BALANCE.keys() + REGISTRY.TRIAL_POWER_POOL_IDS + REGISTRY.BOSS_REWARD_BALANCE.keys():
		var level := int(player.get_trial_power_stack_count(id)) if REGISTRY.TRIAL_POWER_POOL_IDS.has(id) else int(player.get_upgrade_stack_count(id))
		if level > 0:
			levels[id] = level
	return levels

static func from_levels(levels: Dictionary, passive_id: String = "") -> Dictionary:
	var by_keyword := {}
	for id: String in levels:
		var level := int(levels[id])
		if level > 0:
			_add_source(by_keyword, id, level, false, REGISTRY.get_power_keyword_metadata(id, level))
	if PASSIVES.PASSIVES.has(passive_id):
		_add_source(by_keyword, passive_id, 1, true, PASSIVES.get_keyword_metadata(passive_id))
	var effects: Array[Dictionary] = []
	var actions: Array[Dictionary] = []
	for id: String in by_keyword:
		var entry: Dictionary = by_keyword[id]
		entry["count"] = entry.sources.size()
		if ACTION_IDS.has(id):
			actions.append(entry)
		else:
			effects.append(entry)
	effects.sort_custom(_before)
	actions.sort_custom(_before)
	return {"effects": effects, "actions": actions}

static func _add_source(entries: Dictionary, source_id: String, level: int, passive: bool, metadata: Dictionary) -> void:
	# Resolved producer/receiver metadata excludes prose examples and exclusions.
	var produces: Array = metadata.get("produces", [])
	var accepts: Array = metadata.get("accepts", [])
	var ids: Array = produces + accepts + metadata.get("conditions", [])
	var seen := {}
	for id: String in ids:
		if seen.has(id) or not KEYWORDS.KEYWORDS.has(id) or KEYWORDS.PLAIN_TERMS.has(id):
			continue
		seen[id] = true
		if not entries.has(id):
			entries[id] = {"id": id, "sources": [], "count": 0}
		entries[id].sources.append({"id": source_id, "level": level, "passive": passive, "produces": produces.has(id), "uses": accepts.has(id) or metadata.get("conditions", []).has(id)})

static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a.count != b.count:
		return a.count > b.count
	return String(KEYWORDS.KEYWORDS[a.id].label).nocasecmp_to(String(KEYWORDS.KEYWORDS[b.id].label)) < 0

static func compact_bbcode(summary: Dictionary, limit: int = 3) -> String:
	var entries: Array = summary.effects if not summary.effects.is_empty() else summary.actions
	if entries.is_empty():
		return "No keyword powers yet"
	var parts: Array[String] = []
	for entry: Dictionary in entries.slice(0, limit):
		parts.append("%s %d" % [KEYWORDS.keyword_bbcode(entry.id), entry.count])
	return "   ·   ".join(parts)
