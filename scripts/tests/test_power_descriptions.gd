extends "res://scripts/tests/test_blast_feedback.gd"
## Description checks compare real upgrades and hit outcomes with their UI text.

const DESCRIPTION_GUARD := preload("res://scripts/shared/description_cap_guard.gd")
const REGISTRY := preload("res://scripts/power_registry.gd")
const CRESCENT := preload("res://scripts/returning_crescent_controller.gd")
const REWARD_UI := preload("res://scripts/reward_selection_ui.gd")

func _run() -> void:
	_test_boon_current_values()
	_test_bloodpact_sign()
	await _test_motion_damage_descriptions()
	await _test_mark_and_corridor_descriptions()
	_test_complete_changed_cards()
	_test_returning_crescent_descriptions()
	await _test_reward_resize()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Power descriptions: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_reward_resize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var rewards := REWARD_UI.new()
	viewport.add_child(rewards)
	rewards._create_ui()
	for width in [1920, 1280, 960, 1920, 1280]:
		viewport.size = Vector2i(width, 720)
		rewards._on_viewport_size_changed()
		await process_frame
		for index in range(rewards.boon_card_panels.size()):
			var panel := rewards.boon_card_panels[index]
			var label := rewards.boon_card_labels[index]
			_check(panel.get_global_rect().end.x <= float(width), "Reward panel remains inside the viewport after resizing to %d" % width)
			_check(panel.size == rewards.boon_card_rects[index].size, "Visible reward and clickable rectangle agree at %d" % width)
			_check(label.size == label.custom_minimum_size, "Description width follows the new layout at %d" % width)
			_check(label.position.x + label.size.x < rewards.boon_card_stack_labels[index].position.x, "Description keeps clear of the level indicator at %d" % width)
	viewport.free()

func _text(power_id: String) -> String:
	return DESCRIPTION_GUARD.strip_bbcode(player.upgrade_system.get_power_current_description(power_id))

func _test_boon_current_values() -> void:
	var bindings := {
		"heavy_blow": ["damage", "Damage %d."],
		"wide_arc": ["attack_arc_degrees", "Attack arc %.0f deg."],
		"long_reach": ["attack_range", "Attack range %.0f."],
		"fleet_foot": ["max_speed", "Move speed %.0f."],
		"surge_step": ["dash_speed", "Dash speed %.0f."],
		"heartstone": ["max_health", "Max HP %d."]
	}
	for character_id in CHARACTER.CHARACTER_DEFINITIONS:
		_make_world()
		player.apply_character_package(CHARACTER.get_character(character_id))
		for power_id in bindings:
			var binding: Array = bindings[power_id]
			var preview := DESCRIPTION_GUARD.strip_bbcode(player.upgrade_system.get_upgrade_card_description(power_id))
			_check(player.upgrade_system.apply_upgrade(power_id), "%s applies %s through the real upgrade path" % [character_id, power_id])
			var current := _text(power_id)
			var value: Variant = player.get(binding[0])
			_check(current == String(binding[1]) % value, "%s %s shows the actual current stat" % [character_id, power_id])
			var stat_text := "%d" % int(value) if power_id in ["heavy_blow", "heartstone"] else "%.0f" % float(value)
			_check(preview.contains("-> " + stat_text), "%s %s card and resulting current stat agree" % [character_id, power_id])
			_check(current.length() <= 109, "%s build text fits the visible cap" % power_id)
		var snapshot := player.build_run_snapshot()
		var expected: Dictionary = {}
		for power_id in bindings:
			expected[power_id] = _text(power_id)
		player.apply_run_snapshot(snapshot)
		for power_id in bindings:
			_check(_text(power_id) == expected[power_id], "%s %s current text survives resume" % [character_id, power_id])
		_free_world()
	_make_world()
	player.attack_arc_degrees = 269.0
	var arc_preview := DESCRIPTION_GUARD.strip_bbcode(player.upgrade_system.get_upgrade_card_description("wide_arc"))
	player.upgrade_system.apply_upgrade("wide_arc")
	_check(player.attack_arc_degrees == 280.0 and arc_preview.contains("269° -> 280°"), "Wide Arc applies its existing clamp")
	_check(_text("wide_arc") == "Attack arc 280 deg.", "The build does not claim an uncapped +28 gain when only 11 degrees were added")
	_free_world()

func _test_complete_changed_cards() -> void:
	for power_id in ["eclipse_mark", "null_corridor"]:
		_make_world()
		var levels := 4 if power_id == "eclipse_mark" else 2
		for level in range(1, levels + 1):
			var trial: bool = power_id == "eclipse_mark"
			var preview := player.get_trial_power_card_desc(power_id) if trial else player.get_upgrade_card_desc(power_id)
			_check(DESCRIPTION_GUARD.visible_length(preview) <= 109, "%s L%d complete card fits with all controls and metrics" % [power_id, level])
			if trial:
				player.apply_trial_power(power_id)
			else:
				player.apply_upgrade(power_id)
			_check(_text(power_id).length() <= 109, "%s L%d complete current text fits" % [power_id, level])
		_free_world()

func _test_returning_crescent_descriptions() -> void:
	_make_world()
	var registry := REGISTRY.new()
	for level in range(1, 5):
		var preview := DESCRIPTION_GUARD.strip_bbcode(player.get_trial_power_card_desc("returning_crescent"))
		player.apply_trial_power("returning_crescent")
		var current := _text("returning_crescent")
		var ratio := CRESCENT.DAMAGE_RATIO * 100.0 * float(player.get("returning_crescent_damage_scale"))
		var reach := CRESCENT.OUTBOUND_DISTANCE * float(player.get("returning_crescent_reach_scale"))
		_check(preview.contains("%.1f%%" % ratio) and preview.contains("%.0f" % reach), "Crescent L%d previews the damage/range applied by the mapper" % level)
		_check(current.contains("Damage %.1f%% each way" % ratio) and current.contains("reach %.0f" % reach), "Crescent L%d current text exposes its real flight damage/range" % level)
		_check(current.contains("2 blades") if level >= 2 else current.contains("1 blade"), "Crescent L%d describes its actual blade capacity" % level)
		_check(current.contains("wall bounce") == (level >= 3), "Crescent L%d describes the outbound bounce at the right unlock" % level)
		_check(preview.length() <= 109 and current.length() <= 109, "Crescent L%d complete card/current text fits" % level)
		_check(registry.get_trial_power_pool(player).any(func(entry: Dictionary) -> bool: return entry["id"] == "returning_crescent" and entry["desc"] == player.get_trial_power_card_desc("returning_crescent")), "Crescent shared reward pool reads the same live card description")
	_check(player.get_trial_power_stack_count("returning_crescent") == 3 and player.upgrade_system.has_trial_power_prismatic("returning_crescent"), "Crescent descriptions retain the single Prismatic system")
	registry.free()
	_free_world()

func _test_bloodpact_sign() -> void:
	_make_world()
	for level in range(1, 4):
		player.upgrade_system.apply_upgrade("bloodpact")
		var current := _text("bloodpact")
		_check(current.contains("+%d damage" % player.bloodpact_bonus_damage) and not current.contains("++"), "Bloodpact L%d displays its bonus with one plus sign" % level)
	_free_world()

func _test_motion_damage_descriptions() -> void:
	for power_id in ["blast_drive", "razor_orbit"]:
		for level in range(1, 5):
			_make_world()
			# The base helper grants Blast once; reset that grant for equal level coverage.
			player.upgrade_system.reset()
			player.blast_drive_stacks = 0
			player.reward_blast_drive = false
			for _index in range(level):
				player.apply_trial_power(power_id)
			var text := _text(power_id)
			var origin := player.global_position
			var enemy := _enemy(Vector2(45.0, 0.0))
			await physics_frame
			var damage_scale := float(player.get(power_id + "_damage_scale"))
			var reach_scale := float(player.get(power_id + "_reach_scale"))
			if power_id == "blast_drive":
				player.arcana_motion.release_blast(1.0)
				var actual_damage := 10000 - enemy.get_current_health()
				_check(actual_damage == int(round(float(player.damage) * MOTION.BLAST_DAMAGE_MULT_MAX * damage_scale)), "Blast L%d full-charge damage matches its description ratio" % level)
				_check(text.contains("Full Damage x%.2f" % (MOTION.BLAST_DAMAGE_MULT_MAX * damage_scale)) and text.contains("reach %.0f" % (MOTION.BLAST_RANGE_MAX * reach_scale)), "Blast L%d displays full-charge values rather than internal scales" % level)
			else:
				player.arcana_motion._apply_cut_contacts(origin, origin + Vector2(4.0, 0.0))
				var actual_damage := 10000 - enemy.get_current_health()
				_check(actual_damage == int(round(float(player.damage) * MOTION.ORBIT_CUT_DAMAGE_RATIO * damage_scale)), "Orbit L%d cut damage matches its description ratio" % level)
				_check(text.contains("Damage %.1f%%" % (MOTION.ORBIT_CUT_DAMAGE_RATIO * 100.0 * damage_scale)) and text.contains("reach %.0f" % (MOTION.ORBIT_ACQUIRE_RANGE * reach_scale)), "Orbit L%d displays cut ratio and acquisition reach" % level)
				_check(text.contains("orbit 1.4s or release") and (level < 3 or text.contains("kill transfer 2.4s")), "Orbit description states its lifetime, early release and unlocked transfer cap")
			_check(text.length() <= 109, "%s L%d complete build text fits" % [power_id, level])
			_free_world()

func _test_mark_and_corridor_descriptions() -> void:
	_make_world()
	var enemy := _enemy(Vector2(35.0, 0.0))
	for level in range(1, 4):
		player.apply_trial_power("eclipse_mark")
		player._apply_eclipse_mark(enemy.global_position)
		var text := _text("eclipse_mark")
		_check(text.contains("lasts %d hits" % level) and not text.contains("First hit"), "Eclipse L%d describes its real hit allowance without contradicting it" % level)
		for _index in range(level):
			_check(player._consume_eclipse_mark_bonus(enemy, 20) > 0, "Eclipse L%d retains each promised marked hit" % level)
		_check(player._consume_eclipse_mark_bonus(enemy, 20) == 0, "Eclipse L%d expires after its displayed hit count" % level)
	player.upgrade_system.apply_upgrade("null_corridor")
	player._apply_null_corridor_segment(enemy.global_position - Vector2(30.0, 0.0), enemy.global_position + Vector2(30.0, 0.0))
	var before := enemy.get_current_health()
	player._update_null_corridor_segments(0.01)
	var first_damage := before - enemy.get_current_health()
	player._update_null_corridor_segments(0.1)
	_check(first_damage > 0 and enemy.get_current_health() == before - first_damage, "Null Corridor respects its deflection cooldown")
	player._update_null_corridor_segments(0.41)
	_check(enemy.get_current_health() == before - first_damage * 2, "A stationary enemy can be deflected again after 0.5 seconds")
	_check(_text("null_corridor").contains("at most every 0.5s"), "Null Corridor describes repeat deflections rather than a single lifetime hit")
	var registry := REGISTRY.new()
	_check(String(registry.get_damage_model("null_corridor")["formula_note"]).contains("24%/28%"), "Null Corridor metadata reflects the existing two reward levels")
	registry.free()
	_free_world()
