extends "res://scripts/tests/test_run_result_identity.gd"

const RECAP := preload("res://scripts/core/damage_recap.gd")

func _damage_summary() -> Dictionary:
	var summary := fixture_summary()
	summary.outcome = "death"
	var recap: Dictionary = {}
	var abilities := ["archer_projectile", "pyre_death_field", "biome_storm_reach", "lancer_zone_tick", "null_archivist_2", "warden_nova"]
	for index in range(6):
		var before := 85 - index * 12
		var after := before - 12 if index < 5 else 0
		recap = RECAP.record_health(recap, after, {"source": "enemy_ability", "ability": abilities[index],
			"health_before": before, "health_after": after, "elapsed_seconds": 817 + index * 5, "room_depth": 20})
	summary.damage_recap = recap
	return summary

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	screen = SCREEN.new()
	root.add_child(screen)
	var folder := project_path.path_join("damage_recap_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array[Dictionary] = []
	for size in [Vector2i(960, 720), Vector2i(1280, 720)]:
		DisplayServer.window_set_size(size)
		await _settle()
		for state in ["final", "older", "revived", "legacy"]:
			var summary := _damage_summary()
			if state == "revived":
				summary.damage_recap = RECAP.record_health(summary.damage_recap, 40)
			elif state == "legacy":
				summary.erase("damage_recap")
			screen.show_result("Defeat", "Run ended in Crossfire.", summary, true)
			await _settle()
			screen._appearance_tween.custom_step(1.0)
			await _settle()
			var physical := root.get_stretch_transform()
			check(Rect2(Vector2.ZERO, Vector2(size)).grow(2.0).encloses(physical * screen._card.get_global_rect()), "Actual results card fits the physical window")
			check(Rect2(Vector2.ZERO, Vector2(size)).grow(2.0).encloses(physical * screen._action_buttons.get_global_rect()), "Actual results actions remain visible")
			var panel = screen._damage_recap_panel
			if state == "legacy":
				check(not panel.visible and panel.get_child_count() == 0, "Legacy result has no invented recap")
			else:
				check(panel.visible and panel.get_child_count() == 14, "All six native damage rows exist")
				check(panel.get_child(0).text == ("Recent damage" if state == "revived" else "Final damage"), "Heading reflects actual final-health evidence")
				if state == "older":
					screen._content_scroll.ensure_control_visible(panel.get_child(13))
					await _settle()
					# ensure_control_visible uses unscaled offsets; correct the
					# remaining overflow in scroll units under the scaled canvas.
					var overflow: float = panel.get_child(13).get_global_rect().end.y - screen._content_scroll.get_global_rect().end.y
					if overflow > 0.0:
						screen._content_scroll.scroll_vertical += ceili(overflow / screen._root.scale.y) + 4
						await _settle()
					check(screen._content_scroll.get_global_rect().grow(1.0).encloses(panel.get_child(13).get_global_rect()), "Oldest recorded damage can be reached by ordinary scrolling")
				else:
					check(screen._content_scroll.get_global_rect().grow(1.0).encloses(panel.get_child(2).get_global_rect()), "Newest damage source is immediately visible")
				for child in panel.get_children():
					var label := child as Label
					check(label.get_line_count() <= label.get_visible_line_count(), "Damage label shows all wrapped text: " + label.text)
					var rendered_font: float = label.get_theme_font_size("font_size") * absf((physical * label.get_global_transform()).get_scale().y)
					check(rendered_font >= 14.9, "Damage label stays readable after production canvas stretch")
					check(label.size.x <= screen._content_scroll.size.x + 1.0, "Damage label fits scrolling column")
			await RenderingServer.frame_post_draw
			var filename := "%s_%d.png" % [state, size.x]
			var picture := root.get_texture().get_image()
			check(not picture.is_empty() and picture.save_png(folder.path_join(filename)) == OK, "Captured " + filename)
			frames.append({"file": filename, "size": [size.x, size.y], "state": state})
	screen.queue_free()
	await _settle()
	var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	print("[OK] Damage recap render: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
