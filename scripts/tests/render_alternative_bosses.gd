extends "res://scripts/tests/render_motion_arcana.gd"
## Real alternate bodies and all nine committed warnings at combat scale.

const ALTERNATIVE_TEST := preload("res://scripts/tests/test_alternative_bosses.gd")
const BOSS_STAGES := preload("res://scripts/shared/boss_stage_registry.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

class FitCamera extends "res://scripts/player_camera.gd":
	func _ready() -> void:
		enabled = false
		set_physics_process(false)

var arena_renderer: RENDERER
var fit_camera: FitCamera

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Alternative boss GPU fixture requires an isolated project")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Alternative boss GPU fixture requires a GPU renderer")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2(FRAME_SIZE) * 0.5 + Vector2(0.0, 25.0))
	output_directory = project_path.path_join("alternative_boss_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _make_world()
	for child in world.get_children():
		if child.get_script() == RENDERER:
			arena_renderer = child as RENDERER
		if child.is_in_group("arena_columns"):
			child.queue_free()
	arena_renderer.set_obstacle_layout([])
	fit_camera = FitCamera.new()
	world.add_child(fit_camera)
	for label in world.find_children("*", "Label", true, false):
		if String(label.text).begins_with("MOTION ARCANA"):
			label.text = "ALTERNATIVE BOSSES  /  Isolated GPU fixture  /  1280 × 720"
	for id in ALTERNATIVE_TEST.IDS:
		var stage := ALTERNATIVE_TEST.IDS.find(id) + 1
		_fit_arena(stage)
		var boss := ALTERNATIVE_TEST.Alternative.new()
		boss.boss_id = id
		_add_shape(boss, 34.0)
		world.add_child(boss)
		boss.position = Vector2(-100.0, 0.0)
		boss.target = player
		boss.target_candidates = [player]
		arena_renderer.set_boss_entrance_motif(id, true)
		arena_renderer._process(0.5)
		await _capture(id + "_entrance", id.to_upper().replace("_", " ") + " / ENTRANCE", "The entrance motif clears before the first combat warning.")
		arena_renderer.set_boss_entrance_motif(id, false)
		for kind in range(3):
			player.position = Vector2(110.0, 30.0)
			boss._cancel_attack()
			boss.begin_attack(kind)
			boss._process_behavior(boss.warning_duration * 0.55)
			_check(not boss.get_attack_warning_geometry().is_empty(), "%s attack %d has visible geometry" % [id, kind])
			await _capture("%s_%d" % [id, kind], "%s / ATTACK %d" % [id.to_upper().replace("_", " "), kind + 1], "Committed danger boundaries leave readable safe space before the attack resolves.")
		if id != "kilnheart":
			await _party_edge_frame(boss, id)
		boss.free()
		await process_frame
	await _capture("owners_removed", "ALTERNATIVE BOSSES / WARNINGS CLEARED", "Removing the encounter owner removes every active attack warning.")
	await _door_frame()
	await _free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures}
	var file := FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("[OK] Alternative bosses GPU: %d frames, %d failures" % [frames.size(), failures.size()])
	print("ALTERNATIVE_BOSS_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)

func _fit_arena(stage: int) -> void:
	var size: Vector2 = BOSS_STAGES.get_descriptor(stage)["room_size"]
	world.current_effective_room_size = size
	arena_renderer.room_size = size
	arena_renderer.set_environment_identity(stage, "")
	# Use the production room-fit camera calculation, without allowing a fixture
	# camera to follow an offscreen pointer or alter the fixed arena center.
	fit_camera.set_world_bounds(Rect2(-size * 0.5, size))
	var scale: Vector2 = fit_camera.target_zoom
	root.canvas_transform = Transform2D(0.0, scale, 0.0, Vector2(FRAME_SIZE) * 0.5)
	arena_renderer.queue_redraw()

func _party_edge_frame(boss: Node2D, id: String) -> void:
	var actors: Array[Node2D] = [player]
	for index in range(3):
		var actor := RenderPlayer.new()
		_add_shape(actor, 14.0)
		world.add_child(actor)
		actor.arcana_motion.set_process(false)
		actor.boss_combinations.set_process(false)
		actors.append(actor)
	var center := world.current_effective_room_size * 0.5 - Vector2(220.0, 210.0)
	var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(150.0, 0.0), Vector2(-75.0, 129.9), Vector2(-75.0, -129.9)]
	for index in range(actors.size()):
		actors[index].global_position = center + offsets[index]
	boss._cancel_attack()
	boss.target = player
	boss.target_candidates = actors
	if id == "null_archivist":
		boss.begin_attack(0)
		for actor in actors:
			actor.global_position = Vector2(-500.0, -350.0)
		boss._resolve_attack()
		for index in range(actors.size()):
			actors[index].global_position = center + offsets[index]
	boss.begin_attack(2 if id == "glassweaver" else 1)
	boss._process_behavior(boss.warning_duration * 0.55)
	for actor in actors:
		_check(not ALTERNATIVE_TEST.warning_contains(boss.get_attack_warning_geometry(), actor.global_position), id + ": four-player edge cluster preserves all safe centers")
	await _capture(id + "_party_edge", id.to_upper().replace("_", " ") + " / FOUR PLAYERS NEAR THE EDGE", "Overlapping rings share a safe pocket; each marked player's center remains safe.")
	for index in range(1, actors.size()):
		var actor: Node2D = actors[index]
		if is_instance_valid(actor.upgrade_system.power_registry):
			actor.upgrade_system.power_registry.free()
		actor.free()

func _door_frame() -> void:
	_fit_arena(1)
	arena_renderer.choosing_next_room = true
	arena_renderer.door_options.clear()
	for index in range(3):
		var id: String = ALTERNATIVE_TEST.IDS[index]
		var door := CONTRACTS.boss_door_option(["warden", "sovereign", "lacuna"][index])
		door["boss_id"] = id
		door["label"] = BOSS_STAGES.get_descriptor(index + 1, id)["display_name"]
		door["position"] = Vector2(-340.0 + 340.0 * index, -35.0)
		arena_renderer.door_options.append(door)
	player.position = Vector2(0.0, 150.0)
	arena_renderer.player_global_position = player.global_position
	arena_renderer.queue_redraw()
	_check(arena_renderer.choosing_next_room and arena_renderer.door_options.size() == 3, "Three selected boss doors are staged for the preview")
	await process_frame
	await process_frame
	await _capture("boss_doors", "ALTERNATIVE BOSS DOORS / THREE IDENTITIES", "The selected boss name and furnace, glass or page motif identify the upcoming encounter.")
