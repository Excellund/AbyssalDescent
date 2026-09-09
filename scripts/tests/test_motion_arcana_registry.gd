extends SceneTree

const REGISTRY := preload("res://scripts/power_registry.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const UPGRADES := preload("res://scripts/upgrade_system.gd")
const DESCRIPTION_GUARD := preload("res://scripts/shared/description_cap_guard.gd")
const GLOSSARY := preload("res://scripts/shared/glossary_data.gd")
const MOTION := preload("res://scripts/arcana_motion_controller.gd")
const MOTION_IDS: Array[String] = ["blast_drive", "razor_orbit"]

class TestPlayer extends Node:
	var values: Dictionary = {"damage": 20, "attack_cooldown": 0.28, "dash_cooldown": 0.42}

	func _get(property: StringName) -> Variant:
		return values.get(String(property), 0)

	func _set(property: StringName, value: Variant) -> bool:
		values[String(property)] = value
		return true

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _check_description(text: String, power_id: String, level: int, surface: String) -> void:
	var visible := DESCRIPTION_GUARD.strip_bbcode(text)
	_check(not visible.is_empty(), "%s L%d %s is present" % [power_id, level, surface])
	var lines := visible.split("\n", false)
	_check(visible.length() <= DESCRIPTION_GUARD.MAX_VISIBLE_CARD_CHARS, "%s L%d %s full explanation fits: %d chars" % [power_id, level, surface, visible.length()])
	_check(lines.size() == 2 and String(lines[-1]).length() <= DESCRIPTION_GUARD.MAX_VISIBLE_DESC_CHARS, "%s L%d %s separates its explanation from a compact numeric line" % [power_id, level, surface])
	_check(visible.contains("Damage") and visible.contains("reach"), "%s %s names both scaling parameters" % [power_id, surface])
	if power_id == "blast_drive":
		_check(visible.contains("Hold Attack") and visible.contains("release"), "Blast %s explains the existing hold/release control" % surface)
		_check(visible.contains("2 charges") if level >= 2 else visible.contains("1 charge"), "Blast L%d %s shows charge capacity" % [level, surface])
		_check(visible.contains("steer") == (level >= 3), "Blast L%d %s shows steering at its actual unlock" % [level, surface])
	else:
		var lower := visible.to_lower()
		_check(lower.contains("dash") and (lower.contains("hold") or lower.contains("held")) and lower.contains("release"), "Orbit %s explains the existing hold/release control" % surface)
		_check(lower.contains("column") == (level >= 2), "Orbit L%d %s shows column anchors at their actual unlock" % [level, surface])
		_check(lower.contains("transfer once") == (level >= 3) and (level < 3 or lower.contains("anchor dies") and lower.contains("2.4 seconds total")), "Orbit L%d %s shows one bounded transfer on anchor death at its actual unlock" % [level, surface])

func _run() -> void:
	var registry := REGISTRY.new()
	var pool := registry.get_trial_power_pool()
	for power_id in MOTION_IDS:
		var matches := 0
		for entry in pool:
			if String(entry.get("id", "")) == power_id:
				matches += 1
		_check(matches == 1, "%s appears exactly once in the shared Arcana pool" % power_id)
		_check(registry.get_power_stack_limit(power_id) == 3, "%s has a three-level cap" % power_id)
		_check(registry.get_power_display_name(power_id) == ("Blast Drive" if power_id == "blast_drive" else "Razor Orbit"), "%s has canonical display metadata" % power_id)
		var damage_model := registry.get_damage_model(power_id)
		_check(String(damage_model.get("scale_source", "")) == "damage_stat", "%s damage metadata matches runtime scaling" % power_id)
		var player := TestPlayer.new()
		var upgrades := UPGRADES.new()
		upgrades.initialize(player, null, registry)
		for level in range(1, 4):
			var preview := upgrades.get_trial_power_card_description(power_id)
			_check_description(preview, power_id, level, "card")
			_check(upgrades.apply_trial_power(power_id), "%s level %d applies" % [power_id, level])
			var expected_scale := 1.0 + 0.15 * float(level - 1)
			var current := MAPPER.get_current_values(power_id, player)
			_check(is_equal_approx(float(current.get("damage_scale", 0.0)), expected_scale), "%s L%d writes correct damage scale" % [power_id, level])
			_check(is_equal_approx(float(current.get("reach_scale", 0.0)), expected_scale), "%s L%d writes correct reach scale" % [power_id, level])
			_check(bool(player.get("reward_" + power_id)), "%s enables the controller flag" % power_id)
			_check(upgrades.get_trial_power_stack_count(power_id) == level, "%s writes controller level %d" % [power_id, level])
			_check_description(upgrades.get_power_current_description(power_id), power_id, level, "current")
			var expected_damage_text := "x%.2f" % (MOTION.BLAST_DAMAGE_MULT_MAX * expected_scale) if power_id == "blast_drive" else "%.1f%%" % (MOTION.ORBIT_CUT_DAMAGE_RATIO * 100.0 * expected_scale)
			_check(DESCRIPTION_GUARD.strip_bbcode(preview).contains(expected_damage_text), "%s card previews its real hit damage ratio" % power_id)
		var prismatic_preview := upgrades.get_trial_power_card_description(power_id)
		_check_description(prismatic_preview, power_id, 3, "Prismatic card")
		var expected_damage_upgrade := "x%.2f -> x%.2f" % [MOTION.BLAST_DAMAGE_MULT_MAX * 1.30, MOTION.BLAST_DAMAGE_MULT_MAX * 1.56] if power_id == "blast_drive" else "%.1f%% -> %.1f%%" % [MOTION.ORBIT_CUT_DAMAGE_RATIO * 130.0, MOTION.ORBIT_CUT_DAMAGE_RATIO * 156.0]
		_check(DESCRIPTION_GUARD.strip_bbcode(prismatic_preview).contains(expected_damage_upgrade), "%s Prismatic previews its actual hit damage change" % power_id)
		_check(upgrades.can_claim_trial_power_prismatic(power_id), "%s offers Prismatic at the cap" % power_id)
		_check(upgrades.apply_trial_power(power_id), "%s Prismatic applies" % power_id)
		_check(upgrades.has_trial_power_prismatic(power_id), "%s stores Prismatic state" % power_id)
		_check(upgrades.get_trial_power_stack_count(power_id) == 3, "%s Prismatic preserves level 3" % power_id)
		_check(is_equal_approx(float(player.get(power_id + "_damage_scale")), 1.56), "%s Prismatic increases damage" % power_id)
		_check(is_equal_approx(float(player.get(power_id + "_reach_scale")), 1.56), "%s Prismatic increases reach" % power_id)
		_check(not upgrades.can_claim_trial_power_prismatic(power_id), "%s cannot offer another Prismatic" % power_id)
		_check(not upgrades.apply_trial_power(power_id), "%s rejects repeated Prismatic" % power_id)
		_check_description(upgrades.get_power_current_description(power_id), power_id, 3, "Prismatic current")
		player.set(power_id + "_damage_scale", 1.42)
		var live_text := DESCRIPTION_GUARD.strip_bbcode(upgrades.get_power_current_description(power_id))
		var expected_live_damage := "Full blast x%.2f Damage" % (MOTION.BLAST_DAMAGE_MULT_MAX * 1.42) if power_id == "blast_drive" else "Cut damage %.1f%% of Damage" % (MOTION.ORBIT_CUT_DAMAGE_RATIO * 142.0)
		var expected_live_reach := "reach %.0f" % ((MOTION.BLAST_RANGE_MAX if power_id == "blast_drive" else MOTION.ORBIT_ACQUIRE_RANGE) * 1.56)
		_check(live_text.contains(expected_live_damage) and live_text.contains(expected_live_reach), "%s current text reads independent live values" % power_id)
		for property in ["reward_" + power_id, power_id + "_stacks", power_id + "_damage_scale", power_id + "_reach_scale"]:
			_check(MAPPER.get_all_snapshot_properties().has(property), "%s is declared for snapshot integration" % property)
		upgrades.free()
		player.free()
	var glossary := GLOSSARY.glossary_bbcode()
	_check(glossary.contains("Blast Drive") and glossary.contains("Razor Orbit"), "Glossary includes both new Arcana")
	_check(glossary.contains("0.25") and glossary.contains("0.65"), "Glossary explains deliberate and full charge timings")
	_check(glossary.contains("Level 2") and glossary.contains("Level 3"), "Glossary explains structural upgrades")
	_check(not glossary.contains("door reveal"), "Catalyst glossary no longer promises an absent reward")
	registry.free()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("Motion Arcana registry regressions: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
