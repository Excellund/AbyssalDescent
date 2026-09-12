extends RefCounted
## Detached sandbox data. Registry reads never consult or normalize a profile.

const CHARACTERS := preload("res://scripts/character_registry.gd")
const POWERS := preload("res://scripts/power_registry.gd")
const BOSSES := preload("res://scripts/shared/boss_catalogue.gd")
const BIOMES := preload("res://scripts/shared/biome_registry.gd")
const DIFFICULTY := preload("res://scripts/difficulty_config.gd")
const CATALYSTS := preload("res://scripts/progression/catalyst_registry.gd")
const ASCENSION := preload("res://scripts/progression/ascension_modifier_registry.gd")
const CARD_COPY := preload("res://scripts/shared/reward_card_copy.gd")
const UPGRADES := preload("res://scripts/upgrade_system.gd")
const WORDING := preload("res://scripts/shared/combat_keyword_catalogue.gd")
const ENEMIES := {
	"chaser": preload("res://scripts/enemy_chaser.gd"),
	"charger": preload("res://scripts/enemy_charger.gd"),
	"archer": preload("res://scripts/enemy_archer.gd"),
	"shielder": preload("res://scripts/enemy_shielder.gd"),
	"lurker": preload("res://scripts/enemy_lurker.gd"),
	"ram": preload("res://scripts/enemy_ram.gd"),
	"lancer": preload("res://scripts/enemy_lancer.gd"),
	"spectre": preload("res://scripts/enemy_spectre.gd"),
	"pyre": preload("res://scripts/enemy_pyre.gd"),
	"tether": preload("res://scripts/enemy_tether.gd"),
	"drifter": preload("res://scripts/enemy_drifter.gd"),
	"keeper": preload("res://scripts/enemy_keeper.gd"),
	"weaver": preload("res://scripts/enemy_weaver.gd"),
	"sentinel": preload("res://scripts/enemy_sentinel.gd"),
	"seamlock": preload("res://scripts/enemy_seamlock.gd"),
	"mirrorline": preload("res://scripts/enemy_mirrorline.gd"),
	"toll": preload("res://scripts/enemy_toll.gd"),
	"breakwater": preload("res://scripts/enemy_breakwater.gd"),
}
const FLOOR_MIN := 1
const FLOOR_MAX := 25
const ENCOUNTERS := preload("res://scripts/practice/practice_encounters.gd")
const APPLICABLE_CATALYSTS := ["damage_reduction", "starting_max_hp_bonus", "ascension_loadout_preset", "wave_interval_bonus"]
const APPLICABLE_ASCENSION := ["hardened_foes", "sharper_blades", "crowned_bosses", "glass_descent", "pilgrims_burden", "relentless_tide", "specialist_pressure", "shrunken_arcana"]
static var _catalogue: Dictionary = {}

static func defaults() -> Dictionary:
	return {"character_id": "bastion", "floor": 1, "bearing": 1, "biome_id": "shatterfield",
		"encounter_id": "warden", "powers": {}, "prismatic": [],
		"catalysts": [], "ascension": [], "enemy_ai": true, "invulnerable": false}

static func act_for_floor(floor_number: int) -> int:
	var depth := clampi(floor_number, FLOOR_MIN, FLOOR_MAX) - 1
	return 1 if depth <= 8 else (2 if depth <= 16 else 3)

static func catalogue(config: Dictionary = {}) -> Dictionary:
	if _catalogue.is_empty():
		_catalogue = _build_catalogue()
	var result := _catalogue.duplicate(true)
	var character_id: String = config.get("character_id", "bastion") if config.get("character_id", "bastion") is String else ""
	var bearing: int = config.get("bearing", 1) if config.get("bearing", 1) is int else -1
	for power: Dictionary in result.powers:
		var raw_level: Variant = (config.get("powers", {}) as Dictionary).get(power.id, 0) if config.get("powers", {}) is Dictionary else 0
		var level := clampi(raw_level, 0, int(power.max_level)) if raw_level is int else 0
		var is_prismatic: bool = config.get("prismatic", []) is Array and config.get("prismatic", []).has(power.id)
		if power.category != "boon":
			power.description = CARD_COPY.explanation(power.id, maxi(1, level), is_prismatic)
		power.description = ("Level %d / %d%s. " % [level, power.max_level, " · Prismatic" if is_prismatic else ""]) + String(power.description)
		power.available = not (character_id == "riftlancer" and power.id == "wide_arc")
		power.unavailable_reason = "Riftlancer keeps its fixed precision thrust." if not power.available else ""
	for modifier: Dictionary in result.ascension:
		if modifier.available and bearing != 3:
			modifier.available = false
			modifier.unavailable_reason = "Ascension applies to Forsworn only."
	return result

static func _build_catalogue() -> Dictionary:
	var result := {"characters": [], "bearings": [], "biomes": [], "encounters": ENCOUNTERS.entries(), "powers": [], "catalysts": [], "ascension": [],
		"floor_min": FLOOR_MIN, "floor_max": FLOOR_MAX,
		"floor_note": "Floor sets encounter depth and the act used by enemies and abilities. The selected encounter keeps its identity. Acts: 1–9 / 10–17 / 18–25."}
	for id: String in CHARACTERS.get_launch_character_ids():
		var character: Dictionary = CHARACTERS.get_character(id)
		result.characters.append({"id": id, "name": character.name, "description": String(character.get("tagline", ""))})
	for tier in range(4):
		var bearing := DIFFICULTY.get_tier_config(tier)
		result.bearings.append({"id": tier, "name": bearing.name, "description": bearing.description})
	for id: String in BIOMES.BIOME_DEFINITIONS:
		var biome := BIOMES.get_biome(id)
		result.biomes.append({"id": id, "name": biome.name, "description": WORDING.to_plain(String(BIOMES.get_combat_identity(id).get("rule", ""))), "act": biome.act})
	var registry := POWERS.new()
	var descriptions := UPGRADES.new()
	for power: Dictionary in registry.get_all_powers():
		var id := String(power.id)
		var category := "arcana" if id in POWERS.TRIAL_POWER_POOL_IDS else ("boss_reward" if id in POWERS.BOSS_REWARD_POOL_IDS else "boon")
		result.powers.append({"id": id, "name": power.name, "description": _boon_description(id, descriptions) if category == "boon" else CARD_COPY.explanation(id, 1), "category": category,
			"max_level": registry.get_power_stack_limit(id), "supports_prismatic": category == "arcana"})
	registry.free()
	descriptions.free()
	for id: String in CATALYSTS.get_catalyst_ids():
		var row := CATALYSTS.get_definition(id)
		row.merge({"id": id, "name": row.label, "available": id in APPLICABLE_CATALYSTS, "unavailable_reason": ""}, true)
		if not row.available:
			row.unavailable_reason = "Practice has no reward drafts or Rest Sites. Prismatic levels are edited directly."
		result.catalysts.append(row)
	for id: String in ASCENSION.get_modifier_ids():
		var row := ASCENSION.get_definition(id)
		row.merge({"id": id, "name": row.label, "available": id in APPLICABLE_ASCENSION, "unavailable_reason": ""}, true)
		if not row.available:
			row.unavailable_reason = "Practice does not generate routes or reward drafts. Named Trials already specify their mutator."
		result.ascension.append(row)
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var config := defaults()
	var errors: Array[String] = []
	var warnings: Array[String] = []
	for key: String in config:
		if raw.has(key):
			config[key] = raw[key].duplicate(true) if raw[key] is Array or raw[key] is Dictionary else raw[key]
	for key in ["character_id", "biome_id", "encounter_id"]:
		if not (config[key] is String):
			errors.append("Choose a valid %s." % key.replace("_id", ""))
	if not CHARACTERS.get_launch_character_ids().has(config.character_id):
		errors.append("Choose a registered Vessel.")
	if not BIOMES.BIOME_DEFINITIONS.has(config.biome_id):
		errors.append("Choose a registered biome.")
	if not (config.floor is int) or int(config.floor) < FLOOR_MIN or int(config.floor) > FLOOR_MAX:
		errors.append("Floor must be from %d to %d." % [FLOOR_MIN, FLOOR_MAX])
	if not (config.bearing is int) or int(config.bearing) < 0 or int(config.bearing) > 3:
		errors.append("Choose a registered Bearing.")
	for key in ["enemy_ai", "invulnerable"]:
		if not (config[key] is bool):
			errors.append("Invalid training option: " + key)
	var encounter_known := false
	for row: Dictionary in catalogue().encounters:
		if row.id == config.encounter_id:
			encounter_known = true
	if not encounter_known:
		errors.append("Choose a registered encounter.")
	if raw.has("enemies"):
		errors.append("Choose an encounter instead of an individual enemy roster.")
	var power_rows := {}
	for row: Dictionary in catalogue().powers:
		power_rows[row.id] = row
	if not (config.powers is Dictionary):
		errors.append("Invalid build levels.")
	else:
		for id: Variant in config.powers:
			var level: Variant = config.powers[id]
			if not power_rows.has(id) or not (level is int):
				errors.append("Unknown power or non-whole level: " + str(id))
			elif int(level) < 0 or int(level) > int(power_rows[id].max_level):
				errors.append("%s allows levels 0–%d." % [power_rows[id].name, power_rows[id].max_level])
	for key in ["prismatic", "catalysts", "ascension"]:
		if not (config[key] is Array):
			errors.append("Invalid " + key + " selection.")
			continue
		var seen := {}
		for id: Variant in config[key]:
			if not (id is String) or seen.has(id):
				errors.append("Invalid or repeated " + key + " selection.")
				continue
			seen[id] = true
			if key == "prismatic":
				if not power_rows.has(id) or not power_rows[id].supports_prismatic or not (config.powers is Dictionary) or config.powers.get(id, 0) != power_rows[id].max_level:
					errors.append("Prismatic requires a max-level Arcana: " + id)
			elif key == "catalysts" and id not in APPLICABLE_CATALYSTS:
				errors.append("This Catalyst has no applicable Practice effect: " + id)
			elif key == "ascension" and (id not in APPLICABLE_ASCENSION or config.bearing != 3):
				errors.append("Choose applicable Ascension modifiers with Forsworn.")
	if config.catalysts is Array and config.catalysts.size() > CATALYSTS.get_slot_limit():
		errors.append("Catalysts have two equipment slots.")
	if errors.is_empty() and config.ascension is Array and ASCENSION.compute_loadout_rank(config.ascension) > ASCENSION.MAX_ASCENSION_RANK:
		errors.append("Ascension has a maximum rank of %d." % ASCENSION.MAX_ASCENSION_RANK)
	if config.character_id is String and config.character_id == "riftlancer" and config.powers is Dictionary and config.powers.get("wide_arc", 0) is int and config.powers.get("wide_arc", 0) > 0:
		errors.append("Riftlancer keeps its fixed precision thrust and cannot equip Wide Arc.")
	return {"valid": errors.is_empty(), "config": config, "errors": errors, "warnings": warnings}

static func difficulty(config: Dictionary) -> Dictionary:
	var resolved := DIFFICULTY.get_tier_config_with_ascension(int(config.bearing), config.ascension)
	var payload := CATALYSTS.merge_payloads(config.catalysts)
	for key in ["player_damage_taken_mult", "enemy_contact_damage_mult"]:
		resolved[key] = float(resolved.get(key, 1.0)) * float(payload.get(key, 1.0))
	resolved["wave_interval_seconds"] = float(resolved.get("wave_interval_seconds", 8.0)) * float(payload.get("wave_interval_mult", 1.0))
	resolved["player_starting_health_bonus"] = float(resolved.get("player_starting_health_bonus", 0.0)) + float(payload.get("starting_max_hp_add", 0.0))
	return resolved

static func _boon_description(id: String, descriptions: Node) -> String:
	var balance: Dictionary = POWERS.UPGRADE_BALANCE[id]
	var args: Array = []
	var suffix := ""
	if id == "blink_dash":
		args = ["×%.2f" % float(balance.mult)]
		suffix = " Minimum %.2fs." % float(balance.min)
	elif id == "battle_trance":
		args = ["+%.0f%%" % (float(balance.add) * 100.0), "1.25s"]
	elif id == "wide_arc":
		args = ["+%.0f deg" % float(balance.add)]
		suffix = " Maximum %.0f deg." % float(balance.max)
	else:
		args = ["+%d" % int(balance.add)]
	return "Each pick: " + descriptions._power_sentence(id, args) + suffix
