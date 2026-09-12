extends "res://scripts/tests/test_biome_room_context.gd"
## Verify displayed timing/targets against actual configured controllers and
## real room lifecycle, including automatic assistance and cover completion.

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	_check_contour_geometry()
	await _setup_context_world()
	for id: String in BIOMES.BIOME_DEFINITIONS:
		for key: String in ["skirmish", "hold_the_line", "apex_breakwater"]:
			await _enter_context(id, key)
			var rules: Node = world._biome_rules
			var mode: String = rules.mode
			var fragments: bool = rules.fragments
			var description := BIOMES.generate_impact_text(BIOMES.get_biome(id), mode, fragments)
			var cover := id == "shatterfield" and not fragments
			if cover:
				check(description.contains("Three contacts") and not description.contains("READ THE FLOOR"), "Cracked cover explains contacts without inventing a timed impact")
			else:
				check(world._get_biome_rule_status().contains("PAUSED"), "Room survey reports the biome as paused: " + id + "/" + key)
				check(description.contains("%ss warning" % str(rules._warning_time)), "Inspection uses the actual room warning duration: " + id + "/" + key)
				check(description.contains("%ss pause" % str(rules._recovery_time).trim_suffix(".0")), "Inspection uses the actual room recovery duration: " + id + "/" + key)
				if id == "haunt":
					check(description.contains("%d%% slower" % roundi((1.0 - float(rules._slow_mult)) * 100.0)), "Haunt inspection states the actual movement reduction")
				else:
					check(description.contains(str(rules._enemy_damage)), "Inspection states the actual foe damage: " + id + "/" + key)
					if mode != "assistance":
						check(description.contains(str(rules._player_damage)), "Dangerous room inspection states player damage")
			_start_context_combat()
			if cover:
				check(world._get_biome_rule_status().contains("STANDING"), "Cover HUD reports available columns")
				for column: Dictionary in world._arena_cover.snapshot():
					for _contact in range(3):
						world._arena_cover.apply_contact(int(column.id))
				check(world._get_biome_rule_status().contains("ROUTES OPEN") and rules.phase == "idle", "Broken cover is reported as open without inventing a fragment event")
				continue
			for phase: String in ["warning", "active", "recovery"]:
				_context_phase(phase)
				world.hud.refresh(world._get_hud_state(), world.player)
				var displayed: String = world.hud._status_biome_phase_label.text
				check(displayed.contains("FOES ONLY") if rules.mode == "assistance" else displayed.contains("YOU + FOES"), "Live phase names the actual room allegiance: " + id + "/" + key)
				var polarity := "HELP" if rules.mode == "assistance" else "DANGER"
				check(displayed.begins_with(polarity) and world.hud._status_biome_rule_label.text.begins_with(polarity + ":"), "Phase and entry advice explicitly distinguish help from danger: " + id + "/" + key)
				var contours: Array = rules.get_polarity_contours()
				check(contours.is_empty() if phase == "recovery" else not contours.is_empty(), "Polarity contours share the actual visible phase lifetime")
				check(_contours_stay_inside(rules.shape, contours), "Polarity contours follow affected floor without marking a safe gap: " + id + "/" + key)
				check(displayed.contains("WARNING") if phase == "warning" else (displayed.contains("BETWEEN") if phase == "recovery" else displayed.contains("ACTIVE") or displayed.contains("IMPACT")), "Live phase follows the actual controller: " + id + "/" + phase)
			world.hud._on_biome_header_entered()
			check(not world.hud._biome_tooltip_content.get_parsed_text().contains("{kw:"), "Inspection renders authored keyword spans")
			world.hud._on_biome_header_exited()
	await _enter_context("hollow", "intercept_run")
	_start_context_combat()
	world.hud.refresh(world._get_hud_state(), world.player)
	world.hud._on_biome_header_entered()
	world.hud._process(1.0)
	check(world.hud._biome_tooltip_content.get_parsed_text().contains("8 base damage to you"), "An open compact-room inspection starts with its actual danger")
	world.objective_manager.intercept_drone_radius = world.current_effective_room_size.length()
	_context_phase("warning")
	world.hud.refresh(world._get_hud_state(), world.player)
	check(world._biome_rules.mode == "assistance" and world.hud._biome_tooltip_content.get_parsed_text().contains("You are safe") and world.hud._status_biome_phase_label.text.contains("FOES ONLY"), "Automatic assistance updates an already-open inspection and live cue together")
	check(world.hud._status_biome_phase_label.text.begins_with("HELP") and world.hud._biome_tooltip_content.get_parsed_text().contains("smooth double borders"), "Automatic assistance changes the explicit polarity and contour explanation immediately")
	world.hud._on_biome_header_exited()
	await _enter_context("storm_reach", "skirmish")
	_start_context_combat()
	_context_phase("warning")
	world._open_networked_reward_selection("Choose a Boon", ENUMS.RewardMode.BOON)
	check(world._get_biome_rule_status().is_empty(), "Reward selection suppresses an old warning status")
	world._tick_biome_rules(0.0)
	check(world._biome_rules.get_polarity_contours().is_empty(), "Reward selection hides an old floor polarity contour")
	world.reward_selection_ui.close_selection()
	world._enter_rest_site()
	world.hud.refresh(world._get_hud_state(), world.player)
	check(not world.hud._status_biome_phase_label.visible, "Rest entry removes the previous biome status")
	await _dispose_context_world()
	print("[BiomeClarity] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _contours_stay_inside(geometry: Dictionary, contours: Array) -> bool:
	for stroke: Dictionary in contours:
		var points: PackedVector2Array = stroke.points
		for index in range(1, points.size()):
			for step in range(5):
				var point := points[index - 1].lerp(points[index], float(step) / 4.0)
				if not RULES.geometry_contains(geometry, point):
					return false
	return true

func _check_contour_geometry() -> void:
	var bounds := Rect2(-300, -200, 600, 400)
	var geometries: Array[Dictionary] = [
		{"kind": "circle", "center": Vector2(240, 0), "radius": 100.0, "bounds": bounds},
		{"kind": "rects", "rects": [Rect2(-290, -40, 230, 80), Rect2(60, -40, 230, 80)], "bounds": bounds},
		{"kind": "annulus", "center": Vector2.ZERO, "inner": 100.0, "outer": 230.0, "bounds": bounds},
		{"kind": "sector", "center": Vector2(0, 160), "inner": 40.0, "outer": 230.0, "angle": .8, "half_angle": PI / 4.0, "bounds": bounds}
	]
	for geometry: Dictionary in geometries:
		for unit: float in [.7, 1.0, 2.0, 3.2]:
			for friendly: bool in [false, true]:
				var contours := RULES.POLARITY_CONTOUR.build_contours(geometry, friendly, unit)
				check(not contours.is_empty() and _contours_stay_inside(geometry, contours), "Clipped %s contours preserve real geometry and safe holes at unit %.1f" % [geometry.kind, unit])
				var roles: Array = contours.map(func(stroke: Dictionary): return stroke.role)
				check(roles.has("inner") and roles.has("glow") and not roles.has("score") if friendly else roles.has("score") and not roles.has("inner"), "Polarity differs by contour texture independently of color: %s / friendly=%s / unit=%.1f" % [geometry.kind, friendly, unit])
	check(RULES.POLARITY_CONTOUR.tint(false, true) != RULES.POLARITY_CONTOUR.tint(false, false), "Danger changes from amber warning to red active")
	check(RULES.POLARITY_CONTOUR.tint(true, true).g > .9 and RULES.POLARITY_CONTOUR.tint(true, false).g > .9, "Helpful warning and active phases keep the same pale mint family")
