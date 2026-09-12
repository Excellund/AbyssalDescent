extends "res://scripts/tests/render_threadbinder.gd"
## Actual Keeper, floor, camera, effects and Attack path at supported small widths.

func _prime_oath() -> void:
	actor.indomitable_damage_bank = actor._get_indomitable_fill_requirement()
	actor._indomitable_spirit_primed = true
	actor._indomitable_primed_this_attack = false
	actor._sync_oath_ui()

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Oath/Effigy render requires an isolated native GPU fixture")
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	output_directory = ProjectSettings.globalize_path("res://oath_effigy_frames")
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
	var layer := CanvasLayer.new()
	room.add_child(layer)
	heading = Label.new()
	heading.position = Vector2(24, 16)
	heading.add_theme_font_size_override("font_size", 21)
	layer.add_child(heading)
	caption = Label.new()
	caption.position = Vector2(24, 45)
	caption.add_theme_font_size_override("font_size", 15)
	layer.add_child(caption)
	for size in [Vector2i(960, 540), Vector2i(1280, 720)]:
		root.size = size
		root.content_scale_size = size
		_set_room_size(DEFINITIONS.POOL_ROOM_SIZE)
		_make_party(["threadbinder"])
		actor.apply_upgrade("unbroken_oath")
		actor.position = Vector2(-190, 60)
		actor.aim = Vector2.RIGHT
		_prime_oath()
		await process_frame
		actor._try_execute_attack(Vector2.RIGHT)
		_check(actor.effigy_position.is_equal_approx(Vector2(-10, 60)) and actor.indomitable_damage_bank == 0.0, "Primed deployment still spends Oath and plants from its true body origin")
		await _oath_capture("%d_deployment" % size.x, "UNBROKEN OATH / DEPLOYMENT", "The first Attack keeps its sword at the Keeper; the new effigy appears ahead.")
		await create_timer(0.55).timeout
		actor.position = Vector2(-190, -115)
		actor.attack_cooldown_left = 0.0
		actor.attack_lock_time_left = 0.0
		_prime_oath()
		actor._try_execute_attack(Vector2.RIGHT)
		await _oath_capture("%d_effigy" % size.x, "UNBROKEN OATH / FIXED EFFIGY", "The Keeper has walked away. The sword now follows the effigy's Attack.")
		await create_timer(0.55).timeout
		actor.attack_cooldown_left = 0.0
		actor.attack_lock_time_left = 0.0
		_prime_oath()
		actor.perform_motion_blast(Vector2.RIGHT, 1.0)
		await _oath_capture("%d_blast" % size.x, "UNBROKEN OATH / CHARGED ATTACK", "Charged Blast keeps the sword and damage shape together at the effigy.")
		await create_timer(0.7).timeout
		await _oath_capture("%d_settled" % size.x, "UNBROKEN OATH / SETTLED", "The sword fades away; the effigy keeps its fixed battlefield position.")
		_check(actor.effigy_deployed and actor.effigy_position.is_equal_approx(Vector2(-10, 60)), "Presentation and charged Recoil preserve the committed effigy")
	for member in party:
		member.discard_pending_combat_input()
		if is_instance_valid(member.upgrade_system.power_registry):
			member.upgrade_system.power_registry.free()
	EnemyReplicationService.unbind_world(room)
	current_scene = null
	room.free()
	party.clear()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await retirement.wait_until_retired(self), "Native audio retires before fixture exit")
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures}, "\t"))
	print("[OK] Oath Effigy GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _oath_capture(name: String, title: String, explanation: String) -> void:
	heading.text = title
	caption.text = explanation
	var before := _mechanical_state(actor)
	actor.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	_check(before == _mechanical_state(actor), "Native rendering leaves committed Attack state unchanged: " + name)
	var picture := root.get_texture().get_image()
	_check(picture.get_size() == root.size, "Native frame matches viewport size: " + name)
	var path := output_directory.path_join(name + ".png")
	_check(picture.save_png(path) == OK, "Saved " + name)
	frames.append({"name": name, "path": path, "zoom": camera.zoom.x, "room_size": room.current_effective_room_size})
	print("[FRAME] " + path)
