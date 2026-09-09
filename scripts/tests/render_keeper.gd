extends "res://scripts/tests/render_motion_arcana.gd"
## Real Keeper drawing and damage behavior in the existing isolated GPU arena.

const KEEPER_RUNTIME := preload("res://scripts/tests/test_keeper_runtime.gd")
const DAMAGE := preload("res://scripts/shared/damageable.gd")

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Keeper GPU fixture requires an isolated validation project")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Keeper GPU fixture requires a real GPU renderer")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2(FRAME_SIZE) * 0.5 + Vector2(0.0, 25.0))
	output_directory = project_path.path_join("keeper_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _make_world()
	for label in world.find_children("*", "Label", true, false):
		if String(label.text).begins_with("MOTION ARCANA"):
			label.text = "KEEPER / BREACH  /  Isolated GPU playtest fixture  /  1280 × 720"
	player.position = Vector2(-240.0, 0.0)
	var keeper := KEEPER_RUNTIME.Keeper.new()
	_add_shape(keeper, 17.0)
	keeper.position = Vector2(100.0, 0.0)
	world.add_child(keeper)
	var allies: Array[RenderEnemy] = []
	for point in [Vector2(-35.0, -92.0), Vector2(-35.0, 92.0)]:
		var ally := RenderEnemy.new()
		_add_shape(ally, 13.0)
		ally.position = point
		world.add_child(ally)
		ally.set_max_health_and_current(100)
		allies.append(ally)
	await physics_frame
	await process_frame
	keeper._update_wards(0.001)
	_check(keeper.ward_targets.is_empty() and keeper.ward_warmup_left > 0.0, "Warmup frame uses actual pending links")
	await _capture("keeper_warmup", "KEEPER / WARDS FORMING", "Dashed links announce protection. The Keeper itself remains exposed.")
	keeper._update_wards(0.61)
	_check(keeper.ward_targets.size() == 2, "Active frame has exactly two real protected allies")
	DAMAGE.apply_damage(allies[0], 100)
	_check(allies[0].get_current_health() == 30 and world.damage_recorded == 70, "Ward visualization corresponds to an actual 30% damage reduction")
	await _capture("keeper_active", "KEEPER / TWO ALLIES WARDED", "100 damage becomes 70. Thin gold links and shield marks identify the protected allies.")
	DAMAGE.apply_damage(allies[0], 1000)
	_check(allies[0].get_current_health() == 1 and world.damage_recorded == 99, "A lethal burst leaves the warded ally at 1 HP and credits only 29 more damage")
	DAMAGE.apply_damage(allies[0], 1000)
	_check(allies[0].get_current_health() == 1 and world.damage_recorded == 99, "Repeated lethal damage cannot finish the linked ally or add damage credit")
	keeper.queue_redraw()
	await _capture("keeper_saved", "KEEPER / ALLY HELD AT 1 HP", "A lethal burst leaves 1 HP. A bright link and gold shield show why more damage cannot finish this ally.")
	DAMAGE.apply_impulse(keeper, Vector2(180.0, 0.0), 1, true)
	_check(keeper.ward_targets.is_empty() and keeper.ward_rearm_left > 1.2, "Broken frame is caused by an actual player displacement")
	await _capture("keeper_break", "KEEPER / WARDS BROKEN", "A push breaks both links. Gold fragments and a dim crown mark the rearm window.")
	DAMAGE.apply_damage(allies[0], 1000)
	_check(allies[0].get_current_health() == 0 and allies[0].is_queued_for_deletion() and world.damage_recorded == 100, "The next hit kills the saved ally after a break and credits its last 1 HP")
	keeper._update_wards(0.3)
	DAMAGE.apply_damage(keeper, 30)
	_check(keeper.get_current_health() == 48 and world.damage_recorded == 130, "Keeper itself takes all 30 damage while its links are down")
	await _capture("keeper_vulnerable", "KEEPER / EXPOSED SUPPORT", "The next hit kills the freed ally. The Keeper takes full damage; wards need a delay and fresh warmup.")
	_free_world()
	await create_timer(0.2).timeout
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures, "size": [FRAME_SIZE.x, FRAME_SIZE.y]}
	var file := FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("[OK] Keeper GPU fixture: %d frames, %d failures" % [frames.size(), failures.size()])
	print("KEEPER_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)
