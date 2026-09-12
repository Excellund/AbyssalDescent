extends "res://scripts/tests/render_warden_practice.gd"
## Real keyboard/mouse setup, build editing and atomic Apply. AI is disabled
## through the visible training option; terminal damage is deliberately staged.
const CONFIG := preload("res://scripts/practice/practice_config.gd")

func _run() -> void:
	if not _is_isolated() or DisplayServer.get_name() == "headless":
		quit(1)
		return
	MultiplayerSessionManager._multiplayer = get_multiplayer()
	root.content_scale_size = Vector2i(2560,1440)
	frame_folder = ProjectSettings.globalize_path("res://practice_vessel_frames")
	DirAccess.make_dir_recursive_absolute(frame_folder)
	await _prepare_normal_checkpoint()
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.base_viewport_width = 2560
	RunContext.base_viewport_height = 1440
	file_baseline = _file_hashes()
	context_baseline = _context_state()
	for screen in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = screen
		await _settle_native()
		arena = PRACTICE.instantiate() as ARENA
		root.add_child(arena)
		current_scene = arena
		await _settle_native()
		check(arena.mode == "setup" and arena.player == null, "Setup appears before actors exist")
		_check_panel_layout(arena.ui,screen)
		await _capture("sandbox_setup", "Actual initial setup; no injected config or actors")
		var edit = arena.ui.editor
		await _option(edit.character_selector,1,true)
		await _capture("sandbox_vessel_popup", "Actual keyboard-opened list includes all five Vessels without unlock grants")
		await _key(KEY_ENTER)
		await _settle_native()
		check(arena.draft_config.character_id == "hexweaver" and arena.player == null, "Choosing Vessel changes only pre-start draft")
		await _number(edit.floor_input,18)
		await _option(edit.bearing_selector,3)
		await _option(edit.encounter_selector,_encounter_index(edit.encounter_selector,"crossfire"))
		check(arena.draft_config.floor == 18 and arena.draft_config.bearing == 3 and arena.draft_config.encounter_id == "crossfire", "Native controls compose floor, Bearing and encounter")
		check(not edit.encounter_description.text.is_empty(), "Selected encounter explains its goal")
		await _capture("sandbox_encounter", "Native floor18, Forsworn and Crossfire selected")
		await _open_practice_tab(1)
		await _search("Farshot")
		await _number(edit.build_rows["powers:farshot"].input,3)
		_check_power_copy(edit.build_rows["powers:farshot"])
		await _capture("sandbox_boon", "Native search and three Farshot stacks")
		await _option(edit.category_selector,2)
		await _search("Static Wake")
		await _number(edit.build_rows["powers:static_wake"].input,int(edit.build_rows["powers:static_wake"].input.max_value))
		await _click_control(edit.build_rows["powers:static_wake"].prismatic)
		check(arena.draft_config.prismatic.has("static_wake"), "Max-level Arcana supports actual Prismatic checkbox")
		_check_power_copy(edit.build_rows["powers:static_wake"])
		await _capture("sandbox_arcana", "Native Arcana levels and supported Prismatic selection")
		await _option(edit.category_selector,3)
		await _search("Warden")
		await _number(edit.build_rows["powers:wardens_verdict"].input,1)
		_check_power_copy(edit.build_rows["powers:wardens_verdict"])
		await _capture("sandbox_boss_power", "Actual Warden's Verdict selection in full build editor")
		await _option(edit.category_selector,4)
		await _search("")
		await _click_control(edit.build_rows["catalysts:starting_max_hp_bonus"].input)
		await _capture("sandbox_catalysts", "Applicable Catalyst selection; unavailable effects explain their arena limitation")
		await _option(edit.category_selector,5)
		await _click_control(edit.build_rows["ascension:hardened_foes"].input)
		await _capture("sandbox_ascension", "Real Forsworn Ascension modifier selection")
		await _open_practice_tab(2)
		await _click_control(edit.ai_toggle)
		check(not arena.draft_config.enemy_ai and not arena.draft_config.invulnerable, "Visible AI toggle selects stationary enemies without immunity")
		await _capture("sandbox_options", "Training controls, with AI explicitly disabled for native presentation")
		arena.ui.retry_button.grab_focus()
		await _key(KEY_ENTER)
		await _settle_native(12)
		check(arena.mode == "active" and arena.player.active_character_id == "hexweaver" and arena.enemies.size() > 0 and arena.current_config.encounter_id == "crossfire", "Native Start generates selected encounter with configured Vessel")
		check(arena.player.get_upgrade_stack_count("farshot") == 3 and arena.current_config.prismatic.has("static_wake"), "Native Start applies chosen full build")
		_check_arena_frame(screen,"Configured encounter")
		await _capture("sandbox_active", "Real configured actors/build/Bearing/biome; AI off by visible user option")
		var old_actor := arena.player.get_instance_id()
		await _key(KEY_ESCAPE)
		await _open_practice_tab(0)
		await _option(edit.character_selector,4)
		await _option(edit.encounter_selector,_encounter_index(edit.encounter_selector,"relic_recovery"),true)
		var encounter_popup: PopupMenu = edit.encounter_selector.get_popup()
		var popup_scale := root.get_stretch_transform().get_scale()
		var popup_rect := Rect2(Vector2(encounter_popup.position) * popup_scale,Vector2(encounter_popup.size) * popup_scale)
		print("[Popup] size=%s position=%s max=%s viewport=%s window=%s stretch=%s" % [encounter_popup.size,encounter_popup.position,encounter_popup.max_size,root.get_visible_rect(),root.size,popup_scale])
		check(Rect2(Vector2.ZERO,Vector2(screen)).grow(1).encloses(popup_rect), "Complete encounter popup fits physical window")
		var popup_scroll := _popup_scroll(encounter_popup)
		check(popup_scroll != null and (screen.x != 960 or popup_scroll.scroll_vertical > 0), "Native keyboard scrolls lower encounter choices into view at960")
		await _capture("sandbox_encounter_popup", "Actual keyboard navigation scrolls the full named list to Relic Recovery")
		await _key(KEY_ENTER)
		await _settle_native()
		check(arena.player.active_character_id == "hexweaver" and arena.draft_config.character_id == "threadbinder", "Paused draft does not mutate current actor")
		await _capture("sandbox_paused_draft", "Pending Effigy Keeper and Relic Recovery alongside current Crossfire attempt")
		arena.ui.resume_button.grab_focus()
		await _key(KEY_ENTER)
		await _settle_native()
		check(arena.player.get_instance_id() == old_actor and arena.player.active_character_id == "hexweaver" and arena.current_config.encounter_id == "crossfire" and arena.draft_config.encounter_id == "relic_recovery", "Resume retains current configured actor/encounter and pending edit")
		await _key(KEY_ESCAPE)
		if screen.x == 960:
			root.size = Vector2i(1280,720)
			await _settle_native(10)
			_check_panel_layout(arena.ui,Vector2i(1280,720))
			await _capture("sandbox_live_resize", "Actual paused setup resize preserves selected tab and fixed actions")
			root.size = screen
			await _settle_native(10)
		arena.ui.retry_button.grab_focus()
		await _key(KEY_ENTER)
		await _settle_native(12)
		check(arena.mode == "active" and arena.attempt == 2 and arena.player.active_character_id == "threadbinder" and arena.player.get_instance_id() != old_actor and arena.current_config.encounter_id == "relic_recovery", "Apply atomically creates fresh configured encounter")
		_check_panel_layout(arena.ui,screen)
		check(not arena.ui.boss_label.text.is_empty(), "Objective encounter has readable live status")
		await _capture("sandbox_apply", "Native Apply creates Effigy Keeper with configured build and real Relic Recovery objective")
		arena.player.take_damage(10000,{"source":"enemy_ability","ability":"warden_nova"})
		await _settle_native()
		check(arena.mode == "defeat", "Actual accepted fatal damage opens generic attempt results")
		await _capture("sandbox_results", "Accepted fatal event and editable result screen")
		if screen.x == 960:
			await _open_practice_tab(0)
			await _option(edit.encounter_selector,_encounter_index(edit.encounter_selector,"pulse_window"))
			await _open_practice_tab(2)
			await _click_control(edit.invulnerable_toggle)
			arena.ui.retry_button.grab_focus()
			await _key(KEY_ENTER)
			await _settle_native(12)
			check(arena.mode == "active" and arena.current_config.encounter_id == "pulse_window" and arena.current_config.invulnerable, "Real controls apply Pulse Window with visible immunity option")
			check(arena.ui.encounter_hint_label.visible and arena.ui.encounter_hint_label.text.begins_with("Next pulse in"), "Actual Mission countdown is visible during play")
			await _capture("sandbox_pulse_wait", "Actual Pulse Window countdown; AI and damage disabled through visible training options")
			var pulse_deadline := Time.get_ticks_msec() + 15000
			while not arena.objective_manager.pulse_active and Time.get_ticks_msec() < pulse_deadline:
				await process_frame
			await _settle_native(2)
			var rule: String = arena.presentation().get("encounter_hint", "")
			check(arena.objective_manager.pulse_active and not rule.is_empty() and not rule.begins_with("Next pulse in"), "Real Mission clock advances into an actual mutator pulse")
			check(arena.ui.encounter_hint_label.is_visible_in_tree() and arena.ui.encounter_hint_label.text == rule, "Actual current mutator and rule appear in active sidebar")
			_check_panel_layout(arena.ui,screen)
			check(_physical_rect(arena.ui.hud).encloses(_physical_rect(arena.ui.encounter_hint_label)), "Actual mutator rule fits the readable sidebar")
			await _capture("sandbox_pulse_rule", "Real-time first pulse from ObjectiveRuntime; current mutator rule is visible without pausing")
			await _key(KEY_ESCAPE)
			await _settle_native()
			_check_panel_layout(arena.ui,screen)
			check(_physical_rect(arena.ui.modal).encloses(_physical_rect(arena.ui.modal_detail)), "Current Mission banner fits paused dialog")
			await _capture("sandbox_pulse_paused", "Actual current Pulse rule remains fully readable in paused setup at960")
		_check_preserved("Native full sandbox")
		arena.ui.menu_button.grab_focus()
		await _key(KEY_ENTER)
		await _settle_native(24)
		check(current_scene.scene_file_path == "res://scenes/Menu.tscn", "Native Menu returns to ordinary main menu")
		_check_preserved("Native sandbox return")
		current_scene.queue_free()
		current_scene = null
		arena = null
		await _settle_native()
	await _cleanup_recovery_world()
	FileAccess.open(frame_folder.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify({"gpu":RenderingServer.get_video_adapter_name(),"checks":checks,"failures":failures,"frames":frames},"\t"))
	print("[OK] Practice sandbox native: %d frames, %d checks, %d failures" % [frames.size(),checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _option(control: OptionButton,index: int,leave_open: bool = false) -> void:
	control.grab_focus()
	await _settle_native(2)
	await _key(KEY_ENTER)
	await _settle_native(2)
	await _key(KEY_HOME)
	var popup := control.get_popup()
	for _step in control.item_count * 2:
		if popup.get_focused_item() == index:
			break
		await _key(KEY_DOWN if popup.get_focused_item() < index else KEY_UP)
	check(control.get_popup().visible and control.get_popup().get_focused_item() == index, "Native keys reach selected option")
	if not leave_open:
		await _key(KEY_ENTER)
		await _settle_native(2)

func _number(control: SpinBox,value: int) -> void:
	var line := control.get_line_edit()
	line.grab_focus()
	await _settle_native(2)
	line.select_all()
	await _type_text(str(value))
	print("[Input] number typed=%s wanted=%d focused=%s" % [line.text,value,root.gui_get_focus_owner() == line])
	await _key(KEY_ENTER)
	await _settle_native(3)
	print("[Input] number committed=%s wanted=%d" % [control.value,value])
	check(int(control.value) == value, "Native numeric input commits exact whole value")

func _search(value: String) -> void:
	var line: LineEdit = arena.ui.editor.search_input
	line.grab_focus()
	line.select_all()
	await _key(KEY_BACKSPACE)
	await _type_text(value)
	await _settle_native(3)

func _type_text(value: String) -> void:
	for character in value:
		var event := InputEventKey.new()
		event.keycode = character.to_upper().unicode_at(0)
		event.physical_keycode = event.keycode
		event.unicode = character.unicode_at(0)
		event.pressed = true
		root.push_input(event,true)
		var release := event.duplicate() as InputEventKey
		release.pressed = false
		root.push_input(release,true)
	await process_frame

func _click_control(control: Control) -> void:
	control.grab_focus()
	await _settle_native(3)
	await _click_point(control.get_global_transform_with_canvas() * (control.size * 0.5))

func _check_power_copy(row: Dictionary) -> void:
	var description := row.description as RichTextLabel
	var font_pixels := description.get_theme_font_size("normal_font_size") * description.get_global_transform_with_canvas().get_scale().y * root.get_stretch_transform().get_scale().y
	check(not description.get_parsed_text().is_empty() and not description.get_parsed_text().contains("[color") and font_pixels >= 17.99, "Actual level-aware power text renders semantic spans at readable physical size")
	check(description.get_content_height() <= description.size.y + 1.0, "Complete selected-power explanation remains vertically visible")

func _encounter_index(selector: OptionButton,id: String) -> int:
	for index in selector.item_count:
		if String(selector.get_item_metadata(index)) == id:
			return index
	check(false,"Named encounter exists: " + id)
	return 0

func _popup_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node as ScrollContainer
	for child in node.get_children(true):
		var found := _popup_scroll(child)
		if found != null:
			return found
	return null
