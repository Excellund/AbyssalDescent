extends "res://scripts/tests/render_attack_feedback.gd"
## Real player screen layers and world rings at the standard room-fit scale.

const WARDEN := preload("res://scripts/enemy_boss.gd")

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Feedback ownership rendering requires an isolated project")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Feedback ownership rendering requires an actual GPU")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	var zoom := minf(1280.0 / 1180.0, 720.0 / 580.0) * 0.95
	root.canvas_transform = Transform2D(Vector2(zoom, 0.0), Vector2(0.0, zoom), Vector2(FRAME_SIZE) * 0.5 + Vector2(0.0, 25.0))
	output_directory = project_path.path_join("feedback_ownership_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _impact_frame(false)
	await _impact_frame(true)
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "zoom": zoom, "frames": frames, "failures": failures}
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("[OK] Feedback ownership GPU: %d frames, %d failures" % [frames.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func _impact_frame(local_hit: bool) -> void:
	await _prepare_world()
	for label in world.find_children("*", "Label", true, false):
		if String(label.text).begins_with("ATTACK FEEDBACK"):
			label.text = "PLAYER FEEDBACK / Isolated GPU playtest fixture / 1280 × 720"
	var remote := RemotePlayer.new()
	_add_shape(remote, 14.0)
	remote.position = Vector2(160.0, 40.0)
	world.add_child(remote)
	remote.apply_character_package(CHARACTER.get_character("bastion"))
	remote.arcana_motion.set_process(false)
	var boss := WARDEN.new()
	_add_shape(boss, 34.0)
	boss.position = Vector2(-250.0, -145.0)
	world.add_child(boss)
	boss.set_physics_process(false)
	boss.locked_direction = Vector2.RIGHT
	boss.visual_facing_direction = Vector2.RIGHT
	boss.active_attack = boss.ENEMY_STATE_ENUMS.BossAttack.CHARGE
	boss.boss_state = boss.ENEMY_STATE_ENUMS.BossState.TELEGRAPH
	boss.telegraph_alpha = 0.8
	boss._charge_motion.prepare(boss.charge_speed, boss.charge_duration, Vector2.RIGHT)
	boss.queue_redraw()
	var hit_player := player if local_hit else remote
	boss._play_heavy_impact_feedback(hit_player, hit_player.global_position, 76.0)
	_check(remote.player_feedback.damage_flash_layer == null, "Remote avatar has no screen-wide feedback layer")
	_check(hit_player.player_feedback.get_children().any(func(child): return child is Line2D), "Impact world rings are visible at the struck avatar")
	if local_hit:
		_check(is_equal_approx(player.player_feedback.damage_flash_rect.modulate.a, 0.585), "Local heavy impact retains its original strength")
		# Hold this one rendered comparison at the existing flash's peak.
		player.player_feedback.damage_flash_tween.pause()
		await _capture("local_impact", "YOUR HIT / ORIGINAL HEAVY IMPACT", "The same boss cue keeps its full-screen flash when this view's player is struck.")
	else:
		_check(is_zero_approx(player.player_feedback.damage_flash_rect.modulate.a), "A partner impact leaves the local screen clear")
		await _capture("partner_impact", "PARTNER HIT / WORLD FEEDBACK ONLY", "The partner on the right receives impact rings. Your screen and the boss warning remain clear.")
	if is_instance_valid(remote.upgrade_system.power_registry):
		remote.upgrade_system.power_registry.free()
	await _free_world()
