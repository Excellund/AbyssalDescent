extends "res://scripts/tests/render_motion_arcana.gd"
## Native accepted Blast, Relay flight, Stormbrand status and Shatterwake cues.

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		push_error("Keyword synergy GPU fixture requires an isolated project and real renderer")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2(FRAME_SIZE) * .5 + Vector2(0, 25))
	output_directory = project_path.path_join("keyword_synergy_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _native_chain_frames()
	await _cover_frame()
	await _echo_frame()
	await create_timer(.2).timeout
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var manifest := {"size": [FRAME_SIZE.x, FRAME_SIZE.y], "gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures, "scope": "Native local producers, accepted damage, controller geometry and effects; dedicated ENet fixture checks transport."}
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("[KeywordSynergyGPU] %d frames, %d failures" % [frames.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func _learn_chain() -> void:
	player.player_id = 1
	player.apply_trial_power("blast_drive")
	for _level in range(3):
		player.apply_trial_power("spark_relay")
		player.apply_trial_power("stormbrand")
	player.apply_upgrade("shatterwake")
	player.apply_upgrade("patient_hunter")
	player.apply_upgrade("marked_prey")

func _hold_relay() -> void:
	if is_instance_valid(player.spark_relay_controller):
		player.spark_relay_controller.set_physics_process(false)

func _step_relay(seconds: float) -> void:
	# Preserve the requested flight time while recording the same short trail
	# segments as ordinary controller updates, including the final partial step.
	var remaining := seconds
	while remaining > 0.000001:
		var step := minf(1.0 / 120.0, remaining)
		player.spark_relay_controller.tick(step)
		remaining -= step

func _native_chain_frames() -> void:
	await _make_world()
	_learn_chain()
	var primary := _add_enemy(Vector2(-40, 0))
	var nearby := _add_enemy(Vector2(15, 38))
	var distant := _add_enemy(Vector2(90, 0))
	await physics_frame
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	_hold_relay()
	_check(player.spark_relay_controller.projectiles.size() == 1, "A real Blast creates one body-origin Relay")
	_step_relay(.065)
	await _capture("relay_launch", "SPARK RELAY / BURST TO PROJECTILE", "The Blast sends one Electric projectile from the player toward the struck foe.")
	var nearby_before := nearby.get_current_health()
	_step_relay(.105)
	_check(DAMAGEABLE.status_snapshot(primary, 1).mark_ratio > 0.0 and nearby.get_current_health() < nearby_before, "Relay applies Stormbrand on accepted Electric contact and Shatterwake damages the nearby foe")
	await _capture("relay_impact", "STORMBRAND + SHATTERWAKE / FIRST CONTACT", "Electric contact applies a timed Mark. Projectile contact releases one nearby Burst.")
	player.spark_relay_controller.tick(1.0)
	_check(player.spark_relay_controller.projectiles.is_empty() and distant.get_current_health() < 10000, "The same piercing Relay reaches another foe, then retires")
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	_hold_relay()
	_step_relay(.17)
	_check(primary.is_slowed(), "A fresh Relay on an already Marked foe applies Stormbrand L3 Slow")
	await _capture("stormbrand_refresh", "STORMBRAND / PREPARED TARGET", "A later Electric contact refreshes Mark and applies Slow to the already Marked foe.")
	player.spark_relay_controller.tick(1.0)
	await _step_frames(24)
	_check(player.spark_relay_controller.projectiles.is_empty(), "Expired Relay leaves no projectile or damaging afterglow")
	await _capture("relay_expired", "RELAY COMPLETE / MARK REMAINS", "The projectile and Burst have ended. The Mark stays visible while this fixture holds enemy status timers.")
	await _free_world()

func _cover_frame() -> void:
	await _make_world()
	_learn_chain()
	player.apply_trial_power("rupture_wave")
	var target := _add_enemy(Vector2(170, 0))
	_add_column(Vector2.ZERO, 28)
	var columns: Array[Dictionary] = [{"pos": Vector2.ZERO, "radius": 28.0}]
	for child in world.get_children():
		if child is RENDERER:
			child.set_obstacle_layout(columns)
	await physics_frame
	player._apply_rupture_wave(target.global_position, 20)
	_hold_relay()
	var before := target.get_current_health()
	player.spark_relay_controller.tick(1.0)
	_check(target.get_current_health() == before and player.spark_relay_controller.projectiles.is_empty(), "A real column stops Relay before its target")
	await _capture("relay_blocked", "SPARK RELAY / COVER AFTERMATH", "After the column stops the projectile, the foe behind cover has received no Relay damage or Mark.")
	await _free_world()

func _echo_frame() -> void:
	await _make_world()
	_learn_chain()
	player.apply_upgrade("sovereigns_double")
	var target := _add_enemy(Vector2(250, 0))
	player.boss_combinations.create_shade(Vector2(130, 0))
	await physics_frame
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	_hold_relay()
	_check(target.get_current_health() < 10000 and player.spark_relay_controller.projectiles.size() == 1, "A distant copied Blast keeps Burst form and launches one Relay")
	_step_relay(.09)
	_check(player.spark_relay_controller.projectiles[0].position.x < 0.0, "Copied Blast Relay starts at the real body instead of the distant shade")
	await _capture("echo_blast_relay", "SOVEREIGN'S DOUBLE / COPIED BLAST", "The distant shade copies the Blast. Its accepted Burst launches one Electric projectile from the player.")
	await _free_world()
