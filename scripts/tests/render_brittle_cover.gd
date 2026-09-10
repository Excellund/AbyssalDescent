extends "res://scripts/tests/render_character_identity.gd"
## Production floor, columns, character and camera; cover state is staged here.
## Attack acceptance, physical gaps and network delivery have separate fixtures.

const LAYOUTS := preload("res://scripts/shared/arena_layout_registry.gd")
const BIOMES := preload("res://scripts/shared/biome_registry.gd")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		push_error("Cover GPU fixture requires an isolated real renderer")
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	output_directory = ProjectSettings.globalize_path("res://brittle_cover_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	_setup()
	party.append(actor)
	renderer = RENDERER.new()
	room.add_child(renderer)
	renderer.set_process(false)
	camera = CAMERA.new()
	room.add_child(camera)
	camera.set_static_mode(Vector2.ZERO)
	camera.set_physics_process(false)
	_set_room_size(DEFINITIONS.POOL_ROOM_SIZE)
	var biome := BIOMES.get_biome("shatterfield")
	renderer.set_environment_identity(1, "shatterfield")
	renderer.set_biome_color_theme(biome.color_theme)
	var layer := CanvasLayer.new()
	room.add_child(layer)
	heading = Label.new()
	heading.position = Vector2(28.0, 14.0)
	heading.add_theme_font_size_override("font_size", 22)
	layer.add_child(heading)
	caption = Label.new()
	caption.position = Vector2(28.0, 43.0)
	caption.add_theme_font_size_override("font_size", 14)
	layer.add_child(caption)
	_make_party()
	for member in party:
		member.visible = member == actor
	actor.position = Vector2(-40.0, 30.0)
	for mirrored in [false, true]:
		var layout := _layout(mirrored)
		var prefix := "mirror_" if mirrored else "original_"
		var previous: Image
		for remaining in [3, 2, 1, 0]:
			var live: Array[Dictionary] = []
			var rubble: Array[Dictionary] = []
			for source in layout:
				var entry := source.duplicate(true)
				if int(entry.get("break_contacts", 0)) > 0:
					entry["contacts_left"] = remaining
					if remaining == 0:
						rubble.append(entry)
						continue
				live.append(entry)
			renderer.set_obstacle_layout(live)
			renderer.set_cover_rubble_layout(rubble)
			var picture: Image = await _capture(prefix + str(remaining), "SHATTERFIELD / CROSSFIRE", "Cracked cover: %d Attack contacts left · outer shelter stays solid" % remaining)
			_check(live.size() == (2 if remaining == 0 else 4), "Rendered physical silhouettes match remaining cover")
			if previous != null:
				var changed := 0
				var center: Vector2 = layout[1].pos
				for y in range(-32, 37, 2):
					for x in range(-32, 33, 2):
						var sample := center + Vector2(x, y)
						if _color_distance(_pixel_at(picture, sample), _pixel_at(previous, sample)) > 0.06:
							changed += 1
				_check(changed > 8, "Each accepted-contact state visibly differs at normal camera fit")
			if remaining == 0:
				for index in [1, 2]:
					var center: Vector2 = layout[index].pos
					_check(_pixel_at(picture, center).get_luminance() < 0.16, "Broken cover center reads as dark open floor")
			previous = picture
	_make_party()
	var crowded_layout := _layout(true)
	crowded_layout[2]["contacts_left"] = 1
	renderer.set_obstacle_layout(crowded_layout)
	renderer.set_cover_rubble_layout([] as Array[Dictionary])
	await _electric_build_frame(true)
	_make_party()
	for member in party:
		member.visible = member == actor
	actor.position = Vector2(-40.0, 30.0)
	root.size = Vector2i(960, 720)
	root.content_scale_size = Vector2i(960, 720)
	await process_frame
	_set_room_size(DEFINITIONS.POOL_ROOM_SIZE)
	var narrow_layout := _layout(false)
	renderer.set_obstacle_layout(narrow_layout)
	await _capture("narrow_intact", "SHATTERFIELD / CROSSFIRE", "960px window · cracked inner cover and permanent outer shelter")
	var narrow_live: Array[Dictionary] = [narrow_layout[0], narrow_layout[3]]
	var narrow_rubble: Array[Dictionary] = [narrow_layout[1], narrow_layout[2]]
	renderer.set_obstacle_layout(narrow_live)
	renderer.set_cover_rubble_layout(narrow_rubble)
	await _capture("narrow_open", "SHATTERFIELD / CROSSFIRE", "960px window · opened crossings keep clear centers")
	for member in party:
		member.discard_pending_combat_input()
	EnemyReplicationService.unbind_world(room)
	current_scene = null
	room.free()
	party.clear()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await retirement.wait_until_retired(self), "Native audio retires before renderer exit")
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures, "checks": checks, "scope": "Two production Crossfire formations, four staged cover states each, crowded party effects, and 960px intact/open states. Physical hits and ENet are separate."}, "\t"))
	print("[OK] Brittle cover GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _layout(mirrored: bool) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(100):
		rng.seed = seed_value
		var layout := LAYOUTS.pick_layout("Crossfire", DEFINITIONS.POOL_ROOM_SIZE, rng, "shatterfield")
		if (float((layout[0].pos as Vector2).x) > 0.0) == mirrored:
			return layout
	_check(false, "Both authored formations are available")
	return []
