extends "res://scripts/tests/test_blast_feedback.gd"
## Description checks compare real upgrades and hit outcomes with their UI text.

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
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
	_test_voidfire_lockout_description()
	_test_boss_stat_displays()
	await _test_reward_resize()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Power descriptions: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_boss_stat_displays() -> void:
	_make_world(0)
	var target := _enemy(Vector2(30.0, 0.0))
	for level in range(1, 3):
		player.apply_upgrade("wardens_verdict")
		player.apex_predator_combo_hits = 0
		var bonuses: Array[int] = []
		for contact in range(4):
			bonuses.append(player._get_apex_predator_bonus(target, target.global_position, 100))
		var current := _text("wardens_verdict")
		var flat_range := "+%d–%d" % [bonuses[0], bonuses[3] - 42]
		_check(current.contains("Hit bonus " + flat_range), "Warden L%d shows the actual first-to-fourth flat contact bonuses" % level)
		_check(bonuses[1] > bonuses[0] and bonuses[2] > bonuses[1] and bonuses[3] - 42 > bonuses[2], "Warden's four native contacts grow through the advertised range")
		_check(current.contains("fourth +42% attack damage") and current.contains("Burst radius %.0f" % player._get_apex_predator_burst_radius()), "Warden separates the fourth-hit Attack bonus and native Burst reach")
	_free_world()
	_make_world(0)
	player.player_id = 1
	for level in range(1, 3):
		player.apply_upgrade("lacuna_echo")
		for live_damage in [20, 80]:
			player.damage = live_damage
			var pulse_target := _enemy(Vector2(40.0, 0.0))
			player._apply_void_echo(pulse_target.global_position)
			var current := _text("lacuna_echo")
			var shown_ratio := current.get_slice("Field bonus +", 1).get_slice("%", 0).to_float() / 100.0
			var base_pulse := current.get_slice("base pulse ", 1).get_slice("/", 0).to_int()
			_check(is_equal_approx(shown_ratio, 0.203 if level == 1 else 0.266), "Lacuna L%d shows the intended resolved Field bonus" % level)
			_check(player._get_void_echo_zone_bonus(pulse_target, 1000) == int(round(shown_ratio * 1000.0)), "Lacuna's displayed Field bonus matches its native zone modifier")
			var zone: Dictionary = player.void_echo_zones[0]
			var card := DESCRIPTION_GUARD.strip_bbcode(player.upgrade_system.get_upgrade_card_description("lacuna_echo"))
			_check(current.contains("radius %.0f" % float(zone.radius)) and card.contains("well for %.1fs" % float(zone.life)), "Lacuna displays its actual radius and states its fixed lifetime in the explanation")
			var before := pulse_target.get_current_health()
			player._update_void_echo_zones(0.01)
			_check(before - pulse_target.get_current_health() == int(round(base_pulse * (1.0 + shown_ratio))), "Displayed Lacuna base pulse and Field bonus explain native damage at Damage %d, level %d" % [live_damage, level])
			_check(current.contains("base pulse %d/%.2fs" % [base_pulse, float(player.void_echo_zones[0].pulse_left)]), "Lacuna displays the native base pulse and cadence")
			pulse_target.free()
	_free_world()

func _test_voidfire_lockout_description() -> void:
	_make_world()
	for level in range(1, 5):
		var preview := DESCRIPTION_GUARD.strip_bbcode(player.get_trial_power_card_desc("voidfire"))
		player.apply_trial_power("voidfire")
		player._trigger_voidfire_detonation()
		var actual_lock := "%.2fs" % player._voidfire_lockout_left
		var preview_lock := preview.get_slice("lockout ", 1).trim_suffix(".")
		if preview_lock.contains(" -> "):
			preview_lock = preview_lock.get_slice(" -> ", 1)
		_check(preview_lock == actual_lock, "Voidfire L%d preview shows the actual Attack lock, including L3 halving" % level)
		_check(_text("voidfire").contains("lockout " + actual_lock), "Voidfire current description matches native overheat")
		_check(preview.contains("High Heat:") and preview.contains("overheating releases a damaging Burst") and preview.contains("empties the Heat bar"), "Voidfire card distinguishes its conditional Attack bonus, overheat Burst and resource reset")
	_free_world()

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
			var title: Label = rewards.boon_card_title_labels[index]
			var stack: Label = rewards.boon_card_stack_labels[index]
			_check(title.position.x + title.size.x <= stack.position.x, "Title keeps clear of the level indicator at %d" % width)
			_check(label.position.y >= maxf(title.position.y + title.size.y, stack.position.y + stack.size.y), "Full-width description sits below the header at %d" % width)
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
	for power_id in ["eclipse_mark", "null_corridor", "static_wake", "storm_crown", "hunters_snare", "sovereigns_double"]:
		_make_world()
		var trial: bool = REGISTRY.TRIAL_POWER_DEFINITIONS.has(power_id)
		var levels := 4 if trial else 2
		for level in range(1, levels + 1):
			var preview := player.get_trial_power_card_desc(power_id) if trial else player.get_upgrade_card_desc(power_id)
			_check_card_bounds(preview, "%s L%d" % [power_id, level])
			if trial:
				player.apply_trial_power(power_id)
			else:
				player.apply_upgrade(power_id)
			# Build details may add a separate explanatory paragraph above the capped stat sentence.
			var current_lines := _text(power_id).split("\n")
			var current_sentence := String(current_lines[current_lines.size() - 1]).strip_edges()
			_check(current_sentence.length() <= 109, "%s L%d complete current stat sentence fits" % [power_id, level])
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
		_check(current.contains("%.1f%% Damage each way" % ratio) and current.contains("reach %.0f" % reach), "Crescent L%d current text exposes its real flight damage/range" % level)
		_check(current.contains("2 blades") if level >= 2 else current.contains("1 blade"), "Crescent L%d describes its actual blade capacity" % level)
		_check(current.contains("wall bounce") == (level >= 3), "Crescent L%d describes the outbound bounce at the right unlock" % level)
		_check_card_bounds(preview, "Crescent L%d preview" % level)
		_check_current_bounds(current, "Crescent L%d current" % level)
		_check(registry.get_trial_power_pool(player).any(func(entry: Dictionary) -> bool: return entry["id"] == "returning_crescent" and entry["desc"] == player.get_trial_power_card_desc("returning_crescent")), "Crescent shared reward pool reads the same live card description")
	_check(player.get_trial_power_stack_count("returning_crescent") == 3 and player.upgrade_system.has_trial_power_prismatic("returning_crescent"), "Crescent descriptions retain the single Prismatic system")
	registry.free()
	_free_world()

func _test_bloodpact_sign() -> void:
	_make_world()
	for level in range(1, 4):
		player.upgrade_system.apply_upgrade("bloodpact")
		var current := _text("bloodpact")
		_check(current.contains("Damage +%d" % player.bloodpact_bonus_damage) and not current.contains("++"), "Bloodpact L%d displays its bonus with one plus sign" % level)
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
				_check(text.contains("Full blast x%.2f Damage" % (MOTION.BLAST_DAMAGE_MULT_MAX * damage_scale)) and text.contains("reach %.0f" % (MOTION.BLAST_RANGE_MAX * reach_scale)), "Blast L%d displays full-charge values rather than internal scales" % level)
			else:
				player.arcana_motion.start_orbit(enemy)
				player.arcana_motion._apply_cut_contacts(origin, origin + Vector2(4.0, 0.0))
				var actual_damage := 10000 - enemy.get_current_health()
				_check(actual_damage == int(round(float(player.damage) * MOTION.ORBIT_CUT_DAMAGE_RATIO * damage_scale)), "Orbit L%d cut damage matches its description ratio" % level)
				_check(text.contains("Cut damage %.1f%% of Damage" % (MOTION.ORBIT_CUT_DAMAGE_RATIO * 100.0 * damage_scale)) and text.contains("hook reach %.0f" % (MOTION.ORBIT_ACQUIRE_RANGE * reach_scale)), "Orbit L%d displays cut ratio and acquisition reach" % level)
				_check(text.contains("1.4 seconds") and text.to_lower().contains("release to depart") and (level < 3 or text.contains("transfer once, up to 2.4 seconds total")), "Orbit description states its lifetime, early release and unlocked transfer cap")
			_check_current_bounds(text, "%s L%d current" % [power_id, level])
			_free_world()

func _check_card_bounds(text: String, context: String) -> void:
	var plain := DESCRIPTION_GUARD.strip_bbcode(text)
	var lines := plain.split("\n", false)
	_check(plain.length() <= DESCRIPTION_GUARD.MAX_VISIBLE_CARD_CHARS, "%s complete explanation and stats fit the bounded card" % context)
	_check(lines.size() == 2, "%s contains a separate mechanic explanation and numeric line" % context)
	if not lines.is_empty():
		_check(String(lines[-1]).length() <= DESCRIPTION_GUARD.MAX_VISIBLE_DESC_CHARS, "%s numeric line retains the existing compact cap" % context)

func _check_current_bounds(text: String, context: String) -> void:
	var plain := DESCRIPTION_GUARD.strip_bbcode(text)
	var lines := plain.split("\n", false)
	_check(plain.length() <= DESCRIPTION_GUARD.MAX_VISIBLE_CARD_CHARS, "%s current explanation remains bounded" % context)
	_check(lines.size() == 2, "%s owned build keeps its mechanic explanation above the numeric line" % context)
	_check(not lines.is_empty() and String(lines[-1]).length() <= DESCRIPTION_GUARD.MAX_VISIBLE_DESC_CHARS, "%s current numeric line retains the compact cap" % context)

func _test_mark_and_corridor_descriptions() -> void:
	_make_world()
	var enemy := _enemy(Vector2(35.0, 0.0))
	for level in range(1, 4):
		player.apply_trial_power("eclipse_mark")
		player._apply_eclipse_mark(enemy.global_position)
		var text := _text("eclipse_mark")
		_check(text.contains("Mark") and text.contains("%.2fs" % player.eclipse_mark_duration) and not text.contains("hits"), "Eclipse L%d describes its timed vulnerability" % level)
		var mark := DAMAGEABLE.status_snapshot(enemy, player.player_id)
		_check(is_equal_approx(float(mark.mark_ratio), player.eclipse_mark_bonus_ratio), "Eclipse L%d applies the displayed vulnerability" % level)
		for _index in range(4):
			var before_hit := enemy.get_current_health()
			var action := player.new_combat_action("attack")
			var context := preload("res://scripts/shared/combat_interaction_registry.gd").damage_context(action, "melee", {"damage_coefficient": 1.0, "raw_amount": 20.0, "attack_origin": player.global_position})
			DAMAGEABLE.apply_damage(enemy, 20, context, player.player_id)
			_check(enemy.get_current_health() < before_hit - 20, "Eclipse L%d amplifies damage without consuming Mark" % level)
		_check(is_equal_approx(float(DAMAGEABLE.status_snapshot(enemy, player.player_id).mark_ratio), player.eclipse_mark_bonus_ratio), "Four damage events do not spend the timed Mark")
		DAMAGEABLE._target_status(enemy).advance(player.eclipse_mark_duration + 0.01)
		_check(float(DAMAGEABLE.status_snapshot(enemy, player.player_id).mark_ratio) == 0.0, "Eclipse expires at its displayed duration")
	player.upgrade_system.apply_upgrade("null_corridor")
	player._apply_null_corridor_segment(enemy.global_position - Vector2(30.0, 0.0), enemy.global_position + Vector2(30.0, 0.0))
	var before := enemy.get_current_health()
	player._update_null_corridor_segments(0.01)
	var first_damage := before - enemy.get_current_health()
	player._update_null_corridor_segments(0.1)
	_check(first_damage > 0 and enemy.get_current_health() == before - first_damage, "Null Corridor respects its per-target tick cooldown")
	player._update_null_corridor_segments(0.41)
	var marked_tick := int(round(float(first_damage) * 1.1))
	_check(enemy.get_current_health() == before - first_damage - marked_tick and enemy.velocity.is_zero_approx(), "A stationary enemy takes the next tick with its preexisting Mark after half a second, without displacement")
	_check(_text("null_corridor").contains("same enemy again after half a second"), "Null Corridor describes repeated damage within a trail's lifetime")
	var registry := REGISTRY.new()
	_check(String(registry.get_damage_model("null_corridor")["formula_note"]).contains("24%/28%"), "Null Corridor metadata reflects the existing two reward levels")
	registry.free()
	_free_world()
