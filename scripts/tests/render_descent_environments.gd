extends "res://scripts/tests/render_character_identity.gd"
## Production arena/camera, character effects and enemy warnings. Party frames
## stage real player renderers locally; network delivery is a separate check.

const BIOMES := preload("res://scripts/shared/biome_registry.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
var frame_prefix := ""

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		push_error("Descent GPU fixture requires an isolated real renderer")
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	output_directory = ProjectSettings.globalize_path("res://descent_environment_frames")
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
	actor.position = Vector2(-150.0, 0.0)
	var obstacles: Array[Dictionary] = [{"pos": Vector2(-270.0, -140.0), "radius": 28.0}, {"pos": Vector2(270.0, 140.0), "radius": 34.0, "type": "boulder"}]
	renderer.set_obstacle_layout(obstacles)
	var baseline_children := renderer.get_child_count()
	for biome_id: String in BIOMES.BIOME_DEFINITIONS:
		var biome: Dictionary = BIOMES.BIOME_DEFINITIONS[biome_id]
		renderer.set_environment_identity(int(biome.act), biome_id)
		renderer.set_biome_color_theme(biome.color_theme)
		var picture: Image = await _capture("palette_" + biome_id, "ACT %d / %s" % [int(biome.act), String(biome.name).to_upper()], "Normal room camera · continuous arena boundary · decorative depth beyond the wall")
		_check(renderer.get_child_count() == baseline_children and renderer.obstacle_layout == obstacles, "Identity leaves scene nodes and obstacle geometry unchanged: " + biome_id)
		var floor_color := _pixel_at(picture, Vector2(100.0, 0.0))
		_check(maxf(floor_color.r, maxf(floor_color.g, floor_color.b)) < 0.20, "Combat floor remains dark in " + biome_id)
		var border_color := _pixel_at(picture, Vector2(0.0, renderer.room_size.y * 0.5))
		_check(border_color.get_luminance() > floor_color.get_luminance() + 0.12, "True arena edge is stronger than decorative floor in " + biome_id)
	for act in range(1, 4):
		var biome: Dictionary = BIOMES.get_act_biomes(act)[0]
		renderer.set_environment_identity(act, String(biome.id))
		renderer.set_biome_color_theme(biome.color_theme)
		frame_prefix = "act%d_" % act
		await _electric_build_frame(false)
		await _electric_build_frame(true)
	frame_prefix = ""
	_set_room_size(DEFINITIONS.POOL_ROOM_SIZE)
	_make_party()
	for member in party:
		member.visible = member == actor
	actor.position = Vector2(0.0, 70.0)
	for act in range(1, 4):
		var biome: Dictionary = BIOMES.get_act_biomes(act)[0]
		var boss_key: String = ["warden", "sovereign", "lacuna"][act - 1]
		renderer.set_environment_identity(act, String(biome.id))
		renderer.set_biome_color_theme(biome.color_theme)
		await process_frame
		await RenderingServer.frame_post_draw
		var before_intro := root.get_texture().get_image()
		renderer.set_boss_entrance_motif(boss_key, true)
		renderer._process(0.5)
		var intro_picture: Image = await _capture("entrance_" + boss_key, "ACT %d / %s ENTRANCE" % [act, boss_key.to_upper()], "Decorative perimeter motif exists only during the existing entrance state")
		var changed := 0
		for y in range(-120, 121, 8):
			for x in range(26, 87, 6):
				var position := Vector2(renderer.room_size.x * 0.5 + float(x), float(y))
				if _color_distance(_pixel_at(before_intro, position), _pixel_at(intro_picture, position)) > 0.015:
					changed += 1
		_check(changed > 20, "Entrance motif is visible outside the arena at production camera fit: " + boss_key)
		_check(_color_distance(_pixel_at(before_intro, Vector2(100.0, 0.0)), _pixel_at(intro_picture, Vector2(100.0, 0.0))) < 0.008, "Entrance motif leaves playable floor untouched: " + boss_key)
		renderer.set_boss_entrance_motif(boss_key, false)
		_check(not renderer.boss_entrance_active and renderer._boss_entrance_visibility == 0.0, "Entrance motif clears before combat: " + boss_key)
	await _door_frames()
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
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures, "checks": checks, "scope": "Nine palettes, production camera fits, staged solo/party effects and warnings, entrances and focused doors. No live networking."}, "\t"))
	print("[OK] Descent environment GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _door_frames() -> void:
	renderer.choosing_next_room = true
	var options: Array[Dictionary] = [
		{"kind_id": ENUMS.DoorKind.ENCOUNTER, "encounter_key": "skirmish", "label": "Skirmish", "position": Vector2(-260.0, -60.0), "color": Color(0.4, 0.8, 1.0), "icon": "easy", "reward": ENUMS.RewardMode.MISSION, "profile": {"player_mutator": {"name": "Hunter's Focus", "duration_encounters": 3}}},
		{"kind_id": ENUMS.DoorKind.REST, "encounter_key": "rest", "label": "Rest Site", "position": Vector2(0.0, -60.0), "color": Color(0.5, 0.9, 0.6), "icon": "rest", "profile": {}},
		{"kind_id": ENUMS.DoorKind.BOSS, "encounter_key": "warden", "label": "Warden", "position": Vector2(260.0, -60.0), "color": Color(0.9, 0.7, 0.35), "icon": "boss", "profile": {}}
	]
	renderer.door_options = options
	for index in options.size():
		var door: Dictionary = options[index]
		renderer.player_global_position = door.position + Vector2(0.0, 30.0)
		actor.position = renderer.player_global_position
		renderer._focused_door_valid = false
		renderer._focused_chip_morph = 1.0
		renderer.queue_redraw()
		await _capture("door_%d" % index, "FOCUSED ROUTE / " + CONTRACTS.door_reward_preview_text(door).to_upper(), "Only the focused expanded door shows the truthful reward family")
		_check(not CONTRACTS.door_reward_preview_text(door).is_empty(), "Known route has a reward preview")
		_check(renderer._focused_door_position.is_equal_approx(door.position), "Captured expanded preview belongs to the approached door")

func _capture(name: String, title: String, detail: String) -> Image:
	return await super._capture(frame_prefix + name, (frame_prefix.to_upper().trim_suffix("_") + " / " if not frame_prefix.is_empty() else "") + title, detail)
