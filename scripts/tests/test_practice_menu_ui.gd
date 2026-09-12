extends SceneTree

const MENU := preload("res://scripts/menu_controller.gd")
const PANEL := preload("res://scripts/ui/practice/practice_panel.gd")
const AUDIO := preload("res://scripts/tests/fixture_audio_retirement.gd")

class FixtureMenu extends "res://scripts/menu_controller.gd":
	var entries := 0
	var host_calls := 0
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		_build_ui()
		_apply_menu_layout()
		_restore_practice_return_state()
		set_process(false)
	func _enter_practice_scene() -> void:
		_practice_starting = false
		if _practice_is_available():
			entries += 1
		_refresh_practice_button()
	func _create_multiplayer_room_inner() -> void:
		host_calls += 1
		await get_tree().process_frame

var checks := 0
var failures: Array[String] = []
var retirement := AUDIO.new()

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _settle(count: int = 4) -> void:
	for _step in count:
		await process_frame

func _rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	var stretch := root.get_stretch_transform().get_scale()
	return Rect2(transform.origin * stretch, control.size * transform.get_scale() * stretch)

func _font_pixels(control: Control) -> float:
	return control.get_theme_font_size("font_size") * control.get_global_transform_with_canvas().get_scale().y * root.get_stretch_transform().get_scale().y

static func setup_state(mode: String = "setup") -> Dictionary:
	var config := {"character_id": "bastion", "floor": 1, "bearing": 0, "biome_id": "shatterfield", "encounter_id": "warden", "powers": {}, "prismatic": [], "catalysts": [], "ascension": [], "enemy_ai": true, "invulnerable": false}
	var catalogue := {"characters": [{"id": "bastion", "name": "Bastion"}], "bearings": [{"id": 0, "name": "Delver"}], "biomes": [{"id": "shatterfield", "name": "Shatterfield"}], "encounters": [{"id": "warden", "name": "Warden", "description": "Face the Warden.", "category": "boss"}], "powers": [], "catalysts": [], "ascension": []}
	return {"mode": mode, "attempt": 0 if mode == "setup" else 12, "health": 73, "max_health": 130, "enemy_count": 3, "alive_count": 2, "character_name": "Bastion", "draft_config": config, "current_config": config.duplicate(true), "catalogue": catalogue, "validation": {"valid": true, "errors": [], "warnings": []}}

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	# Bind the actual fresh SceneMultiplayer API exactly as production _ready
	# does, so suppression of autoload startup cannot hide an idle-peer guard.
	MultiplayerSessionManager._multiplayer = get_multiplayer()
	check(not MultiplayerSessionManager.has_active_session_state(), "Fresh production SceneMultiplayer API is available for solo practice")
	root.content_scale_size = Vector2i(2560, 1440)
	var menu := FixtureMenu.new()
	root.add_child(menu)
	await _settle()
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		await _settle()
		menu._apply_menu_layout()
		await _settle()
		check(Rect2(Vector2.ZERO, Vector2(size)).encloses(_rect(menu.root_panel)), "Physical main menu fits %s" % size)
		check(is_equal_approx(_font_pixels(menu.practice_button), 18.0), "Practice entry stays18physical pixels %s" % size)
		check(menu.practice_button.get_index() == menu.checkpoint_discard_button.get_index() + 1, "Practice follows checkpoint controls")
		check(menu.practice_button.text == "Practice" and menu.root_actions.get_child(menu.practice_button.get_index() + 1).get("text") == "Multiplayer", "Practice has no subtitle before the next menu action")
		menu.practice_button.grab_focus()
		await _settle()
		check(_rect(menu._root_action_scroll).grow(1).encloses(_rect(menu.practice_button)), "Focus scrolls Practice fully into view")
		var last := menu.root_actions.get_child(menu.root_actions.get_child_count() - 1) as Button
		last.grab_focus()
		await _settle()
		check(_rect(menu._root_action_scroll).grow(1).encloses(_rect(last)), "Last existing action is fully reachable")
		check(_font_pixels(last) >= 18.0, "Existing main actions remain readable")
		check(Rect2(Vector2.ZERO, Vector2(size)).encloses(_rect(menu.update_panel)), "Existing update card stays within the physical screen")
		check(not _rect(menu.update_panel).intersects(_rect(menu.flavor_quote_label)), "Existing update card leaves the brand quote unobstructed")
	menu._show_character_selector()
	menu._apply_menu_layout()
	check(not menu.root_panel.visible, "Resize during an outgoing transition cannot expose main actions behind another panel")
	menu._show_root_panel(false)
	menu._apply_menu_layout()
	check(menu.root_panel.visible, "Main can reopen after an interrupted outgoing animation")
	menu.show_checkpoint_error("This checkpoint cannot be resumed. It has not been discarded.")
	var token: Dictionary = menu._practice_menu_return_state()
	var profile_before := RunContext.meta_progress_profile.duplicate(true)
	var selected_before: String = RunContext.selected_character_id
	var mode_before: int = RunContext.run_mode
	menu._on_practice_pressed()
	await _settle()
	check(menu.entries == 1, "Solo entry reaches its dedicated transition")
	check(menu._practice_menu_return_state() == token, "Entering preserves local checkpoint error and retry controls")
	check(RunContext.meta_progress_profile == profile_before and RunContext.selected_character_id == selected_before and RunContext.run_mode == mode_before, "Entry leaves profile, selection and run mode unchanged")
	MultiplayerSessionManager.session_connected = true
	menu._refresh_practice_button()
	menu._on_practice_pressed()
	await _settle()
	check(menu.practice_button.disabled and menu.entries == 1, "Connected party blocks both control and direct activation")
	MultiplayerSessionManager.session_connected = false
	MultiplayerSessionManager.room_code = "PENDING"
	check(not menu._practice_is_available(), "Registered host blocks entry before connection")
	MultiplayerSessionManager.room_code = ""
	menu._multiplayer_join_attempt = {"generation": 1}
	check(not menu._practice_is_available(), "Pending menu join blocks entry before transport")
	menu._multiplayer_join_attempt = {}
	RunContext.multiplayer_session_id = "retained-party"
	check(not menu._practice_is_available(), "Retained party context also blocks entry")
	RunContext.multiplayer_session_id = ""
	menu._create_multiplayer_room()
	check(menu._multiplayer_host_pending and not menu._practice_is_available(), "Async registration disables practice before host transport exists")
	menu._create_multiplayer_room()
	await _settle()
	check(menu.host_calls == 1 and not menu._multiplayer_host_pending and menu._practice_is_available(), "Registration guard prevents duplicate hosts and clears after completion")
	menu._on_practice_pressed()
	menu._multiplayer_host_pending = true
	await _settle()
	check(menu.entries == 1, "New host operation blocks a deferred practice activation")
	menu._multiplayer_host_pending = false
	menu.free()
	menu = FixtureMenu.new()
	menu.practice_return_state = token.duplicate(true)
	root.add_child(menu)
	await _settle()
	check(menu.primary_run_button.text == "Retry Resume" and menu.checkpoint_status_label.text == token.checkpoint_error and menu.checkpoint_discard_button.visible, "Returning restores the exact checkpoint error action")
	check(root.gui_get_focus_owner() == menu.practice_button, "Returning restores Practice keyboard focus")
	menu._show_options_panel()
	check(not menu.root_panel.visible, "Enlarged main actions are hidden while Options is open")
	menu._show_root_panel(false)
	menu._show_glossary_panel()
	check(not menu.root_panel.visible, "Enlarged main actions are hidden while Glossary is open")
	menu.free()
	var panel := PANEL.new()
	root.add_child(panel)
	await _settle()
	var emitted: Array[String] = []
	panel.pause_requested.connect(func() -> void: emitted.append("pause"))
	panel.resume_requested.connect(func() -> void: emitted.append("resume"))
	panel.start_requested.connect(func() -> void: emitted.append("start"))
	panel.apply_requested.connect(func() -> void: emitted.append("apply"))
	panel.menu_requested.connect(func() -> void: emitted.append("menu"))
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		await _settle()
		for state in ["setup", "active", "paused", "victory", "defeat", "error"]:
			panel.present(setup_state(state))
			await _settle()
			check(Rect2(Vector2.ZERO, Vector2(size)).encloses(_rect(panel.hud)), "Practice HUD fits %s %s" % [size, state])
			check(_font_pixels(panel.context_label) >= 18.0, "No-progression notice remains readable")
			for label in [panel.heading, panel.attempt_label, panel.context_label, panel.player_label, panel.boss_label]:
				check(_rect(panel.hud).encloses(_rect(label)), "Complete sidebar text fits: " + label.text)
			var play_rect: Rect2 = panel.get_gameplay_rect()
			var stretch := root.get_stretch_transform().get_scale()
			var physical_play := Rect2(play_rect.position * stretch, play_rect.size * stretch)
			check(physical_play.size.x > 0.0 and physical_play.size.y > 0.0 and not physical_play.intersects(_rect(panel.hud)) and not physical_play.intersects(_rect(panel.controls_label)), "Practice camera area excludes the readable sidebar and controls")
			if state != "active":
				check(Rect2(Vector2.ZERO, Vector2(size)).encloses(_rect(panel.modal)), "Practice dialog fits %s %s" % [size, state])
				check(_rect(panel.modal).encloses(_rect(panel.menu_button)), "Menu action fits inside the practice dialog")
				check(_font_pixels(panel.modal_notice) >= 18.0, "Dialog isolation promise remains readable")
			var expected: Control = panel.resume_button if state == "paused" else panel.menu_button if state == "error" else panel.retry_button
			check(root.gui_get_focus_owner() == null if state == "active" else root.gui_get_focus_owner() == expected, "Mode transition restores correct focus: " + state)
			check(panel.player_label.text == "Bastion  73 / 130" and panel.boss_label.text == "Enemies remaining\n2 / 3", "HUD uses actual health and whole-roster counts")
	for screen in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = screen
		var mission := setup_state("active")
		mission.encounter_name = "Pulse Window"
		mission.encounter_status = "Kills 0 / 30 · 28s"
		mission.encounter_hint = "Overcharged Tethers: Tether links surge and sweep, turning safe lanes into kill corridors"
		mission.objective_state = {"active": true}
		panel.present(mission)
		await _settle(8)
		check(panel.encounter_hint_label.is_visible_in_tree() and panel.encounter_hint_label.text == mission.encounter_hint, "Active Mission rule remains visible outside the modal")
		check(_font_pixels(panel.encounter_hint_label) >= 17.99, "Mission rule remains18physical pixels")
		check(Rect2(Vector2.ZERO, Vector2(screen)).encloses(_rect(panel.hud)) and _rect(panel.hud).encloses(_rect(panel.encounter_hint_label)) and not _rect(panel.encounter_hint_label).intersects(_rect(panel.pause_button)), "Longest Mission rule fits sidebar without covering Pause")
		check(not panel.boss_bar.visible, "Objective progress replaces aggregate foe health")
		mission.mode = "paused"
		mission.detail = mission.encounter_hint
		panel.present(mission)
		await _settle(8)
		check(Rect2(Vector2.ZERO, Vector2(screen)).encloses(_rect(panel.modal)), "Paused Mission with longest rule fits physical window")
		check(_rect(panel.modal).encloses(_rect(panel.modal_detail)) and panel.modal_detail.text == mission.encounter_hint, "Paused Mission keeps the complete current rule")
		check(_rect(panel.modal).encloses(_rect(panel.resume_button)) and _rect(panel.modal).encloses(_rect(panel.retry_button)), "Long Mission rule leaves fixed actions available")
	panel.present(setup_state("active"))
	check(not panel.encounter_hint_label.visible, "A different encounter clears the previous Mission rule")
	panel._request("apply")
	panel._request("resume")
	panel._request("menu")
	check(emitted.is_empty(), "Hidden stale modal actions cannot act during combat")
	panel._request("pause")
	panel.present(setup_state("paused"))
	panel._request("resume")
	panel.present(setup_state("victory"))
	panel._request("apply")
	panel.present(setup_state("setup"))
	panel._request("apply")
	panel.present(setup_state("error"))
	panel._request("menu")
	check(emitted == ["pause", "resume", "apply", "start", "menu"], "Available practice actions emit the expected request once")
	panel.free()
	check(await retirement.wait_until_retired(self), "Practice UI fixture releases native audio")
	print("[OK] Practice menu/UI: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
