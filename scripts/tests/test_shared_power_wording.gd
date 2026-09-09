extends "res://scripts/tests/test_motion_arcana_registry.gd"

const KEYWORDS := preload("res://scripts/shared/combat_keyword_catalogue.gd")
const PASSIVES := preload("res://scripts/shared/character_passive_catalogue.gd")
const CHARACTERS := preload("res://scripts/character_registry.gd")

func _run() -> void:
	_test_authored_keywords()
	_test_passive_wording()
	var registry := REGISTRY.new()
	for id in ["hunters_snare", "wraithstep", "eclipse_mark", "dread_resonance"]:
		var actor := TestPlayer.new()
		var upgrades := UPGRADES.new()
		upgrades.initialize(actor, null, registry)
		for pick in range(1, 5):
			var preview := upgrades.get_trial_power_card_description(id)
			_check(not preview.contains("{kw:"), "%s pick %d renders authored markers" % [id, pick])
			_check(upgrades.apply_trial_power(id), "%s pick %d applies through the real mapper" % [id, pick])
			var current := MAPPER.get_current_values(id, actor)
			var expected: float
			if id == "dread_resonance":
				expected = 0.024 if pick == 4 else 0.02
				_check(is_equal_approx(float(current.damage_ratio_per_stack), expected), "Dread uses percentage points, including fractional Prismatic")
				_check(int(current.max_stacks) == [8, 10, 12, 15][pick - 1], "Dread preserves level-specific per-foe stack caps")
				_check(is_equal_approx(float(current.mark_bonus_ratio), 0.10) and float(current.mark_duration) == 3.0, "Dread Mark stays 10% for 3s at every level")
			else:
				expected = ([0.20, 0.25, 0.30, 0.45] if id == "hunters_snare" else [0.15, 0.20, 0.25, 0.30])[pick - 1]
				_check(is_equal_approx(float(current.bonus_ratio), expected), "%s pick %d maps the approved ratio without rounding to integer damage" % [id, pick])
				if id == "eclipse_mark":
					_check(is_equal_approx(float(current.mark_duration), [4.0, 5.0, 6.0, 7.8][pick - 1]), "Eclipse lifetime and existing Prismatic duration agree")
			var saved := current.duplicate(true)
			actor.set("health", 17)
			actor.set("dash_cooldown", 0.37)
			for key in current:
				actor.set(MAPPER.get_property_name(id, key), -99)
			_check(upgrades.reapply_shared_power_parameters(id), "%s migration recalculates learned values" % id)
			_check(MAPPER.get_current_values(id, actor) == saved, "%s migrated parameters retain level and Prismatic" % id)
			_check(actor.get("health") == 17 and actor.get("dash_cooldown") == 0.37, "Migration leaves unrelated health and cooldown untouched")
		upgrades.free()
		actor.free()
	_test_metadata(registry)
	_test_whole_roster_cards(registry)
	_test_legacy_restore(registry)
	_test_farline_prismatic_acquisition(registry)
	registry.free()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[SharedPowerWording] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_passive_wording() -> void:
	var glossary := GLOSSARY._character_passives_section_bbcode()
	for character: Dictionary in CHARACTERS.get_launch_characters():
		var id := String(character.passive_id)
		_check(PASSIVES.PASSIVES.has(id), "Every launch character has shared passive rules: " + id)
		var short := PASSIVES.get_short_description(id)
		var detail := PASSIVES.get_description(id)
		_check(not short.contains("{kw:") and not detail.contains("{kw:"), "Passive surfaces render semantic spans: " + id)
		_check(short.contains(KEYWORDS.ACTION_COLOR) and detail.contains(KEYWORDS.ACTION_COLOR), "Passive actions use canonical keyword styling: " + id)
		_check(DESCRIPTION_GUARD.strip_bbcode(short).length() <= 150, "Character selection keeps a compact passive explanation: " + id)
		_check(glossary.contains(detail), "The glossary retains every full passive rule: " + id)
		var metadata := PASSIVES.get_keyword_metadata(id)
		for key in metadata.produces + metadata.accepts + metadata.description_keywords:
			_check(KEYWORDS.KEYWORDS.has(key), "Passive metadata uses registered properties: %s/%s" % [id, key])
		_check(not metadata.produces.has("attack_hit") and not metadata.produces.has("electric") and not metadata.produces.has("field") and not metadata.produces.has("push"), "Passive output does not promise extra attacks or unsupported properties: " + id)
		metadata.produces.append("electric")
		_check(not PASSIVES.get_keyword_metadata(id).produces.has("electric"), "Build matching cannot mutate shared passive metadata: " + id)
	_check(PASSIVES.get_keyword_metadata("farline_focus").attack_hit_sources == ["melee", "blast_drive"], "Farline eligibility excludes extended arcs even though they are attack hits")
	_check(PASSIVES.get_keyword_metadata("veilstep_rhythm").produces.has("dash"), "Veilstep exposes its real Dash refresh to build inspection")
	_check(PASSIVES.get_keyword_metadata("sigil_burst").accepts == ["dash", "attack_hit"], "Sigil readiness cannot be spent by arbitrary damage or a generic Field")

func _test_farline_prismatic_acquisition(registry: Node) -> void:
	var actor := TestPlayer.new()
	var upgrades := UPGRADES.new()
	upgrades.initialize(actor, null, registry)
	for pick in range(3):
		_check(upgrades.apply_trial_power("farline_volley"), "Farline reaches level 3 through ordinary acquisition")
	_check(int(actor.get("farline_volley_bonus_per_stack")) == 2 and int(actor.get("farline_volley_stack_cap")) == 5, "Ordinary Farline retains its fixed damage per stack and capacity")
	_check(upgrades.apply_trial_power("farline_volley"), "Eligible Farline receives its one-time Prismatic upgrade")
	_check(int(actor.get("farline_volley_bonus_per_stack")) == 3, "Prismatic Farline retains the existing +1 fixed damage per stack")
	_check(int(actor.get("farline_volley_stack_cap")) == 8 and is_equal_approx(float(actor.get("farline_volley_arc_per_stack")), 16.8), "Prismatic Farline retains its capacity and arc improvements")
	_check(not upgrades.apply_trial_power("farline_volley") and int(actor.get("farline_volley_bonus_per_stack")) == 3, "An extra Prismatic pick cannot stack another Farline bonus")
	_check(upgrades.apply_upgrade("heavy_blow"), "A later Damage Boon applies through the same upgrade system")
	_check(int(actor.get("farline_volley_bonus_per_stack")) == 3, "Damage-derived refresh preserves Farline's fixed Prismatic bonus")
	upgrades.free()
	actor.free()

func _test_authored_keywords() -> void:
	var authored := "{kw:attack} creates {kw:electric} damage; {kw:slow|Slowed} foes help. Hit and lightning flavor stay plain."
	var formatted := KEYWORDS.format_text(authored)
	_check(KEYWORDS.to_plain(authored) == "Attack creates Electric damage; Slowed foes help. Hit and lightning flavor stay plain.", "Formatting preserves exact authored wording")
	_check(formatted.contains(KEYWORDS.keyword_bbcode("slow", "Slowed")), "Aliases share the canonical keyword style")
	_check(KEYWORDS.keyword_ids(authored) == ["attack", "electric", "slow"], "Only explicitly authored semantic spans become keywords")
	_check(KEYWORDS.format_text(formatted) == formatted, "Formatting already formatted cards is idempotent")
	_check(KEYWORDS.format_text("Electric ornament, Hit and marksmanship") == "Electric ornament, Hit and marksmanship", "Ordinary prose is not broadly replaced")
	for id in KEYWORDS.KEYWORDS:
		var styled := KEYWORDS.keyword_bbcode(id)
		if KEYWORDS.PLAIN_TERMS.has(id):
			_check(styled == KEYWORDS.KEYWORDS[id].label, "%s remains ordinary prose or a stat name" % id)
		else:
			_check(styled.contains("[b]") and styled.contains("[color=#"), "%s has text and color emphasis" % id)
		_check(not String(KEYWORDS.KEYWORDS[id].definition).is_empty(), "%s has a shared definition" % id)
	_check(KEYWORDS.keyword_ids("{kw:damage_stat} and {kw:damage} with {kw:slow}") == ["slow"], "Damage terms do not become glossary keywords")

func _test_metadata(registry: Node) -> void:
	_check(not REGISTRY.get_power_keyword_metadata("hunters_snare", 1).accepts.has("damage"), "Snare L1 does not advertise automatic damage amplification")
	_check(REGISTRY.get_power_keyword_metadata("hunters_snare", 2).accepts.has("damage"), "Snare L2 advertises all qualifying damage")
	_check(not REGISTRY.get_power_keyword_metadata("static_wake", 2).produces.has("slow") and REGISTRY.get_power_keyword_metadata("static_wake", 3).produces.has("slow"), "Wake Slow compatibility follows actual level")
	_check(not REGISTRY.get_power_keyword_metadata("wraithstep", 1).produces.has("burst") and REGISTRY.get_power_keyword_metadata("wraithstep", 2).produces.has("burst"), "Wraith Burst is unavailable before level 2")
	_check(REGISTRY.get_power_keyword_metadata("storm_crown", 1).accepts == ["damage"], "Crown does not require Electric damage")
	_check(REGISTRY.get_power_keyword_metadata("aegis_field", 3).produces == ["slow"], "Aegis Pulse does not promise a persistent Field or damage")
	for pair in [["aegis_field", "Aegis Pulse"], ["fracture_field", "Fracture"], ["lacuna_echo", "Lacuna Well"]]:
		_check(registry.get_power_display_name(pair[0]) == pair[1], "Canonical names change without changing save IDs")
	for id in REGISTRY.UPGRADE_POOL_IDS + REGISTRY.TRIAL_POWER_POOL_IDS + REGISTRY.BOSS_REWARD_POOL_IDS:
		var data := REGISTRY.get_power_keyword_metadata(id, 3)
		_check(not data.description_keywords.is_empty() or not data.condition_text.is_empty(), "%s has authored build metadata" % id)
		for keyword in data.description_keywords:
			_check(KEYWORDS.KEYWORDS.has(keyword), "%s references known keyword %s" % [id, keyword])

func _test_whole_roster_cards(registry: Node) -> void:
	_check(DESCRIPTION_GUARD.MAX_VISIBLE_DESC_CHARS == 109 and DESCRIPTION_GUARD.MAX_VISIBLE_CARD_CHARS == 260, "Explanation space does not silently raise the compact stat-line cap")
	var boon_actor := TestPlayer.new()
	var boon_upgrades := UPGRADES.new()
	boon_upgrades.initialize(boon_actor, null, registry)
	boon_actor.set("battle_trance_duration", 1.25)
	for id in REGISTRY.UPGRADE_POOL_IDS + REGISTRY.BOSS_REWARD_POOL_IDS:
		var boss: bool = REGISTRY.BOSS_REWARD_POOL_IDS.has(id)
		for pick in range(1, 3 if boss else 2):
			var card := boon_upgrades.get_upgrade_card_description(id)
			_check(not card.contains("{kw:"), "%s renders authored card markers" % id)
			_check_card_contract(card, "%s pick %d" % [id, pick], boss)
			if boss:
				_check(boon_upgrades.apply_upgrade(id), "%s pick %d applies through normal acquisition" % [id, pick])
			_check_card_contract(boon_upgrades.get_power_current_description(id), "%s current %d" % [id, pick], boss)
	boon_upgrades.free()
	boon_actor.free()
	for id in REGISTRY.TRIAL_POWER_POOL_IDS:
		var actor := TestPlayer.new()
		var upgrades := UPGRADES.new()
		upgrades.initialize(actor, null, registry)
		for pick in range(1, 5):
			var card := upgrades.get_trial_power_card_description(id)
			_check_card_contract(card, "%s pick %d" % [id, pick], true)
			_check(upgrades.apply_trial_power(id), "%s normal acquisition remains available" % id)
			_check_card_contract(upgrades.get_power_current_description(id), "%s current pick %d" % [id, pick], true)
		upgrades.free()
		actor.free()

func _check_card_contract(card: String, context: String, explanatory: bool) -> void:
	var body := DESCRIPTION_GUARD.strip_bbcode(card)
	var lines := body.split("\n", false)
	_check(body.length() <= DESCRIPTION_GUARD.MAX_VISIBLE_CARD_CHARS, "%s complete card stays bounded: %s" % [context, body])
	_check(lines.size() == (2 if explanatory else 1), "%s separates one explanation from one stat line; Boons remain one line" % context)
	if lines.is_empty():
		return
	_check(String(lines[-1]).length() <= DESCRIPTION_GUARD.MAX_VISIBLE_DESC_CHARS, "%s compact stat line retains its 109-character cap" % context)
	if explanatory:
		_check(String(lines[0]).strip_edges().length() >= 20 and String(lines[0]) != String(lines[-1]), "%s has a real explanation instead of duplicating its stats" % context)

func _test_legacy_restore(registry: Node) -> void:
	var actor := TestPlayer.new()
	var upgrades := UPGRADES.new()
	upgrades.initialize(actor, null, registry)
	_check(not upgrades.reapply_shared_power_parameters("wraithstep"), "Empty legacy snapshot cannot grant a power")
	actor.set("reward_wraithstep", true)
	actor.set("wraithstep_mark_bonus_damage", 24)
	_check(upgrades.reapply_shared_power_parameters("wraithstep"), "A legacy learned flag without a level remains playable")
	_check(actor.get("wraithstep_stacks") == 1 and is_equal_approx(float(actor.get("wraithstep_mark_bonus_ratio")), 0.15), "Legacy flag fallback is L1, never inferred from an old damage scalar")
	actor.set("wraithstep_stacks", 0)
	upgrades.trial_power_stacks["wraithstep"] = 3
	upgrades.trial_power_prismatic_states["wraithstep"] = true
	_check(upgrades.reapply_shared_power_parameters("wraithstep"), "Restored learned-level backup can recover absent old stack properties")
	_check(actor.get("wraithstep_stacks") == 3 and is_equal_approx(float(actor.get("wraithstep_mark_bonus_ratio")), 0.30), "Legacy learned level and Prismatic are retained together")
	_check(not upgrades.reapply_shared_power_parameters("phantom_step"), "Migration cannot replay acquisition-only cooldown changes")
	upgrades.free()
	actor.free()
