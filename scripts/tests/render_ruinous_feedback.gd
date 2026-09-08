extends "res://scripts/tests/render_motion_arcana.gd"
## Actual launch, compression and impact cues against the gameplay renderer.

const FEEDBACK := preload("res://scripts/ruinous_impact_feedback.gd")

class RenderBoss extends "res://scripts/enemy_boss_2.gd":
	func _ready() -> void:
		max_health = 10000
		super._ready()
		set_physics_process(false)

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		push_error("Ruinous GPU fixture requires an isolated project with a real renderer")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2(FRAME_SIZE) * 0.5 + Vector2(0.0, 25.0))
	output_directory = project_path.path_join("ruinous_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _launch_frame()
	await _collision_frame()
	await _compression_frames()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var file := FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures}, "\t"))
	file.close()
	print("[OK] Ruinous GPU fixture: %d frames, %d failures" % [frames.size(), failures.size()])
	print("RUINOUS_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)

func _prepare_world() -> void:
	await _make_world()
	player.apply_upgrade("ruinous_impact")
	for label in world.find_children("*", "Label", true, false):
		if String(label.text).begins_with("MOTION ARCANA"):
			label.text = "RUINOUS IMPACT  /  Isolated GPU playtest fixture  /  1280 × 720"

func _feedback() -> FEEDBACK:
	var feedback: FEEDBACK = EnemyReplicationService._ruinous_feedback
	feedback.set_process(false)
	feedback._impact_sound.stop()
	feedback._impact_sound.stream = null
	return feedback

func _launch_frame() -> void:
	await _prepare_world()
	var launched := _add_enemy(Vector2(-55.0, 0.0))
	_add_enemy(Vector2(170.0, 85.0))
	_add_enemy(Vector2(150.0, -100.0))
	await physics_frame
	player.boss_combinations.launch_enemy(launched, Vector2.RIGHT * 450.0, 1)
	var feedback := _feedback()
	launched.get_launch_state().step(launched, 0.12)
	_check(launched.position.x > -10.0 and feedback.launches.size() == 1, "The real launched enemy carries its directional cue after moving")
	await _capture("ruinous_launch", "RUINOUS IMPACT / THE ENEMY BECOMES THE PROJECTILE", "An amber rim and short trailing streak show the launched enemy and its direction. Ordinary enemies remain readable nearby.")
	player.boss_combinations.cancel()
	EnemyReplicationService.clear_state()
	await _free_world()

func _collision_frame() -> void:
	await _prepare_world()
	var launched := _add_enemy(Vector2(-55.0, 0.0))
	var struck := _add_enemy(Vector2(40.0, 0.0))
	var safe := _add_enemy(Vector2(120.0, 95.0))
	await physics_frame
	player.boss_combinations.launch_enemy(launched, Vector2.RIGHT * 450.0, 1)
	var feedback := _feedback()
	launched.get_launch_state().step(launched, 0.20)
	_check(not launched.get_launch_state().active and struck.get_current_health() < 10000 and safe.get_current_health() == 10000, "A real enemy collision bursts once inside its visible radius")
	_check(feedback.launches.is_empty() and feedback.bursts.size() == 1, "The launch cue is replaced by one collision burst")
	feedback.bursts[0]["left"] = FEEDBACK.BURST_LIFETIME - 0.055
	feedback.queue_redraw()
	await _capture("ruinous_collision", "RUINOUS IMPACT / COLLISION", "The fractured bright ring expands to the stationary amber damage boundary. The enemy outside it is untouched.")
	EnemyReplicationService.clear_state()
	await _free_world()

func _compression_frames() -> void:
	await _prepare_world()
	var boss := RenderBoss.new()
	_add_shape(boss, 36.0)
	boss.position = Vector2(20.0, 0.0)
	world.add_child(boss)
	boss.target = player
	await physics_frame
	var origin := boss.global_position
	var health := boss.get_current_health()
	player.boss_combinations.launch_enemy(boss, Vector2.RIGHT * 450.0, 1)
	var feedback := _feedback()
	var cue: Dictionary = feedback.launches.values().front()
	cue["left"] = 0.09
	feedback.queue_redraw()
	_check(boss.get_launch_state().compression and boss.global_position == origin, "The boss is visibly compressed without interrupting movement or attacks")
	await _capture("ruinous_compression", "RUINOUS IMPACT / COMPRESSION", "Immovable enemies get inward-facing brackets during the existing short delay. No stun, displacement or extra screen flash.")
	boss.get_launch_state().step(boss, 0.16)
	_check(boss.global_position == origin and boss.get_current_health() < health and feedback.bursts.size() == 1, "The same boss receives exactly one stationary compression burst")
	feedback.bursts[0]["left"] = FEEDBACK.BURST_LIFETIME - 0.05
	feedback.queue_redraw()
	await _capture("ruinous_compression_burst", "RUINOUS IMPACT / PRESSURE RELEASE", "Compression releases the same bounded burst. The visual marks its real origin and reach while preserving the boss silhouette.")
	EnemyReplicationService.clear_state()
	await _free_world()
