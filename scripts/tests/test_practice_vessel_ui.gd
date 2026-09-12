extends "res://scripts/tests/test_practice_menu_ui.gd"
## Real-catalogue draft editing; actor application has its own runtime proof.
const CONFIG := preload("res://scripts/practice/practice_config.gd")
const VESSELS: Array[Dictionary] = [{"id":"bastion","name":"Bastion"},{"id":"hexweaver","name":"Hexweaver"},{"id":"veilstrider","name":"Veilstrider"},{"id":"riftlancer","name":"Riftlancer"},{"id":"threadbinder","name":"Effigy Keeper"}]

static func vessel_state(mode: String, index: int) -> Dictionary:
	var state := setup_state(mode)
	var config := CONFIG.defaults()
	config.character_id = VESSELS[index].id
	state.character_id = config.character_id
	state.character_name = VESSELS[index].name
	state.current_config = config.duplicate(true)
	state.draft_config = config.duplicate(true)
	state.catalogue = CONFIG.catalogue(config)
	state.validation = CONFIG.validate(config)
	return state

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	root.content_scale_size = Vector2i(2560, 1440)
	var panel := PANEL.new()
	root.add_child(panel)
	await _settle()
	var changes: Array[Dictionary] = []
	panel.config_requested.connect(func(value: Dictionary) -> void: changes.append(value.duplicate(true)))
	var profile_before: Dictionary = RunContext.meta_progress_profile.duplicate(true)
	var selected_before: String = RunContext.selected_character_id
	for screen in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = screen
		for index in VESSELS.size():
			for mode in ["setup","paused","victory","defeat"]:
				var state := vessel_state(mode,index)
				state.attempt = 0 if mode == "setup" else 3
				panel.present(state)
				await _settle(5)
				check(panel.editor.character_selector.item_count == 5 and String(panel.editor.character_selector.get_selected_metadata()) == VESSELS[index].id, "All registered Vessels are selectable without unlocks")
				for tab in range(3):
					panel.editor.tabs.current_tab = tab
					await _settle(3)
					_check_setup_fit(panel,screen)
				panel.menu_button.grab_focus()
				panel.present(state.duplicate(true))
				check(root.gui_get_focus_owner() == panel.menu_button and panel.editor.tabs.current_tab == 2, "Refresh retains tab and action focus")
	var state := vessel_state("paused",0)
	panel.present(state)
	var edit = panel.editor
	check(edit.floor_input.min_value == 1 and edit.floor_input.max_value == 25, "Floor input follows real supported bounds")
	check(edit.encounter_selector.item_count == state.catalogue.encounters.size(), "Every supported encounter appears by real name")
	for index in state.catalogue.encounters.size():
		var entry: Dictionary = state.catalogue.encounters[index]
		check(edit.encounter_selector.get_item_text(index) == String(entry.name) and String(edit.encounter_selector.get_item_metadata(index)) == String(entry.id), "Encounter keeps its real name and canonical choice: " + String(entry.name))
	for metadata: Dictionary in state.catalogue.powers:
		var row: Dictionary = edit.build_rows["powers:" + String(metadata.id)]
		check(row.input.min_value == 0 and row.input.max_value == metadata.max_level, "Actual power cap: " + String(metadata.name))
		check(row.has("prismatic") == bool(metadata.supports_prismatic), "Actual Prismatic support: " + String(metadata.name))
		if row.has("prismatic"):
			check(row.prismatic.disabled, "Unselected Arcana cannot request Prismatic")
	edit.character_selector.select(1)
	edit.character_selector.item_selected.emit(1)
	check(changes.size() == 1 and changes[-1].character_id == "hexweaver" and panel.shown_state.current_config.character_id == "bastion", "Vessel changes only detached draft")
	changes[-1].character_id = "mutated"
	check(edit._draft.character_id == "hexweaver", "Signal consumers cannot mutate editor draft")
	edit.floor_input.value = 18
	edit.bearing_selector.select(3)
	edit.bearing_selector.item_selected.emit(3)
	check(changes[-1].floor == 18 and changes[-1].bearing == 3, "Scalar edits compose in one draft")
	var encounter_index := _encounter_index(edit.encounter_selector, "crossfire")
	edit.encounter_selector.select(encounter_index)
	edit.encounter_selector.item_selected.emit(encounter_index)
	check(changes[-1].encounter_id == "crossfire" and not changes[-1].has("enemies") and not edit.encounter_description.text.is_empty(), "Encounter changes update the detached choice and explanation")
	edit.build_rows["powers:farshot"].input.value = 3
	check(changes[-1].powers.farshot == 3, "Boon supports actual stack count")
	var arcana: Dictionary = {}
	for metadata: Dictionary in state.catalogue.powers:
		if metadata.supports_prismatic:
			arcana = edit.build_rows["powers:" + String(metadata.id)]
			break
	arcana.input.value = arcana.input.max_value
	check(not arcana.prismatic.disabled, "Maximum Arcana level enables Prismatic")
	arcana.prismatic.button_pressed = true
	check(changes[-1].prismatic.has(arcana.id), "Supported Prismatic accompanies selected Arcana")
	arcana.input.value = 0
	check(not changes[-1].powers.has(arcana.id) and not changes[-1].prismatic.has(arcana.id), "Removing Arcana also removes Prismatic")
	edit.ai_toggle.button_pressed = false
	edit.invulnerable_toggle.button_pressed = true
	check(not changes[-1].enemy_ai and changes[-1].invulnerable, "Training toggles edit draft only")
	panel.present(vessel_state("paused",0))
	edit.tabs.current_tab = 1
	edit.category_selector.select(0)
	edit.search_input.text = "farshot"
	edit.search_input.text_changed.emit(edit.search_input.text)
	check(edit.build_rows["powers:farshot"].root.visible and _visible_build_rows(edit) == 1, "Search finds real player-facing power names")
	edit.search_input.text = "no such power here"
	edit.search_input.text_changed.emit(edit.search_input.text)
	check(edit.no_results.visible and _visible_build_rows(edit) == 0, "No-match search explains empty results")
	edit.search_input.grab_focus()
	panel.present(panel.shown_state.duplicate(true))
	check(edit.search_input.text == "no such power here" and root.gui_get_focus_owner() == edit.search_input, "Repeated refresh preserves typing and focus")
	var level_state := vessel_state("paused",0)
	level_state.draft_config.powers = {"stormbrand": 1}
	level_state.catalogue = CONFIG.catalogue(level_state.draft_config)
	panel.present(level_state)
	var storm: Dictionary = edit.build_rows["powers:stormbrand"]
	var storm_control_id: int = storm.input.get_instance_id()
	var first_copy: String = storm.description.get_parsed_text()
	storm.input.get_line_edit().grab_focus()
	level_state.draft_config.powers.stormbrand = 3
	level_state.catalogue = CONFIG.catalogue(level_state.draft_config)
	panel.present(level_state)
	check(storm.input.get_instance_id() == storm_control_id and root.gui_get_focus_owner() == storm.input.get_line_edit(), "Level-dependent copy updates keep the exact control and keyboard focus")
	check(not first_copy.contains("Slows") and storm.description.get_parsed_text().contains("Slows"), "Stormbrand level3 explains its additional Slow rule")
	level_state.draft_config.powers = {"execution_edge": 3}
	level_state.catalogue = CONFIG.catalogue(level_state.draft_config)
	panel.present(level_state)
	var execution_copy: String = edit.build_rows["powers:execution_edge"].description.get_parsed_text()
	level_state.draft_config.prismatic = ["execution_edge"]
	level_state.catalogue = CONFIG.catalogue(level_state.draft_config)
	panel.present(level_state)
	check(execution_copy != edit.build_rows["powers:execution_edge"].description.get_parsed_text() and edit.build_rows["powers:execution_edge"].description.get_parsed_text().contains("Every Attack"), "Prismatic Execution Edge presents its actual every-Attack rule")
	edit.search_input.text = "Electric"
	edit.search_input.text_changed.emit(edit.search_input.text)
	check(edit.build_rows["powers:stormbrand"].root.visible, "Effect search finds canonical description keywords, not only names")
	var incompatible := vessel_state("paused",3)
	incompatible.draft_config.powers = {"wide_arc": 1}
	incompatible.catalogue = CONFIG.catalogue(incompatible.draft_config)
	panel.present(incompatible)
	var wide: Dictionary = edit.build_rows["powers:wide_arc"]
	check(not wide.input.editable and wide.remove.visible and not wide.reason.text.is_empty(), "An incompatible selected power explains its limit and remains individually removable")
	wide.remove.pressed.emit()
	check(not changes[-1].powers.has("wide_arc"), "Removing an incompatible choice repairs the draft without clearing other powers")
	var unavailable := vessel_state("paused",0)
	unavailable.draft_config.ascension = ["hardened_foes"]
	unavailable.catalogue = CONFIG.catalogue(unavailable.draft_config)
	panel.present(unavailable)
	var ascension: Dictionary = edit.build_rows["ascension:hardened_foes"]
	check(ascension.input.button_pressed and not ascension.input.disabled and not ascension.reason.text.is_empty(), "Selected Ascension remains removable after a Bearing change")
	ascension.input.button_pressed = false
	check(changes[-1].ascension.is_empty(), "Removing unavailable Ascension leaves a repairable draft")
	var invalid := vessel_state("paused",0)
	invalid.validation = {"valid":false,"errors":["Choose a supported encounter."],"warnings":[]}
	panel.present(invalid)
	check(panel.retry_button.disabled and panel.validation_label.text == "Choose a supported encounter." and panel.resume_button.visible, "Invalid draft blocks Apply but preserves Resume")
	var before_count := changes.size()
	panel.present(vessel_state("active",0))
	edit._set_power("farshot",1)
	edit._set_scalar("encounter_id","crossfire")
	check(changes.size() == before_count and not panel.modal.visible, "Stale editor calls cannot change active combat")
	check(RunContext.meta_progress_profile == profile_before and RunContext.selected_character_id == selected_before, "Editor never changes normal profile or selection")
	panel.queue_free()
	await _settle()
	print("[OK] Practice sandbox UI: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _visible_build_rows(edit: Control) -> int:
	var count := 0
	for row: Dictionary in edit.build_rows.values():
		if row.root.visible:
			count += 1
	return count

func _check_setup_fit(panel: CanvasLayer, screen: Vector2i) -> void:
	var bounds := _rect(panel.modal)
	check(Rect2(Vector2.ZERO,Vector2(screen)).grow(0.1).encloses(bounds), "Setup fits physical window")
	check(bounds.grow(0.1).encloses(_rect(panel.editor)) and panel.editor.size.y >= 180.0, "Tabs retain useful scrolling area")
	for control in [panel.modal_title,panel.modal_detail,panel.modal_notice,panel.retry_button,panel.menu_button]:
		check(bounds.grow(0.1).encloses(_rect(control)) and _font_pixels(control) >= 17.99, "Fixed setup copy and actions remain readable")
	check(_rect(panel.editor).end.y <= _rect(panel.retry_button).position.y + 0.1, "Scrolling content leaves actions fixed")
	check(panel.editor.tabs.get_tab_count() == 3 and panel.editor.tabs.get_tab_title(2) == "Options", "Encounter, Build and Options expose the complete setup")

func _encounter_index(selector: OptionButton, id: String) -> int:
	for index in selector.item_count:
		if String(selector.get_item_metadata(index)) == id:
			return index
	return -1
