extends "res://scripts/tests/test_pulse_hud.gd"
## Visible HUD changes through real Player state and the public refresh contract.

const REFRESH_PLAYER := preload("res://scenes/Player.tscn")
const REFRESH_CHARACTERS := preload("res://scripts/character_registry.gd")
const REFRESH_PASSIVES := preload("res://scripts/shared/character_passive_catalogue.gd")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("HUD refresh invalidation tests require disposable user data")
		quit(1)
		return
	_prepare_pulse_world()
	_test_timer_refresh()
	_test_live_stats()
	_test_build_refresh()
	_test_biome_explanation_refresh()
	await _test_player_replacement()
	await _test_stats_layout_refresh()
	await _release_pulse_world()
	print("[OK] HUD refresh invalidation: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _stat_value(name: String) -> String:
	for line: String in world.hud.stats_label.get_parsed_text().split("\n"):
		if line.begins_with(name + ":"):
			return line.substr(name.length() + 1).strip_edges()
	return ""

func _check_health(label: String, actor: Node) -> void:
	var shown := _stat_value("Health").split("/")
	check(shown.size() == 2 and int(shown[0]) == actor.get_current_health() and int(shown[1]) == actor.get_max_health(), label)

func _check_cooldowns(label: String) -> void:
	check(absf(_stat_value("Attack Speed").to_float() - world.player.get_effective_attack_cooldown()) <= 0.0051, label + ": displayed Attack cooldown agrees with the real effective value")
	check(absf(_stat_value("Dash Cooldown").to_float() - world.player.get_effective_dash_cooldown()) <= 0.0051, label + ": displayed Dash cooldown agrees with the real effective value")

func _test_timer_refresh() -> void:
	# Elapsed seconds are a World-supplied presentation input. Keep the same
	# dictionary through each transition, as a caller may reuse its state object.
	var state := world._get_hud_state()
	state.timer_visible_in_hud = true
	state.run_elapsed_seconds = 59
	world.hud.refresh(state, world.player)
	check(_stat_value("Run Time") == "00:59", "Timer presents the last second before a minute")
	state.run_elapsed_seconds = 60
	world.hud.refresh(state, world.player)
	check(_stat_value("Run Time") == "01:00", "The next refresh advances the minute without waiting for another stat change")
	state.run_elapsed_seconds = 59
	state.timer_visible_in_hud = false
	world.hud.refresh(state, world.player)
	var hidden_text: String = world.hud.stats_label.get_parsed_text()
	check(_stat_value("Run Time").is_empty(), "Disabling the timer immediately removes its row")
	state.run_elapsed_seconds = 60
	world.hud.refresh(state, world.player)
	check(world.hud.stats_label.get_parsed_text() == hidden_text, "A minute rollover keeps the disabled timer hidden")
	state.run_elapsed_seconds = 61
	state.timer_visible_in_hud = true
	world.hud.refresh(state, world.player)
	check(_stat_value("Run Time") == "01:01", "Enabling the timer catches up to the current second")

func _test_live_stats() -> void:
	var actor := world.player
	actor.set_max_health_and_current(100, 100)
	var state := world._get_hud_state()
	world.hud.refresh(state, actor)
	_check_health("Initial real health appears in Stats", actor)
	actor.take_damage(17)
	world.hud.refresh(state, actor)
	check(actor.get_current_health() < 100, "The health fixture took actual damage")
	_check_health("Actual damage updates Health on the same refresh", actor)
	var injured_health: int = actor.get_current_health()
	actor.heal(5)
	world.hud.refresh(state, actor)
	check(actor.get_current_health() > injured_health, "The health fixture received actual healing")
	_check_health("Actual healing updates Health on the same refresh", actor)
	var normal_speed := _stat_value("Move Speed")
	actor.apply_external_slow(1.0, 0.5)
	world.hud.refresh(state, actor)
	var slowed_speed := _stat_value("Move Speed")
	check(slowed_speed.contains("(slowed)") and slowed_speed.to_float() < normal_speed.to_float(), "Entering Slow changes both visible movement speed and status")
	actor._update_external_slow(0.9)
	world.hud.refresh(state, actor)
	check(_stat_value("Move Speed") == slowed_speed, "An active Slow remains displayed while its duration counts down")
	actor._update_external_slow(0.2)
	world.hud.refresh(state, actor)
	check(_stat_value("Move Speed") == normal_speed, "Actual Slow expiry restores normal speed and removes its status immediately")
	var normal_attack := _stat_value("Attack Speed")
	var normal_dash := _stat_value("Dash Cooldown")
	var base_attack_cooldown: float = actor.attack_cooldown
	var base_dash_cooldown: float = actor.dash_cooldown
	actor.apply_objective_mutator(world.encounter_profile_builder._build_overcharge_mutator())
	world.hud.refresh(state, actor)
	check(actor.attack_cooldown == base_attack_cooldown and actor.dash_cooldown == base_dash_cooldown, "The actual Overcharge Mission changes effective cooldowns without changing base cooldowns")
	check(_stat_value("Attack Speed") != normal_attack and _stat_value("Dash Cooldown") != normal_dash, "Mission cooldown changes invalidate both displayed cooldowns")
	_check_cooldowns("Active Mission")
	for encounter in range(3):
		actor.tick_objective_mutators_for_encounter()
	world.hud.refresh(state, actor)
	check(_stat_value("Attack Speed") == normal_attack and _stat_value("Dash Cooldown") == normal_dash, "The third encounter clears the Mission's effective cooldown changes from Stats")
	_check_cooldowns("Expired Mission")

func _test_build_refresh() -> void:
	world.player.apply_upgrade("heavy_blow")
	world.player.apply_trial_power("static_wake")
	world.player.apply_upgrade("shatterwake")
	var state := world._get_hud_state()
	world.hud.refresh(state, world.player)
	var boon_index: int = state.active_boons.find("heavy_blow")
	var arcana_index: int = state.active_arcana.find("static_wake")
	var boss_index: int = state.active_boss_rewards.find("shatterwake")
	check(boon_index >= 0 and arcana_index >= 0 and boss_index >= 0, "Actual power acquisition supplies all three HUD build categories")
	if boon_index < 0 or arcana_index < 0 or boss_index < 0:
		return
	check(world.hud.build_strip_boon_stack_labels[boon_index].text.is_empty() and world.hud.build_strip_arcana_stack_labels[arcana_index].text.is_empty() and world.hud.build_strip_boss_stack_labels[boss_index].text.is_empty(), "Single stacks have no redundant stack badge")
	var original_ids := [state.active_boons.duplicate(), state.active_arcana.duplicate(), state.active_boss_rewards.duplicate()]
	var original_damage := _stat_value("Damage").to_int()
	world.player.apply_upgrade("heavy_blow")
	world.player.apply_trial_power("static_wake")
	world.player.apply_upgrade("shatterwake")
	world.hud.refresh(state, world.player)
	check([state.active_boons, state.active_arcana, state.active_boss_rewards] == original_ids, "Stack increments reuse exactly the same active-ID lists")
	check(world.hud.build_strip_boon_stack_labels[boon_index].text == "x2", "An existing Boon's second stack updates its badge")
	check(world.hud.build_strip_arcana_stack_labels[arcana_index].text == "x2", "An existing Arcana's second stack updates its badge")
	check(world.hud.build_strip_boss_stack_labels[boss_index].text == "x2", "An existing boss reward's second stack updates its badge")
	check(_stat_value("Damage").to_int() == world.player.damage and world.player.damage > original_damage, "The same-ID Boon increment also updates the actual Damage stat")
	world.player.apply_upgrade("patient_hunter")
	var shared_ids: Array = state.active_boons
	shared_ids.append("patient_hunter")
	world.hud.refresh(state, world.player)
	var appended_index := shared_ids.size() - 1
	var patient_name: String = world.player.upgrade_system.power_registry.get_power_display_name("patient_hunter")
	check(world.hud.build_strip_boon_chips[appended_index].visible and world.hud.build_strip_boon_labels[appended_index].text == patient_name, "Appending to the existing active-ID array shows the acquired power")
	shared_ids.reverse()
	world.hud.refresh(state, world.player)
	check(world.hud.build_strip_boon_labels[0].text == patient_name, "Reordering the same array updates the visible power order")
	shared_ids.clear()
	world.hud.refresh(state, world.player)
	check(not world.hud.build_strip_boon_chips[0].visible and world.hud.build_strip_boon_labels[0].text.is_empty() and world.hud.build_strip_boon_stack_labels[0].text.is_empty(), "Clearing that array hides and clears its previous label and stack badge")

func _test_biome_explanation_refresh() -> void:
	var state := world._get_hud_state()
	world.hud.refresh(state, world.player)
	world.hud._on_biome_header_entered()
	world.hud._process(1.0)
	check(world.hud._biome_tooltip_panel.visible and not world.hud._biome_tooltip_content.get_parsed_text().is_empty(), "The real biome explanation opens through its hover path")
	world.hud._on_biome_header_exited()
	var old_title: String = world.hud._status_header_biome_name.text
	# Same biome name and accent, but newly supplied explanation content.
	state.active_biome_impact_text = "A newly observed chamber rule."
	world.hud.refresh(state, world.player)
	world.hud._on_biome_header_entered()
	world.hud._process(1.0)
	check(world.hud._status_header_biome_name.text == old_title and world.hud._biome_tooltip_content.get_parsed_text().contains("A newly observed chamber rule."), "An unchanged biome heading still receives its new hover explanation")
	world.hud._on_biome_header_exited()

func _test_player_replacement() -> void:
	var state := world._get_hud_state()
	var boon_index: int = state.active_boons.find("heavy_blow")
	if boon_index < 0:
		check(false, "Player replacement requires the acquired Heavy Blow in the actual HUD state")
		return
	var boon_name: String = world.player.upgrade_system.power_registry.get_power_display_name("heavy_blow")
	world.hud.refresh(state, null)
	check(world.hud.stats_label.get_parsed_text().contains("No player"), "Losing the player removes its previous Stats")
	check(world.hud.build_strip_boon_labels[boon_index].text == "?" and world.hud.build_strip_boon_stack_labels[boon_index].text.is_empty(), "An unavailable player cannot retain a previous owner's stack badge")
	world.hud.refresh(state, world.player)
	_check_health("Recovering the valid player restores its health", world.player)
	check(world.hud.build_strip_boon_labels[boon_index].text == boon_name and world.hud.build_strip_boon_stack_labels[boon_index].text == "x2", "Recovering the player restores its known build and stacks")
	var replacement := REFRESH_PLAYER.instantiate()
	replacement.player_id = world.player.player_id
	world.add_child(replacement)
	replacement.apply_character_package(REFRESH_CHARACTERS.get_character("veilstrider"))
	replacement.set_max_health_and_current(137, 43)
	replacement.apply_upgrade("heavy_blow")
	world.hud.refresh(state, replacement)
	_check_health("A different instance with the same owner ID replaces the previous health", replacement)
	check(world.hud.build_strip_boon_labels[boon_index].text == boon_name and world.hud.build_strip_boon_stack_labels[boon_index].text.is_empty(), "A replacement owner's single stack removes the old owner's x2 badge")
	var previous_passive: String = world.hud.build_strip_passive_label.get_parsed_text()
	var bastion := REFRESH_CHARACTERS.get_character("bastion")
	replacement.apply_character_package(bastion)
	state.current_character_passive_name = bastion.passive_id
	state.active_boons = []
	state.active_arcana = []
	state.active_boss_rewards = []
	world.hud.refresh(state, replacement)
	check(world.hud.build_strip_passive_label.get_parsed_text() == REFRESH_PASSIVES.get_display_name(bastion.passive_id) and world.hud.build_strip_passive_label.get_parsed_text() != previous_passive, "Changing character on the same instance replaces its passive title")
	_check_health("The replacement character's real health package appears immediately", replacement)
	check(not world.hud.build_strip_boon_chips[0].visible and not world.hud.build_strip_arcana_chips[0].visible and not world.hud.build_strip_boss_chips[0].visible, "Character replacement clears every old build category")
	replacement.queue_free()
	await process_frame
	world.hud.refresh(world._get_hud_state(), world.player)

func _settle_stats_layout(state: Dictionary) -> void:
	# Control wrapping and minimum-size propagation settle normally; no direct
	# call to the production resize helper or assumptions about cache internals.
	world.hud.refresh(state, world.player)
	await process_frame
	await process_frame
	world.hud.refresh(state, world.player)
	await process_frame

func _check_stats_fit(label: String) -> void:
	var hud := world.hud
	check(hud.stats_label.size.y >= hud.stats_label.get_content_height(), label + ": all wrapped lines fit the Stats label")
	check(hud.stats_panel.get_global_rect().encloses(hud.stats_label.get_global_rect()), label + ": the Stats card encloses its full text")

func _test_stats_layout_refresh() -> void:
	var hud := world.hud
	var state := world._get_hud_state()
	state.run_elapsed_seconds = 61
	state.timer_visible_in_hud = true
	await _settle_stats_layout(state)
	var original_text: String = hud.stats_label.get_parsed_text()
	var original_height: float = hud.stats_panel.size.y
	var original_panel_width: float = hud.stats_panel.size.x
	var original_label_width: float = hud.stats_label.size.x
	var original_font_size: int = hud.stats_label.get_theme_font_size("normal_font_size")
	var original_chip_width: float = hud.build_strip_passive_chip.size.x
	_check_stats_fit("Initial layout")
	hud.stats_label.custom_minimum_size.x = 130.0
	hud.stats_label.size.x = 130.0
	hud.stats_panel.custom_minimum_size.x = 150.0
	hud.stats_panel.size.x = 150.0
	await _settle_stats_layout(state)
	check(hud.stats_label.get_parsed_text() == original_text and hud.stats_panel.size.y > original_height, "Narrowing the label reflows unchanged Stats into a taller card")
	check(hud.build_strip_passive_chip.size.x < original_chip_width, "The build strip follows the changed Stats column width")
	_check_stats_fit("Narrow layout")
	var narrow_height: float = hud.stats_panel.size.y
	hud.stats_label.add_theme_font_size_override("normal_font_size", original_font_size + 7)
	await _settle_stats_layout(state)
	check(hud.stats_label.get_parsed_text() == original_text and hud.stats_panel.size.y > narrow_height, "Changing the font size grows the card even with identical player values and text")
	_check_stats_fit("Larger font")
	hud.stats_label.add_theme_font_size_override("normal_font_size", original_font_size)
	hud.stats_label.custom_minimum_size.x = original_label_width
	hud.stats_label.size.x = original_label_width
	hud.stats_panel.custom_minimum_size.x = original_panel_width
	hud.stats_panel.size.x = original_panel_width
	await _settle_stats_layout(state)
	check(is_equal_approx(hud.stats_panel.size.y, original_height), "Restoring width and font releases the added Stats height")
	_check_stats_fit("Restored layout")
