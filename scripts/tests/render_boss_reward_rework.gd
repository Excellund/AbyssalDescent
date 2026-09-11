extends "res://scripts/tests/render_motion_arcana.gd"
## Native stationary reward effects beside a real, committed Charger warning.

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")
const CHARGER := preload("res://scripts/enemy_charger.gd")
const STATES := preload("res://scripts/shared/enemy_state_enums.gd")
var checks := 0

func _check(condition: bool, message: String) -> void:
	checks += 1
	super._check(condition, message)

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		push_error("Reward GPU fixture requires an isolated project and real renderer")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2(FRAME_SIZE) * .5 + Vector2(0, 25))
	output_directory = project_path.path_join("boss_reward_rework_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _edict_frames()
	await _well_frames()
	await _corridor_frames()
	await create_timer(.2).timeout
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var manifest := {"frames": frames, "failures": failures, "checks": checks, "gpu": RenderingServer.get_video_adapter_name(), "scope": "Real accepted reward producers, Charger warning geometry, status and phase cleanup; dedicated ENet covers transport."}
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("[RewardReworkGPU] %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _warning(position: Vector2) -> CHARGER:
	var enemy := CHARGER.new()
	enemy.max_health = 10000
	_add_shape(enemy, 13)
	enemy.position = position
	world.add_child(enemy)
	enemy.target = player
	enemy.spawn_transport_time_left = 0.0
	enemy.set_physics_process(false)
	enemy._enter_windup_state()
	enemy._process_windup_state(.25)
	enemy.queue_redraw()
	return enemy

func _assert_warning(enemy: CHARGER, origin: Vector2, direction: Vector2, length: float) -> void:
	_check(enemy.global_position == origin and enemy.velocity == Vector2.ZERO and not enemy.get_launch_state().active, "Reward preserves actual enemy position and does not launch it")
	_check(enemy.charger_state == STATES.ChargerState.WINDUP and enemy.charger_charge_direction == direction and enemy.charger_charge_preview_length == length, "Committed native Charger warning retains its original direction and geometry")
	enemy.queue_redraw()

func _edict_frames() -> void:
	await _make_world()
	player.player_id = 1
	player.apply_upgrade("edict_of_the_court")
	var victim := _add_enemy(player.global_position + Vector2(40, 0))
	victim.set_health(1)
	victim.spawn_transport_time_left = 0.0
	var enemy := _warning(victim.global_position + Vector2(60, 65))
	var origin := enemy.global_position
	var direction := enemy.charger_charge_direction
	var length := enemy.charger_charge_preview_length
	await physics_frame
	player._perform_melee_attack(Vector2.RIGHT, {"damage": player.damage, "range": player.attack_range, "arc_degrees": player.attack_arc_degrees})
	_check(enemy.get_current_health() < 10000 and enemy.is_slowed(), "Actual Attack Kill releases Edict damage and survivor Slow")
	_assert_warning(enemy, origin, direction, length)
	await _capture("edict_burst", "EDICT OF THE COURT / KILL BURST", "The accepted Kill releases one Burst. The nearby Charger is Slowed; its committed warning stays in place.")
	await create_timer(.35).timeout
	_assert_warning(enemy, origin, direction, length)
	await _capture("edict_survivor", "EDICT OF THE COURT / SURVIVOR", "After the Burst fades, Slow remains visible around the stationary foe. No Push changes the warning.")
	await _free_world()

func _well_frames() -> void:
	await _make_world()
	player.player_id = 1
	player.apply_upgrade("lacuna_echo")
	var enemy := _warning(Vector2(20, -30))
	var origin := enemy.global_position
	var direction := enemy.charger_charge_direction
	var length := enemy.charger_charge_preview_length
	player._apply_void_echo(origin)
	player._update_void_echo_zones(.01)
	_check(enemy.is_slowed() and enemy.get_current_health() < 10000, "Real Lacuna pulse damages then Slows a living Charger")
	_assert_warning(enemy, origin, direction, length)
	await _capture("lacuna_slow", "LACUNA WELL / SLOW FIELD", "A pulse Slows the foe in place. The Field and the Charger's committed lane remain distinct.")
	var before := enemy.get_current_health()
	await create_timer(.36).timeout
	player._apply_void_echo(Vector2(270, 100))
	player._update_void_echo_zones(.33)
	_check(player.void_echo_zones.size() == 1 and enemy.get_current_health() == before, "A new Well replaces the old damage area")
	_assert_warning(enemy, origin, direction, length)
	await _capture("lacuna_replaced", "LACUNA WELL / REPLACEMENT", "The new Well is away from the Charger. Its prior Slow can remain briefly while the old damage area has ended.")
	await _free_world()

func _corridor_frames() -> void:
	await _make_world()
	player.player_id = 1
	player.apply_upgrade("null_corridor")
	var enemy := _warning(Vector2(70, 0))
	var origin := enemy.global_position
	var direction := enemy.charger_charge_direction
	var length := enemy.charger_charge_preview_length
	player._null_corridor_dash_origin = Vector2(-30, 0)
	player._apply_null_corridor_segment(Vector2(-30, 0), Vector2(260, 0))
	player._update_null_corridor_segments(.01)
	_check(DAMAGEABLE.status_snapshot(enemy, 1).mark_ratio > 0 and enemy.get_current_health() < 10000, "Real Corridor tick damages then Marks its living target")
	_assert_warning(enemy, origin, direction, length)
	await _capture("corridor_mark", "NULL CORRIDOR / MARK FIELD", "The trail Marks its target after damage. No side Push displaces the Charger's attack warning.")
	var before := enemy.get_current_health()
	player.clear_lingering_combat_effects()
	player._update_null_corridor_segments(.6)
	_check(player.null_corridor_segments.is_empty() and DAMAGEABLE.status_snapshot(enemy, 1).mark_ratio == 0 and enemy.get_current_health() == before, "Room cleanup removes the trail, its Mark and delayed damage")
	_assert_warning(enemy, origin, direction, length)
	await create_timer(.35).timeout
	await _capture("corridor_cleared", "NULL CORRIDOR / ROOM CLEANUP", "The trail and owned Mark clear at the room boundary. The fixture holds the same warning for comparison.")
	await _free_world()
