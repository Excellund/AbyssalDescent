extends "res://scripts/tests/test_reward_build_inspection.gd"

const SUMMARY := preload("res://scripts/shared/build_keyword_summary.gd")
const HUD := preload("res://scripts/world_hud.gd")

class ShortcutWorld extends "res://scripts/world_generator.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)


func _run() -> void:
	var retirement := AUDIO_RETIREMENT.new()
	node_added.connect(retirement.observe_node)
	_setup_ui()
	_check_counts()
	await _check_overview_ui()
	await _check_native_tab_toggle()
	await _check_live_hud()
	ui.close_selection()
	viewport.free()
	registry.free()
	_free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await retirement.wait_until_retired(self), "Overview audio retires")
	print("[OK] Build keyword overview: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _entry(summary: Dictionary, id: String) -> Dictionary:
	for entry: Dictionary in summary.effects + summary.actions:
		if entry.id == id:
			return entry
	return {"id": id, "count": 0, "sources": []}

func _check_counts() -> void:
	var mixed := SUMMARY.from_levels({"static_wake": 3, "storm_crown": 2, "stormbrand": 1, "spark_relay": 1, "shatterwake": 2, "patient_hunter": 8}, "iron_retort")
	_check(_entry(mixed, "electric").count == 4, "Electric counts three producers and one receiver once each")
	_check(_entry(mixed, "burst").count == 3, "Hybrid Electric/Burst receiver and passive Burst count separately")
	_check(_entry(mixed, "slow").count == 3, "Slow counts producing, conditional and repeat Boon sources once each")
	_check(_entry(mixed, "field").count == 1, "Only the acquired Field power counts")
	var hunter := SUMMARY.from_levels({"hunters_snare": 2})
	_check(_entry(hunter, "field").count == 0 and _entry(hunter, "projectile").count == 0 and _entry(hunter, "echo").count == 0, "Examples in Hunter's Snare prose do not invent acquired properties")
	var veil := SUMMARY.from_levels({}, "veilstep_rhythm")
	_check(_entry(veil, "dash").count == 1 and _entry(veil, "attack").count == 0 and _entry(veil, "recoil").count == 0, "Passive uses resolved roles, deduplicating produced/accepted Dash and excluding explicit exceptions")
	for id in ["static_wake", "stormbrand"]:
		_check(_entry(SUMMARY.from_levels({id: 2}), "slow").count == 0 and _entry(SUMMARY.from_levels({id: 3}), "slow").count == 1, "Level 3 reveals newly learned Slow: " + id)
	for id in ["riftpunch", "sigil_chain", "farline_volley", "rupture_wave"]:
		_check(_entry(SUMMARY.from_levels({id: 1}), "slow").count == 0 and _entry(SUMMARY.from_levels({id: 2}), "slow").count == 1, "Level 2 reveals newly learned Slow: " + id)
	_check(_entry(SUMMARY.from_levels({"aegis_field": 1}), "burst").count == 1 and _entry(SUMMARY.from_levels({"aegis_field": 1}), "field").count == 0, "Aegis Pulse counts its non-damaging Burst, never a Field from its old internal name")
	_check(SUMMARY.from_levels({}).effects.is_empty() and SUMMARY.from_levels({"static_wake": 0}).actions.is_empty(), "Empty and removed builds have no stale keywords")
	_check(SUMMARY.from_levels({"static_wake": 1, "storm_crown": 1}).effects == SUMMARY.from_levels({"storm_crown": 1, "static_wake": 1}).effects or SUMMARY.compact_bbcode(SUMMARY.from_levels({"static_wake": 1, "storm_crown": 1})) == SUMMARY.compact_bbcode(SUMMARY.from_levels({"storm_crown": 1, "static_wake": 1})), "Equal counts keep stable display order")

func _keyword_button(id: String) -> Button:
	for flow: HFlowContainer in [build.keyword_effect_flow, build.keyword_action_flow]:
		for child in flow.get_children():
			if child is Button and child.get_meta("keyword_id", "") == id:
				return child
	return null

func _seed_overview() -> void:
	for id in ["static_wake", "storm_crown", "stormbrand", "spark_relay", "blast_drive"]:
		player.apply_trial_power(id)
	player.apply_upgrade("shatterwake")

func _check_overview_ui() -> void:
	_seed_overview()
	_open()
	ui._request_build_inspection()
	await process_frame
	await process_frame
	_check(not build.keyword_breakdown.visible and build.keyword_overview_toggle.size.y <= 44.0, "Keyword summary starts collapsed in one compact row")
	build.keyword_overview_toggle.grab_focus()
	await _press_pad(JOY_BUTTON_A)
	_check(build.keyword_breakdown.visible, "Controller expands the complete keyword breakdown")
	var electric := _keyword_button("electric")
	_check(electric != null and electric.text == "Electric  4", "Native Build overview shows accumulated Electric count")
	electric.grab_focus()
	await _press_pad(JOY_BUTTON_A)
	var details := build.keyword_source_details.get_parsed_text()
	_check(build.keyword_source_details.visible and details.contains("Produces:") and details.contains("Uses:") and details.contains("Stormbrand (Lv 1)"), "Controller opens producer/receiver list with power levels")
	_check(not details.contains("Blast Drive") and not details.contains("Iron Retort"), "Contributor list only names owned powers that use or produce Electric")
	await _press_pad(JOY_BUTTON_A)
	_check(not build.keyword_source_details.visible, "Selecting the same keyword collapses its source list")
	build.close()
	ui.close_selection()

func _check_live_hud() -> void:
	var hud := HUD.new()
	viewport.add_child(hud)
	hud.setup(5)
	var empty_mutators: Array[Dictionary] = []
	var state := {"current_character_passive_name": "iron_retort", "active_boons": [], "active_arcana": ["static_wake", "storm_crown", "stormbrand", "spark_relay", "blast_drive"], "active_boss_rewards": ["shatterwake"], "active_player_mutators": empty_mutators}
	hud.refresh(state, player)
	await process_frame
	var original := hud.build_keyword_label.text
	_check(hud.build_keyword_label.get_parsed_text().contains("Electric 4") and not hud.build_keyword_label.get_parsed_text().contains("Top keywords"), "HUD shows a restrained leading-keyword line with actual owned counts")
	for _level in range(3):
		player.apply_trial_power("static_wake")
	_check(player.has_trial_power_prismatic("static_wake"), "HUD fixture actually acquires Prismatic")
	hud.refresh(state, player)
	_check(hud.build_keyword_label.get_parsed_text().contains("Electric 4"), "Upgrades and Prismatic never multiply learned keyword source counts")
	var levels := SUMMARY.owned_levels(player)
	player.apply_objective_mutator({"id": "overcharge", "remaining_encounters": 3, "player_attack_cooldown_mult": 0.8})
	_check(SUMMARY.owned_levels(player) == levels, "Temporary Mission effects do not become acquired powers")
	hud.refresh(state, null)
	_check(not hud.build_keyword_label.get_parsed_text().contains("Electric"), "Losing the player clears old keyword counts")
	hud.refresh(state, player)
	_check(hud.build_keyword_label.get_parsed_text().contains("Electric 4"), "Restoring the player restores current keyword counts")
	var before := hud.build_keyword_label.text
	for _frame in range(100):
		hud.refresh(state, player)
	_check(hud.build_keyword_label.text == before and not original.is_empty(), "Unchanged HUD refreshes keep the same keyword presentation")
	hud.free()

func _tab(pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_TAB
	event.keycode = KEY_TAB
	event.pressed = pressed
	event.echo = echo
	viewport.push_input(event, true)

func _check_native_tab_toggle() -> void:
	# Use the production World's opener and real native GUI dispatch. Only its
	# unrelated bootstrap/process work is suppressed by the isolated fixture.
	var shortcut_world := ShortcutWorld.new()
	shortcut_world.player = player
	shortcut_world.build_detail_panel = build
	shortcut_world.current_character_id = "bastion"
	viewport.add_child(shortcut_world)
	for dimensions in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = dimensions
		_tab(true)
		await process_frame
		await process_frame
		_check(build.is_open() and build._close_button.visible, "Native Tab opens normal build with visible close control at %d" % dimensions.x)
		await _click_reward_pointer(build.keyword_overview_toggle.get_global_rect().get_center())
		var electric := _keyword_button("electric")
		await _click_reward_pointer(electric.get_global_rect().get_center())
		_check(build.keyword_source_details.visible and build._selected_keyword == "electric", "Mouse can inspect a keyword while Tab remains held at %d" % dimensions.x)
		var focus := viewport.gui_get_focus_owner()
		var scroll_position := build._scroll.scroll_vertical
		for _repeat in range(16):
			_tab(true, true)
			await process_frame
		_check(build.is_open() and viewport.gui_get_focus_owner() == focus and build._scroll.scroll_vertical == scroll_position, "Held Tab echoes cannot change selection or scroll at %d" % dimensions.x)
		_tab(false)
		_check(build.is_open() and build.keyword_source_details.visible, "Releasing Tab keeps inspection usable at %d" % dimensions.x)
		var next := InputEventKey.new()
		next.keycode = KEY_RIGHT
		next.physical_keycode = KEY_RIGHT
		next.pressed = true
		viewport.push_input(next, true)
		next.pressed = false
		viewport.push_input(next, true)
		_check(viewport.gui_get_focus_owner() != focus, "Arrow keys still navigate keywords at %d" % dimensions.x)
		_tab(true)
		_tab(false)
		_check(not build.is_open(), "Fresh Tab press closes normal inspection at %d" % dimensions.x)
	await _press_pad(JOY_BUTTON_Y)
	_check(build.is_open(), "Controller Y opens normal build")
	await _press_pad(JOY_BUTTON_B)
	_check(not build.is_open(), "Controller B closes normal build")
	shortcut_world.free()
