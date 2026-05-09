extends Node2D

const ENEMY_CHASER_SCRIPT := preload("res://scripts/enemy_chaser.gd")
const ENEMY_CHARGER_SCRIPT := preload("res://scripts/enemy_charger.gd")
const ENEMY_ARCHER_SCRIPT := preload("res://scripts/enemy_archer.gd")
const ENEMY_SHIELDER_SCRIPT := preload("res://scripts/enemy_shielder.gd")
const ENEMY_SEAMLOCK_SCRIPT := preload("res://scripts/enemy_seamlock.gd")
const ENEMY_LURKER_SCRIPT := preload("res://scripts/enemy_lurker.gd")
const ENEMY_RAM_SCRIPT := preload("res://scripts/enemy_ram.gd")
const ENEMY_LANCER_SCRIPT := preload("res://scripts/enemy_lancer.gd")
const ENEMY_SPECTRE_SCRIPT := preload("res://scripts/enemy_spectre.gd")
const ENEMY_PYRE_SCRIPT := preload("res://scripts/enemy_pyre.gd")
const ENEMY_TETHER_SCRIPT := preload("res://scripts/enemy_tether.gd")
const PYRE_FIELD_SCRIPT := preload("res://scripts/pyre_field.gd")
const ENEMY_BOSS_SCRIPT := preload("res://scripts/enemy_boss.gd")
const ENEMY_BOSS_2_SCRIPT := preload("res://scripts/enemy_boss_2.gd")
const ENEMY_BOSS_3_SCRIPT := preload("res://scripts/enemy_boss_3.gd")
const POWER_REGISTRY := preload("res://scripts/power_registry.gd")
const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const MUSIC_SYSTEM_SCRIPT := preload("res://scripts/music_system.gd")
const DIFFICULTY_CONFIG_MULTIPLAYER := preload("res://scripts/encounter_difficulty_multiplayer_config.gd")
const ENEMY_SPAWNER_SCRIPT := preload("res://scripts/enemy_spawner.gd")
const ENCOUNTER_PROFILE_BUILDER_SCRIPT := preload("res://scripts/encounter_profile_builder.gd")
const ENCOUNTER_FLOW_SYSTEM_SCRIPT := preload("res://scripts/encounter_flow_system.gd")
const OBJECTIVE_RUNTIME_SCRIPT := preload("res://scripts/objective_runtime.gd")
const OBJECTIVE_MANAGER_SCRIPT := preload("res://scripts/objective_manager.gd")
const REWARD_SELECTION_UI_SCRIPT := preload("res://scripts/reward_selection_ui.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const ENDLESS_PROFILE_SCALER := preload("res://scripts/shared/endless_profile_scaler.gd")
const BEARING_KEY_NORMALIZER := preload("res://scripts/shared/bearing_key_normalizer.gd")
const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")
const AUDIO_LEVELS := preload("res://scripts/shared/audio_levels.gd")
const RUN_TELEMETRY_STORE := preload("res://scripts/run_telemetry_store.gd")
const TELEMETRY_SPIKE_SENDER_SCRIPT := preload("res://scripts/telemetry_spike_sender.gd")
const RUN_SNAPSHOT_SERVICE := preload("res://scripts/run_snapshot_service.gd")
const META_PROGRESS := preload("res://scripts/meta_progress_store.gd")
const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")
const DEBUG_ENUMS := preload("res://scripts/shared/debug_enums.gd")
const GLOSSARY_DATA := preload("res://scripts/shared/glossary_data.gd")
const DEBUG_SETTINGS_SCRIPT := preload("res://scripts/debug_settings.gd")
const VALIDATION_HARNESS_SCRIPT := preload("res://scripts/validation_harness.gd")
const RUN_SESSION_SCRIPT := preload("res://scripts/core/run_session.gd")
const RUN_SUMMARY_RECORDER_SCRIPT := preload("res://scripts/core/run_summary_recorder.gd")
const ENEMY_STATE_SYNC_BROADCASTER_SCRIPT := preload("res://scripts/core/enemy_state_sync_broadcaster.gd")
const PLAYER_PROFILE_SCRIPT := preload("res://scripts/core/player_profile.gd")
const PROFILE_PERSISTENCE_STORE_SCRIPT := preload("res://scripts/core/profile_persistence_store.gd")
const RUN_SUMMARY_WITH_PROFILE_SCRIPT := preload("res://scripts/core/run_summary_with_profile.gd")
const RUN_HISTORY_STORE_SCRIPT := preload("res://scripts/core/run_history_store.gd")
const WORLD_BOOTSTRAP_COORDINATOR_SCRIPT := preload("res://scripts/core/world_bootstrap_coordinator.gd")
const ENCOUNTER_ROUTE_CONTROLLER_SCRIPT := preload("res://scripts/core/encounter_route_controller.gd")
const OBJECTIVE_LIFECYCLE_COORDINATOR_SCRIPT := preload("res://scripts/core/objective_lifecycle_coordinator.gd")
const OBJECTIVE_FRAME_COORDINATOR_SCRIPT := preload("res://scripts/core/objective_frame_coordinator.gd")
const OBJECTIVE_PROGRESS_COORDINATOR_SCRIPT := preload("res://scripts/core/objective_progress_coordinator.gd")
const ROOM_CLEAR_OUTCOME_COORDINATOR_SCRIPT := preload("res://scripts/core/room_clear_outcome_coordinator.gd")
const COMBAT_PHASE_COORDINATOR_SCRIPT := preload("res://scripts/core/combat_phase_coordinator.gd")
const PLAYER_FLOW_COORDINATOR_SCRIPT := preload("res://scripts/core/player_flow_coordinator.gd")
const WORLD_MULTIPLAYER_SYNC_STATE_SCRIPT := preload("res://scripts/core/world_multiplayer_sync_state.gd")
const RUN_CONTEXT_PATH := "/root/RunContext"
const MENU_SCENE_PATH := "res://scenes/Menu.tscn"
const RUN_SNAPSHOT_VERSION := 1
const ENABLE_FULL_VALIDATION := false  # Set to true to run comprehensive validation harness on startup (debug only)
const BOSS_SPAWN_TRANSPORT_DURATION := 0.40
const INTRO_SURVEY_TRANSPORT_PULSE_DURATION := 0.24
const WORLD_HUD_SCRIPT := preload("res://scripts/world_hud.gd")
const WORLD_RENDERER_SCRIPT := preload("res://scripts/world_renderer.gd")
const PAUSE_MENU_CONTROLLER_SCRIPT := preload("res://scripts/pause_menu_controller.gd")
const VICTORY_SCREEN_SCRIPT := preload("res://scripts/victory_screen.gd")
const DEFEAT_SCREEN_SCRIPT := preload("res://scripts/defeat_screen.gd")
const BUILD_DETAIL_PANEL_SCRIPT := preload("res://scripts/build_detail_panel.gd")
const SEAMLOCK_SYNC_GROUP := "seamlock_sync_group"
const ARCHER_PROJECTILE_SYNC_PAYLOAD_BUDGET_BYTES_DEFAULT: int = 960
const ENEMY_REMOTE_SNAP_DISTANCE_PX_DEFAULT: float = 180.0
const STAT_ATTRIBUTION_TRACE := false

func _find_debug_encounter_entry(key: String) -> Dictionary:
	return ENCOUNTER_CONTRACTS.debug_encounter_entry(key)

func _get_debug_encounter_reward_mode(encounter_key: String) -> int:
	if encounter_key == "trial" or encounter_key == "apex_trial":
		return ENUMS.RewardMode.ARCANA
	if ENCOUNTER_CONTRACTS.debug_encounter_is_objective(encounter_key):
		return ENUMS.RewardMode.MISSION
	return ENUMS.RewardMode.BOON

@export var player_path: NodePath = NodePath("Player")
@export var encounter_count: int = 8
@export var room_base_size: Vector2 = Vector2(940.0, 700.0)
@export var room_size_growth: Vector2 = Vector2(80.0, 45.0)
@export var spawn_padding: float = 90.0
@export var spawn_safe_radius: float = 170.0
@export var static_camera_room_threshold: float = 980.0
@export var base_chaser_count: int = 5
@export var chasers_per_room: int = 2
@export var chargers_start_room: int = 2
@export var chargers_per_room: int = 1
@export var archer_start_room: int = 1
@export var archers_per_room: int = 1
@export var shielder_start_room: int = 2
@export var shielders_per_room: int = 1
@export var boss_chaser_count: int = 10
@export var boss_charger_count: int = 5
@export var door_distance_from_center: float = 290.0
@export var door_use_radius: float = 72.0
@export var camera_room_margin: Vector2 = Vector2(160.0, 120.0)
@export_range(0.85, 2.0, 0.01) var camera_base_zoom_in: float = 0.95
@export var boon_choice_count: int = 3
@export var camera_player_margin: float = 18.0
@export var boon_reveal_duration: float = 0.22
@export var floor_grid_step: float = 70.0
@export var floor_grid_fine_step: float = 35.0
@export var arena_glow_strength: float = 0.22
@export var ambient_backdrop_alpha: float = 0.96
@export var floor_coarse_grid_alpha: float = 0.075
@export var floor_fine_grid_alpha: float = 0.024
@export var floor_border_alpha: float = 0.72
@export var hud_background_alpha: float = 0.7
@export var normal_room_music: AudioStream
@export var boss_room_music: AudioStream
@export var music_volume_db: float = -20.0
@export var sfx_volume_db: float = 0.0
@export var music_intro_fade_duration: float = 1.6
@export var music_crossfade_duration: float = 0.75
@export var rest_heal_ratio: float = 0.32
@export var hard_room_enemy_bonus: int = 3
@export var second_boss_encounter_count: int = 7
@export var third_boss_encounter_count: int = 7
@export var multiplayer_camera_padding: Vector2 = Vector2(220.0, 180.0)
@export var multiplayer_camera_min_zoom: float = 0.58
@export var multiplayer_camera_max_zoom: float = 1.05
@export var multiplayer_use_shared_camera: bool = false
@export var multiplayer_force_static_arena_camera: bool = true
var settings_enabled: bool = false
var apply_test_powers_on_start: bool = false
var skip_starting_boon_selection: bool = false
var start_power_preset: int = DEBUG_ENUMS.PowerPreset.NONE
var start_power_ids: PackedStringArray = PackedStringArray()
var start_encounter: int = ENCOUNTER_CONTRACTS.DEBUG_ENCOUNTER_NONE
var start_depth: int = 1
var start_bearing: int = -1
var mutator_override: int = DEBUG_ENUMS.MutatorOverride.NONE
var end_screen_preview: int = DEBUG_ENUMS.EndScreenPreview.NONE
var victory_unlock_tier: int = -1

var player: Node2D
var player_camera: Camera2D
var rng := RandomNumberGenerator.new()
var power_registry_instance: Node
var current_difficulty_tier: int = 0
var current_difficulty_config: Dictionary = {}
var _multiplayer_difficulty_config = DIFFICULTY_CONFIG_MULTIPLAYER.new()
var current_character_id: String = "bastion"

var rooms_cleared: int = 0
var room_depth: int = 0
var active_room_enemy_count: int = 0
var boss_unlocked: bool = false
var in_boss_room: bool = false
var in_second_boss_room: bool = false
var in_third_boss_room: bool = false
var first_boss_defeated: bool = false
var second_boss_defeated: bool = false
var phase_two_rooms_cleared: int = 0
var phase_three_rooms_cleared: int = 0
var endless_boss_defeated: bool = false
var choosing_next_room: bool = false
var run_cleared: bool = false
var boss_reward_pending: bool = false
var last_defeated_boss_id: String = ""

var current_room_size: Vector2 = Vector2.ZERO
var current_effective_room_size: Vector2 = Vector2.ZERO
var _last_applied_camera_room_size: Vector2 = Vector2.ZERO
var current_room_static_camera: bool = true
var current_room_label: String = ""
var door_options: Array[Dictionary] = []
var pending_room_reward: int = ENUMS.RewardMode.NONE
var current_room_enemy_mutator: Dictionary = {}
var current_room_player_mutator: Dictionary = {}

var encounter_intro_grace_active: bool = false
var _encounter_ready_peers: Dictionary = {}  # Dictionary[int, bool] - host only
var _local_player_ready: bool = false

var hud: Node
var renderer: Node2D
var music_system: Node
var enemy_spawner: Node
var encounter_profile_builder
var encounter_flow_system
var objective_runtime: Node
var objective_manager: Node
var reward_selection_ui
var pause_menu_controller: Node
var victory_screen: Node
var defeat_screen: Node
var build_detail_panel: Node
var run_summary_recorder
var player_defeated: bool = false
var telemetry_spike_enabled: bool = false
var telemetry_spike_endpoint: String = ""
var telemetry_spike_api_key: String = ""
var telemetry_spike_timeout_seconds: float = 8.0
var telemetry_spike_sender
var telemetry_spike_requested: bool = false
var run_session
var profile_persistence_store: RefCounted = null
var current_player_profile: RefCounted = null
var bootstrap_coordinator
var encounter_route_controller
var objective_lifecycle_coordinator
var objective_frame_coordinator
var objective_progress_coordinator
var room_clear_outcome_coordinator
var combat_phase_coordinator
var player_flow_coordinator

## Multiplayer state
var is_multiplayer: bool = false
var multiplayer_session_id: String = ""
var multiplayer_encounter_seed: int = 0
var game_state_replication_service: Node = null
var enemy_state_sync_broadcaster
var archer_projectile_sync_interval_sec: float = 0.016
var _archer_projectile_sync_elapsed: float = 0.0
var archer_projectile_sync_payload_budget_bytes: int = ARCHER_PROJECTILE_SYNC_PAYLOAD_BUDGET_BYTES_DEFAULT
var objective_state_sync_interval_sec: float = 0.05
var _objective_state_sync_elapsed: float = 0.0
var _objective_state_sync_sequence: int = 0
var _last_applied_objective_state_sync_sequence: int = -1
var _objective_state_sync_was_active: bool = false
var multiplayer_perf_logging_enabled: bool = false
var multiplayer_perf_log_interval_sec: float = 2.0
var _multiplayer_perf_log_elapsed: float = 0.0
var _multiplayer_client_perf_report_interval_sec: float = 0.5
var _multiplayer_client_perf_report_elapsed: float = 0.0
var _multiplayer_latest_client_perf_by_peer: Dictionary = {}
var _multiplayer_last_feedback_event_count: int = 0
var _multiplayer_last_feedback_estimated_bytes: int = 0
## Cache TTL must stay tight so a boss entering WINDUP escalates the network sync
## rate within a few frames; otherwise joiners see telegraphs appear up to TTL ms
## after the host, shrinking their dodge window.
var _perf_attribution_enabled: bool = false
var _perf_attribution_sample_ms: float = 1000.0
var _perf_attribution_elapsed: float = 0.0
var _perf_attr_frame_count: int = 0
var _perf_attr_total_pre_ms: float = 0.0
var _perf_attr_total_sim_ms: float = 0.0
var _perf_attr_total_post_ms: float = 0.0
var _perf_attr_total_frame_ms: float = 0.0
var _perf_attr_total_ui_ms: float = 0.0
var _perf_attr_total_enemy_drawn: int = 0
var _perf_attr_last_sample: Dictionary = {}
var _perf_attr_live_snapshot: Dictionary = {}
var _enemy_clamp_cached_nodes: Array[Node2D] = []
var _enemy_clamp_refresh_elapsed: float = 0.0
var _enemy_clamp_refresh_interval_sec: float = 0.25
var _enemy_clamp_frame_stride: int = 2
var _enemy_clamp_frame_cursor: int = 0
var _enemy_clamp_last_room_size: Vector2 = Vector2.ZERO
var enemy_remote_position_lerp_speed: float = 14.0
var enemy_remote_rotation_lerp_speed: float = 18.0
var enemy_remote_snap_distance_px: float = ENEMY_REMOTE_SNAP_DISTANCE_PX_DEFAULT
var _reward_phase_active: bool = false
var _reward_phase_is_initial: bool = false
var _reward_phase_mode: int = ENUMS.RewardMode.NONE
var _reward_phase_completed_peers: Dictionary = {}  ## peer_id -> bool
var _doors_spawn_ready: bool = false
var _world_multiplayer_sync_state = WORLD_MULTIPLAYER_SYNC_STATE_SCRIPT.new()
var _depth_sanity_last_logged_depth: int = -1
var _depth_sanity_last_log_usec: int = 0

## ============================================================================
## STRESS TEST METRICS (debug only)
## ============================================================================
var _stress_test_active: bool = false
var _stress_test_coordinator: RefCounted = null

var second_player: Node2D = null
var _known_fallen_player_ids: Dictionary = {}

func _get_player_network_id(player_node: Node2D) -> int:
	if not is_instance_valid(player_node):
		return -1
	if player_node.has_method("get"):
		return int(player_node.get("player_id"))
	return -1

func _refresh_fallen_player_tracking() -> bool:
	var currently_fallen_ids: Dictionary = {}
	var has_new_fallen := false
	for player_node in _get_multiplayer_player_nodes():
		if not is_instance_valid(player_node):
			continue
		if not player_node.has_method("is_dead"):
			continue
		if not bool(player_node.call("is_dead")):
			continue
		var player_id := _get_player_network_id(player_node)
		if player_id <= 0:
			continue
		currently_fallen_ids[player_id] = true
		if not bool(_known_fallen_player_ids.get(player_id, false)):
			has_new_fallen = true
	_known_fallen_player_ids = currently_fallen_ids
	return has_new_fallen

func _apply_debug_settings_from_node() -> void:
	var debug_settings := get_node_or_null("DebugSettings")
	if not (is_instance_valid(debug_settings) and debug_settings.get_script() == DEBUG_SETTINGS_SCRIPT):
		return
	settings_enabled = bool(debug_settings.get("enabled"))
	apply_test_powers_on_start = bool(debug_settings.get("apply_test_powers_on_start"))
	skip_starting_boon_selection = bool(debug_settings.get("skip_starting_boon_selection"))
	start_power_preset = int(debug_settings.get("start_power_preset"))
	var start_power_ids_value: Variant = debug_settings.get("start_power_ids")
	if start_power_ids_value is PackedStringArray:
		start_power_ids = start_power_ids_value
	else:
		start_power_ids = PackedStringArray()
	start_encounter = int(debug_settings.get("start_encounter"))
	start_depth = int(debug_settings.get("start_depth"))
	start_bearing = int(debug_settings.get("start_bearing"))
	mutator_override = int(debug_settings.get("mutator_override"))
	end_screen_preview = int(debug_settings.get("end_screen_preview"))
	victory_unlock_tier = int(debug_settings.get("victory_unlock_tier"))
	telemetry_spike_enabled = bool(debug_settings.get("telemetry_spike_enabled"))
	var telemetry_endpoint_value: Variant = debug_settings.get("telemetry_spike_endpoint")
	var telemetry_api_key_value: Variant = debug_settings.get("telemetry_spike_api_key")
	var telemetry_timeout_value: Variant = debug_settings.get("telemetry_spike_timeout_seconds")
	telemetry_spike_endpoint = String(telemetry_endpoint_value) if telemetry_endpoint_value != null else ""
	telemetry_spike_api_key = String(telemetry_api_key_value) if telemetry_api_key_value != null else ""
	telemetry_spike_timeout_seconds = float(telemetry_timeout_value) if telemetry_timeout_value != null else 8.0
	multiplayer_perf_logging_enabled = bool(debug_settings.get("multiplayer_perf_logging_enabled"))
	_perf_attribution_enabled = bool(debug_settings.get("perf_attribution_enabled"))
	if enemy_state_sync_broadcaster != null:
		enemy_state_sync_broadcaster.perf_attribution_enabled = _perf_attribution_enabled
	var perf_attr_interval_value: Variant = debug_settings.get("perf_attribution_sample_ms")
	if perf_attr_interval_value != null:
		_perf_attribution_sample_ms = maxf(250.0, float(perf_attr_interval_value))
	else:
		_perf_attribution_sample_ms = 1000.0

func _ready() -> void:
	bootstrap_coordinator = WORLD_BOOTSTRAP_COORDINATOR_SCRIPT.new()
	var bootstrap_stages: Array[Callable] = [
		Callable(self, "_validate_encounter_content_sync"),
		Callable(self, "_initialize_bootstrap_context"),
		Callable(self, "_setup_world_bootstrap_state"),
		Callable(self, "_setup_run_systems_phase"),
		Callable(self, "_setup_ui_phase"),
		Callable(self, "_setup_objective_runtime_system")
	]
	bootstrap_coordinator.run_bootstrap(bootstrap_stages)
	EnemyReplicationService.bind_world(self)
	var boot_flows: Array[Callable] = [
		Callable(self, "_run_resume_flow"),
		Callable(self, "_run_debug_boot_flow")
	]
	if bootstrap_coordinator.run_first_success(boot_flows):
		return
	_begin_new_run_flow()

func _exit_tree() -> void:
	EnemyReplicationService.unbind_world(self)

func _validate_encounter_content_sync() -> void:
	var encounter_sync_issues := ENCOUNTER_CONTRACTS.validate_encounter_sync(GLOSSARY_DATA._encounter_rows())
	for issue in encounter_sync_issues:
		push_error("[Encounter Sync] %s" % issue)
	
	# Run comprehensive validation harness if enabled (debug mode only)
	if ENABLE_FULL_VALIDATION:
		var harness := VALIDATION_HARNESS_SCRIPT.new()
		harness.run_full_validation()

func _initialize_bootstrap_context() -> void:
	rng.randomize()
	_apply_debug_settings_from_node()
	_maybe_start_telemetry_spike_probe()
	run_session = RUN_SESSION_SCRIPT.new()
	run_session.reset_for_new_run()
	run_summary_recorder = RUN_SUMMARY_RECORDER_SCRIPT.new(self)
	enemy_state_sync_broadcaster = ENEMY_STATE_SYNC_BROADCASTER_SCRIPT.new(self)
	enemy_state_sync_broadcaster.perf_attribution_enabled = _perf_attribution_enabled
	profile_persistence_store = PROFILE_PERSISTENCE_STORE_SCRIPT.new()
	current_player_profile = profile_persistence_store.load_or_create_profile()
	
	## Detect multiplayer session
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null:
		multiplayer_session_id = run_context.get_multiplayer_session_id()
		is_multiplayer = not multiplayer_session_id.is_empty()
		if is_multiplayer:
			print_debug("[WorldGenerator] Detected multiplayer session: %s" % multiplayer_session_id)
	
	objective_lifecycle_coordinator = OBJECTIVE_LIFECYCLE_COORDINATOR_SCRIPT.new()
	objective_frame_coordinator = OBJECTIVE_FRAME_COORDINATOR_SCRIPT.new()
	objective_progress_coordinator = OBJECTIVE_PROGRESS_COORDINATOR_SCRIPT.new()
	room_clear_outcome_coordinator = ROOM_CLEAR_OUTCOME_COORDINATOR_SCRIPT.new()
	combat_phase_coordinator = COMBAT_PHASE_COORDINATOR_SCRIPT.new()
	player_flow_coordinator = PLAYER_FLOW_COORDINATOR_SCRIPT.new()
	power_registry_instance = POWER_REGISTRY.new()
	player = get_node_or_null(player_path) as Node2D
	_setup_player_runtime_bindings()
	_sync_audio_settings_from_context()
	endless_boss_defeated = false

	if is_multiplayer:
		_setup_multiplayer_second_player()

func _setup_player_runtime_bindings() -> void:
	if is_instance_valid(player):
		player.set_power_registry(power_registry_instance)
	if is_instance_valid(player):
		player_camera = player.get_node_or_null("Camera2D") as Camera2D
		if is_instance_valid(player_camera):
			player_camera.set_room_fit_zoom_scale(camera_base_zoom_in)
		if player.has_signal("damage_taken"):
			player.connect("damage_taken", Callable(self, "_on_player_damage_taken"))
		if player.has_signal("health_changed"):
			player.connect("health_changed", Callable(self, "_on_player_health_changed_for_summary").bind(player))
		if player.has_signal("died"):
			player.connect("died", Callable(self, "_on_player_died_for_telemetry"))
			player.connect("died", Callable(self, "_on_player_died"))

		player_camera.set_room_fit_zoom_scale(camera_base_zoom_in)
	_bind_camera_to_local_player()

func _setup_multiplayer_second_player() -> void:
	"""Create second player node for multiplayer co-op."""
	var multiplayer_session_manager := get_node_or_null("/root/MultiplayerSessionManager")
	var player_replication_service := get_node_or_null("/root/PlayerReplicationService")
	var run_context := _get_run_context()
	if multiplayer_session_manager == null:
		push_error("[Multiplayer] MultiplayerSessionManager autoload is missing")
		return
	if player_replication_service == null:
		push_error("[Multiplayer] PlayerReplicationService autoload is missing")
		return
	
	# Joiner flag: expect initial sync from host before applying normal sanitizer logic.
	if not multiplayer_session_manager.is_host():
		_world_multiplayer_sync_state.joiner_awaiting_initial_sync = true
	
	## Set multiplayer identification
	var peer_ids: Array = multiplayer_session_manager.get_peer_ids()
	var local_peer: int = multiplayer_session_manager.local_peer_id
	var active_multiplayer := get_tree().get_multiplayer()
	if active_multiplayer != null:
		var active_peer_id := int(active_multiplayer.get_unique_id())
		if active_peer_id > 0:
			local_peer = active_peer_id
			if multiplayer_session_manager.local_peer_id != active_peer_id:
				print_debug("[Multiplayer] Correcting local peer id from %d to %d" % [multiplayer_session_manager.local_peer_id, active_peer_id])
				multiplayer_session_manager.local_peer_id = active_peer_id
	var remote_peer: int = 0
	for peer_id in peer_ids:
		if peer_id != local_peer:
			remote_peer = peer_id
			break
	
	if local_peer > 0:
		player.player_id = local_peer
		player.is_local_player = true
		player_replication_service.register_player(player.player_id, player)
	
	if remote_peer <= 0:
		second_player = null
		print_debug("[Multiplayer] No remote peer present; skipping remote avatar setup")
		return
	
	const PLAYER_SCENE := "res://scenes/Player.tscn"
	var player_scene = load(PLAYER_SCENE)
	if player_scene == null:
		push_error("[Multiplayer] Failed to load Player scene")
		return
	
	second_player = player_scene.instantiate()
	if second_player == null:
		push_error("[Multiplayer] Failed to instantiate Player scene")
		return
	
	## Position second player offset from first player
	second_player.position = player.position + Vector2(80.0, 0.0)
	second_player.player_id = remote_peer
	second_player.is_local_player = remote_peer == local_peer
	if run_context != null and second_player.has_method("apply_character_package"):
		var remote_character_id := String(run_context.get_peer_character_selection(remote_peer)).strip_edges().to_lower()
		var remote_character_data: Dictionary = CHARACTER_REGISTRY.get_character(remote_character_id)
		if not remote_character_data.is_empty():
			second_player.apply_character_package(remote_character_data)
	
	add_child(second_player)
	_disable_player_collision_pair(player, second_player)
	player_replication_service.register_player(second_player.player_id, second_player)
	if second_player.has_signal("died"):
		second_player.connect("died", Callable(self, "_on_player_died"))
	if second_player.has_signal("health_changed"):
		second_player.connect("health_changed", Callable(self, "_on_player_health_changed_for_summary").bind(second_player))
	if is_instance_valid(player_camera):
		var zoom_scale := camera_base_zoom_in * 0.65 if multiplayer_use_shared_camera else camera_base_zoom_in
		player_camera.set_room_fit_zoom_scale(zoom_scale)
	_bind_camera_to_local_player()
	
	print_debug("[Multiplayer] Second player created (peer %d)" % remote_peer)


func _disable_player_collision_pair(primary_player: Node, secondary_player: Node) -> void:
	if not (primary_player is PhysicsBody2D):
		return
	if not (secondary_player is PhysicsBody2D):
		return
	var primary_body := primary_player as PhysicsBody2D
	var secondary_body := secondary_player as PhysicsBody2D
	if primary_body == null or secondary_body == null:
		return
	primary_body.add_collision_exception_with(secondary_body)
	secondary_body.add_collision_exception_with(primary_body)


func _bind_camera_to_local_player() -> void:
	var local_player_node := _find_local_player_node()
	var primary_camera := player.get_node_or_null("Camera2D") as Camera2D if is_instance_valid(player) else null
	var secondary_camera := second_player.get_node_or_null("Camera2D") as Camera2D if is_instance_valid(second_player) else null
	var local_camera := local_player_node.get_node_or_null("Camera2D") as Camera2D if is_instance_valid(local_player_node) else null

	if is_instance_valid(primary_camera):
		primary_camera.enabled = false
	if is_instance_valid(secondary_camera):
		secondary_camera.enabled = false

	if not is_instance_valid(local_camera):
		player_camera = primary_camera
		return

	local_camera.enabled = true
	local_camera.make_current()
	player_camera = local_camera


func _find_local_player_node() -> Node2D:
	if is_instance_valid(player) and _is_local_control_owner(player) and _is_player_alive(player):
		return player
	if is_instance_valid(second_player) and _is_local_control_owner(second_player) and _is_player_alive(second_player):
		return second_player
	if is_instance_valid(player) and _is_player_alive(player):
		return player
	if is_instance_valid(second_player) and _is_player_alive(second_player):
		return second_player
	if is_instance_valid(player) and _is_local_control_owner(player):
		return player
	if is_instance_valid(second_player) and _is_local_control_owner(second_player):
		return second_player
	if is_instance_valid(player):
		return player
	if is_instance_valid(second_player):
		return second_player
	return null


func _find_local_owned_player_node() -> Node2D:
	if is_instance_valid(player) and _is_local_control_owner(player):
		return player
	if is_instance_valid(second_player) and _is_local_control_owner(second_player):
		return second_player
	return _find_local_player_node()


func _is_player_alive(player_node: Node) -> bool:
	if player_node == null:
		return false
	if not player_node.has_method("is_dead"):
		return true
	return not bool(player_node.call("is_dead"))


func _is_local_control_owner(player_node: Node) -> bool:
	if player_node == null:
		return false
	if player_node.has_method("_is_local_control_owner"):
		return bool(player_node.call("_is_local_control_owner"))
	if player_node.has_method("is_multiplayer_authority"):
		return bool(player_node.call("is_multiplayer_authority"))
	return true


func _resolve_local_peer_id() -> int:
	var active_multiplayer := get_tree().get_multiplayer()
	if active_multiplayer != null:
		var active_peer_id := int(active_multiplayer.get_unique_id())
		if active_peer_id > 0:
			return active_peer_id
	var multiplayer_session_manager := get_node_or_null("/root/MultiplayerSessionManager")
	if multiplayer_session_manager != null:
		return int(multiplayer_session_manager.local_peer_id)
	if is_instance_valid(player) and player.has_method("get"):
		return int(player.get("player_id"))
	return 0


func _resolve_local_character_id(run_context: Node, fallback_character_id: String) -> String:
	if run_context == null:
		return fallback_character_id
	var resolved_character_id := fallback_character_id
	var selected_character_id := String(run_context.get_selected_character_id()).strip_edges().to_lower()
	if not selected_character_id.is_empty():
		resolved_character_id = selected_character_id
	var local_peer_id := _resolve_local_peer_id()
	if local_peer_id > 0:
		var peer_character_id := String(run_context.get_peer_character_selection(local_peer_id)).strip_edges().to_lower()
		if not peer_character_id.is_empty() and peer_character_id == selected_character_id:
			resolved_character_id = peer_character_id
	if resolved_character_id.is_empty():
		resolved_character_id = fallback_character_id
	return resolved_character_id


func _apply_multiplayer_character_packages(run_context: Node) -> void:
	if run_context == null:
		return
	if is_instance_valid(player) and player.has_method("apply_character_package"):
		var local_selected_id := String(run_context.get_selected_character_id()).strip_edges().to_lower()
		if local_selected_id.is_empty():
			local_selected_id = current_character_id
		var local_data: Dictionary = CHARACTER_REGISTRY.get_character(local_selected_id)
		if not local_data.is_empty():
			player.apply_character_package(local_data)
			current_character_id = local_selected_id
	if is_instance_valid(second_player) and second_player.has_method("apply_character_package"):
		var remote_peer_id := int(second_player.get("player_id"))
		var remote_character_id := String(run_context.get_peer_character_selection(remote_peer_id)).strip_edges().to_lower()
		if remote_character_id.is_empty() or remote_character_id == current_character_id:
			var fallback_remote_id := ""
			for peer_key in run_context.multiplayer_peer_characters.keys():
				var candidate_id := String(run_context.multiplayer_peer_characters.get(peer_key, "")).strip_edges().to_lower()
				if not candidate_id.is_empty() and candidate_id != current_character_id:
					fallback_remote_id = candidate_id
					break
			remote_character_id = fallback_remote_id
		if not remote_character_id.is_empty():
			var remote_data: Dictionary = CHARACTER_REGISTRY.get_character(remote_character_id)
			if not remote_data.is_empty():
				second_player.apply_character_package(remote_data)


func _log_multiplayer_player_stats(stage: String) -> void:
	if not is_multiplayer:
		return
	for player_node in [player, second_player]:
		if not is_instance_valid(player_node):
			continue
		var node_name := String(player_node.name)
		var peer_id := int(player_node.get("player_id")) if player_node.has_method("get") else 0
		var is_local_owner := _is_local_control_owner(player_node)
		var character_id := String(player_node.get("active_character_id")) if player_node.has_method("get") else ""
		var attack_range_value := float(player_node.get("attack_range")) if player_node.has_method("get") else 0.0
		var attack_arc_value := float(player_node.get("attack_arc_degrees")) if player_node.has_method("get") else 0.0
		print_debug("[Multiplayer][%s] %s peer=%d local_owner=%s character=%s range=%.1f arc=%.1f" % [stage, node_name, peer_id, str(is_local_owner), character_id, attack_range_value, attack_arc_value])

func _setup_world_bootstrap_state() -> void:
	current_room_size = room_base_size
	_reset_effective_room_bounds()
	current_room_label = "Starting Chamber"
	_apply_camera_bounds_for_room(current_effective_room_size)

func _setup_run_systems_phase() -> void:
	music_system = MUSIC_SYSTEM_SCRIPT.new()
	add_child(music_system)
	music_system.initialize(normal_room_music, boss_room_music, music_volume_db, music_crossfade_duration)
	encounter_flow_system = ENCOUNTER_FLOW_SYSTEM_SCRIPT.new()
	add_child(encounter_flow_system)
	encounter_route_controller = ENCOUNTER_ROUTE_CONTROLLER_SCRIPT.new()
	encounter_route_controller.set_encounter_flow_system(encounter_flow_system)
	_setup_reward_selection_system()
	_setup_encounter_profile_builder_system()
	_setup_enemy_spawner_system()
	_play_room_music(false, false, music_intro_fade_duration)
	
	if is_multiplayer:
		game_state_replication_service = get_node_or_null("/root/GameStateReplicationService")
		if game_state_replication_service != null:
			game_state_replication_service.initialize(self)
			print_debug("[WorldGenerator] Initialized GameStateReplicationService for multiplayer")
		else:
			push_error("[WorldGenerator] GameStateReplicationService autoload is missing")

func _setup_reward_selection_system() -> void:
	reward_selection_ui = REWARD_SELECTION_UI_SCRIPT.new()
	add_child(reward_selection_ui)
	reward_selection_ui.initialize(boon_choice_count, boon_reveal_duration)
	if reward_selection_ui.has_signal("reward_selected"):
		reward_selection_ui.connect("reward_selected", Callable(self, "_on_reward_selected"))
	if reward_selection_ui.has_signal("reward_offers_presented"):
		reward_selection_ui.connect("reward_offers_presented", Callable(self, "_on_reward_offers_presented"))

func _setup_encounter_profile_builder_system() -> void:
	encounter_profile_builder = ENCOUNTER_PROFILE_BUILDER_SCRIPT.new()
	add_child(encounter_profile_builder)
	encounter_profile_builder.initialize(rng)
	if encounter_profile_builder.has_method("set_use_multiplayer_difficulty_config"):
		encounter_profile_builder.call("set_use_multiplayer_difficulty_config", is_multiplayer)
	if encounter_profile_builder.has_method("set_multiplayer_party_size"):
		encounter_profile_builder.call("set_multiplayer_party_size", _get_multiplayer_party_size_for_scaling())
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	var should_apply_difficulty := false
	var difficulty_tier := current_difficulty_tier
	if run_context != null:
		difficulty_tier = int(run_context.get_current_difficulty_tier())
		var fallback_character_id := String(run_context.get_selected_character_id()).strip_edges().to_lower()
		if is_multiplayer:
			current_character_id = _resolve_local_character_id(run_context, fallback_character_id)
		else:
			current_character_id = fallback_character_id
		should_apply_difficulty = true
	var debug_bearing_tier := _debug_bearing_override_tier()
	if debug_bearing_tier >= 0:
		difficulty_tier = debug_bearing_tier
		should_apply_difficulty = true
	if is_instance_valid(player) and player.has_method("apply_character_package"):
		var char_data: Dictionary = CHARACTER_REGISTRY.get_character(current_character_id)
		player.apply_character_package(char_data)
	if is_multiplayer:
		_apply_multiplayer_character_packages(run_context)
		_log_multiplayer_player_stats("post_character_apply")
	if should_apply_difficulty:
		encounter_profile_builder.set_difficulty_tier(difficulty_tier)
		_apply_difficulty_tier_bonuses(difficulty_tier)
	encounter_profile_builder.configure({
		"room_base_size": room_base_size,
		"room_size_growth": room_size_growth,
		"static_camera_room_threshold": static_camera_room_threshold,
		"base_chaser_count": base_chaser_count,
		"chasers_per_room": chasers_per_room,
		"chargers_start_room": chargers_start_room,
		"chargers_per_room": chargers_per_room,
		"archer_start_room": archer_start_room,
		"archers_per_room": archers_per_room,
		"shielder_start_room": shielder_start_room,
		"shielders_per_room": shielders_per_room,
		"hard_room_enemy_bonus": hard_room_enemy_bonus
	})

func _setup_enemy_spawner_system() -> void:
	enemy_spawner = ENEMY_SPAWNER_SCRIPT.new()
	add_child(enemy_spawner)
	enemy_spawner.initialize(self, player, rng, {
		"chaser": ENEMY_CHASER_SCRIPT,
		"charger": ENEMY_CHARGER_SCRIPT,
		"archer": ENEMY_ARCHER_SCRIPT,
		"shielder": ENEMY_SHIELDER_SCRIPT,
		"seamlock": ENEMY_SEAMLOCK_SCRIPT,
		"lurker": ENEMY_LURKER_SCRIPT,
		"ram": ENEMY_RAM_SCRIPT,
		"lancer": ENEMY_LANCER_SCRIPT,
		"spectre": ENEMY_SPECTRE_SCRIPT,
		"pyre": ENEMY_PYRE_SCRIPT,
		"tether": ENEMY_TETHER_SCRIPT
	}, Callable(self, "_on_room_enemy_died"), Callable(self, "_get_multiplayer_player_nodes"))

func _setup_ui_phase() -> void:
	hud = WORLD_HUD_SCRIPT.new()
	add_child(hud)
	hud.setup(encounter_count, 18.0)
	renderer = WORLD_RENDERER_SCRIPT.new()
	add_child(renderer)
	renderer.configure({
		"ambient_backdrop_alpha": ambient_backdrop_alpha,
		"arena_glow_strength": arena_glow_strength,
		"floor_coarse_grid_alpha": floor_coarse_grid_alpha,
		"floor_fine_grid_alpha": floor_fine_grid_alpha,
		"floor_border_alpha": floor_border_alpha,
		"floor_grid_step": floor_grid_step,
		"floor_grid_fine_step": floor_grid_fine_step,
		"door_use_radius": door_use_radius,
	})
	pause_menu_controller = PAUSE_MENU_CONTROLLER_SCRIPT.new()
	add_child(pause_menu_controller)
	pause_menu_controller.initialize(RUN_CONTEXT_PATH, Callable(self, "_set_music_volume_runtime"), Callable(self, "_set_sfx_volume_runtime"))
	pause_menu_controller.connect("pause_opened", Callable(self, "_on_pause_menu_opened"))
	pause_menu_controller.connect("pause_closed", Callable(self, "_on_pause_menu_closed"))
	pause_menu_controller.connect("back_to_main_menu_requested", Callable(self, "_on_pause_back_to_menu_requested"))
	pause_menu_controller.connect("abandon_run_requested", Callable(self, "_on_pause_abandon_run_requested"))
	pause_menu_controller.connect("exit_game_requested", Callable(self, "_on_pause_exit_game_requested"))
	victory_screen = VICTORY_SCREEN_SCRIPT.new()
	add_child(victory_screen)
	victory_screen.connect("back_to_main_menu_requested", Callable(self, "_on_victory_back_to_menu"))
	victory_screen.connect("retry_run_requested", Callable(self, "_on_victory_retry_run"))
	defeat_screen = DEFEAT_SCREEN_SCRIPT.new()
	add_child(defeat_screen)
	defeat_screen.connect("back_to_main_menu_requested", Callable(self, "_on_defeat_back_to_menu"))
	defeat_screen.connect("retry_run_requested", Callable(self, "_on_defeat_retry_run"))
	build_detail_panel = BUILD_DETAIL_PANEL_SCRIPT.new()
	add_child(build_detail_panel)
	build_detail_panel.setup()
	build_detail_panel.connect("build_detail_opened", Callable(self, "_on_build_detail_opened"))
	build_detail_panel.connect("build_detail_closed", Callable(self, "_on_build_detail_closed"))

func _setup_objective_runtime_system() -> void:
	objective_manager = OBJECTIVE_MANAGER_SCRIPT.new()
	add_child(objective_manager)
	objective_runtime = OBJECTIVE_RUNTIME_SCRIPT.new()
	add_child(objective_runtime)
	objective_runtime.initialize(self, rng, objective_manager)

func _run_resume_flow() -> bool:
	var resumed_run := _try_resume_saved_run()
	run_summary_recorder.run_started_at_msec = Time.get_ticks_msec()
	run_summary_recorder.reset_summary_tracker()
	run_summary_recorder.initialize(not _is_debug_boot_session())
	hud.refresh(_get_hud_state(), player)
	return resumed_run

func _run_debug_boot_flow() -> bool:
	_apply_debug_start_powers_if_needed()
	if settings_enabled:
		match end_screen_preview:
			DEBUG_ENUMS.EndScreenPreview.VICTORY:
				victory_screen.show_victory(0, victory_unlock_tier, {}, not is_multiplayer)
				return true
			DEBUG_ENUMS.EndScreenPreview.DEFEAT:
				defeat_screen.show_defeat("Debug Arena", max(1, start_depth), {}, not is_multiplayer)
				return true
		if start_encounter != ENCOUNTER_CONTRACTS.DEBUG_ENCOUNTER_NONE:
			_start_debug_selected_encounter(start_encounter)
			return true
		# Stress test gets its own clean arena - bypass normal encounter flow
		var debug_settings := get_node_or_null("DebugSettings")
		if debug_settings != null and bool(debug_settings.get("stress_test_enabled")):
			_start_stress_test_arena()
			return true
	return false

func _start_stress_test_arena() -> void:
	run_summary_recorder.mark_debug_mode()
	_reset_for_debug_jump()
	current_room_size = Vector2(1200.0, 900.0)
	_reset_effective_room_bounds()
	current_room_label = "Stress Test Arena"
	current_room_static_camera = true
	active_room_enemy_count = 0
	_apply_camera_bounds_for_room(current_effective_room_size)
	if is_instance_valid(enemy_spawner):
		enemy_spawner.configure_room(current_room_size, spawn_padding, spawn_safe_radius, {}, [] as Array[Dictionary])
	if is_instance_valid(player_camera):
		player_camera.position = Vector2.ZERO
	hud.show_banner("Stress Test Arena", "")
	run_summary_recorder.initialize(false)
	hud.refresh(_get_hud_state(), player)
	print_debug("[StressTest] Clean arena ready - scheduling stress test start")
	call_deferred("_maybe_start_stress_test")

func _begin_new_run_flow() -> void:
	_world_multiplayer_sync_state.reset_for_new_run()
	run_summary_recorder.mark_run_start()
	rooms_cleared = 0
	room_depth = 0
	boss_unlocked = false
	in_boss_room = false
	in_second_boss_room = false
	in_third_boss_room = false
	first_boss_defeated = false
	second_boss_defeated = false
	phase_two_rooms_cleared = 0
	phase_three_rooms_cleared = 0
	endless_boss_defeated = false
	run_cleared = false
	boss_reward_pending = false
	last_defeated_boss_id = ""
	pending_room_reward = ENUMS.RewardMode.NONE
	current_room_enemy_mutator.clear()
	current_room_player_mutator.clear()
	_world_multiplayer_sync_state.clear_pending_chosen_door_sync()
	choosing_next_room = false
	door_options.clear()
	_doors_spawn_ready = false
	if settings_enabled and skip_starting_boon_selection:
		pending_room_reward = ENUMS.RewardMode.BOON
		_begin_room(_build_skirmish_profile(room_depth))
	else:
		_open_boon_selection("Choose Starting Arcana", true, ENUMS.RewardMode.ARCANA, {}, "", current_character_id)

func start_run_with_powers(power_ids: Array[String]) -> Dictionary:
	var applied: Array[String] = []
	var unknown: Array[String] = []
	if not is_instance_valid(player):
		return {
			"applied": applied,
			"unknown": power_ids.duplicate()
		}

	for power_id in power_ids:
		var id := _resolve_debug_power_id(power_id)
		if id.is_empty():
			continue
		if not _is_known_power_id(id):
			unknown.append(id)
			continue
		if bool(player.apply_power_for_test(id)):
			applied.append(id)
		else:
			unknown.append(id)

	hud.refresh(_get_hud_state(), player)
	_broadcast_local_player_build_snapshot()
	return {
		"applied": applied,
		"unknown": unknown
	}

func start_run_with_command(command: String) -> Dictionary:
	return start_run_with_powers(_parse_power_command(command))

func start_run_with_preset(preset_key: String) -> Dictionary:
	var normalized := preset_key.strip_edges().to_lower()
	var preset := DEBUG_ENUMS.PowerPreset.NONE
	match normalized:
		"dash", "dasher", "dash_specialist", "dash specialist":
			preset = DEBUG_ENUMS.PowerPreset.DASH_SPECIALIST
		"bruiser", "no_dash_bruiser", "no dash bruiser", "iron_vanguard", "iron vanguard", "grounded", "non_dash", "non-dash":
			preset = DEBUG_ENUMS.PowerPreset.NO_DASH_BRUISER
		"marksman", "high_range_dps", "high range dps", "ranged", "range_dps", "range dps":
			preset = DEBUG_ENUMS.PowerPreset.HIGH_RANGE_DPS
		_:
			preset = DEBUG_ENUMS.PowerPreset.NONE
	return start_run_with_powers(_get_debug_power_preset_ids(preset, _debug_depth_for_power_preset()))

func get_balance_telemetry(max_runs: int = 10, max_age_days: int = 21, include_debug: bool = false, game_version: String = "") -> Dictionary:
	return RUN_TELEMETRY_STORE.build_balance_summary(max_runs, max_age_days, include_debug, game_version)

func go_do_that_thing(state: String) -> Dictionary:
	return start_debug_encounter(state)

func start_objective_test(kind: String = "") -> Dictionary:
	return _start_debug_objective_room(kind)

func start_last_stand_test() -> Dictionary:
	return _start_debug_objective_room("last_stand")

func start_endurance_test() -> Dictionary:
	return _start_debug_objective_room("last_stand")

func start_debug_encounter(encounter_key: String) -> Dictionary:
	var entry := _find_debug_encounter_entry(encounter_key)
	if entry.is_empty():
		return {"ok": false, "note": "Unknown encounter key."}
	return _start_debug_selected_encounter(entry["id"])

func _debug_encounter_key(encounter_state: int) -> String:
	return ENCOUNTER_CONTRACTS.debug_encounter_key_from_id(encounter_state)

func _start_debug_selected_encounter(encounter_state: int) -> Dictionary:
	run_summary_recorder.mark_debug_mode()
	var encounter_key := _debug_encounter_key(encounter_state)
	if encounter_key.is_empty():
		return {"ok": true, "note": "No debug encounter selected."}
	if encounter_key == "warden":
		return _start_debug_boss_room()
	if encounter_key == "sovereign":
		return _start_debug_second_boss_room()
	if encounter_key == "lacuna":
		return _start_debug_third_boss_room()

	_reset_for_debug_jump()
	var encounter_depth := start_depth
	rooms_cleared = encounter_depth - 1
	room_depth = encounter_depth
	boss_unlocked = false

	if encounter_key == "rest":
		_enter_rest_site()
		hud.refresh(_get_hud_state(), player)
		return {"ok": true, "state": "debug_encounter", "encounter": "Rest Site"}

	var profile := _build_debug_encounter_profile(encounter_key, encounter_depth)
	profile = _apply_debug_mutator_override(profile)
	if profile.is_empty():
		return {"ok": false, "state": "debug_encounter", "note": "Could not build encounter profile."}
	pending_room_reward = _get_debug_encounter_reward_mode(encounter_key)
	if ENCOUNTER_CONTRACTS.debug_encounter_is_objective(encounter_key):
		pending_room_reward = ENUMS.RewardMode.MISSION
	_begin_room(profile)
	hud.refresh(_get_hud_state(), player)
	return {
		"ok": true,
		"state": "debug_encounter",
		"encounter": ENCOUNTER_CONTRACTS.profile_label(profile)
	}

func _start_debug_boss_room() -> Dictionary:
	_reset_for_debug_jump()
	rooms_cleared = encounter_count
	room_depth = encounter_count
	boss_unlocked = true
	first_boss_defeated = false
	second_boss_defeated = false
	in_second_boss_room = false
	in_third_boss_room = false
	phase_two_rooms_cleared = 0
	phase_three_rooms_cleared = 0
	boss_reward_pending = false
	last_defeated_boss_id = ""
	_begin_boss_room()
	hud.refresh(_get_hud_state(), player)
	return {"ok": true, "state": "debug_encounter", "encounter": "Warden"}

func _start_debug_second_boss_room() -> Dictionary:
	_reset_for_debug_jump()
	rooms_cleared = encounter_count + second_boss_encounter_count
	room_depth = rooms_cleared
	boss_unlocked = true
	first_boss_defeated = true
	second_boss_defeated = false
	in_second_boss_room = false
	in_third_boss_room = false
	phase_two_rooms_cleared = second_boss_encounter_count
	phase_three_rooms_cleared = 0
	_begin_second_boss_room()
	hud.refresh(_get_hud_state(), player)
	return {"ok": true, "state": "debug_encounter", "encounter": "Sovereign"}

func _start_debug_third_boss_room() -> Dictionary:
	_reset_for_debug_jump()
	rooms_cleared = _get_third_boss_target_depth()
	room_depth = rooms_cleared
	boss_unlocked = true
	first_boss_defeated = true
	second_boss_defeated = true
	in_second_boss_room = false
	in_third_boss_room = false
	phase_two_rooms_cleared = second_boss_encounter_count
	phase_three_rooms_cleared = third_boss_encounter_count
	_begin_third_boss_room()
	hud.refresh(_get_hud_state(), player)
	return {"ok": true, "state": "debug_encounter", "encounter": "Lacuna"}

func _build_debug_encounter_profile(encounter_key: String, depth: int) -> Dictionary:
	if not is_instance_valid(encounter_profile_builder):
		return {}
	return encounter_profile_builder.build_debug_encounter_profile(encounter_key, depth)

func _debug_mutator_key(state_value: int) -> String:
	match state_value:
		DEBUG_ENUMS.MutatorOverride.BLOOD_RUSH:
			return "blood_rush"
		DEBUG_ENUMS.MutatorOverride.FLASHPOINT:
			return "flashpoint"
		DEBUG_ENUMS.MutatorOverride.SIEGEBREAK:
			return "siegebreak"
		DEBUG_ENUMS.MutatorOverride.IRON_VOLLEY:
			return "iron_volley"
		DEBUG_ENUMS.MutatorOverride.KILLBOX:
			return "killbox"
		DEBUG_ENUMS.MutatorOverride.PHASE_COLLAPSE:
			return "convergence"
		DEBUG_ENUMS.MutatorOverride.CONFLAGRATION:
			return "conflagration"
		DEBUG_ENUMS.MutatorOverride.TETHER_WEB:
			return "tether_web"
		DEBUG_ENUMS.MutatorOverride.RANDOM_HARD:
			return "random_hard"
		_:
			return ""

func _debug_bearing_override_tier() -> int:
	if not settings_enabled:
		return -1
	if start_bearing < BEARING_ENUMS.BearingTier.PILGRIM:
		return -1
	return clampi(start_bearing, BEARING_ENUMS.BearingTier.PILGRIM, BEARING_ENUMS.BearingTier.FORSWORN)

func _apply_debug_mutator_override(profile: Dictionary) -> Dictionary:
	if not settings_enabled:
		return profile
	if profile.is_empty():
		return profile
	var mutator_key := _debug_mutator_key(mutator_override)
	if mutator_key.is_empty():
		return profile
	if not is_instance_valid(encounter_profile_builder):
		return profile
	var mutator: Dictionary = encounter_profile_builder.build_debug_mutator(mutator_key)
	if mutator.is_empty():
		return profile
	return encounter_profile_builder.apply_mutator_variant_to_profile(profile, mutator, room_depth)

func _reset_for_debug_jump() -> void:
	player_flow_coordinator.close_reward_selection_if_active(reward_selection_ui)
	_set_combat_paused(false)
	_doors_spawn_ready = false
	choosing_next_room = false
	door_options.clear()
	pending_room_reward = ENUMS.RewardMode.NONE
	run_cleared = false
	in_boss_room = false
	in_second_boss_room = false
	in_third_boss_room = false
	first_boss_defeated = false
	second_boss_defeated = false
	phase_two_rooms_cleared = 0
	phase_three_rooms_cleared = 0
	endless_boss_defeated = false
	active_room_enemy_count = 0
	boss_reward_pending = false
	last_defeated_boss_id = ""
	_clear_all_enemies()
	player_flow_coordinator.reset_player_position(player)

func _start_debug_objective_room(kind: String = "") -> Dictionary:
	run_summary_recorder.mark_debug_mode()
	_reset_for_debug_jump()
	var objective_depth := 1
	rooms_cleared = objective_depth - 1
	room_depth = objective_depth
	boss_unlocked = false
	var profile := _build_objective_test_profile(objective_depth, kind)
	profile = _apply_debug_mutator_override(profile)
	if profile.is_empty():
		return {"ok": false, "state": "objective_test", "note": "Could not build objective profile."}
	pending_room_reward = ENUMS.RewardMode.MISSION
	_begin_room(profile)
	hud.refresh(_get_hud_state(), player)
	return {
		"ok": true,
		"state": "objective_test",
		"objective": ENCOUNTER_CONTRACTS.profile_label(profile)
	}

func _build_objective_test_profile(depth: int, kind: String = "") -> Dictionary:
	if not is_instance_valid(encounter_profile_builder):
		return {}
	return encounter_profile_builder.build_objective_profile(depth, kind)

func _apply_debug_start_powers_if_needed() -> void:
	if not settings_enabled:
		return
	if not apply_test_powers_on_start:
		return
	var ids: Array[String] = []
	ids.append_array(_get_debug_power_preset_ids(start_power_preset, start_depth))
	for id in start_power_ids:
		ids.append(String(id))
	if ids.is_empty():
		return
	start_run_with_powers(ids)

func _debug_depth_for_power_preset() -> int:
	if settings_enabled:
		return maxi(1, start_depth)
	if room_depth > 0:
		return room_depth
	return 1

func _debug_preset_power_count_for_depth(depth: int) -> int:
	var clamped_depth := maxi(1, depth)
	return 2 + int(floor(float(clamped_depth - 1) / 2.0))

func _get_debug_power_preset_pool(preset: int) -> Array[String]:
	match preset:
		DEBUG_ENUMS.PowerPreset.DASH_SPECIALIST:
			return [
				"fleet_foot",
				"blink_dash",
				"surge_step",
				"phantom_step",
				"reaper_step",
				"static_wake",
				"wraithstep"
			]
		DEBUG_ENUMS.PowerPreset.NO_DASH_BRUISER:
			return [
				"heavy_blow",
				"wide_arc",
				"long_reach",
				"iron_skin",
				"heartstone",
				"battle_trance",
				"rupture_wave",
				"aegis_field",
				"hunters_snare"
			]
		DEBUG_ENUMS.PowerPreset.HIGH_RANGE_DPS:
			return [
				"first_strike",
				"heavy_blow",
				"long_reach",
				"razor_wind",
				"execution_edge",
				"storm_crown",
				"hunters_snare"
			]
		_:
			return []

func _get_debug_power_preset_ids(preset: int, depth: int = -1) -> Array[String]:
	var pool := _get_debug_power_preset_pool(preset)
	if pool.is_empty():
		return []
	var resolved_depth := depth if depth > 0 else _debug_depth_for_power_preset()
	var target_count := mini(pool.size(), _debug_preset_power_count_for_depth(resolved_depth))
	var selected: Array[String] = []
	for i in range(target_count):
		selected.append(pool[i])
	return selected

func _parse_power_command(command: String) -> Array[String]:
	var normalized := command.to_lower()
	for keyword in ["start", "a", "run", "with", "these", "powers", "power", "and"]:
		normalized = normalized.replace(keyword, " ")
	for sep in [",", ";", "|", "\n", "\t"]:
		normalized = normalized.replace(sep, " ")

	var ids: Array[String] = []
	for token in normalized.split(" ", false):
		var id := token.strip_edges()
		if id.is_empty():
			continue
		ids.append(id)
	return ids

func _is_known_power_id(power_id: String) -> bool:
	return power_registry_instance.is_valid_power_id(_resolve_debug_power_id(power_id))

func _resolve_debug_power_id(raw_power_id: String) -> String:
	var id := raw_power_id.strip_edges().to_lower()
	if id.is_empty():
		return ""
	if power_registry_instance != null and power_registry_instance.is_valid_power_id(id):
		return id

	var canonical := id.replace("-", "_").replace(" ", "_").replace("'", "")
	if power_registry_instance != null and power_registry_instance.is_valid_power_id(canonical):
		return canonical

	match canonical:
		"wardens_verdict":
			return "wardens_verdict"
		"lacuna_echo":
			return "lacuna_echo"
		"sovereign_tempo":
			return "sovereign_tempo"
		"pillar_convergence":
			return "pillar_convergence"
		"bastions_oath":
			return "unbroken_oath"
		"unbroken_oath":
			return "unbroken_oath"
		_:
			return canonical

func _unhandled_input(event: InputEvent) -> void:
	# Hold Tab to show build details; release Tab to close.
	if event is InputEventKey and event.keycode == KEY_TAB and not event.echo:
		if is_instance_valid(build_detail_panel):
			if event.pressed:
				if is_instance_valid(defeat_screen) and bool(defeat_screen.is_open()):
					return
				if is_instance_valid(pause_menu_controller) and bool(pause_menu_controller.is_open()):
					return
				if is_instance_valid(reward_selection_ui) and bool(reward_selection_ui.is_active()):
					return
				if not build_detail_panel.is_open():
					var active_powers := _get_active_player_powers()
					build_detail_panel.refresh(current_character_id, active_powers["boons"], active_powers["arcana"], active_powers["boss_rewards"], player)
					build_detail_panel.open()
				get_viewport().set_input_as_handled()
				return
			if build_detail_panel.is_open():
				build_detail_panel.close()
				get_viewport().set_input_as_handled()
				return
	
	if is_instance_valid(defeat_screen) and bool(defeat_screen.is_open()):
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if not is_instance_valid(pause_menu_controller):
		return
	if bool(pause_menu_controller.is_open()) and bool(pause_menu_controller.is_options_open()):
		pause_menu_controller.close_options()
		get_viewport().set_input_as_handled()
		return
	if bool(pause_menu_controller.is_open()) and bool(pause_menu_controller.is_glossary_open()):
		pause_menu_controller.close_glossary()
		get_viewport().set_input_as_handled()
		return
	if bool(pause_menu_controller.is_open()):
		pause_menu_controller.close()
		get_viewport().set_input_as_handled()
		return
	pause_menu_controller.open()
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _handle_modal_frame(delta):
		return
	var perf_frame_start_usec := Time.get_ticks_usec() if _perf_attribution_enabled and is_multiplayer else 0

	_refresh_effective_room_bounds_from_seamlock_penalty()
	_keep_player_inside_current_room()
	_keep_enemies_inside_current_room(delta)
	_keep_player_inside_camera_view()
	var _grace_active := _update_encounter_intro_grace()
	var objective_frame_result: Dictionary = objective_frame_coordinator.tick(objective_manager, objective_runtime, delta, _grace_active)
	if bool(objective_frame_result.get("should_redraw", false)):
		queue_redraw()
	_try_use_door()
	_update_encounter_state()
	_update_camera_mode()
	if is_multiplayer and multiplayer_use_shared_camera:
		_update_multiplayer_camera()
	if is_multiplayer:
		var sim_start_usec := Time.get_ticks_usec() if _perf_attribution_enabled else 0
		_process_multiplayer_sync(delta)
		var sim_elapsed_ms := 0.0
		if sim_start_usec > 0:
			sim_elapsed_ms = float(Time.get_ticks_usec() - sim_start_usec) / 1000.0
		var post_start_usec := Time.get_ticks_usec() if sim_start_usec > 0 else 0
		_refresh_frame_ui()
		if post_start_usec > 0 and perf_frame_start_usec > 0:
			var post_elapsed_ms := float(Time.get_ticks_usec() - post_start_usec) / 1000.0
			var frame_elapsed_ms := float(Time.get_ticks_usec() - perf_frame_start_usec) / 1000.0
			var pre_elapsed_ms := maxf(0.0, frame_elapsed_ms - sim_elapsed_ms - post_elapsed_ms)
			_record_perf_attribution_sample(delta, pre_elapsed_ms, sim_elapsed_ms, post_elapsed_ms, frame_elapsed_ms)
		return
	_refresh_frame_ui()

func _process_multiplayer_sync(delta: float) -> void:
	_sync_objective_state_tick(delta)
	_sync_archer_projectile_state_tick(delta)
	enemy_state_sync_broadcaster.tick(delta)
	EnemyReplicationService.interpolate_remote_enemies(delta, enemy_remote_position_lerp_speed, enemy_remote_rotation_lerp_speed)
	_flush_pending_client_door_syncs()
	_flush_pending_client_boss_spawn_syncs()
	_flush_pending_client_spawn_syncs()
	_flush_pending_client_objective_spawn_syncs()
	_report_client_perf_sample(delta)
	_update_multiplayer_perf_logging(delta)
	_tick_multiplayer_stress_test(delta)


func _tick_multiplayer_stress_test(delta: float) -> void:
	if not _stress_test_active:
		return
	if _stress_test_coordinator == null:
		_stress_test_coordinator = load("res://scripts/multiplayer_stress_test.gd").new()
		_stress_test_coordinator.world_gen = self
	_stress_test_coordinator.tick_frame(delta, enemy_state_sync_broadcaster.last_sync_estimated_bytes, enemy_state_sync_broadcaster.last_sync_batch_count)


func _update_multiplayer_perf_logging(delta: float) -> void:
	if not multiplayer_perf_logging_enabled:
		return
	if not MultiplayerSessionManager.should_broadcast():
		return
	_multiplayer_perf_log_elapsed += delta
	var log_interval := maxf(0.25, multiplayer_perf_log_interval_sec)
	if _multiplayer_perf_log_elapsed < log_interval:
		return
	_multiplayer_perf_log_elapsed = 0.0
	var player_replication_service := get_node_or_null("/root/PlayerReplicationService")
	if player_replication_service != null:
		var feedback_metrics := player_replication_service.get_last_cue_event_sync_metrics() as Dictionary
		_multiplayer_last_feedback_event_count = int(feedback_metrics.get("event_count", 0))
		_multiplayer_last_feedback_estimated_bytes = int(feedback_metrics.get("estimated_bytes", 0))
	else:
		_multiplayer_last_feedback_event_count = 0
		_multiplayer_last_feedback_estimated_bytes = 0
	print("[MP PERF] tracked=%d room_active=%d sync_enemies=%d sync_batches=%d sync_est_bytes=%d" % [
		EnemyReplicationService.enemy_nodes_by_id.size(),
		active_room_enemy_count,
		enemy_state_sync_broadcaster.last_sync_enemy_count,
		enemy_state_sync_broadcaster.last_sync_batch_count,
		enemy_state_sync_broadcaster.last_sync_estimated_bytes
	] + " tether_sync_enemies=%d tether_sync_est_bytes=%d feedback_events=%d feedback_est_bytes=%d" % [
		enemy_state_sync_broadcaster.last_sync_tether_enemy_count,
		enemy_state_sync_broadcaster.last_sync_tether_estimated_bytes,
		_multiplayer_last_feedback_event_count,
		_multiplayer_last_feedback_estimated_bytes
	])
	if not _perf_attr_last_sample.is_empty():
		print("[MP PERF][ATTR] pre_ms=%.2f sync_ms=%.2f post_ms=%.2f frame_ms=%.2f ui_ms=%.2f enemy_drawn_avg=%.1f runtime_delta_ms=%.2f runtime_delta_calls=%.1f" % [
			float(_perf_attr_last_sample.get("avg_pre_ms", 0.0)),
			float(_perf_attr_last_sample.get("avg_sim_ms", 0.0)),
			float(_perf_attr_last_sample.get("avg_post_ms", 0.0)),
			float(_perf_attr_last_sample.get("avg_frame_ms", 0.0)),
			float(_perf_attr_last_sample.get("avg_ui_ms", 0.0)),
			float(_perf_attr_last_sample.get("avg_enemy_drawn", 0.0)),
			float(_perf_attr_last_sample.get("avg_runtime_delta_ms", 0.0)),
			float(_perf_attr_last_sample.get("avg_runtime_delta_calls", 0.0))
		])
	if not _multiplayer_latest_client_perf_by_peer.is_empty():
		for peer_id_variant in _multiplayer_latest_client_perf_by_peer.keys():
			var peer_id := int(peer_id_variant)
			var sample := _multiplayer_latest_client_perf_by_peer.get(peer_id, {}) as Dictionary
			print("[MP PERF][CLIENT %d] fps=%.1f enemy_nodes=%d room=%s pre_ms=%.2f sync_ms=%.2f post_ms=%.2f frame_ms=%.2f ui_ms=%.2f enemy_drawn_avg=%.1f" % [
				peer_id,
				float(sample.get("fps", 0.0)),
				int(sample.get("enemy_nodes", 0)),
				String(sample.get("room_label", "")),
				float(sample.get("pre_ms", 0.0)),
				float(sample.get("sim_ms", 0.0)),
				float(sample.get("post_ms", 0.0)),
				float(sample.get("frame_ms", 0.0)),
				float(sample.get("ui_ms", 0.0)),
				float(sample.get("enemy_drawn_avg", 0.0))
			])

func _record_perf_attribution_sample(delta: float, pre_elapsed_ms: float, sim_elapsed_ms: float, post_elapsed_ms: float, frame_elapsed_ms: float) -> void:
	if not _perf_attribution_enabled:
		return
	if not is_multiplayer:
		return
	if delta <= 0.0:
		return
	var frame_ms := frame_elapsed_ms if frame_elapsed_ms > 0.0 else delta * 1000.0
	var pre_ms := maxf(0.0, pre_elapsed_ms)
	var sim_ms := maxf(0.0, sim_elapsed_ms)
	var post_ms := maxf(0.0, post_elapsed_ms)
	var ui_ms := pre_ms + post_ms
	var runtime_delta_ms := float(enemy_state_sync_broadcaster.perf_runtime_delta_total_usec) / 1000.0
	var runtime_delta_calls: int = enemy_state_sync_broadcaster.perf_runtime_delta_calls
	_perf_attr_live_snapshot = {
		"avg_pre_ms": pre_ms,
		"avg_sim_ms": sim_ms,
		"avg_sync_ms": sim_ms,
		"avg_post_ms": post_ms,
		"avg_frame_ms": frame_ms,
		"avg_ui_ms": ui_ms,
		"avg_enemy_drawn": float(EnemyReplicationService.enemy_nodes_by_id.size()),
		"avg_runtime_delta_ms": runtime_delta_ms,
		"avg_runtime_delta_calls": float(runtime_delta_calls),
		"sample_frames": 1
	}
	_perf_attr_frame_count += 1
	_perf_attr_total_pre_ms += pre_ms
	_perf_attr_total_sim_ms += sim_ms
	_perf_attr_total_post_ms += post_ms
	_perf_attr_total_frame_ms += frame_ms
	_perf_attr_total_ui_ms += ui_ms
	_perf_attr_total_enemy_drawn += EnemyReplicationService.enemy_nodes_by_id.size()
	_perf_attribution_elapsed += frame_ms
	if _perf_attribution_elapsed < _perf_attribution_sample_ms:
		return
	var samples := maxf(1.0, float(_perf_attr_frame_count))
	_perf_attr_last_sample = {
		"avg_pre_ms": _perf_attr_total_pre_ms / samples,
		"avg_sim_ms": _perf_attr_total_sim_ms / samples,
		"avg_sync_ms": _perf_attr_total_sim_ms / samples,
		"avg_post_ms": _perf_attr_total_post_ms / samples,
		"avg_frame_ms": _perf_attr_total_frame_ms / samples,
		"avg_ui_ms": _perf_attr_total_ui_ms / samples,
		"avg_enemy_drawn": float(_perf_attr_total_enemy_drawn) / samples,
		"avg_runtime_delta_ms": (float(enemy_state_sync_broadcaster.perf_runtime_delta_total_usec) / 1000.0) / samples,
		"avg_runtime_delta_calls": float(enemy_state_sync_broadcaster.perf_runtime_delta_calls) / samples,
		"sample_frames": _perf_attr_frame_count
	}
	_perf_attribution_elapsed = 0.0
	_perf_attr_frame_count = 0
	_perf_attr_total_pre_ms = 0.0
	_perf_attr_total_sim_ms = 0.0
	_perf_attr_total_post_ms = 0.0
	_perf_attr_total_frame_ms = 0.0
	_perf_attr_total_ui_ms = 0.0
	_perf_attr_total_enemy_drawn = 0
	enemy_state_sync_broadcaster.reset_perf_attribution()

func _get_perf_attribution_snapshot() -> Dictionary:
	if not _perf_attr_last_sample.is_empty():
		return _perf_attr_last_sample.duplicate(true)
	return _perf_attr_live_snapshot.duplicate(true)

func _report_client_perf_sample(delta: float) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	# Keep this traffic to active diagnostics windows only.
	if not multiplayer_perf_logging_enabled and not _perf_attribution_enabled:
		return
	_multiplayer_client_perf_report_elapsed += delta
	if _multiplayer_client_perf_report_elapsed < _multiplayer_client_perf_report_interval_sec:
		return
	_multiplayer_client_perf_report_elapsed = 0.0
	var fps := float(Engine.get_frames_per_second())
	var perf_sample := _get_perf_attribution_snapshot()
	var pre_ms := float(perf_sample.get("avg_pre_ms", 0.0))
	var sim_ms := float(perf_sample.get("avg_sim_ms", 0.0))
	var post_ms := float(perf_sample.get("avg_post_ms", 0.0))
	var frame_ms := float(perf_sample.get("avg_frame_ms", 0.0))
	var ui_ms := float(perf_sample.get("avg_ui_ms", 0.0))
	var enemy_drawn_avg := float(perf_sample.get("avg_enemy_drawn", 0.0))
	_sync_client_perf_sample.rpc_id(1, fps, EnemyReplicationService.enemy_nodes_by_id.size(), current_room_label, pre_ms, sim_ms, post_ms, frame_ms, ui_ms, enemy_drawn_avg)

@rpc("unreliable", "any_peer")
func _sync_client_perf_sample(
	fps: float,
	enemy_nodes: int,
	room_label: String,
	pre_ms: float = 0.0,
	sim_ms: float = 0.0,
	post_ms: float = 0.0,
	frame_ms: float = 0.0,
	ui_ms: float = 0.0,
	enemy_drawn_avg: float = 0.0
) -> void:
	if not MultiplayerSessionManager.should_broadcast():
		return
	var sender_peer_id := int(multiplayer.get_remote_sender_id())
	if sender_peer_id <= 0:
		return
	_multiplayer_latest_client_perf_by_peer[sender_peer_id] = {
		"fps": fps,
		"enemy_nodes": enemy_nodes,
		"room_label": room_label,
		"pre_ms": pre_ms,
		"sim_ms": sim_ms,
		"post_ms": post_ms,
		"frame_ms": frame_ms,
		"ui_ms": ui_ms,
		"enemy_drawn_avg": enemy_drawn_avg,
		"timestamp_ms": Time.get_ticks_msec()
	}

func _can_apply_client_door_sync() -> bool:
	if not MultiplayerSessionManager.is_remote_replica():
		return false
	if _world_multiplayer_sync_state.awaiting_authoritative_door_choice:
		return false
	if _is_reward_selection_active():
		return false
	if current_room_label == "Starting Chamber":
		return false
	return true

func _should_defer_client_door_sync_payload(synced_choosing_next_room: bool, progress_state: Dictionary) -> bool:
	if not MultiplayerSessionManager.is_remote_replica():
		return false
	if not synced_choosing_next_room:
		return false
	if _world_multiplayer_sync_state.awaiting_authoritative_door_choice:
		return false
	if not choosing_next_room:
		return false
	if door_options.is_empty():
		return false
	var incoming_rooms_cleared := int(progress_state.get("rooms_cleared", rooms_cleared))
	var incoming_room_depth := int(progress_state.get("room_depth", room_depth))
	return incoming_rooms_cleared != rooms_cleared or incoming_room_depth != room_depth

func _apply_synced_door_options_payload(synced_door_options: Array, synced_choosing_next_room: bool, synced_boss_unlocked: bool, progress_state: Dictionary) -> void:
	door_options.clear()
	for option in synced_door_options:
		if option is Dictionary:
			door_options.append((option as Dictionary).duplicate(true))
	choosing_next_room = synced_choosing_next_room
	boss_unlocked = synced_boss_unlocked
	_apply_progress_sync_state(progress_state)

func _flush_pending_client_door_syncs() -> void:
	if not _can_apply_client_door_sync():
		return
	if not _world_multiplayer_sync_state.pending_chosen_door.is_empty():
		var chosen_payload := _world_multiplayer_sync_state.consume_pending_chosen_door_sync()
		var chosen_door := chosen_payload.get("chosen_door", {}) as Dictionary
		var progress_state := chosen_payload.get("progress_state", {}) as Dictionary
		_world_multiplayer_sync_state.clear_authoritative_door_wait()
		_choose_door(chosen_door)
		_apply_progress_sync_state(progress_state)
	if not _world_multiplayer_sync_state.pending_door_sync_payload.is_empty():
		var door_payload := _world_multiplayer_sync_state.consume_pending_door_sync_payload()
		var synced_door_options: Array = door_payload.get("door_options", []) as Array
		var synced_choosing_next_room := bool(door_payload.get("choosing_next_room", false))
		var synced_boss_unlocked := bool(door_payload.get("boss_unlocked", boss_unlocked))
		var progress_state := door_payload.get("progress_state", {}) as Dictionary
		_apply_synced_door_options_payload(synced_door_options, synced_choosing_next_room, synced_boss_unlocked, progress_state)

func _can_apply_client_spawn_sync(payload: Dictionary) -> bool:
	if not MultiplayerSessionManager.is_remote_replica():
		return false
	if not is_instance_valid(enemy_spawner):
		return false
	var source_room_sync_id := int(payload.get("room_sync_id", 0))
	var allow_initial_sync_alignment: bool = _world_multiplayer_sync_state.current_room_sync_id == 0 and current_room_label == "Starting Chamber" and not _is_reward_selection_active()
	if not _world_multiplayer_sync_state.can_accept_source_sync_id(source_room_sync_id, allow_initial_sync_alignment):
		return false
	if _is_reward_selection_active():
		return false
	if current_room_label == "Starting Chamber" and not allow_initial_sync_alignment:
		return false
	var payload_room_label := String(payload.get("room_label", "")).strip_edges()
	if payload_room_label.is_empty():
		return true
	if allow_initial_sync_alignment:
		return true
	return payload_room_label == current_room_label

func _apply_synced_spawn_batch_payload(payload: Dictionary) -> void:
	var spawn_batch: Array = payload.get("spawn_batch", []) as Array
	var synced_enemy_count := int(payload.get("synced_enemy_count", 0))
	var source_room_sync_id := int(payload.get("room_sync_id", 0))
	_clear_all_enemies()
	for spawn_entry_variant in spawn_batch:
		if not (spawn_entry_variant is Dictionary):
			continue
		var spawn_entry := spawn_entry_variant as Dictionary
		var enemy_type := String(spawn_entry.get("enemy_type", ""))
		var enemy_position := spawn_entry.get("position", Vector2.ZERO) as Vector2
		var enemy_id := int(spawn_entry.get("enemy_id", -1))
		if enemy_type.is_empty() or enemy_id <= 0:
			continue
		var enemy: CharacterBody2D = enemy_spawner.spawn_enemy_from_sync(enemy_type, enemy_position)
		if is_instance_valid(enemy):
			enemy_state_sync_broadcaster.register_enemy(enemy, enemy_id)
	active_room_enemy_count = synced_enemy_count
	_world_multiplayer_sync_state.apply_spawn_sync_id(source_room_sync_id)

func _flush_pending_client_spawn_syncs() -> void:
	if not _world_multiplayer_sync_state.has_pending_spawn_sync_payload():
		return
	if not _can_apply_client_spawn_sync(_world_multiplayer_sync_state.peek_pending_spawn_sync_payload()):
		return
	var payload := _world_multiplayer_sync_state.consume_pending_spawn_sync_payload()
	_apply_synced_spawn_batch_payload(payload)

func _apply_synced_objective_spawn_batch_payload(payload: Dictionary) -> void:
	var spawn_batch: Array = payload.get("spawn_batch", []) as Array
	var synced_enemy_count := int(payload.get("synced_enemy_count", 0))
	var source_room_sync_id := int(payload.get("room_sync_id", 0))
	for spawn_entry_variant in spawn_batch:
		if not (spawn_entry_variant is Dictionary):
			continue
		var spawn_entry := spawn_entry_variant as Dictionary
		var enemy_type := String(spawn_entry.get("enemy_type", ""))
		var enemy_position := spawn_entry.get("position", Vector2.ZERO) as Vector2
		var enemy_id := int(spawn_entry.get("enemy_id", -1))
		var spawn_meta := spawn_entry.get("spawn_meta", {}) as Dictionary
		if enemy_type.is_empty() or enemy_id <= 0:
			continue
		var enemy: CharacterBody2D = enemy_spawner.spawn_enemy_from_sync(enemy_type, enemy_position)
		if is_instance_valid(enemy):
			enemy_state_sync_broadcaster.register_enemy(enemy, enemy_id)
			if not spawn_meta.is_empty():
				_apply_objective_spawn_meta(enemy, spawn_meta)
			if enemy.has_method("set_network_simulation_enabled"):
				enemy.call("set_network_simulation_enabled", false)
		if enemy.has_signal("died"):
			var captured_enemy_id := enemy_id
			if not enemy.died.is_connected(Callable(enemy_state_sync_broadcaster, "on_enemy_died").bind(captured_enemy_id)):
				enemy.died.connect(Callable(enemy_state_sync_broadcaster, "on_enemy_died").bind(captured_enemy_id))
	active_room_enemy_count = synced_enemy_count
	_world_multiplayer_sync_state.apply_spawn_sync_id(source_room_sync_id)

func _flush_pending_client_objective_spawn_syncs() -> void:
	if not _world_multiplayer_sync_state.has_pending_objective_spawn_sync_payloads():
		return
	var remaining_payloads: Array[Dictionary] = []
	for payload in _world_multiplayer_sync_state.get_pending_objective_spawn_sync_payloads():
		if not _can_apply_client_spawn_sync(payload):
			var source_room_sync_id := int(payload.get("room_sync_id", 0))
			if _world_multiplayer_sync_state.is_stale_room_sync_id(source_room_sync_id):
				continue
			remaining_payloads.append(payload)
			continue
		_apply_synced_objective_spawn_batch_payload(payload)
	_world_multiplayer_sync_state.set_pending_objective_spawn_sync_payloads(remaining_payloads)

func _is_current_room_boss_stage(boss_stage: int) -> bool:
	match boss_stage:
		1:
			return in_boss_room and not in_second_boss_room and not in_third_boss_room
		2:
			return in_second_boss_room and not in_third_boss_room
		3:
			return in_third_boss_room
		_:
			return false

func _can_apply_client_boss_spawn_sync(payload: Dictionary) -> bool:
	if not MultiplayerSessionManager.is_remote_replica():
		return false
	if not is_instance_valid(enemy_spawner):
		return false
	if _is_reward_selection_active():
		return false
	if current_room_label == "Starting Chamber":
		return false
	var source_room_sync_id := int(payload.get("room_sync_id", 0))
	if not _world_multiplayer_sync_state.can_accept_source_sync_id(source_room_sync_id, false):
		return false
	var boss_stage := int(payload.get("boss_stage", 0))
	if not _is_current_room_boss_stage(boss_stage):
		return false
	var payload_room_label := String(payload.get("room_label", "")).strip_edges()
	if payload_room_label.is_empty():
		return true
	return payload_room_label == current_room_label

func _apply_synced_boss_spawn_payload(payload: Dictionary) -> void:
	var boss_stage := int(payload.get("boss_stage", 0))
	var enemy_id := int(payload.get("enemy_id", -1))
	var spawn_position := payload.get("position", Vector2.ZERO) as Vector2
	var source_room_sync_id := int(payload.get("room_sync_id", 0))
	if boss_stage <= 0 or enemy_id <= 0:
		return
	var existing_enemy := EnemyReplicationService.enemy_nodes_by_id.get(enemy_id) as Node2D
	if is_instance_valid(existing_enemy):
		active_room_enemy_count = maxi(1, active_room_enemy_count)
		return
	var boss := _spawn_boss_for_stage(boss_stage, spawn_position)
	if is_instance_valid(boss):
		enemy_state_sync_broadcaster.register_enemy(boss, enemy_id)
	active_room_enemy_count = 1
	_world_multiplayer_sync_state.apply_spawn_sync_id(source_room_sync_id)

func _flush_pending_client_boss_spawn_syncs() -> void:
	if not _world_multiplayer_sync_state.has_pending_boss_spawn_sync_payload():
		return
	var peek_payload := _world_multiplayer_sync_state.peek_pending_boss_spawn_sync_payload()
	if not _can_apply_client_boss_spawn_sync(peek_payload):
		return
	var payload := _world_multiplayer_sync_state.consume_pending_boss_spawn_sync_payload()
	_apply_synced_boss_spawn_payload(payload)

func _handle_modal_frame(delta: float) -> bool:
	if is_instance_valid(defeat_screen) and bool(defeat_screen.is_open()):
		_refresh_frame_ui()
		return true
	if is_instance_valid(build_detail_panel) and bool(build_detail_panel.is_open()):
		_refresh_frame_ui()
		return true
	if is_instance_valid(pause_menu_controller) and bool(pause_menu_controller.is_open()):
		_refresh_frame_ui()
		return true
	if is_instance_valid(reward_selection_ui) and reward_selection_ui.is_active():
		reward_selection_ui.process_input(delta)
		_refresh_frame_ui()
		return true
	return false

func _refresh_frame_ui() -> void:
	hud.refresh(_get_hud_state(), player)
	_sync_renderer()

func _draw() -> void:
	var control_overlay: Dictionary = {}
	if is_instance_valid(objective_manager) and objective_manager.has_method("get_control_overlay_state"):
		control_overlay = objective_manager.get_control_overlay_state()
	if not bool(control_overlay.get("should_draw", false)):
		return
	var goal := maxf(0.01, float(control_overlay.get("goal", 0.0)))
	var progress := float(control_overlay.get("progress", 0.0))
	var progress_ratio := clampf(progress / goal, 0.0, 1.0)
	var anchor := Vector2(control_overlay.get("anchor", Vector2.ZERO))
	var radius := float(control_overlay.get("radius", 0.0))
	var player_inside := bool(control_overlay.get("player_inside", false))
	var contested := bool(control_overlay.get("contested", false))
	var fill_color := Color(0.32, 0.72, 0.96, 0.08)
	var ring_color := Color(0.46, 0.86, 1.0, 0.4)
	var progress_color := Color(0.98, 0.86, 0.42, 0.92)
	if player_inside and not contested:
		fill_color = Color(0.38, 0.92, 0.62, 0.1)
		ring_color = Color(0.56, 1.0, 0.74, 0.5)
		progress_color = Color(0.92, 1.0, 0.7, 0.98)
	elif contested:
		fill_color = Color(0.98, 0.46, 0.34, 0.08)
		ring_color = Color(1.0, 0.64, 0.44, 0.54)
		progress_color = Color(1.0, 0.8, 0.52, 0.94)
	draw_circle(anchor, radius, fill_color)
	draw_arc(anchor, radius, 0.0, TAU, 72, ring_color, 3.0)
	draw_arc(anchor, radius - 8.0, -PI * 0.5, -PI * 0.5 + TAU * progress_ratio, 64, progress_color, 6.0)
	draw_circle(anchor, 8.0, Color(1.0, 0.96, 0.72, 0.75))

func _clamp_position_to_current_room(target_position: Vector2, margin: float = 28.0) -> Vector2:
	if current_effective_room_size == Vector2.ZERO:
		return target_position
	var half := current_effective_room_size * 0.5 - Vector2.ONE * margin
	return Vector2(
		clampf(target_position.x, -half.x, half.x),
		clampf(target_position.y, -half.y, half.y)
	)

func _reset_effective_room_bounds() -> void:
	current_effective_room_size = current_room_size
	_last_applied_camera_room_size = Vector2.ZERO

func _refresh_effective_room_bounds_from_seamlock_penalty() -> void:
	if current_room_size == Vector2.ZERO:
		current_effective_room_size = current_room_size
		return
	var effective_size := current_room_size
	var max_applied_steps := 0.0
	var shrink_per_step := 0.0
	for node in get_tree().get_nodes_in_group(SEAMLOCK_SYNC_GROUP):
		if not is_instance_valid(node):
			continue
		var applied_steps_variant: Variant = node.get("_arena_penalty_applied_steps")
		var shrink_step_variant: Variant = node.get("arena_shrink_per_step")
		if applied_steps_variant == null or shrink_step_variant == null:
			continue
		max_applied_steps = maxf(max_applied_steps, float(applied_steps_variant))
		shrink_per_step = maxf(shrink_per_step, float(shrink_step_variant))
	if max_applied_steps > 0.0 and shrink_per_step > 0.0:
		var side_shrink := max_applied_steps * shrink_per_step * 2.0
		effective_size = Vector2(
			maxf(320.0, current_room_size.x - side_shrink),
			maxf(240.0, current_room_size.y - side_shrink)
		)
	if effective_size == current_effective_room_size:
		return
	current_effective_room_size = effective_size
	if _last_applied_camera_room_size != current_effective_room_size:
		_last_applied_camera_room_size = current_effective_room_size
		_apply_camera_bounds_for_room(current_effective_room_size)

func _get_hud_state() -> Dictionary:
	var display_room_depth := room_depth
	var between_rooms := choosing_next_room or _is_reward_selection_active()
	var display_enemy_mutator := current_room_enemy_mutator
	if between_rooms:
		display_enemy_mutator = {}
	# Keep the visible depth anchored to the cleared room until the next room is entered.
	if between_rooms and not run_cleared and current_room_label != "Rest Site":
		display_room_depth = maxi(0, room_depth - 1)
	
	# Get current character passive name
	var current_character_passive_name := "Passive"
	if not current_character_id.is_empty():
		var char_data := CHARACTER_REGISTRY.get_character(current_character_id)
		if char_data != null and char_data.has("passive_id"):
			current_character_passive_name = String(char_data.get("passive_id", "Passive"))
	
	var objective_hud_state: Dictionary = {}
	if is_instance_valid(objective_manager) and objective_manager.has_method("get_hud_state"):
		objective_hud_state = objective_manager.get_hud_state()
	
	var hud_state := {
		"room_size": current_room_size,
		"current_room_label": current_room_label,
		"current_difficulty_tier": current_difficulty_tier,
		"rooms_cleared": rooms_cleared,
		"room_depth": display_room_depth,
		"run_cleared": run_cleared,
		"current_room_enemy_mutator": display_enemy_mutator,
		"in_boss_room": in_boss_room,
		"active_room_enemy_count": active_room_enemy_count,
		"active_objective_kind": String(objective_hud_state.get("active_objective_kind", "")),
		"objective_time_left": float(objective_hud_state.get("time_left", 0.0)),
		"objective_kills": int(objective_hud_state.get("kills", 0)),
		"objective_kill_target": int(objective_hud_state.get("kill_target", 0)),
		"objective_overtime": bool(objective_hud_state.get("overtime", false)),
		"objective_target_name": String(objective_hud_state.get("hunt_target_name", "")),
		"objective_target_health": int(objective_hud_state.get("hunt_target_health", 0)),
		"objective_target_max_health": int(objective_hud_state.get("hunt_target_max_health", 0)),
		"objective_hunt_kill_progress": int(objective_hud_state.get("hunt_target_kill_progress", 0)),
		"objective_hunt_kill_goal": int(objective_hud_state.get("hunt_target_kill_goal", 0)),
		"objective_control_progress": float(objective_hud_state.get("control_progress", 0.0)),
		"objective_control_goal": float(objective_hud_state.get("control_goal", 0.0)),
		"objective_control_enemies_in_zone": int(objective_hud_state.get("control_enemies_in_zone", 0)),
		"objective_control_contested": bool(objective_hud_state.get("control_contested", false)),
		"objective_control_player_inside": bool(objective_hud_state.get("control_player_inside", false)),
		"objective_exposure_left": float(objective_hud_state.get("exposure_left", 0.0)),
		"objective_last_relocated_escort_count": int(objective_hud_state.get("last_relocated_escort_count", 0)),
		"objective_relocation_hint_left": float(objective_hud_state.get("relocation_hint_left", 0.0)),
		"active_player_mutators": _get_active_player_mutators_for_hud(),
		"objective_target_flee_thresholds": objective_hud_state.get("hunt_target_flee_thresholds", [0.75, 0.5, 0.25]),
		"objective_target_next_flee_index": int(objective_hud_state.get("hunt_target_next_flee_index", 0)),
		"encounter_intro_grace_active": encounter_intro_grace_active,
		"boss_unlocked": boss_unlocked,
		"first_boss_defeated": first_boss_defeated,
		"second_boss_defeated": second_boss_defeated,
		"second_boss_unlocked": _is_second_boss_unlocked(),
		"third_boss_unlocked": _is_third_boss_unlocked(),
		"current_character_passive_name": current_character_passive_name,
		"run_elapsed_seconds": run_summary_recorder.get_run_elapsed_seconds(),
		"timer_visible_in_hud": true,
	}
	var run_context := _get_run_context()
	if run_context != null:
		hud_state["timer_visible_in_hud"] = bool(run_context.is_timer_visible_in_hud())
	var active_powers := _get_active_player_powers()
	hud_state["active_boons"] = active_powers["boons"]
	hud_state["active_arcana"] = active_powers["arcana"]
	hud_state["active_boss_rewards"] = active_powers["boss_rewards"]
	return hud_state

func _get_active_player_powers() -> Dictionary:
	# Returns {"boons": [id1, id2, ...], "arcana": [id1, id2, ...], "boss_rewards": [id1, id2, ...]}
	var result := {"boons": [], "arcana": [], "boss_rewards": []}
	if not is_instance_valid(player):
		return result
	
	# Check all boons (upgrades)
	for power_id in POWER_REGISTRY.UPGRADE_BALANCE.keys():
		var stack_count := int(player.get_upgrade_stack_count(power_id))
		if stack_count > 0:
			result["boons"].append(power_id)
	
	# Check all arcana (trial powers)
	for power_id in POWER_REGISTRY.TRIAL_POWER_BALANCE.keys():
		var stack_count := int(player.get_trial_power_stack_count(power_id))
		if stack_count > 0:
			result["arcana"].append(power_id)

	# Check boss rewards (boss-exclusive upgrades)
	for power_id in POWER_REGISTRY.BOSS_REWARD_BALANCE.keys():
		var stack_count := int(player.get_upgrade_stack_count(power_id))
		if stack_count > 0:
			result["boss_rewards"].append(power_id)
	
	return result

func _sync_renderer() -> void:
	if not is_instance_valid(renderer):
		return
	var allow_door_visibility := false
	if MultiplayerSessionManager.is_remote_replica():
		allow_door_visibility = choosing_next_room and not _is_reward_selection_active() and current_room_label != "Starting Chamber" and not door_options.is_empty()
	else:
		allow_door_visibility = choosing_next_room and active_room_enemy_count <= 0 and not _is_reward_selection_active() and current_room_label != "Starting Chamber"
	var visible_door_options: Array[Dictionary] = []
	if allow_door_visibility:
		visible_door_options = door_options
	renderer.room_size = current_effective_room_size if current_effective_room_size != Vector2.ZERO else current_room_size
	renderer.choosing_next_room = allow_door_visibility
	renderer.door_options = visible_door_options
	renderer.player_global_position = player.global_position if is_instance_valid(player) else Vector2.ZERO

func _keep_player_inside_current_room() -> void:
	if not is_instance_valid(player):
		return
	if current_effective_room_size == Vector2.ZERO:
		return
	var half := current_effective_room_size * 0.5
	player.global_position.x = clampf(player.global_position.x, -half.x, half.x)
	player.global_position.y = clampf(player.global_position.y, -half.y, half.y)

func _refresh_enemy_clamp_cache() -> void:
	_enemy_clamp_cached_nodes.clear()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Node2D:
			_enemy_clamp_cached_nodes.append(enemy as Node2D)

func _keep_enemies_inside_current_room(delta: float) -> void:
	if current_effective_room_size == Vector2.ZERO:
		_enemy_clamp_last_room_size = current_effective_room_size
		return
	var room_size_changed := _enemy_clamp_last_room_size != current_effective_room_size
	_enemy_clamp_last_room_size = current_effective_room_size
	_enemy_clamp_refresh_elapsed += maxf(0.0, delta)
	_enemy_clamp_frame_cursor += 1
	var should_refresh_cache := room_size_changed or _enemy_clamp_cached_nodes.is_empty() or _enemy_clamp_refresh_elapsed >= _enemy_clamp_refresh_interval_sec
	if should_refresh_cache:
		_refresh_enemy_clamp_cache()
		_enemy_clamp_refresh_elapsed = 0.0
	var stride := 1 if current_effective_room_size != current_room_size else maxi(1, _enemy_clamp_frame_stride)
	if not room_size_changed and (_enemy_clamp_frame_cursor % stride) != 0:
		return
	var half := current_effective_room_size * 0.5
	var stale_entries := false
	for enemy_body in _enemy_clamp_cached_nodes:
		if not is_instance_valid(enemy_body):
			stale_entries = true
			continue
		enemy_body.global_position.x = clampf(enemy_body.global_position.x, -half.x, half.x)
		enemy_body.global_position.y = clampf(enemy_body.global_position.y, -half.y, half.y)
	if stale_entries:
		_refresh_enemy_clamp_cache()

func _keep_player_inside_camera_view() -> void:
	if not is_instance_valid(player):
		return
	if not is_instance_valid(player_camera):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var half_view := Vector2(
		viewport_size.x * 0.5 / maxf(0.001, player_camera.zoom.x),
		viewport_size.y * 0.5 / maxf(0.001, player_camera.zoom.y)
	)
	var min_visible := player_camera.global_position - half_view + Vector2.ONE * camera_player_margin
	var max_visible := player_camera.global_position + half_view - Vector2.ONE * camera_player_margin

	player.global_position.x = clampf(player.global_position.x, min_visible.x, max_visible.x)
	player.global_position.y = clampf(player.global_position.y, min_visible.y, max_visible.y)

func _update_encounter_state() -> void:
	if MultiplayerSessionManager.is_remote_replica():
		return
	if choosing_next_room or run_cleared:
		return
	if _is_reward_selection_active():
		return
	if current_room_label == "Starting Chamber":
		return
	if encounter_intro_grace_active:
		return
	if objective_manager.has_active_objective():
		return
	if active_room_enemy_count > 0:
		return
	if _world_multiplayer_sync_state.is_current_room_clear_processed():
		return
	_on_room_cleared()

func _on_room_cleared() -> void:
	if not is_instance_valid(encounter_flow_system):
		return
	_end_combat_phase()
	_try_revive_fallen_multiplayer_players()
	var cleared_boss_id: String = run_summary_recorder.get_active_boss_id()
	if not cleared_boss_id.is_empty():
		run_summary_recorder.close_active_room({
			"boss_id": cleared_boss_id,
			"boss_cleared": true
		})
	else:
		run_summary_recorder.close_active_room()
	if in_second_boss_room:
		_world_multiplayer_sync_state.mark_current_room_clear_processed()
		_finish_second_boss_clear()
		return
	if in_third_boss_room:
		_world_multiplayer_sync_state.mark_current_room_clear_processed()
		_finish_third_boss_clear()
		return
	if in_boss_room and not first_boss_defeated:
		_world_multiplayer_sync_state.mark_current_room_clear_processed()
		_finish_first_boss_clear()
		return
	if is_instance_valid(player):
		player.tick_objective_mutators_for_encounter()
	var outcome: Dictionary = room_clear_outcome_coordinator.resolve_outcome(
		encounter_flow_system,
		in_boss_room,
		pending_room_reward,
		rooms_cleared,
		room_depth,
		encounter_count
	)
	if outcome.is_empty():
		return
	var outcome_state: Dictionary = room_clear_outcome_coordinator.process_outcome({
		"outcome": outcome,
		"in_boss_room": in_boss_room,
		"endless_mode": _is_endless_mode(),
		"endless_boss_defeated": endless_boss_defeated,
		"first_boss_defeated": first_boss_defeated,
		"second_boss_defeated": second_boss_defeated,
		"can_unlock_second": _is_second_boss_unlocked(),
		"can_unlock_third": _is_third_boss_unlocked(),
		"rooms_cleared": rooms_cleared,
		"room_depth": room_depth,
		"boss_unlocked": boss_unlocked,
		"pending_room_reward": pending_room_reward,
		"choosing_next_room": choosing_next_room
	})
	if not bool(outcome_state.get("ok", false)):
		return
	_world_multiplayer_sync_state.mark_current_room_clear_processed()
	run_cleared = bool(outcome_state.get("run_cleared", run_cleared))
	in_boss_room = bool(outcome_state.get("in_boss_room", in_boss_room))
	endless_boss_defeated = bool(outcome_state.get("endless_boss_defeated", endless_boss_defeated))
	rooms_cleared = int(outcome_state.get("rooms_cleared", rooms_cleared))
	var outcome_depth := int(outcome_state.get("room_depth", room_depth))
	if outcome_depth > 50:
		push_error("[Room Outcome] Warning: extremely high room_depth from outcome: %d (rooms_cleared=%d)" % [outcome_depth, rooms_cleared])
	room_depth = outcome_depth
	boss_unlocked = bool(outcome_state.get("boss_unlocked", boss_unlocked))
	pending_room_reward = int(outcome_state.get("pending_room_reward", pending_room_reward))
	choosing_next_room = bool(outcome_state.get("choosing_next_room", choosing_next_room))
	phase_two_rooms_cleared += int(outcome_state.get("phase_two_increment", 0))
	phase_three_rooms_cleared += int(outcome_state.get("phase_three_increment", 0))
	_clamp_room_depth_to_sane_range()
	if bool(outcome_state.get("show_endless_boss_banner", false)):
		hud.show_banner("Boss Defeated", "")
	if bool(outcome_state.get("terminal_run_cleared", false)):
		return
	var reward_mode: int = int(outcome_state.get("open_reward_mode", ENUMS.RewardMode.NONE))
	if reward_mode == ENUMS.RewardMode.BOON:
		_open_networked_reward_selection("Choose Boon Reward", ENUMS.RewardMode.BOON)
		return
	if reward_mode == ENUMS.RewardMode.MISSION:
		_open_networked_reward_selection("Choose Mission Reward", ENUMS.RewardMode.MISSION, current_room_player_mutator)
		return
	if reward_mode == ENUMS.RewardMode.ARCANA:
		_open_networked_reward_selection("Choose Arcana", ENUMS.RewardMode.ARCANA)
		return
	if bool(outcome_state.get("spawn_doors", false)):
		_spawn_door_options()

func _clamp_room_depth_to_sane_range() -> void:
	var max_sane := _get_third_boss_target_depth() + 2
	if room_depth > max_sane:
		var now_usec := Time.get_ticks_usec()
		var should_log := room_depth != _depth_sanity_last_logged_depth or now_usec - _depth_sanity_last_log_usec >= 2000000
		if should_log:
			push_warning("[Depth Sanity] Clamping high room_depth %d -> %d (rooms_cleared=%d, bosses: 1st=%s, 2nd=%s, 3rd=%s)" % [
				room_depth, max_sane, rooms_cleared,
				first_boss_defeated, second_boss_defeated, second_boss_defeated
			])
			_depth_sanity_last_logged_depth = room_depth
			_depth_sanity_last_log_usec = now_usec
		room_depth = max_sane

func _finish_first_boss_clear() -> void:
	in_boss_room = false
	first_boss_defeated = true
	in_second_boss_room = false
	in_third_boss_room = false
	phase_two_rooms_cleared = 0
	phase_three_rooms_cleared = 0
	rooms_cleared += 1
	room_depth += 1
	_clamp_room_depth_to_sane_range()
	boss_unlocked = false
	pending_room_reward = ENUMS.RewardMode.NONE
	last_defeated_boss_id = "warden"
	run_summary_recorder.record_boss_defeat(last_defeated_boss_id)
	boss_reward_pending = true
	hud.show_banner("Warden Defeated", "")
	var epitaph: String = power_registry_instance.get_boss_epitaph("warden", current_character_id)
	_open_networked_reward_selection("Claim Warden's Power", ENUMS.RewardMode.BOSS, {}, epitaph)

func _finish_second_boss_clear() -> void:
	in_second_boss_room = false
	second_boss_defeated = true
	active_room_enemy_count = 0
	choosing_next_room = false
	rooms_cleared += 1
	room_depth += 1
	_clamp_room_depth_to_sane_range()
	boss_unlocked = false
	pending_room_reward = ENUMS.RewardMode.NONE
	phase_three_rooms_cleared = 0
	last_defeated_boss_id = "sovereign"
	run_summary_recorder.record_boss_defeat(last_defeated_boss_id)
	boss_reward_pending = true
	hud.show_banner("Sovereign Defeated", "")
	var epitaph: String = power_registry_instance.get_boss_epitaph("sovereign", current_character_id)
	_open_networked_reward_selection("Claim Sovereign's Power", ENUMS.RewardMode.BOSS, {}, epitaph)

func _finish_third_boss_clear() -> void:
	in_third_boss_room = false
	active_room_enemy_count = 0
	run_cleared = true
	choosing_next_room = false
	boss_unlocked = false
	pending_room_reward = ENUMS.RewardMode.NONE
	_clear_active_run_checkpoint()
	last_defeated_boss_id = "lacuna"
	run_summary_recorder.record_boss_defeat(last_defeated_boss_id)
	hud.show_banner("Run Complete", "")
	var run_context := _get_run_context()
	var unlocked_tier := -1
	if run_context != null:
		run_context.set_last_run_outcome("clear")
		run_context.award_run_clear_unlocks()
		unlocked_tier = int(run_context.consume_just_unlocked_tier())
	if unlocked_tier >= 0:
		var unlock_config := DIFFICULTY_CONFIG.get_tier_config(unlocked_tier)
		run_summary_recorder.record_unlock("Unlocked Bearing: %s" % String(unlock_config.get("name", "Unknown")))
	run_summary_recorder.mark_full_clear_boss_credits()
	run_summary_recorder.finish_run("clear")
	if MultiplayerSessionManager.should_broadcast():
		if STAT_ATTRIBUTION_TRACE:
			print_debug("[StatAttribution][OutcomeSend] outcome=clear stats=%s" % str(run_summary_recorder.get_stats_by_peer()))
		_sync_run_outcome.rpc("clear", unlocked_tier, "", room_depth, run_summary_recorder.latest_run_summary, run_summary_recorder.get_stats_by_peer(), run_summary_recorder.get_latest_peer_summary_overrides())
	_show_victory_feedback(unlocked_tier, run_summary_recorder.latest_run_summary)

func _get_run_context() -> Node:
	return get_node_or_null(RUN_CONTEXT_PATH)

func _enqueue_leaderboard_submission(run_summary: Dictionary) -> void:
	if run_summary.is_empty():
		return
	var run_context := _get_run_context()
	if run_context == null:
		return
	if not run_context.has_method("enqueue_leaderboard_summary"):
		return
	run_context.enqueue_leaderboard_summary(run_summary)

func _get_difficulty_config_provider() -> Object:
	if is_multiplayer:
		if _multiplayer_difficulty_config == null:
			_multiplayer_difficulty_config = DIFFICULTY_CONFIG_MULTIPLAYER.new()
		return _multiplayer_difficulty_config
	return DIFFICULTY_CONFIG

func _resolve_current_difficulty_config(tier: int) -> Dictionary:
	var provider: Object = _get_difficulty_config_provider()
	if provider != null and provider.has_method("get_tier_config"):
		return provider.get_tier_config(tier)
	return DIFFICULTY_CONFIG.get_tier_config(tier)

func _get_multiplayer_party_size_for_scaling() -> int:
	if not is_multiplayer:
		return 1
	if not MultiplayerSessionManager.is_session_connected():
		return 1
	var session_info := MultiplayerSessionManager.get_session_info() if MultiplayerSessionManager.has_method("get_session_info") else {}
	var peer_count := int(session_info.get("connected_peer_count", 0))
	if peer_count <= 0 and MultiplayerSessionManager.has_method("get_peer_ids"):
		peer_count = (MultiplayerSessionManager.get_peer_ids() as Array).size()
	if peer_count <= 0:
		peer_count = _get_multiplayer_player_nodes().size()
	return clampi(peer_count, 1, 4)

func _get_multiplayer_health_scaling_mult(is_boss: bool) -> float:
	var party_size := _get_multiplayer_party_size_for_scaling()
	if party_size <= 1:
		return 1.0
	var per_extra_key := "coop_boss_health_per_extra_player" if is_boss else "coop_enemy_health_per_extra_player"
	var curve_power_key := "coop_boss_health_curve_power" if is_boss else "coop_enemy_health_curve_power"
	var cap_key := "coop_boss_health_max_mult" if is_boss else "coop_enemy_health_max_mult"
	var per_extra := maxf(0.0, float(current_difficulty_config.get(per_extra_key, 0.0)))
	if per_extra <= 0.0:
		return 1.0
	var curve_power := maxf(0.01, float(current_difficulty_config.get(curve_power_key, 1.0)))
	var cap_mult := maxf(1.0, float(current_difficulty_config.get(cap_key, 4.0)))
	var extras := float(party_size - 1)
	var health_mult := 1.0 + per_extra * pow(extras, curve_power)
	return clampf(health_mult, 1.0, cap_mult)

func _build_multiplayer_enemy_durability_mutator() -> Dictionary:
	if not is_multiplayer:
		return {}
	var health_mult := _get_multiplayer_health_scaling_mult(false)
	if health_mult <= 1.001:
		return {}
	return {
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_ID: "coop_durability_scaling",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME: "Co-op Fortification",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_TARGET_SCOPE: "enemy",
		ENCOUNTER_CONTRACTS.MUTATOR_STAT_ENEMY_HEALTH_MULT: health_mult
	}

func _apply_difficulty_tier_bonuses(difficulty_tier: int) -> void:
	if not is_instance_valid(player):
		return
	
	current_difficulty_tier = difficulty_tier
	current_difficulty_config = _resolve_current_difficulty_config(difficulty_tier)
	var difficulty_config := current_difficulty_config
	var encounter_target := int(difficulty_config.get("encounter_count_before_boss", encounter_count))
	if encounter_target > 0:
		encounter_count = encounter_target
		second_boss_encounter_count = maxi(1, encounter_target - 1)
		third_boss_encounter_count = maxi(1, encounter_target - 1)

	player.set_incoming_damage_taken_mult(float(difficulty_config.get("player_damage_taken_mult", 1.0)))
	player.set_incoming_contact_damage_mult(float(difficulty_config.get("enemy_contact_damage_mult", 1.0)))
	var health_bonus := float(difficulty_config.get("player_starting_health_bonus", 0.0))
	if health_bonus > 0.0:
		var current_max: int = int(player.get_max_health())
		var new_max: int = current_max + int(health_bonus)
		player.set_max_health_and_current(new_max, new_max)

func _get_second_boss_target_depth() -> int:
	return maxi(encounter_count + 1, encounter_count * 2)

func _get_third_boss_target_depth() -> int:
	return maxi(_get_second_boss_target_depth() + 1, _get_second_boss_target_depth() + third_boss_encounter_count + 1)

func _build_route_context(depth: int) -> Dictionary:
	var target_depth := encounter_count
	if second_boss_defeated:
		target_depth = _get_third_boss_target_depth()
	elif first_boss_defeated:
		target_depth = _get_second_boss_target_depth()
	return {
		"depth": depth,
		"rooms_until_boss": maxi(0, target_depth - depth)
	}

func _is_second_boss_unlocked() -> bool:
	return first_boss_defeated and not second_boss_defeated and room_depth >= _get_second_boss_target_depth()

func _is_third_boss_unlocked() -> bool:
	return second_boss_defeated and room_depth >= _get_third_boss_target_depth()

func _get_boss_difficulty_mult() -> float:
	if current_difficulty_config.is_empty():
		return 1.0
	return float(current_difficulty_config.get("boss_difficulty_mult", 1.0))

func _objective_pressure_mult() -> float:
	return DIFFICULTY_CONFIG.get_objective_pressure_mult(current_difficulty_tier)

func _apply_boss_difficulty_scaling(boss: CharacterBody2D) -> void:
	if not is_instance_valid(boss):
		return
	var boss_mult := _get_boss_difficulty_mult()
	var boss_health_mult := boss_mult * _get_multiplayer_health_scaling_mult(true)
	if is_equal_approx(boss_mult, 1.0) and is_equal_approx(boss_health_mult, 1.0):
		return
	var base_max_health: int = int(boss.get_max_health())
	var scaled_max_health := maxi(1, int(round(float(base_max_health) * boss_health_mult)))
	boss.set_max_health_and_current(scaled_max_health, scaled_max_health)
	for damage_property in ["charge_damage", "nova_damage", "cleave_damage", "prism_damage", "gravity_damage", "echo_dash_damage", "orbital_lance_damage", "polar_shift_pull_inner_damage", "sever_damage", "null_ring_damage", "gap_damage", "echo_cross_damage", "seam_tick_damage"]:
		if boss.get(damage_property) == null:
			continue
		var base_damage := int(boss.get(damage_property))
		boss.set(damage_property, maxi(1, int(round(float(base_damage) * boss_mult))))

func _try_resume_saved_run() -> bool:
	var run_context := _get_run_context()
	if run_context == null:
		return false

	var should_apply_difficulty := false
	if is_multiplayer:
		## Multiplayer: get difficulty from multiplayer tier
		current_difficulty_tier = int(run_context.get_multiplayer_difficulty_tier())
		multiplayer_encounter_seed = rng.randi_range(1, 999999)
		encounter_profile_builder.initialize_with_seed(rng, multiplayer_encounter_seed)
		## Never apply singleplayer run snapshots in multiplayer sessions.
		## Snapshot payload can contain stale per-character combat stats from prior runs.
		current_character_id = String(run_context.get_selected_character_id()).strip_edges().to_lower()
		if current_character_id.is_empty():
			current_character_id = CHARACTER_REGISTRY.get_default_character_id()
		should_apply_difficulty = true
		if should_apply_difficulty:
			_apply_difficulty_tier_bonuses(current_difficulty_tier)
		return false
	else:
		current_difficulty_tier = int(run_context.get_current_difficulty_tier())
	current_character_id = String(run_context.get_selected_character_id()).strip_edges().to_lower()
	should_apply_difficulty = true
	if should_apply_difficulty:
		_apply_difficulty_tier_bonuses(current_difficulty_tier)

	var snapshot := run_context.load_active_run() as Dictionary
	if snapshot.is_empty():
		return false
	if int(snapshot.get("version", -1)) != RUN_SNAPSHOT_VERSION:
		run_context.clear_active_run()
		return false
	if not _apply_active_run_snapshot(snapshot):
		run_context.clear_active_run()
		return false
	return true

func _save_active_run_checkpoint() -> void:
	var run_context := _get_run_context()
	if run_context == null:
		return
	var snapshot := _build_active_run_snapshot()
	if snapshot.is_empty():
		return
	run_context.save_active_run(snapshot)

func _clear_active_run_checkpoint() -> void:
	var run_context := _get_run_context()
	if run_context == null:
		return
	run_context.clear_active_run()
	run_context.clear_resume_saved_run_request()

func _build_active_run_snapshot() -> Dictionary:
	var run_context := _get_run_context()
	var fallback_run_mode: Variant = ENUMS.RunMode.ENDLESS if _is_endless_mode() else ENUMS.RunMode.STANDARD
	return RUN_SNAPSHOT_SERVICE.build_snapshot(self, player, run_context, RUN_SNAPSHOT_VERSION, fallback_run_mode)

func _apply_active_run_snapshot(snapshot: Dictionary) -> bool:
	var run_context := _get_run_context()
	if not RUN_SNAPSHOT_SERVICE.apply_snapshot(
		self,
		player,
		run_context,
		snapshot,
		room_base_size,
		ENUMS.RunMode.STANDARD,
		ENUMS.RewardMode.NONE
	):
		return false

	_clear_all_enemies()
	player_flow_coordinator.reset_player_position(player)
	_reset_effective_room_bounds()
	_apply_camera_bounds_for_room(current_effective_room_size)
	_play_room_music(false, false)
	hud.refresh(_get_hud_state(), player)
	_set_combat_paused(false)
	return true

func _is_endless_mode() -> bool:
	var run_context := _get_run_context()
	if run_context == null:
		return false
	return bool(run_context.is_endless_mode())

func _sync_audio_settings_from_context() -> void:
	var run_context := _get_run_context()
	if run_context == null:
		return
	var music_volume_value: Variant = run_context.get("music_volume_db")
	if music_volume_value != null:
		music_volume_db = AUDIO_LEVELS.clamp_db(float(music_volume_value))
	var sfx_volume_value: Variant = run_context.get("sfx_volume_db")
	if sfx_volume_value != null:
		sfx_volume_db = AUDIO_LEVELS.clamp_db(float(sfx_volume_value))
	_set_sfx_volume_runtime(sfx_volume_db)

func _is_reward_selection_active() -> bool:
	return is_instance_valid(reward_selection_ui) and reward_selection_ui.is_active()

func _set_music_volume_runtime(music_db: float) -> void:
	music_volume_db = AUDIO_LEVELS.clamp_db(music_db)
	if is_instance_valid(music_system):
		music_system.set_music_volume_db(music_volume_db)

func _set_sfx_volume_runtime(volume_db: float) -> void:
	sfx_volume_db = AUDIO_LEVELS.clamp_db(volume_db)
	if is_instance_valid(player):
		player.set_sfx_volume_db(sfx_volume_db)

func _on_pause_menu_opened() -> void:
	_set_combat_paused(true)

func _on_pause_menu_closed() -> void:
	_set_combat_paused(_is_reward_selection_active())

func _on_build_detail_opened() -> void:
	_set_combat_paused(true)

func _on_build_detail_closed() -> void:
	_set_combat_paused(false)

func _on_victory_back_to_menu() -> void:
	_teardown_multiplayer_session_for_menu_transition()
	run_summary_recorder.finish_run("clear")
	_clear_active_run_checkpoint()
	get_tree().change_scene_to_file(MENU_SCENE_PATH)

func _on_victory_retry_run() -> void:
	_retry_current_run()

func _on_defeat_back_to_menu() -> void:
	_teardown_multiplayer_session_for_menu_transition()
	_set_combat_paused(false)
	run_summary_recorder.finish_run("death")
	_clear_active_run_checkpoint()
	get_tree().change_scene_to_file(MENU_SCENE_PATH)

func _on_defeat_retry_run() -> void:
	_retry_current_run()

func _retry_current_run() -> void:
	_teardown_multiplayer_session_for_menu_transition()
	_set_combat_paused(false)
	_clear_active_run_checkpoint()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_pause_back_to_menu_requested() -> void:
	_teardown_multiplayer_session_for_menu_transition()
	run_summary_recorder.finish_run("menu_exit")
	player_flow_coordinator.prepare_for_menu_transition(combat_phase_coordinator, player, get_tree(), pause_menu_controller)
	get_tree().change_scene_to_file(MENU_SCENE_PATH)

func _on_pause_abandon_run_requested() -> void:
	_teardown_multiplayer_session_for_menu_transition()
	player_flow_coordinator.prepare_for_menu_transition(combat_phase_coordinator, player, get_tree(), pause_menu_controller)
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null:
		run_context.set_last_run_outcome("death")
	run_summary_recorder.finish_run("abandon")
	_clear_active_run_checkpoint()
	get_tree().change_scene_to_file(MENU_SCENE_PATH)

func _teardown_multiplayer_session_for_menu_transition() -> void:
	if not is_multiplayer:
		return
	var multiplayer_session_manager := get_node_or_null("/root/MultiplayerSessionManager")
	if multiplayer_session_manager != null and multiplayer_session_manager.has_method("leave_room"):
		multiplayer_session_manager.leave_room()
	var run_context := _get_run_context()
	if run_context != null:
		if run_context.has_method("clear_multiplayer_session"):
			run_context.clear_multiplayer_session()
		if run_context.has_method("suppress_menu_multiplayer_dev_autostart"):
			run_context.suppress_menu_multiplayer_dev_autostart()

func _on_pause_exit_game_requested() -> void:
	run_summary_recorder.finish_run("quit")
	get_tree().quit()

func _spawn_door_options() -> void:
	if MultiplayerSessionManager.is_remote_replica():
		return
	if not is_instance_valid(encounter_flow_system):
		return
	if _is_reward_selection_active():
		return
	if is_multiplayer and not _doors_spawn_ready:
		return
	if choosing_next_room and not door_options.is_empty():
		return
	combat_phase_coordinator.clear_player_lingering_effects(player)
	door_options.clear()
	var route_options := _roll_route_options(_build_route_context(room_depth))
	var route_state: Dictionary = encounter_route_controller.build_route_state(
		choosing_next_room,
		door_options,
		boss_unlocked,
		first_boss_defeated,
		second_boss_defeated,
		room_depth,
		door_distance_from_center,
		route_options,
		_is_second_boss_unlocked(),
		_is_third_boss_unlocked()
	)
	if not bool(route_state.get("ok", false)):
		return
	choosing_next_room = bool(route_state.get("choosing_next_room", true))
	door_options = route_state.get("door_options", [])
	boss_unlocked = bool(route_state.get("boss_unlocked", boss_unlocked))
	if MultiplayerSessionManager.should_broadcast():
		_sync_door_options.rpc(door_options, choosing_next_room, boss_unlocked, _build_progress_sync_state())
	_save_active_run_checkpoint()

func _try_use_door() -> void:
	if not choosing_next_room:
		return
	var local_player := _find_local_player_node()
	if not is_instance_valid(local_player):
		return
	if not Input.is_action_just_pressed("interact"):
		return
	if not is_instance_valid(encounter_flow_system):
		return
	var used_door: Dictionary = encounter_route_controller.find_used_door(local_player.global_position, door_options, door_use_radius)
	if used_door.is_empty():
		return
	if MultiplayerSessionManager.is_remote_replica():
		# Optimistically hide doors on joiner while host resolves the authoritative choice.
		choosing_next_room = false
		door_options.clear()
		_world_multiplayer_sync_state.begin_authoritative_door_wait()
		_request_use_door.rpc_id(1, used_door.duplicate(true))
		return
	if MultiplayerSessionManager.should_broadcast():
		_choose_door(used_door)
		_sync_chosen_door.rpc(used_door, _build_progress_sync_state())
		return
	_choose_door(used_door)

@rpc("reliable", "any_peer")
func _request_use_door(requested_door: Dictionary = {}) -> void:
	if not MultiplayerSessionManager.should_broadcast():
		return
	if not choosing_next_room:
		return
	var sender_peer_id := get_tree().get_multiplayer().get_remote_sender_id()
	if sender_peer_id <= 0:
		return
	var used_door := _find_authoritative_door_option(requested_door)
	if used_door.is_empty():
		_sync_door_options.rpc(door_options, choosing_next_room, boss_unlocked, _build_progress_sync_state())
		return
	_choose_door(used_door)
	_sync_chosen_door.rpc(used_door, _build_progress_sync_state())

func _find_authoritative_door_option(requested_door: Dictionary) -> Dictionary:
	if requested_door.is_empty():
		return {}
	for door_option in door_options:
		if not (door_option is Dictionary):
			continue
		var candidate := door_option as Dictionary
		if ENCOUNTER_CONTRACTS.door_option_kind_id(candidate) != ENCOUNTER_CONTRACTS.door_option_kind_id(requested_door):
			continue
		if ENCOUNTER_CONTRACTS.door_option_reward_mode(candidate) != ENCOUNTER_CONTRACTS.door_option_reward_mode(requested_door):
			continue
		if ENCOUNTER_CONTRACTS.door_option_get_position(candidate).distance_squared_to(ENCOUNTER_CONTRACTS.door_option_get_position(requested_door)) > 1.0:
			continue
		if ENCOUNTER_CONTRACTS.door_option_profile(candidate) != ENCOUNTER_CONTRACTS.door_option_profile(requested_door):
			continue
		return candidate.duplicate(true)
	return {}

@rpc("reliable", "authority")
func _sync_door_options(synced_door_options: Array, synced_choosing_next_room: bool, synced_boss_unlocked: bool, progress_state: Dictionary = {}) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	var sanitized_progress_state := _sanitize_progress_sync_state(progress_state)
	if bool(sanitized_progress_state.get("invalid", false)):
		_world_multiplayer_sync_state.pending_door_sync_payload.clear()
		return
	if not _can_apply_client_door_sync() or _should_defer_client_door_sync_payload(synced_choosing_next_room, sanitized_progress_state):
		_world_multiplayer_sync_state.pending_door_sync_payload = {
			"door_options": synced_door_options.duplicate(true),
			"choosing_next_room": synced_choosing_next_room,
			"boss_unlocked": synced_boss_unlocked,
			"progress_state": sanitized_progress_state
		}
		return
	_apply_synced_door_options_payload(synced_door_options, synced_choosing_next_room, synced_boss_unlocked, sanitized_progress_state)

@rpc("reliable", "authority")
func _sync_chosen_door(chosen_door: Dictionary, progress_state: Dictionary = {}) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	var sanitized_progress_state := _sanitize_progress_sync_state(progress_state)
	if bool(sanitized_progress_state.get("invalid", false)):
		return
	if _is_reward_selection_active() or current_room_label == "Starting Chamber":
		_world_multiplayer_sync_state.pending_chosen_door = chosen_door.duplicate(true)
		_world_multiplayer_sync_state.pending_chosen_progress_state = sanitized_progress_state
		return
	_world_multiplayer_sync_state.clear_authoritative_door_wait()
	_choose_door(chosen_door)
	_apply_progress_sync_state(sanitized_progress_state)
	_flush_pending_client_door_syncs()

@rpc("reliable", "authority")
func _sync_objective_spawn_batch(spawn_batch: Array, synced_enemy_count: int, source_room_label: String = "", source_room_sync_id: int = 0) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	if _world_multiplayer_sync_state.is_objective_already_cleared_for_sync_id(source_room_sync_id):
		return
	if _world_multiplayer_sync_state.is_stale_room_sync_id(source_room_sync_id):
		return
	var payload := {
		"spawn_batch": spawn_batch.duplicate(true),
		"synced_enemy_count": synced_enemy_count,
		"room_label": source_room_label,
		"room_sync_id": source_room_sync_id
	}
	if not _can_apply_client_spawn_sync(payload):
		_world_multiplayer_sync_state.enqueue_pending_objective_spawn_sync_payload(payload)
		return
	_apply_synced_objective_spawn_batch_payload(payload)

@rpc("reliable", "authority")
func _sync_objective_control_zone(control_anchor: Vector2, control_radius: float, control_goal: float, control_decay_rate: float, control_contest_threshold: int) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	if not is_instance_valid(objective_manager):
		return
	objective_manager.control_anchor = control_anchor
	objective_manager.control_radius = control_radius
	objective_manager.control_goal = control_goal
	objective_manager.control_decay_rate = control_decay_rate
	objective_manager.control_contest_threshold = control_contest_threshold
	queue_redraw()

@rpc("unreliable", "authority")
func _sync_objective_control_zone_state(control_progress: float, control_enemies_in_zone: int, control_contested: bool, control_player_inside: bool) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	if not is_instance_valid(objective_manager):
		return
	objective_manager.control_progress = maxf(0.0, control_progress)
	objective_manager.control_enemies_in_zone = maxi(0, control_enemies_in_zone)
	objective_manager.control_contested = control_contested
	objective_manager.control_player_inside = control_player_inside
	queue_redraw()

@rpc("reliable", "authority")
func _sync_objective_cleared() -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	_world_multiplayer_sync_state.mark_objective_cleared_for_current_room()
	if is_instance_valid(objective_manager):
		objective_manager.reset()
	_world_multiplayer_sync_state.clear_pending_objective_spawn_sync_payloads()
	_clear_all_enemies()
	active_room_enemy_count = 0
	queue_redraw()

@rpc("unreliable", "authority")
func _sync_objective_state(objective_state: Dictionary, source_room_sync_id: int, sequence: int) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	if not is_instance_valid(objective_manager):
		return
	if objective_state.is_empty():
		return
	if _world_multiplayer_sync_state.is_stale_room_sync_id(source_room_sync_id):
		return
	if sequence <= _last_applied_objective_state_sync_sequence:
		return
	_last_applied_objective_state_sync_sequence = sequence
	objective_manager.apply_sync_state(objective_state)
	queue_redraw()

func _build_progress_sync_state() -> Dictionary:
	return {
		"room_sync_id": _world_multiplayer_sync_state.current_room_sync_id,
		"rooms_cleared": rooms_cleared,
		"room_depth": room_depth,
		"phase_two_rooms_cleared": phase_two_rooms_cleared,
		"phase_three_rooms_cleared": phase_three_rooms_cleared,
		"boss_unlocked": boss_unlocked,
		"first_boss_defeated": first_boss_defeated,
		"second_boss_defeated": second_boss_defeated,
		"in_boss_room": in_boss_room,
		"in_second_boss_room": in_second_boss_room,
		"in_third_boss_room": in_third_boss_room,
		"choosing_next_room": choosing_next_room
	}

func _sanitize_progress_sync_state(progress_state: Dictionary) -> Dictionary:
	if progress_state.is_empty():
		return {}
	var sanitized := progress_state.duplicate(true)
	var incoming_room_sync_id := int(sanitized.get("room_sync_id", _world_multiplayer_sync_state.current_room_sync_id))
	if _world_multiplayer_sync_state.is_stale_room_sync_id(incoming_room_sync_id):
		sanitized["invalid"] = true
		return sanitized
	if _world_multiplayer_sync_state.is_sync_id_too_far_ahead(incoming_room_sync_id, 4):
		sanitized["invalid"] = true
		return sanitized
	var incoming_first_boss_defeated := bool(sanitized.get("first_boss_defeated", first_boss_defeated))
	var incoming_second_boss_defeated := bool(sanitized.get("second_boss_defeated", second_boss_defeated))
	if not incoming_first_boss_defeated:
		incoming_second_boss_defeated = false
	var max_depth := _get_second_boss_target_depth()
	if incoming_second_boss_defeated:
		max_depth = _get_third_boss_target_depth() + 1
	elif incoming_first_boss_defeated:
		max_depth = _get_third_boss_target_depth()
	var incoming_room_depth := int(sanitized.get("room_depth", room_depth))
	incoming_room_depth = clampi(incoming_room_depth, 0, maxi(1, max_depth))
	if rooms_cleared <= 1 and incoming_room_depth > 3:
		sanitized["invalid"] = true
		return sanitized
	# Allow large depth jumps if joiner just joined (rooms_cleared == 0) OR if explicitly awaiting door choice.
	# This permits joiners mid-run to synchronize with the host's current depth.
	var is_joiner_initial_sync := MultiplayerSessionManager.is_authoritative() or (MultiplayerSessionManager.is_remote_replica() and rooms_cleared == 0)
	if incoming_room_depth > room_depth + 2 and not _world_multiplayer_sync_state.awaiting_authoritative_door_choice and not is_joiner_initial_sync:
		sanitized["invalid"] = true
		return sanitized
	var incoming_rooms_cleared := int(sanitized.get("rooms_cleared", rooms_cleared))
	incoming_rooms_cleared = clampi(incoming_rooms_cleared, 0, incoming_room_depth)
	var incoming_phase_two := int(sanitized.get("phase_two_rooms_cleared", phase_two_rooms_cleared))
	incoming_phase_two = clampi(incoming_phase_two, 0, maxi(0, second_boss_encounter_count))
	var incoming_phase_three := int(sanitized.get("phase_three_rooms_cleared", phase_three_rooms_cleared))
	incoming_phase_three = clampi(incoming_phase_three, 0, maxi(0, third_boss_encounter_count))
	sanitized["room_sync_id"] = incoming_room_sync_id
	sanitized["rooms_cleared"] = incoming_rooms_cleared
	sanitized["room_depth"] = incoming_room_depth
	sanitized["phase_two_rooms_cleared"] = incoming_phase_two
	sanitized["phase_three_rooms_cleared"] = incoming_phase_three
	sanitized["first_boss_defeated"] = incoming_first_boss_defeated
	sanitized["second_boss_defeated"] = incoming_second_boss_defeated
	sanitized.erase("invalid")
	return sanitized

func _apply_progress_sync_state(progress_state: Dictionary) -> void:
	var sanitized_progress_state := _sanitize_progress_sync_state(progress_state)
	if sanitized_progress_state.is_empty():
		return
	if bool(sanitized_progress_state.get("invalid", false)):
		return
	# Clear joiner-join flag once first valid sync is received.
	if _world_multiplayer_sync_state.joiner_awaiting_initial_sync:
		_world_multiplayer_sync_state.joiner_awaiting_initial_sync = false
		print_debug("[Multiplayer] Joiner received initial progress sync")
	
	var incoming_depth := int(sanitized_progress_state.get("room_depth", room_depth))
	var max_sane_depth := _get_third_boss_target_depth() + 2
	if incoming_depth > max_sane_depth:
		push_error("[Progress Sync] Rejected impossibly high incoming depth %d (max sane: %d)" % [incoming_depth, max_sane_depth])
		return
	
	_world_multiplayer_sync_state.merge_current_room_sync_id(int(sanitized_progress_state.get("room_sync_id", _world_multiplayer_sync_state.current_room_sync_id)))
	rooms_cleared = int(sanitized_progress_state.get("rooms_cleared", rooms_cleared))
	room_depth = incoming_depth
	_clamp_room_depth_to_sane_range()
	phase_two_rooms_cleared = int(sanitized_progress_state.get("phase_two_rooms_cleared", phase_two_rooms_cleared))
	phase_three_rooms_cleared = int(sanitized_progress_state.get("phase_three_rooms_cleared", phase_three_rooms_cleared))
	boss_unlocked = bool(sanitized_progress_state.get("boss_unlocked", boss_unlocked))
	first_boss_defeated = bool(sanitized_progress_state.get("first_boss_defeated", first_boss_defeated))
	second_boss_defeated = bool(sanitized_progress_state.get("second_boss_defeated", second_boss_defeated))
	in_boss_room = bool(sanitized_progress_state.get("in_boss_room", in_boss_room))
	in_second_boss_room = bool(sanitized_progress_state.get("in_second_boss_room", in_second_boss_room))
	in_third_boss_room = bool(sanitized_progress_state.get("in_third_boss_room", in_third_boss_room))
	choosing_next_room = bool(sanitized_progress_state.get("choosing_next_room", choosing_next_room))
	var enforce_local_door_safety := MultiplayerSessionManager.is_authoritative()
	if enforce_local_door_safety and (active_room_enemy_count > 0 or _is_reward_selection_active()):
		choosing_next_room = false
		door_options.clear()

func _get_player_for_peer(peer_id: int) -> Node2D:
	if is_instance_valid(player) and int(player.player_id) == peer_id:
		return player
	if is_instance_valid(second_player) and int(second_player.player_id) == peer_id:
		return second_player
	return null

func _choose_door(door: Dictionary) -> void:
	choosing_next_room = false
	door_options.clear()
	_clear_all_enemies()

	if not is_instance_valid(player):
		return
	player_flow_coordinator.reset_player_position(player)
	if not is_instance_valid(encounter_flow_system):
		return
	var choice: Dictionary = encounter_route_controller.resolve_choice(door)
	if choice.is_empty():
		return
	run_summary_recorder.record_door_choice(choice)
	var action_id: int = ENCOUNTER_CONTRACTS.door_choice_action_id(choice)
	if action_id == ENUMS.EncounterAction.BOSS:
		if second_boss_defeated:
			_begin_third_boss_room()
		elif first_boss_defeated:
			_begin_second_boss_room()
		else:
			_begin_boss_room()
		return
	if action_id == ENUMS.EncounterAction.REST:
		_enter_rest_site()
		return
	var profile: Dictionary = ENCOUNTER_CONTRACTS.door_choice_profile(choice)
	profile = _apply_endless_scaling_to_profile(profile)
	pending_room_reward = ENCOUNTER_CONTRACTS.door_choice_reward_mode(choice)
	current_room_enemy_mutator = profile.get("enemy_mutator", {})
	_begin_room(profile)

func _apply_endless_scaling_to_profile(profile: Dictionary) -> Dictionary:
	return ENDLESS_PROFILE_SCALER.apply_scaling(
		profile,
		_is_endless_mode(),
		endless_boss_defeated,
		room_depth,
		encounter_count,
		room_base_size,
		static_camera_room_threshold
	)

func _prepare_room_sync_transition() -> void:
	_world_multiplayer_sync_state.begin_room_transition(MultiplayerSessionManager.is_authoritative())

func get_current_room_sync_id() -> int:
	return _world_multiplayer_sync_state.current_room_sync_id

func _begin_room(profile: Dictionary) -> void:
	_doors_spawn_ready = false
	if profile.is_empty():
		return
	_prepare_room_sync_transition()
	choosing_next_room = false
	door_options.clear()
	encounter_intro_grace_active = false
	combat_phase_coordinator.begin_combat_phase(player, get_tree())
	in_boss_room = false
	in_second_boss_room = false
	in_third_boss_room = false
	objective_lifecycle_coordinator.reset_for_new_room(objective_manager, objective_runtime)
	_play_room_music(false)
	current_room_size = ENCOUNTER_CONTRACTS.profile_room_size(profile)
	_reset_effective_room_bounds()
	current_room_static_camera = ENCOUNTER_CONTRACTS.profile_static_camera(profile)
	current_room_label = ENCOUNTER_CONTRACTS.profile_label(profile)
	current_room_enemy_mutator = ENCOUNTER_CONTRACTS.profile_enemy_mutator(profile)
	current_room_player_mutator = ENCOUNTER_CONTRACTS.profile_player_mutator(profile)
	run_summary_recorder.record_room_entry("encounter", profile)
	var mutator_name := ENCOUNTER_CONTRACTS.mutator_name(current_room_enemy_mutator)
	var _room_subtitle := ""
	var sub_color := Color(0.78, 0.9, 1.0, 0.92)
	if not mutator_name.is_empty():
		var banner_suffix := ENCOUNTER_CONTRACTS.mutator_banner_suffix(current_room_enemy_mutator)
		_room_subtitle = mutator_name
		if not banner_suffix.is_empty():
			_room_subtitle += "  -  " + banner_suffix
		sub_color = ENCOUNTER_CONTRACTS.mutator_theme_color(current_room_enemy_mutator, sub_color)
		sub_color.a = 0.92
	hud.show_banner(current_room_label, "", sub_color)
	if is_instance_valid(enemy_spawner):
		enemy_spawner.configure_room(current_room_size, spawn_padding, spawn_safe_radius, current_room_enemy_mutator, _get_active_enemy_mutators_for_room())
	_apply_camera_bounds_for_room(current_effective_room_size)
	if is_multiplayer:
		if MultiplayerSessionManager.should_broadcast():
			var spawn_report: Array[Dictionary] = enemy_spawner.spawn_profile_enemies_report(profile)
			active_room_enemy_count = spawn_report.size()
			var spawn_batch: Array = []
			for spawn_entry in spawn_report:
				var enemy: Node2D = spawn_entry.get("enemy") as Node2D
				if not is_instance_valid(enemy):
					continue
				var enemy_id: int = enemy_state_sync_broadcaster.register_enemy(enemy)
				spawn_batch.append({
					"enemy_id": enemy_id,
					"enemy_type": String(spawn_entry.get("enemy_type", "")),
					"position": enemy.global_position
				})
			_sync_spawn_enemy_batch.rpc(spawn_batch, active_room_enemy_count, current_room_label, room_depth, _world_multiplayer_sync_state.current_room_sync_id)
		else:
			active_room_enemy_count = 0
			_flush_pending_client_spawn_syncs()
	else:
		active_room_enemy_count = _spawn_profile_enemies(profile)
	objective_lifecycle_coordinator.begin_for_new_room(objective_runtime, profile)
	_start_encounter_intro_grace()

func _apply_objective_spawn_meta(enemy: CharacterBody2D, spawn_meta: Dictionary) -> void:
	if not is_instance_valid(enemy):
		return
	var role := String(spawn_meta.get("role", "")).strip_edges()
	if role.is_empty():
		return
	if role == "cut_signal_target":
		if is_instance_valid(objective_runtime) and objective_runtime.has_method("configure_priority_target_enemy_from_sync"):
			objective_runtime.call("configure_priority_target_enemy_from_sync", enemy, spawn_meta)
		elif is_instance_valid(objective_manager):
			objective_manager.hunt_target_enemy = enemy

func _enter_rest_site() -> void:
	in_boss_room = false
	_play_room_music(false)
	current_room_label = "Rest Site"
	run_summary_recorder.record_room_entry("rest", {})
	hud.show_banner("Rest Site", "")
	current_room_static_camera = true
	if second_boss_defeated:
		rooms_cleared += 1
		room_depth += 1
		phase_three_rooms_cleared += 1
		boss_unlocked = _is_third_boss_unlocked()
		_clamp_room_depth_to_sane_range()
	elif first_boss_defeated:
		rooms_cleared += 1
		room_depth += 1
		phase_two_rooms_cleared += 1
		boss_unlocked = _is_second_boss_unlocked()
		_clamp_room_depth_to_sane_range()
	else:
		_advance_room_progress()
		_clamp_room_depth_to_sane_range()
	if is_instance_valid(player):
		var player_max_health: int = int(player.get_max_health())
		var heal_ratio_mult := float(current_difficulty_config.get("rest_heal_ratio_mult", 1.0))
		var heal_amount := maxi(8, int(round(float(player_max_health) * rest_heal_ratio * heal_ratio_mult)))
		player.heal(heal_amount)
		player.play_rest_site_heal_feedback()
	_spawn_door_options()

func _advance_room_progress() -> void:
	if not is_instance_valid(encounter_flow_system):
		return
	var progress: Dictionary = encounter_flow_system.advance_room_progress(rooms_cleared, room_depth, encounter_count)
	rooms_cleared = int(progress.get("rooms_cleared", rooms_cleared))
	room_depth = int(progress.get("room_depth", room_depth))
	boss_unlocked = bool(progress.get("boss_unlocked", boss_unlocked))

func _pick_boss_spawn_position(min_player_distance: float = 260.0, wall_margin: float = 210.0) -> Vector2:
	if rng == null:
		return Vector2.ZERO
	var half := current_room_size * 0.5
	var usable_half := Vector2(
		maxf(80.0, half.x - wall_margin),
		maxf(80.0, half.y - wall_margin)
	)
	var fallback := Vector2.ZERO
	for _try in range(80):
		var candidate := Vector2(
			rng.randf_range(-usable_half.x, usable_half.x),
			rng.randf_range(-usable_half.y, usable_half.y)
		)
		fallback = candidate
		if is_instance_valid(player) and candidate.distance_to(player.global_position) < min_player_distance:
			continue
		return candidate
	return fallback

func _begin_configured_boss_room(boss_stage: int, room_size: Vector2, room_label: String, room_entry_key: String, banner_title: String, boss_script, collision_radius: float, min_player_distance: float, wall_margin: float) -> void:
	_prepare_room_sync_transition()
	encounter_intro_grace_active = false
	combat_phase_coordinator.begin_combat_phase(player, get_tree())
	in_boss_room = boss_stage == 1
	in_second_boss_room = boss_stage == 2
	in_third_boss_room = boss_stage == 3
	_play_room_music(true)
	current_room_size = room_size
	_reset_effective_room_bounds()
	current_room_static_camera = false
	current_room_label = room_label
	current_room_enemy_mutator = {}
	current_room_player_mutator = {}
	run_summary_recorder.record_room_entry(room_entry_key, {})
	hud.show_banner(banner_title, "")
	_apply_camera_bounds_for_room(current_effective_room_size)
	active_room_enemy_count = 1
	if MultiplayerSessionManager.is_remote_replica():
		_start_encounter_intro_grace()
		_flush_pending_client_boss_spawn_syncs()
		return
	var boss := CharacterBody2D.new()
	boss.set_script(boss_script)

	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = CircleShape2D.new()
	collision_shape.shape.radius = collision_radius
	boss.add_child(collision_shape)

	boss.global_position = _pick_boss_spawn_position(min_player_distance, wall_margin)
	add_child(boss)
	boss.begin_spawn_transport(BOSS_SPAWN_TRANSPORT_DURATION)
	_assign_enemy_target_candidates(boss)
	boss.set("arena_size", current_room_size)
	_apply_boss_difficulty_scaling(boss)
	var boss_enemy_id: int = enemy_state_sync_broadcaster.register_enemy(boss)
	if boss.has_signal("died"):
		var captured_boss := boss
		boss.died.connect(func(): _on_room_enemy_died(captured_boss.global_position if is_instance_valid(captured_boss) else Vector2.ZERO))
	if boss.has_signal("damage_received"):
		boss.damage_received.connect(func(applied_amount: int, _remaining_health: int): _on_enemy_damage_received(applied_amount))
	if MultiplayerSessionManager.should_broadcast():
		_sync_spawn_boss.rpc({
			"boss_stage": boss_stage,
			"enemy_id": boss_enemy_id,
			"position": boss.global_position,
			"room_label": current_room_label,
			"room_sync_id": _world_multiplayer_sync_state.current_room_sync_id
		})
	_start_encounter_intro_grace()

func _begin_boss_room() -> void:
	_begin_configured_boss_room(
		1,
		Vector2(1260.0, 900.0),
		"Boss Chamber: The Warden",
		"warden",
		"The Warden",
		ENEMY_BOSS_SCRIPT,
		34.0,
		maxf(260.0, spawn_safe_radius + 90.0),
		maxf(210.0, spawn_padding + 110.0)
	)

func _begin_second_boss_room() -> void:
	_begin_configured_boss_room(
		2,
		Vector2(1360.0, 960.0),
		"Abyss Core: Sovereign",
		"sovereign",
		"Sovereign",
		ENEMY_BOSS_2_SCRIPT,
		38.0,
		maxf(280.0, spawn_safe_radius + 110.0),
		maxf(230.0, spawn_padding + 130.0)
	)

func _begin_third_boss_room() -> void:
	_begin_configured_boss_room(
		3,
		Vector2(1460.0, 1040.0),
		"Silent Threshold: Lacuna",
		"lacuna",
		"Lacuna",
		ENEMY_BOSS_3_SCRIPT,
		40.0,
		maxf(300.0, spawn_safe_radius + 130.0),
		maxf(250.0, spawn_padding + 150.0)
	)

func _spawn_profile_enemies(profile: Dictionary) -> int:
	if not is_instance_valid(enemy_spawner):
		return 0
	return int(enemy_spawner.spawn_profile_enemies(profile))

func _play_room_music(is_boss_room: bool, instant: bool = false, fade_duration: float = -1.0) -> void:
	if not is_instance_valid(music_system):
		return
	music_system.play_room_music(is_boss_room, instant, fade_duration)

func _on_room_enemy_died(kill_pos: Vector2 = Vector2.ZERO) -> void:
	active_room_enemy_count = maxi(0, active_room_enemy_count - 1)
	run_summary_recorder.record_enemy_kill_for_tracker()
	var objective_progress_result: Dictionary = objective_progress_coordinator.on_enemy_killed(objective_manager, objective_runtime, kill_pos)
	if bool(objective_progress_result.get("should_redraw", false)):
		queue_redraw()
	if is_instance_valid(player):
		player.notify_enemy_killed(kill_pos)

func _on_enemy_damage_received(_applied_amount: int) -> void:
	# Damage dealt tracking is now centralized in shared damage application paths.
	# Keep this handler for compatibility with older signal wiring.
	pass

func record_player_damage_dealt(applied_amount: int, source_peer_id: int = 0, _killed_enemy: bool = false, enemy_id: int = 0) -> void:
	run_summary_recorder.record_damage_dealt(applied_amount, source_peer_id)
	EnemyReplicationService.credit_damage(enemy_id, source_peer_id)

func _record_peer_enemy_kill(peer_id: int) -> void:
	run_summary_recorder.record_peer_enemy_kill(peer_id)

func _clear_all_enemies() -> void:
	EnemyReplicationService.clear_state()
	enemy_state_sync_broadcaster.clear_state()
	_archer_projectile_sync_elapsed = 0.0
	_enemy_clamp_cached_nodes.clear()
	_enemy_clamp_refresh_elapsed = 0.0
	if is_instance_valid(enemy_spawner):
		enemy_spawner.clear_all_enemies()

func _sync_archer_projectile_state_tick(delta: float) -> void:
	if not MultiplayerSessionManager.should_broadcast():
		return
	_archer_projectile_sync_elapsed += delta
	if _archer_projectile_sync_elapsed < maxf(0.008, archer_projectile_sync_interval_sec):
		return
	_archer_projectile_sync_elapsed = 0.0
	var synced_archer_projectiles: Array = []
	for enemy_id_variant in EnemyReplicationService.enemy_nodes_by_id.keys():
		var enemy_id := int(enemy_id_variant)
		var enemy := EnemyReplicationService.enemy_nodes_by_id.get(enemy_id) as Node
		if not is_instance_valid(enemy):
			continue
		if not enemy.has_method("get_projectile_network_sync_state"):
			continue
		var projectile_sync_state := enemy.call("get_projectile_network_sync_state") as Dictionary
		if projectile_sync_state.is_empty():
			continue
		synced_archer_projectiles.append({
			"enemy_id": enemy_id,
			"payload": projectile_sync_state
		})
	if synced_archer_projectiles.is_empty():
		return
	var mtu_safe_payload_budget: int = maxi(512, enemy_state_sync_broadcaster.transport_mtu_bytes - enemy_state_sync_broadcaster.transport_safety_margin_bytes)
	var payload_budget := mini(maxi(640, archer_projectile_sync_payload_budget_bytes), mtu_safe_payload_budget)
	var per_batch_overhead := 160
	var current_batch: Array = []
	var current_batch_bytes := 0
	for sync_entry_variant in synced_archer_projectiles:
		if not (sync_entry_variant is Dictionary):
			continue
		var sync_entry := sync_entry_variant as Dictionary
		var entry_size: int = enemy_state_sync_broadcaster.estimate_variant_size_bytes(sync_entry) + 24
		var would_exceed_budget := not current_batch.is_empty() and (current_batch_bytes + entry_size + per_batch_overhead > payload_budget)
		if would_exceed_budget:
			_sync_archer_projectile_states.rpc(current_batch, _world_multiplayer_sync_state.current_room_sync_id)
			current_batch.clear()
			current_batch_bytes = 0
		current_batch.append(sync_entry)
		current_batch_bytes += entry_size
	if not current_batch.is_empty():
		_sync_archer_projectile_states.rpc(current_batch, _world_multiplayer_sync_state.current_room_sync_id)

func _build_objective_state_sync_payload() -> Dictionary:
	if not is_instance_valid(objective_manager):
		return {}
	var objective_active := not String(objective_manager.active_objective_kind).is_empty()
	if not objective_active and not _objective_state_sync_was_active:
		return {}
	_objective_state_sync_was_active = objective_active
	return objective_manager.serialize_sync_state()

func _sync_objective_state_tick(delta: float) -> void:
	if not MultiplayerSessionManager.should_broadcast():
		return
	if not is_instance_valid(objective_manager):
		return
	_objective_state_sync_elapsed += delta
	var sync_interval := maxf(0.03, objective_state_sync_interval_sec)
	if _objective_state_sync_elapsed < sync_interval:
		return
	_objective_state_sync_elapsed = 0.0
	var objective_state := _build_objective_state_sync_payload()
	if objective_state.is_empty():
		return
	_objective_state_sync_sequence += 1
	_sync_objective_state.rpc(objective_state, _world_multiplayer_sync_state.current_room_sync_id, _objective_state_sync_sequence)

func _spawn_synced_pyre_death_field(effect_payload: Dictionary) -> void:
	if effect_payload.is_empty():
		return
	var parent_node := get_parent()
	if not is_instance_valid(parent_node):
		return
	var field := PYRE_FIELD_SCRIPT.new()
	parent_node.add_child(field)
	field.global_position = effect_payload.get("position", Vector2.ZERO) as Vector2
	field.initialize(
		null,
		float(effect_payload.get("radius", 94.0)),
		float(effect_payload.get("duration", 6.5)),
		float(effect_payload.get("tick_interval", 0.42)),
		0
	)


func request_enemy_damage_from_client(enemy_id: int, amount: int, damage_context: Dictionary = {}) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	if enemy_id <= 0 or amount <= 0:
		return
	_sync_request_enemy_damage.rpc_id(1, enemy_id, amount, damage_context)


@rpc("reliable", "any_peer")
func _sync_request_enemy_damage(enemy_id: int, amount: int, damage_context: Dictionary = {}) -> void:
	if not MultiplayerSessionManager.should_broadcast():
		return
	if enemy_id <= 0 or amount <= 0:
		return
	var enemy := EnemyReplicationService.enemy_nodes_by_id.get(enemy_id) as Node
	if not is_instance_valid(enemy):
		return
	if not enemy.has_method("take_damage"):
		return
	var sender_peer_id := get_tree().get_multiplayer().get_remote_sender_id()
	var source_peer_id := int(damage_context.get("source_peer_id", 0))
	if source_peer_id <= 0:
		source_peer_id = sender_peer_id
	if STAT_ATTRIBUTION_TRACE:
		print_debug("[StatAttribution][HostRecv] enemy_id=%d sender=%d source=%d amount=%d attack=%s" % [enemy_id, sender_peer_id, source_peer_id, amount, String(damage_context.get("attack_type", "unknown"))])
	var health_before := int(enemy.call("get_current_health")) if enemy.has_method("get_current_health") else -1
	if damage_context.is_empty():
		enemy.call("take_damage", amount)
	else:
		enemy.call("take_damage", amount, damage_context)
	EnemyReplicationService.credit_damage(enemy_id, source_peer_id)
	if health_before >= 0 and enemy.has_method("get_current_health"):
		var health_after := int(enemy.call("get_current_health"))
		if STAT_ATTRIBUTION_TRACE:
			print_debug("[StatAttribution][HostApplied] enemy_id=%d source=%d before=%d after=%d applied=%d" % [enemy_id, source_peer_id, health_before, health_after, maxi(0, health_before - health_after)])
		record_player_damage_dealt(maxi(0, health_before - health_after), source_peer_id, false, enemy_id)

func _spawn_boss_for_stage(boss_stage: int, spawn_position: Vector2) -> Node2D:
	var boss_script = null
	var collision_radius := 34.0
	match boss_stage:
		1:
			boss_script = ENEMY_BOSS_SCRIPT
			collision_radius = 34.0
		2:
			boss_script = ENEMY_BOSS_2_SCRIPT
			collision_radius = 38.0
		3:
			boss_script = ENEMY_BOSS_3_SCRIPT
			collision_radius = 40.0
		_:
			return null
	var boss := CharacterBody2D.new()
	boss.set_script(boss_script)
	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = CircleShape2D.new()
	collision_shape.shape.radius = collision_radius
	boss.add_child(collision_shape)
	boss.global_position = spawn_position
	add_child(boss)
	boss.begin_spawn_transport(BOSS_SPAWN_TRANSPORT_DURATION)
	_assign_enemy_target_candidates(boss)
	boss.set("arena_size", current_room_size)
	_apply_boss_difficulty_scaling(boss)
	if boss.has_signal("died"):
		var captured_boss := boss
		boss.died.connect(func(): _on_room_enemy_died(captured_boss.global_position if is_instance_valid(captured_boss) else Vector2.ZERO))
	if boss.has_signal("damage_received"):
		boss.damage_received.connect(func(applied_amount: int, _remaining_health: int): _on_enemy_damage_received(applied_amount))
	return boss

@rpc("reliable", "authority")
func _sync_spawn_enemy_batch(spawn_batch: Array, synced_enemy_count: int, source_room_label: String = "", source_room_depth: int = 0, source_room_sync_id: int = 0) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	if _world_multiplayer_sync_state.is_stale_room_sync_id(source_room_sync_id):
		return
	var payload := {
		"spawn_batch": spawn_batch.duplicate(true),
		"synced_enemy_count": synced_enemy_count,
		"room_label": source_room_label,
		"room_depth": source_room_depth,
		"room_sync_id": source_room_sync_id
	}
	if not _can_apply_client_spawn_sync(payload):
		_world_multiplayer_sync_state.queue_pending_spawn_sync_payload_if_newer(payload, source_room_sync_id)
		return
	_apply_synced_spawn_batch_payload(payload)

@rpc("reliable", "authority")
func _sync_spawn_boss(spawn_data: Dictionary) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	var payload := {
		"boss_stage": int(spawn_data.get("boss_stage", 0)),
		"enemy_id": int(spawn_data.get("enemy_id", -1)),
		"position": spawn_data.get("position", Vector2.ZERO),
		"room_label": String(spawn_data.get("room_label", "")),
		"room_sync_id": int(spawn_data.get("room_sync_id", 0))
	}
	if int(payload.get("boss_stage", 0)) <= 0 or int(payload.get("enemy_id", -1)) <= 0:
		return
	var source_room_sync_id := int(payload.get("room_sync_id", 0))
	if _world_multiplayer_sync_state.is_stale_room_sync_id(source_room_sync_id):
		return
	if not _can_apply_client_boss_spawn_sync(payload):
		_world_multiplayer_sync_state.queue_pending_boss_spawn_sync_payload_if_newer(payload, source_room_sync_id)
		return
	_apply_synced_boss_spawn_payload(payload)

@rpc("unreliable", "authority")
func _sync_enemy_states(synced_states: Array, synced_enemy_count: int) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	for state_variant in synced_states:
		if not (state_variant is Dictionary):
			continue
		var state := state_variant as Dictionary
		var enemy_id := int(state.get("enemy_id", -1))
		if enemy_id <= 0:
			continue
		var enemy := EnemyReplicationService.enemy_nodes_by_id.get(enemy_id) as Node2D
		if not is_instance_valid(enemy):
			continue
		if state.has("position"):
			var synced_position := state.get("position", enemy.global_position) as Vector2
			if enemy.global_position.distance_to(synced_position) >= enemy_remote_snap_distance_px:
				enemy.global_position = synced_position
			EnemyReplicationService.target_positions_by_id[enemy_id] = synced_position
		if state.has("facing_angle"):
			var synced_facing_angle := float(state.get("facing_angle", enemy.global_rotation))
			EnemyReplicationService.target_facing_angles_by_id[enemy_id] = synced_facing_angle
		if state.has("health") and enemy.has_method("set_health"):
			enemy.call("set_health", float(state.get("health", 0.0)))
		if enemy.has_method("apply_network_runtime_state"):
			var runtime_state_delta := state.get("runtime_state_delta", {}) as Dictionary
			enemy.call("apply_network_runtime_state", runtime_state_delta)
	active_room_enemy_count = synced_enemy_count

@rpc("unreliable", "authority")
func _sync_archer_projectile_states(synced_archer_projectiles: Array, source_room_sync_id: int) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	if _world_multiplayer_sync_state.is_stale_room_sync_id(source_room_sync_id):
		return
	for sync_variant in synced_archer_projectiles:
		if not (sync_variant is Dictionary):
			continue
		var sync_data := sync_variant as Dictionary
		var enemy_id := int(sync_data.get("enemy_id", -1))
		if enemy_id <= 0:
			continue
		var enemy := EnemyReplicationService.enemy_nodes_by_id.get(enemy_id) as Node
		if not is_instance_valid(enemy):
			continue
		if not enemy.has_method("apply_projectile_network_sync_state"):
			continue
		var payload := sync_data.get("payload", {}) as Dictionary
		if payload.is_empty():
			continue
		enemy.call("apply_projectile_network_sync_state", payload)

@rpc("reliable", "authority")
func _sync_enemy_died(enemy_id: int, death_effect_payload: Dictionary = {}) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	var enemy := EnemyReplicationService.enemy_nodes_by_id.get(enemy_id) as Node2D
	if String(death_effect_payload.get("effect", "")) == "pyre_death_field":
		_spawn_synced_pyre_death_field(death_effect_payload)
	if is_instance_valid(enemy):
		enemy.queue_free()
	enemy_state_sync_broadcaster.deregister_enemy(enemy_id)


func _clear_enemy_lingering_effects() -> void:
	combat_phase_coordinator.clear_enemy_lingering_effects(get_tree())

func _set_player_combat_damage_enabled(enabled: bool) -> void:
	combat_phase_coordinator.set_player_combat_damage_enabled(player, enabled)

func _end_combat_phase() -> void:
	combat_phase_coordinator.end_combat_phase(player, get_tree())

func _apply_camera_bounds_for_room(room_size: Vector2) -> void:
	if not is_instance_valid(player_camera):
		return
	var rect := Rect2(-room_size * 0.5, room_size)
	player_camera.set_world_bounds(rect)

func _update_camera_mode() -> void:
	if not is_instance_valid(player_camera):
		return
	if is_multiplayer and multiplayer_force_static_arena_camera:
		player_camera.set_static_mode(Vector2.ZERO)
		return
	if (is_instance_valid(reward_selection_ui) and reward_selection_ui.is_active()) or choosing_next_room:
		player_camera.set_static_mode(Vector2.ZERO)
		return
	if current_room_static_camera:
		player_camera.set_static_mode(Vector2.ZERO)
		return
	player_camera.set_follow_mode()

func _update_multiplayer_camera() -> void:
	if not is_instance_valid(player_camera):
		return
	if not is_instance_valid(player) or not is_instance_valid(second_player):
		return
	
	## Fit camera to include both players with padding
	var p1 := player.global_position
	var p2 := second_player.global_position
	var min_x := minf(p1.x, p2.x) - multiplayer_camera_padding.x
	var max_x := maxf(p1.x, p2.x) + multiplayer_camera_padding.x
	var min_y := minf(p1.y, p2.y) - multiplayer_camera_padding.y
	var max_y := maxf(p1.y, p2.y) + multiplayer_camera_padding.y
	
	var target_center := Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return
	
	var required_w := maxf(1.0, max_x - min_x)
	var required_h := maxf(1.0, max_y - min_y)
	var zoom_x := required_w / viewport_size.x
	var zoom_y := required_h / viewport_size.y
	var target_zoom_scalar := clampf(maxf(zoom_x, zoom_y), multiplayer_camera_min_zoom, multiplayer_camera_max_zoom)
	
	player_camera.global_position = player_camera.global_position.lerp(target_center, 0.15)
	player_camera.zoom = player_camera.zoom.lerp(Vector2(target_zoom_scalar, target_zoom_scalar), 0.12)

func _build_skirmish_profile(depth: int) -> Dictionary:
	if not is_instance_valid(encounter_profile_builder):
		return {}
	return encounter_profile_builder.build_skirmish_profile(depth)

func _get_active_player_mutators_for_hud() -> Array[Dictionary]:
	var local_player := _find_local_owned_player_node()
	if not is_instance_valid(local_player):
		return []
	return local_player.get_active_objective_mutators() as Array[Dictionary]

func _get_active_enemy_mutators_for_room() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var local_player := _find_local_owned_player_node()
	if is_instance_valid(local_player):
		var player_mutators := local_player.get_active_enemy_objective_mutators() as Array[Dictionary]
		for mutator in player_mutators:
			result.append((mutator as Dictionary).duplicate(true))
	var coop_scaling_mutator := _build_multiplayer_enemy_durability_mutator()
	if not coop_scaling_mutator.is_empty():
		result.append(coop_scaling_mutator)
	return result

func _roll_route_options(route_context: Variant) -> Array[Dictionary]:
	if not is_instance_valid(encounter_profile_builder):
		return []
	return encounter_profile_builder.roll_route_options(route_context)

func _open_boon_selection(title: String, is_initial: bool, mode: int = ENUMS.RewardMode.BOON, player_mutator: Dictionary = {}, epitaph: String = "", character_id: String = "") -> void:
	if is_initial:
		choosing_next_room = false
		door_options.clear()
	if not is_initial:
		_clear_enemy_lingering_effects()
	if is_instance_valid(reward_selection_ui):
		var local_player := _find_local_owned_player_node()
		if not is_instance_valid(local_player):
			local_player = player
		_begin_reward_phase_sync(is_initial, mode)
		reward_selection_ui.open_selection(title, is_initial, mode, power_registry_instance, local_player, rng, player_mutator, epitaph, character_id)
		_set_combat_paused(true)

func _open_networked_reward_selection(title: String, mode: int, player_mutator: Dictionary = {}, epitaph: String = "") -> void:
	if MultiplayerSessionManager.should_broadcast():
		_sync_open_reward_selection.rpc(title, false, mode, player_mutator, epitaph)
	_open_boon_selection(title, false, mode, player_mutator, epitaph, current_character_id)

@rpc("reliable", "authority")
func _sync_open_reward_selection(title: String, is_initial: bool, mode: int, player_mutator: Dictionary = {}, epitaph: String = "") -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	_open_boon_selection(title, is_initial, mode, player_mutator, epitaph, current_character_id)

func _on_reward_selected(choice: Dictionary, mode: int, is_initial: bool) -> void:
	run_summary_recorder.record_reward_choice(choice, mode, is_initial)
	var tracked_choice := choice.duplicate(true)
	if mode == ENUMS.RewardMode.MISSION:
		var mission_upgrade := tracked_choice.get("mission_upgrade", {}) as Dictionary
		if not mission_upgrade.is_empty():
			tracked_choice["id"] = String(mission_upgrade.get("id", tracked_choice.get("id", "")))
			tracked_choice["name"] = String(mission_upgrade.get("name", tracked_choice.get("name", "")))
	run_summary_recorder.record_reward_choice_for_tracker(tracked_choice, mode, room_depth)
	_record_local_peer_reward_timeline_choice(tracked_choice, mode, room_depth)
	if mode == ENUMS.RewardMode.ARCANA:
		_apply_arcana_to_player(String(choice["id"]))
		run_session.record_arcana(String(choice["name"]))
	elif mode == ENUMS.RewardMode.MISSION:
		_apply_mission_reward(choice)
	elif mode == ENUMS.RewardMode.BOSS:
		_apply_boon_to_player(String(choice["id"]))
		run_session.record_boon(String(choice["name"]))
		boss_reward_pending = false
	else:
		_apply_boon_to_player(String(choice["id"]))
		run_session.record_boon(String(choice["name"]))
	if is_multiplayer:
		_mark_local_reward_phase_complete(is_initial, mode)
	elif is_initial:
		_reset_progress_for_first_encounter()
		_set_combat_paused(false)
		pending_room_reward = ENUMS.RewardMode.BOON
		_begin_room(_build_skirmish_profile(room_depth))
	else:
		_set_combat_paused(false)
		_spawn_door_options()
	hud.refresh(_get_hud_state(), player)

func _record_local_peer_reward_timeline_choice(choice: Dictionary, mode: int, depth: int) -> void:
	if not is_multiplayer:
		return
	var local_peer_id := _resolve_local_peer_id()
	if local_peer_id <= 0:
		return
	var event_unix := int(Time.get_unix_time_from_system())
	run_summary_recorder.record_peer_reward_timeline_choice(local_peer_id, choice, mode, depth, event_unix)
	if MultiplayerSessionManager.should_broadcast():
		return
	_sync_reward_choice_for_summary.rpc_id(1, local_peer_id, choice.duplicate(true), mode, depth, event_unix)

@rpc("reliable", "any_peer")
func _sync_reward_choice_for_summary(peer_id: int, choice: Dictionary, mode: int, depth: int, event_unix: int) -> void:
	if not MultiplayerSessionManager.should_broadcast():
		return
	run_summary_recorder.record_peer_reward_timeline_choice(peer_id, choice, mode, depth, event_unix)


func _begin_reward_phase_sync(is_initial: bool, mode: int) -> void:
	if not is_multiplayer:
		_reward_phase_active = false
		_reward_phase_completed_peers.clear()
		return
	_reward_phase_active = true
	_reward_phase_is_initial = is_initial
	_reward_phase_mode = mode
	_reward_phase_completed_peers.clear()
	if is_instance_valid(hud):
		hud.hide_persistent_banner()


func _mark_local_reward_phase_complete(is_initial: bool, mode: int) -> void:
	if not is_multiplayer:
		return
	var local_peer_id := _resolve_local_peer_id()
	if local_peer_id <= 0:
		return
	if is_instance_valid(hud):
		hud.show_persistent_banner("Reward Locked In", "Waiting for other player...", Color(0.78, 0.9, 1.0, 0.92))
	_sync_reward_phase_complete.rpc(local_peer_id, is_initial, mode)


func _all_reward_phase_peers_completed() -> bool:
	var multiplayer_session_manager := get_node_or_null("/root/MultiplayerSessionManager")
	if multiplayer_session_manager == null:
		return false
	var required_peers: Array = multiplayer_session_manager.get_peer_ids()
	if required_peers.is_empty():
		return false
	for peer_id_variant in required_peers:
		var peer_id := int(peer_id_variant)
		if not bool(_reward_phase_completed_peers.get(peer_id, false)):
			return false
	return true


func _finalize_reward_phase_and_advance(is_initial: bool, mode: int) -> void:
	if not _reward_phase_active:
		return
	_reward_phase_active = false
	_reward_phase_completed_peers.clear()
	_reward_phase_mode = ENUMS.RewardMode.NONE
	_reward_phase_is_initial = false
	if is_instance_valid(hud):
		hud.hide_persistent_banner()
	_set_combat_paused(false)
	if is_initial:
		_reset_progress_for_first_encounter()
		pending_room_reward = ENUMS.RewardMode.BOON
		_begin_room(_build_skirmish_profile(room_depth))
	else:
		if mode == ENUMS.RewardMode.BOSS:
			boss_reward_pending = false
		if MultiplayerSessionManager.should_broadcast():
			_doors_spawn_ready = true
			_sync_doors_spawn_ready.rpc()
		else:
			_doors_spawn_ready = true
		_spawn_door_options()
	hud.refresh(_get_hud_state(), player)


func _reset_progress_for_first_encounter() -> void:
	_world_multiplayer_sync_state.reset_for_new_run()
	rooms_cleared = 0
	room_depth = 0
	boss_unlocked = false
	in_boss_room = false
	in_second_boss_room = false
	in_third_boss_room = false
	first_boss_defeated = false
	second_boss_defeated = false
	phase_two_rooms_cleared = 0
	phase_three_rooms_cleared = 0
	endless_boss_defeated = false
	boss_reward_pending = false
	last_defeated_boss_id = ""
	_world_multiplayer_sync_state.clear_pending_chosen_door_sync()


@rpc("reliable", "any_peer", "call_local")
func _sync_reward_phase_complete(peer_id: int, is_initial: bool, mode: int) -> void:
	if not is_multiplayer:
		return
	if not _reward_phase_active:
		return
	if _reward_phase_is_initial != is_initial or _reward_phase_mode != mode:
		return
	_reward_phase_completed_peers[int(peer_id)] = true
	if not MultiplayerSessionManager.should_broadcast():
		return
	if not _all_reward_phase_peers_completed():
		return
	_finalize_reward_phase_and_advance(is_initial, mode)
	_sync_reward_phase_advance.rpc(is_initial, mode)


@rpc("reliable", "authority")
func _sync_reward_phase_advance(is_initial: bool, mode: int) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	_finalize_reward_phase_and_advance(is_initial, mode)

@rpc("reliable", "authority")
func _sync_doors_spawn_ready() -> void:
	if not is_multiplayer:
		return
	_doors_spawn_ready = true
	_spawn_door_options()

@rpc("reliable", "authority")
func _sync_run_outcome(outcome: String, unlocked_tier: int, room_label: String, depth: int, run_summary: Dictionary = {}, stats_by_peer: Dictionary = {}, peer_summary_overrides: Dictionary = {}) -> void:
	if not MultiplayerSessionManager.is_remote_replica():
		return
	if STAT_ATTRIBUTION_TRACE:
		print_debug("[StatAttribution][OutcomeRecv] local_peer=%d outcome=%s stats_keys=%s" % [_resolve_local_peer_id(), outcome, str(stats_by_peer.keys())])
	var synced_summary: Dictionary = run_summary_recorder.summary_with_local_peer_stats(run_summary, stats_by_peer)
	synced_summary = run_summary_recorder.summary_with_local_peer_overrides(synced_summary, peer_summary_overrides)
	run_summary_recorder.latest_run_summary = synced_summary
	if outcome == "clear":
		run_cleared = true
		choosing_next_room = false
		active_room_enemy_count = 0
		_set_combat_paused(true)
		player_flow_coordinator.close_reward_selection_if_active(reward_selection_ui)
		player_flow_coordinator.close_pause_menu_if_open(pause_menu_controller)
		_show_victory_feedback(unlocked_tier, synced_summary)
		return
	if outcome == "death":
		player_defeated = true
		run_cleared = true
		choosing_next_room = false
		active_room_enemy_count = 0
		_set_combat_paused(true)
		player_flow_coordinator.close_reward_selection_if_active(reward_selection_ui)
		player_flow_coordinator.close_pause_menu_if_open(pause_menu_controller)
		objective_lifecycle_coordinator.clear_on_player_defeat(objective_manager)
		_show_defeat_feedback(room_label, depth, synced_summary)

func _on_reward_offers_presented(offers: Array[Dictionary], mode: int, is_initial: bool, stage: int) -> void:
	run_summary_recorder.record_reward_offers(offers, mode, is_initial, stage)

func _is_debug_boot_session() -> bool:
	if not settings_enabled:
		return false
	var debug_settings := get_node_or_null("DebugSettings")
	if debug_settings != null and bool(debug_settings.get("stress_test_enabled")):
		return true
	if end_screen_preview != DEBUG_ENUMS.EndScreenPreview.NONE:
		return true
	if start_encounter != ENCOUNTER_CONTRACTS.DEBUG_ENCOUNTER_NONE:
		return true
	if _debug_bearing_override_tier() >= 0:
		return true
	if apply_test_powers_on_start:
		return true
	if start_power_preset != DEBUG_ENUMS.PowerPreset.NONE:
		return true
	if skip_starting_boon_selection:
		return true
	return false

func _maybe_start_telemetry_spike_probe() -> void:
	if telemetry_spike_requested:
		return
	if not settings_enabled or not telemetry_spike_enabled:
		return
	telemetry_spike_requested = true
	var endpoint := telemetry_spike_endpoint.strip_edges()
	if endpoint.is_empty():
		push_warning("Telemetry spike probe skipped: endpoint is empty.")
		return
	telemetry_spike_sender = TELEMETRY_SPIKE_SENDER_SCRIPT.new()
	add_child(telemetry_spike_sender)
	telemetry_spike_sender.connect("probe_completed", Callable(self, "_on_telemetry_spike_probe_completed"), CONNECT_ONE_SHOT)
	telemetry_spike_sender.begin_probe({
		"endpoint": endpoint,
		"api_key": telemetry_spike_api_key,
		"timeout_seconds": clampf(telemetry_spike_timeout_seconds, 3.0, 20.0),
		"game_version": String(ProjectSettings.get_setting("application/config/version", "dev")),
	})
	print("Telemetry spike probe started: %s" % endpoint)

func _on_telemetry_spike_probe_completed(success: bool, http_code: int, error_message: String, response_preview: String) -> void:
	if success:
		print("Telemetry spike probe succeeded (HTTP %d)." % http_code)
	else:
		push_warning("Telemetry spike probe failed (%s, HTTP %d)." % [error_message, http_code])
	if not response_preview.is_empty():
		print("Telemetry spike response preview: %s" % response_preview)
	if is_instance_valid(telemetry_spike_sender):
		telemetry_spike_sender.queue_free()
	telemetry_spike_sender = null

func _on_player_damage_taken(raw_amount: int, final_amount: int, damage_context: Dictionary) -> void:
	run_summary_recorder.record_player_damage_taken(raw_amount, final_amount, damage_context)

func _on_player_health_changed_for_summary(current_health: int, _max_health: int, player_node: Node) -> void:
	run_summary_recorder.on_player_health_changed(current_health, _max_health, player_node)

func _on_player_died_for_telemetry() -> void:
	run_summary_recorder.on_player_died_for_telemetry()

func _on_player_died() -> void:
	run_summary_recorder.reconcile_damage_taken_to_player_health()
	if player_defeated:
		return
	var has_new_fallen := _refresh_fallen_player_tracking()
	if is_multiplayer:
		_sync_multiplayer_fallen_player_presence()
		_refresh_all_enemy_target_candidates()
		_bind_camera_to_local_player()
	if is_multiplayer and _count_alive_players() > 0:
		if has_new_fallen and is_instance_valid(hud):
			hud.show_banner("Ally Down", "Clear encounter to revive")
		return
	player_defeated = true
	_set_combat_paused(true)
	player_flow_coordinator.close_reward_selection_if_active(reward_selection_ui)
	player_flow_coordinator.close_pause_menu_if_open(pause_menu_controller)
	run_cleared = true
	choosing_next_room = false
	objective_lifecycle_coordinator.clear_on_player_defeat(objective_manager)
	active_room_enemy_count = 0
	var run_context := _get_run_context()
	if run_context != null:
		run_context.set_last_run_outcome("death")
		run_context.clear_active_run()
		run_context.clear_resume_saved_run_request()
	var current_summary: Dictionary = run_summary_recorder.latest_run_summary
	if current_summary.is_empty() or String(current_summary.get("outcome", "")) != "death":
		run_summary_recorder.finish_run("death", run_summary_recorder.build_death_event_snapshot())
	if MultiplayerSessionManager.should_broadcast():
		if STAT_ATTRIBUTION_TRACE:
			print_debug("[StatAttribution][OutcomeSend] outcome=death stats=%s" % str(run_summary_recorder.get_stats_by_peer()))
		_sync_run_outcome.rpc("death", -1, current_room_label, room_depth, run_summary_recorder.latest_run_summary, run_summary_recorder.get_stats_by_peer(), run_summary_recorder.get_latest_peer_summary_overrides())
	_show_defeat_feedback(current_room_label, room_depth, run_summary_recorder.latest_run_summary)

func _show_victory_feedback(unlocked_tier: int, run_summary: Dictionary = {}) -> void:
	if is_instance_valid(victory_screen):
		victory_screen.show_victory(rooms_cleared, unlocked_tier, run_summary, not is_multiplayer)

func _show_defeat_feedback(room_label: String, depth: int, run_summary: Dictionary = {}) -> void:
	player_flow_coordinator.show_defeat_feedback(hud, defeat_screen, room_label, depth, run_summary, not is_multiplayer)

func get_current_player_profile() -> RefCounted:
	if current_player_profile != null and current_player_profile.is_valid():
		return current_player_profile
	if profile_persistence_store != null:
		current_player_profile = profile_persistence_store.load_or_create_profile()
		return current_player_profile
	return null

func wrap_summary_with_profile(summary: Dictionary) -> RefCounted:
	var profile := get_current_player_profile()
	return RUN_SUMMARY_WITH_PROFILE_SCRIPT.create(summary, profile)

func _get_multiplayer_player_nodes() -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	if is_instance_valid(player):
		nodes.append(player)
	if is_instance_valid(second_player):
		nodes.append(second_player)
	return nodes

func _assign_enemy_target_candidates(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	var alive_targets: Array = []
	for player_node in _get_multiplayer_player_nodes():
		if _is_player_alive(player_node):
			alive_targets.append(player_node)
	var targets := alive_targets
	if targets.is_empty():
		targets = _get_multiplayer_player_nodes()
	if targets.is_empty():
		return
	enemy.set("target", targets[0])
	if enemy.has_method("set_target_candidates"):
		enemy.call("set_target_candidates", targets)

func _refresh_all_enemy_target_candidates() -> void:
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		_assign_enemy_target_candidates(enemy_node as Node2D)

func _spawn_test_enemies(count: int) -> void:
	"""Spawn N test enemies for stress testing"""
	if not is_instance_valid(player):
		return
	if not is_instance_valid(enemy_spawner):
		return
	
	# Tether excluded: its complex state (tether connections, anchors) inflates per-packet size
	# beyond regular enemies, making it unrepresentative for bandwidth testing.
	var enemy_types := ["chaser", "archer", "charger", "shielder"]
	var spawn_batch: Array = []
	
	for i in range(count):
		var enemy_type = enemy_types[i % enemy_types.size()]
		var angle = (TAU / maxf(count, 1)) * i
		var distance = 150.0 + (i / 5.0) * 50.0
		var spawn_pos = player.global_position + Vector2(cos(angle), sin(angle)) * distance
		
		if enemy_spawner.has_method("_create_test_enemy"):
			var enemy: CharacterBody2D = enemy_spawner._create_test_enemy(enemy_type, spawn_pos)
			if is_instance_valid(enemy):
				var enemy_id: int = enemy_state_sync_broadcaster.register_enemy(enemy)
				spawn_batch.append({
					"enemy_id": enemy_id,
					"enemy_type": enemy_type,
					"position": enemy.global_position
				})
				active_room_enemy_count += 1

	if MultiplayerSessionManager.should_broadcast() and not spawn_batch.is_empty():
		_sync_spawn_enemy_batch.rpc(spawn_batch, active_room_enemy_count, current_room_label, room_depth, _world_multiplayer_sync_state.current_room_sync_id)

func start_network_stress_test(initial_count: int = 10, increment: int = 10, max_count: int = 100) -> void:
	"""Start the multiplayer network stress test (debug only)"""
	if not is_multiplayer:
		print_debug("[StressTest] Stress test requires multiplayer mode")
		return
	
	if _stress_test_active:
		print_debug("[StressTest] Stress test already running")
		return
	
	if _stress_test_coordinator == null:
		_stress_test_coordinator = load("res://scripts/multiplayer_stress_test.gd").new()
		_stress_test_coordinator.world_gen = self
	var debug_settings := get_node_or_null("DebugSettings")
	if debug_settings != null:
		_stress_test_coordinator.fps_drop_stop_below_fps = float(debug_settings.get("stress_test_drop_stop_below_fps"))
	
	_stress_test_coordinator.start_test(initial_count, increment, max_count)

func _maybe_start_stress_test() -> void:
	"""Check debug settings and start stress test if enabled"""
	var debug_settings := get_node_or_null("DebugSettings")
	if not debug_settings:
		return
	
	if not bool(debug_settings.get("stress_test_enabled")):
		return
	
	if not is_multiplayer:
		print_debug("[StressTest] Stress test is enabled but game is not in multiplayer mode")
		return
	
	if not MultiplayerSessionManager.should_broadcast():
		print_debug("[StressTest] Skipping on client - host only")
		return
	
	var initial: int = int(debug_settings.get("stress_test_initial_enemies"))
	var increment: int = int(debug_settings.get("stress_test_increment"))
	var max_count: int = int(debug_settings.get("stress_test_max_enemies"))
	
	print_debug("[StressTest] Starting from debug settings (initial:%d, increment:%d, max:%d)" % [initial, increment, max_count])
	start_network_stress_test(initial, increment, max_count)

func _count_alive_players() -> int:
	var alive_count := 0
	for player_node in _get_multiplayer_player_nodes():
		if not player_node.has_method("is_dead"):
			alive_count += 1
			continue
		if not bool(player_node.call("is_dead")):
			alive_count += 1
	return alive_count


func _sync_multiplayer_fallen_player_presence() -> void:
	if not is_multiplayer:
		return
	for player_node in _get_multiplayer_player_nodes():
		if not player_node.has_method("set_combat_removed") or not player_node.has_method("is_dead"):
			continue
		var is_dead := bool(player_node.call("is_dead"))
		player_node.call("set_combat_removed", is_dead)

func _try_revive_fallen_multiplayer_players() -> void:
	if not is_multiplayer:
		return
	if _count_alive_players() <= 0:
		return
	var multiplayer_session_manager := get_node_or_null("/root/MultiplayerSessionManager")
	if multiplayer_session_manager == null or not bool(multiplayer_session_manager.is_host()):
		return
	var player_replication_service := get_node_or_null("/root/PlayerReplicationService")
	for player_node in _get_multiplayer_player_nodes():
		if not player_node.has_method("is_dead") or not player_node.has_method("revive_with_health"):
			continue
		if not bool(player_node.call("is_dead")):
			continue
		player_node.call("revive_with_health", 1.0)
		if player_replication_service != null and player_node.has_method("get"):
			var peer_id := int(player_node.get("player_id"))
			player_replication_service.broadcast_player_revived(peer_id, 1.0)
	_refresh_fallen_player_tracking()
	_sync_multiplayer_fallen_player_presence()
	_refresh_all_enemy_target_candidates()
	_bind_camera_to_local_player()

func _apply_boon_to_player(boon_id: String) -> void:
	var local_player := _find_local_owned_player_node()
	if not is_instance_valid(local_player):
		return
	local_player.apply_upgrade(boon_id)
	_broadcast_local_player_build_snapshot()

func _apply_mission_reward(choice: Dictionary) -> void:
	var chosen_upgrade := choice.get("mission_upgrade", choice) as Dictionary
	var chosen_mutator := choice.get("mission_mutator", {}) as Dictionary
	var chosen_id := String(chosen_upgrade.get("id", ""))
	if chosen_id.is_empty():
		return
	_apply_boon_to_player(chosen_id)
	run_session.record_boon(String(chosen_upgrade.get("name", chosen_id)))
	if is_instance_valid(hud):
		hud.show_banner("Mission Reward", String(chosen_upgrade.get("name", chosen_id)))
	if not chosen_mutator.is_empty():
		_apply_objective_mutator(chosen_mutator)
		return
	if current_room_player_mutator.is_empty():
		return
	_apply_objective_mutator({
		"name": String(current_room_player_mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME, "Objective Mutator")),
		"full_data": current_room_player_mutator
	})

func _roll_bonus_mission_boon(excluded_id: String) -> Dictionary:
	if not is_instance_valid(power_registry_instance):
		return {}
	var pool: Array[Dictionary] = power_registry_instance.get_objective_upgrade_pool(player)
	var available: Array[Dictionary] = []
	for entry in pool:
		var entry_id := String(entry.get("id", ""))
		if entry_id == excluded_id:
			continue
		if current_character_id == "riftlancer" and entry_id == "wide_arc":
			continue
		var limit := int(entry.get("stack_limit", 0))
		if limit > 0 and is_instance_valid(player):
			var current := int(player.get_upgrade_stack_count(entry_id))
			if current >= limit:
				continue
		available.append(entry)
	if available.is_empty():
		return {}
	return available[rng.randi_range(0, available.size() - 1)]

func _apply_arcana_to_player(reward_id: String) -> void:
	var local_player := _find_local_owned_player_node()
	if not is_instance_valid(local_player):
		return
	local_player.apply_trial_power(reward_id)
	_broadcast_local_player_build_snapshot()

func _apply_objective_mutator(choice: Dictionary) -> void:
	var local_player := _find_local_owned_player_node()
	if not is_instance_valid(local_player):
		return
	var mutator_data := choice.get("full_data", {}) as Dictionary
	if mutator_data.is_empty():
		return
	var applied_mutator := mutator_data.duplicate(true)
	var duration := maxi(1, int(applied_mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_DURATION_ENCOUNTERS, 3)))
	applied_mutator[ENCOUNTER_CONTRACTS.MUTATOR_KEY_DURATION_ENCOUNTERS] = duration
	local_player.apply_objective_mutator(applied_mutator)
	_broadcast_local_player_build_snapshot()
	var mutator_name := String(choice.get("name", "Objective Mutator"))
	if is_instance_valid(hud):
		hud.show_banner("Objective Reward", mutator_name)

func _set_combat_paused(paused: bool) -> void:
	combat_phase_coordinator.set_combat_paused(player, get_tree(), paused)

func _broadcast_local_player_build_snapshot() -> void:
	if not is_multiplayer:
		return
	var local_player := _find_local_owned_player_node()
	if not is_instance_valid(local_player):
		return
	if not local_player.has_method("broadcast_network_build_snapshot"):
		return
	local_player.broadcast_network_build_snapshot()

func _is_spawn_transport_active(enemy: Node) -> bool:
	return bool(enemy.is_spawn_transporting())

func _begin_spawn_transport_if_idle(enemy: Node, duration: float) -> void:
	if _is_spawn_transport_active(enemy):
		return
	enemy.begin_spawn_transport(duration)

func _start_encounter_intro_grace() -> void:
	encounter_intro_grace_active = true
	_encounter_ready_peers.clear()
	_local_player_ready = false
	if is_instance_valid(player) and player is CharacterBody2D:
		(player as CharacterBody2D).velocity = Vector2.ZERO
	var local_node := _find_local_player_node()
	if is_instance_valid(local_node) and local_node.has_method("set"):
		local_node.set("encounter_input_frozen", true)
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node):
			continue
		var enemy := enemy_node as Node
		_begin_spawn_transport_if_idle(enemy, INTRO_SURVEY_TRANSPORT_PULSE_DURATION)
	_set_enemy_targets_passive(true)
	hud.show_banner("Survey the arena", "")

func _update_encounter_intro_grace() -> bool:
	if not encounter_intro_grace_active:
		return false
	if not is_instance_valid(player) and not is_instance_valid(second_player):
		return false
	
	if _local_player_ready:
		return true
	
	var local_player_node := _find_local_player_node()
	if local_player_node == null:
		return true
	
	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var player_moving := move_input.length_squared() > 0.0
	var player_attacking := Input.is_action_just_pressed("attack")
	
	if player_moving or player_attacking:
		var detected_via := "movement" if player_moving else "attack"
		print_debug("Grace: Local player ready via %s [peer:%d]" % [detected_via, get_tree().get_multiplayer().get_unique_id()])
		_signal_local_player_ready()
	
	return true

func _signal_local_player_ready() -> void:
	if _local_player_ready:
		return
	_local_player_ready = true
	
	if not is_multiplayer:
		_exit_encounter_intro_grace()
		return
	
	hud.show_persistent_banner("Ready", "Waiting for ally...")
	
	var local_peer_id := _resolve_local_peer_id()
	if MultiplayerSessionManager.should_broadcast():
		_on_player_ready_signal(local_peer_id)
	else:
		_notify_host_player_ready.rpc_id(1, local_peer_id)

@rpc("reliable", "any_peer")
func _notify_host_player_ready(peer_id: int) -> void:
	if not MultiplayerSessionManager.should_broadcast():
		return
	var sender := get_tree().get_multiplayer().get_remote_sender_id()
	if sender > 0 and sender != peer_id:
		return
	_on_player_ready_signal(peer_id)

func _on_player_ready_signal(peer_id: int) -> void:
	_encounter_ready_peers[peer_id] = true
	
	for player_node in _get_multiplayer_player_nodes():
		if not _is_player_alive(player_node):
			continue
		var pid := int(player_node.get("player_id"))
		if not _encounter_ready_peers.get(pid, false):
			return
	
	_exit_encounter_intro_grace()
	_broadcast_all_players_ready.rpc()

@rpc("reliable", "authority")
func _broadcast_all_players_ready() -> void:
	_exit_encounter_intro_grace()

func _exit_encounter_intro_grace() -> void:
	if not encounter_intro_grace_active:
		return
	encounter_intro_grace_active = false
	var local_node := _find_local_player_node()
	if is_instance_valid(local_node) and local_node.has_method("set"):
		local_node.set("encounter_input_frozen", false)
	var debug_msg := "Grace exit: grace deactivated"
	if is_multiplayer:
		debug_msg += " [peer:%d, host:%s]" % [get_tree().get_multiplayer().get_unique_id(), MultiplayerSessionManager.is_host()]
	print_debug(debug_msg)
	hud.hide_persistent_banner()
	_set_enemy_targets_passive(false)
	hud.show_banner("Engage", "")

func _set_enemy_targets_passive(passive: bool) -> void:
	var active_targets: Array = []
	for player_node in _get_multiplayer_player_nodes():
		if not _is_player_alive(player_node):
			continue
		active_targets.append(player_node)
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is CharacterBody2D):
			continue
		var enemy := enemy_node as CharacterBody2D
		if passive:
			enemy.set("target", null)
			if enemy.has_method("set_target_candidates"):
				enemy.call("set_target_candidates", [])
			if enemy is CharacterBody2D:
				enemy.velocity = Vector2.ZERO
		else:
			if not active_targets.is_empty():
				enemy.set("target", active_targets[0])
				if enemy.has_method("set_target_candidates"):
					enemy.call("set_target_candidates", active_targets)
			else:
				enemy.set("target", player)
			var cooldown_key := ""
			if enemy.get("attack_cooldown_left") != null:
				cooldown_key = "attack_cooldown_left"
			if not cooldown_key.is_empty():
				var current_cd := float(enemy.get(cooldown_key))
				if current_cd < 0.32:
					enemy.set(cooldown_key, 0.32)
