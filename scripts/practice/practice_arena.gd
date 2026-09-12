extends Node2D
## An ephemeral solo sandbox. Configuration is detached from every normal save.
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const PLAYER := preload("res://scripts/player.gd")
const TRAINING_PLAYER := preload("res://scripts/practice/practice_player.gd")
const CONFIG := preload("res://scripts/practice/practice_config.gd")
const ENVIRONMENT := preload("res://scripts/practice/practice_environment.gd")
const SPAWNER := preload("res://scripts/practice/practice_enemy_spawner.gd")
const ENEMY := preload("res://scripts/enemy_base.gd")
const POWERS := preload("res://scripts/power_registry.gd")
const BOSSES := preload("res://scripts/shared/boss_stage_registry.gd")
const CHARACTERS := preload("res://scripts/character_registry.gd")
const RENDERER := preload("res://scripts/world_renderer.gd")
const MUSIC := preload("res://scripts/music_system.gd")
const SCORE := preload("res://scripts/shared/riot_depth_catalogue.gd")
const COMBAT_PHASE := preload("res://scripts/core/combat_phase_coordinator.gd")
const SYNC_STATE := preload("res://scripts/core/world_multiplayer_sync_state.gd")
const PANEL := preload("res://scripts/ui/practice/practice_panel.gd")
const ENCOUNTERS := preload("res://scripts/practice/practice_encounters.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const OBJECTIVE_MANAGER := preload("res://scripts/objective_manager.gd")
const OBJECTIVE_RUNTIME := preload("res://scripts/objective_runtime.gd")
const OBJECTIVE_OVERLAY := preload("res://scripts/objective_control_overlay.gd")
const OBJECTIVE_FEEDBACK := preload("res://scripts/practice/practice_objective_feedback.gd")
const OBJECTIVE_LIFECYCLE := preload("res://scripts/core/objective_lifecycle_coordinator.gd")
const OBJECTIVE_FRAME := preload("res://scripts/core/objective_frame_coordinator.gd")
const OBJECTIVE_PROGRESS := preload("res://scripts/core/objective_progress_coordinator.gd")

var menu_return_state: Dictionary = {}
var player: PLAYER
var boss: Node2D # First boss alias retained for focused integration consumers.
var enemies: Array[Node2D] = []
var enemy_spawner: SPAWNER
var environment: ENVIRONMENT
var ui: CanvasLayer
var music_system: MUSIC
var renderer: RENDERER
var power_registry: POWERS
var rng := RandomNumberGenerator.new()
var current_effective_room_size := Vector2(1260.0, 900.0)
var current_room_size := Vector2(1260.0, 900.0)
var current_config: Dictionary = {}
var draft_config: Dictionary = CONFIG.defaults()
var current_difficulty_config: Dictionary = {}
var room_depth := 0
var current_act := 1
var _world_multiplayer_sync_state := SYNC_STATE.new()
var combat_phase := COMBAT_PHASE.new()
var mode := "setup"
var detail := ""
var attempt := 0
var elapsed_seconds := 0.0
var damage_dealt := 0
var encounter_profile_builder: ENCOUNTERS
var current_profile: Dictionary = {}
var objective_manager: OBJECTIVE_MANAGER
var objective_runtime: OBJECTIVE_RUNTIME
var objective_overlay: OBJECTIVE_OVERLAY
var hud: OBJECTIVE_FEEDBACK
var run_summary_recorder: Node = null
var current_difficulty_tier := 1
var current_room_label := ""
var active_room_enemy_count := 0
var spawn_safe_radius := 240.0
var is_multiplayer := false
var choosing_next_room := true
var _attempt_seed := 0
var _objective_frame := OBJECTIVE_FRAME.new()
var _objective_progress := OBJECTIVE_PROGRESS.new()
var _transition_pending := false
var _ui_refresh_left := 0.0
var current_character_id := "bastion"
var next_character_id := "bastion"
var _retry_character_id := "bastion"
var _pending_config: Dictionary = {}
var _setup_can_resume := false

func _ready() -> void:
	ui = PANEL.new()
	add_child(ui)
	ui.pause_requested.connect(request_pause)
	ui.resume_requested.connect(request_resume)
	ui.retry_requested.connect(request_retry)
	ui.menu_requested.connect(request_menu)
	ui.vessel_requested.connect(request_vessel)
	ui.config_requested.connect(request_config)
	ui.start_requested.connect(request_start)
	ui.apply_requested.connect(request_apply)
	ui.configure_requested.connect(request_configure)
	ui.gameplay_rect_changed.connect(_update_camera_frame)
	if _party_is_active():
		mode = "error"
		detail = "Leave the party before starting solo practice."
		_refresh_ui()
		return
	rng.randomize()
	renderer = RENDERER.new()
	renderer.room_size = current_effective_room_size
	renderer.set_environment_identity(1, "shatterfield")
	add_child(renderer)
	power_registry = POWERS.new()
	add_child(power_registry)
	music_system = MUSIC.new()
	add_child(music_system)
	var context := get_node_or_null("/root/RunContext")
	music_system.initialize(SCORE.LAYERS[1], SCORE.LAYERS[4], float(context.music_volume_db) if context != null else -20.0, 0.75)
	music_system.configure_adaptive_score(SCORE.LAYERS, SCORE.BPM)
	music_system.set_run_location(1, 0, false)
	music_system.play_room_music(false, true)
	EnemyReplicationService.bind_world(self)
	_refresh_ui()

static func available_characters_for_profile(_profile: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in CONFIG.catalogue().characters:
		result.append(row.duplicate(true))
	return result

func _available_characters() -> Array[Dictionary]:
	return available_characters_for_profile({})

func _character_is_available(id: String) -> bool:
	return CHARACTERS.get_launch_character_ids().has(id)

func request_vessel(id: String) -> bool:
	if not _character_is_available(id):
		return false
	var next := draft_config.duplicate(true)
	next.character_id = id
	return request_config(next)

func request_config(config: Dictionary) -> bool:
	if _transition_pending or mode not in ["setup", "paused", "victory", "defeat"] or _party_is_active():
		return false
	draft_config = config.duplicate(true)
	next_character_id = String(draft_config.get("character_id", "bastion"))
	_refresh_ui()
	return true

func request_configure() -> void:
	if _transition_pending or mode == "error" or _party_is_active():
		return
	_setup_can_resume = mode in ["active", "paused"] and is_instance_valid(player) and not player.is_dead()
	_set_combat_paused(true)
	mode = "setup"
	_refresh_ui()

func request_start() -> void:
	if attempt == 0 and mode == "setup":
		request_apply()

func request_apply() -> void:
	if _transition_pending or mode not in ["setup", "paused", "victory", "defeat"] or _party_is_active():
		return
	var validation := CONFIG.validate(draft_config)
	if not validation.valid:
		_refresh_ui()
		return
	_pending_config = validation.config.duplicate(true)
	_transition_pending = true
	_set_combat_paused(true)
	call_deferred("_retry_attempt")

func request_retry() -> void:
	if _transition_pending or mode == "error" or _party_is_active():
		return
	if mode == "active":
		_pending_config = current_config.duplicate(true)
		_transition_pending = true
		_set_combat_paused(true)
		call_deferred("_retry_attempt")
	else:
		request_apply()

func _retry_attempt() -> void:
	var validation := CONFIG.validate(_pending_config)
	if _party_is_active() or not validation.valid:
		_transition_pending = false
		_set_combat_paused(mode != "active")
		_refresh_ui()
		return
	_retire_attempt()
	_start_attempt(validation.config)
	_pending_config.clear()
	_transition_pending = false
	_refresh_ui()

func _start_attempt(configuration: Dictionary = {}) -> void:
	var validation := CONFIG.validate(configuration if not configuration.is_empty() else draft_config)
	if _party_is_active() or not validation.valid:
		mode = "error"
		detail = "Practice could not apply this configuration."
		_refresh_ui()
		return
	var applied: Dictionary = validation.config
	attempt += 1
	_world_multiplayer_sync_state.current_room_sync_id += 1
	room_depth = int(applied.floor) - 1
	current_act = CONFIG.act_for_floor(int(applied.floor))
	current_character_id = String(applied.character_id)
	next_character_id = current_character_id
	current_difficulty_config = CONFIG.difficulty(applied)
	elapsed_seconds = 0.0
	damage_dealt = 0
	detail = ""
	_setup_can_resume = false
	current_config = applied.duplicate(true)
	current_difficulty_tier = int(applied.bearing)
	if _attempt_seed == 0:
		_attempt_seed = rng.randi()
	rng.seed = _attempt_seed
	encounter_profile_builder = ENCOUNTERS.new()
	add_child(encounter_profile_builder)
	encounter_profile_builder.initialize(rng)
	encounter_profile_builder.set_difficulty_tier(current_difficulty_tier)
	encounter_profile_builder.set_ascension_loadout(applied.ascension)
	encounter_profile_builder.set_active_biome(CONFIG.BIOMES.get_biome(applied.biome_id))
	current_profile = encounter_profile_builder.build_selected(applied.encounter_id, room_depth)
	if current_profile.is_empty():
		_fail_configuration("Could not generate the selected encounter.")
		return
	current_effective_room_size = CONTRACTS.profile_room_size(current_profile)
	current_room_label = CONTRACTS.profile_label(current_profile)
	var boss_stage := CONFIG.BOSSES.stage_for_id(applied.encounter_id)
	var has_boss := boss_stage > 0
	renderer.room_size = current_effective_room_size
	renderer.set_environment_identity(current_act, String(applied.biome_id))
	current_room_size = current_effective_room_size
	player = PLAYER_SCENE.instantiate() as PLAYER
	# Preserve the authored Player scene package when attaching its narrow
	# training-only damage gate. No ordinary Player property is redefined.
	var exported := {}
	for property: Dictionary in player.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
			exported[String(property.name)] = player.get(property.name)
	player.set_script(TRAINING_PLAYER)
	for key: String in exported:
		player.set(key, exported[key])
	add_child(player)
	player.set_physics_process(false)
	player.apply_character_package(CHARACTERS.get_character(current_character_id))
	player.set_power_registry(power_registry)
	_apply_player_difficulty()
	for row: Dictionary in CONFIG.catalogue(applied).powers:
		var id := String(row.id)
		var count := int(applied.powers.get(id, 0))
		for level in count:
			if row.category == "arcana":
				player.apply_trial_power(id)
			else:
				player.apply_upgrade(id)
			var actual := player.get_trial_power_stack_count(id) if row.category == "arcana" else player.get_upgrade_stack_count(id)
			if actual != level + 1:
				_fail_configuration("Could not apply %s level %d." % [row.name, level + 1])
				return
		if applied.prismatic.has(id):
			player.apply_trial_power(id)
			if not player.has_trial_power_prismatic(id):
				_fail_configuration("Could not apply Prismatic " + String(row.name))
				return
	player.set("practice_invulnerable", bool(applied.invulnerable))
	player.died.connect(_finish_attempt.bind("defeat"))
	var context := get_node_or_null("/root/RunContext")
	player.set_sfx_volume_db(float(context.sfx_volume_db) if context != null else 0.0)
	player.discard_pending_combat_input()
	enemy_spawner = SPAWNER.new()
	add_child(enemy_spawner)
	enemy_spawner.initialize(self, player, rng, CONFIG.ENEMIES, Callable(), _get_multiplayer_player_nodes)
	enemy_spawner.configure_room(current_effective_room_size, 100.0, spawn_safe_radius, CONTRACTS.profile_enemy_mutator(current_profile))
	enemy_spawner.bearing_wave_interval_seconds = float(current_difficulty_config.get("wave_interval_seconds", 8.0))
	enemy_spawner.set_ascension_enemy_health_mult(float((current_difficulty_config.get("ascension", {}) as Dictionary).get("enemy_health_mult", 1.0)))
	objective_manager = OBJECTIVE_MANAGER.new()
	add_child(objective_manager)
	objective_runtime = OBJECTIVE_RUNTIME.new()
	add_child(objective_runtime)
	objective_runtime.initialize(self, rng, objective_manager)
	objective_overlay = OBJECTIVE_OVERLAY.new()
	objective_overlay.objective_manager = objective_manager
	add_child(objective_overlay)
	hud = OBJECTIVE_FEEDBACK.new()
	hud.arena = self
	add_child(hud)
	environment = ENVIRONMENT.new()
	add_child(environment)
	environment.configure(self, String(applied.biome_id), current_profile, has_boss)
	active_room_enemy_count = CONTRACTS.profile_total_enemy_count(current_profile)
	if has_boss:
		boss = BOSSES.create_boss_node(boss_stage, enemy_spawner.pick_room_position(270.0, 120.0), applied.encounter_id)
		add_child(boss)
		boss.set("arena_size", current_effective_room_size)
		boss.set_target_candidates([player])
		_apply_boss_difficulty(boss)
		_register_enemy(boss, applied.encounter_id)
		active_room_enemy_count = 1
	else:
		# Reserve the complete native profile before the first staggered wave.
		# A temporary zero living enemies must not complete a pending wave room.
		enemy_spawner.spawn_profile_enemies(current_profile)
	choosing_next_room = false
	OBJECTIVE_LIFECYCLE.new().reset_and_begin_for_new_room(objective_manager, objective_runtime, current_profile)
	current_config = applied.duplicate(true)
	draft_config = current_config.duplicate(true)
	mode = "active"
	combat_phase.begin_combat_phase(player, get_tree())
	player.set_physics_process(true)
	for actor in enemies:
		actor.combat_ai_enabled = bool(applied.enemy_ai)
		actor.set_physics_process(true)
	music_system.set_run_location(current_act, room_depth, has_boss)
	music_system.play_room_music(has_boss, false)
	_refresh_ui()
	_update_camera_frame()

func _apply_player_difficulty() -> void:
	player.set_incoming_damage_taken_mult(float(current_difficulty_config.get("player_damage_taken_mult", 1.0)))
	player.set_incoming_contact_damage_mult(float(current_difficulty_config.get("enemy_contact_damage_mult", 1.0)))
	var maximum := maxi(1, player.get_max_health() + int(current_difficulty_config.get("player_starting_health_bonus", 0)))
	maximum = maxi(1, int(round(float(maximum) * float(current_difficulty_config.get("player_max_health_mult", 1.0)))))
	player.set_max_health_and_current(maximum, maximum)

func _apply_boss_difficulty(actor: Node2D) -> void:
	var multiplier := float(current_difficulty_config.get("boss_difficulty_mult", 1.0))
	var maximum := maxi(1, int(round(float(actor.get_max_health()) * multiplier)))
	actor.set_max_health_and_current(maximum, maximum)
	for key in ["attack_damage", "charge_damage", "nova_damage", "cleave_damage", "prism_damage", "gravity_damage", "echo_dash_damage", "orbital_lance_damage", "polar_shift_pull_inner_damage", "sever_damage", "null_ring_damage", "gap_damage", "echo_cross_damage", "seam_tick_damage"]:
		if actor.get(key) != null:
			actor.set(key, maxi(1, int(round(float(actor.get(key)) * multiplier))))

func _register_enemy(actor: Node2D, id: String) -> void:
	enemies.append(actor)
	actor.set_meta("practice_enemy_id", id)
	actor.set_meta("practice_attempt", attempt)
	var network_id := actor.get_instance_id()
	actor.set_meta("network_enemy_id", network_id)
	EnemyReplicationService.enemy_nodes_by_id[network_id] = actor
	actor.died.connect(_on_enemy_died.bind(actor, attempt))
	actor.combat_ai_enabled = bool(current_config.get("enemy_ai", true))

func _on_enemy_died(actor: Node2D, generation: int) -> void:
	if generation != attempt or _transition_pending or mode != "active" or not is_instance_valid(actor):
		return
	if is_instance_valid(player) and not player.is_dead() and not (is_instance_valid(environment) and environment.rules.environment_damage_active):
		player.notify_enemy_killed(actor.global_position)
	EnemyReplicationService.enemy_nodes_by_id.erase(actor.get_instance_id())
	active_room_enemy_count = maxi(0, active_room_enemy_count - 1)
	_objective_progress.on_enemy_killed(objective_manager, objective_runtime, actor.global_position)
	if objective_manager.active_objective_kind.is_empty() and active_room_enemy_count == 0:
		_finish_attempt("victory")

func get_live_enemies() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for actor in enemies:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.get_current_health() > 0:
			result.append(actor)
	return result

func _get_multiplayer_player_nodes() -> Array:
	return [player] if is_instance_valid(player) and not player.is_dead() else []

func get_current_room_sync_id() -> int:
	return _world_multiplayer_sync_state.current_room_sync_id

func request_brittle_cover_attack(action: Dictionary, origin: Vector2, direction: Vector2, blast_strength: float = -1.0) -> void:
	if is_instance_valid(environment):
		environment.accept_attack(action, origin, direction, blast_strength)

func _fail_configuration(reason: String) -> void:
	_retire_attempt()
	mode = "error"
	detail = reason
	_refresh_ui()

func _process(delta: float) -> void:
	var active := mode == "active" and not _transition_pending
	if active:
		elapsed_seconds += maxf(0.0, delta)
		_objective_frame.tick(objective_manager, objective_runtime, delta, false)
	if is_instance_valid(environment):
		environment.tick(delta, mode == "active" and not _transition_pending, player, get_live_enemies())
	if is_instance_valid(renderer) and is_instance_valid(player):
		renderer.player_global_position = player.global_position
	_ui_refresh_left -= delta
	if _ui_refresh_left <= 0.0:
		_ui_refresh_left = 0.1
		_refresh_ui()

func _physics_process(_delta: float) -> void:
	if mode != "active" or not is_instance_valid(player):
		return
	_refresh_effective_bounds()
	var half := current_effective_room_size * 0.5
	player.global_position = player.global_position.clamp(-half, half)
	for actor in get_live_enemies():
		actor.global_position = actor.global_position.clamp(-half, half)

func _refresh_effective_bounds() -> void:
	var steps := 0.0
	var shrink := 0.0
	for actor in enemies:
		if not is_instance_valid(actor) or String(actor.get_meta("practice_enemy_id", "")) != "seamlock":
			continue
		steps = maxf(steps, float(actor.get("_arena_penalty_applied_steps")))
		shrink = maxf(shrink, float(actor.get("arena_shrink_per_step")))
	var effective := Vector2(maxf(320.0, current_room_size.x - steps * shrink * 2.0), maxf(240.0, current_room_size.y - steps * shrink * 2.0))
	if effective == current_effective_room_size:
		return
	current_effective_room_size = effective
	renderer.room_size = effective
	_update_camera_frame()
	if is_instance_valid(environment):
		environment.rules.set_room_context(effective, _get_biome_objective_exclusions(), true)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if mode == "active":
		request_pause()
	elif mode == "paused" or (mode == "setup" and _setup_can_resume):
		request_resume()
	else:
		return
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and mode == "active" and is_instance_valid(ui):
		request_pause()

func request_pause() -> void:
	if mode != "active" or _transition_pending:
		return
	mode = "paused"
	_set_combat_paused(true)
	_refresh_ui()

func request_resume() -> void:
	if _transition_pending or not (mode == "paused" or (mode == "setup" and _setup_can_resume)):
		return
	mode = "active"
	_setup_can_resume = false
	_set_combat_paused(false)
	_refresh_ui()

func _finish_attempt(outcome: String) -> void:
	if mode != "active" or _transition_pending:
		return
	mode = outcome
	choosing_next_room = true
	_set_combat_paused(true)
	combat_phase.end_combat_phase(player, get_tree())
	_refresh_ui()

func record_player_damage_dealt(amount: int, _peer: int, _killed: bool, _enemy_id: int) -> void:
	if not _transition_pending and mode in ["active", "victory", "defeat"]:
		damage_dealt += maxi(0, amount)

func presentation() -> Dictionary:
	var living := get_live_enemies()
	var health := 0
	var maximum := 0
	for actor in living:
		health += int(actor.get_current_health())
		maximum += int(actor.get_max_health())
	var validation := CONFIG.validate(draft_config)
	var objective := objective_manager.get_hud_state() if is_instance_valid(objective_manager) else {}
	objective["active"] = not String(objective.get("active_objective_kind", "")).is_empty()
	return {
		"mode": mode, "title": "Practice", "character_id": current_character_id,
		"character_name": String(CHARACTERS.get_character(current_character_id).name),
		"next_character_id": next_character_id, "available_characters": _available_characters(),
		"current_config": current_config.duplicate(true), "draft_config": draft_config.duplicate(true),
		"catalogue": CONFIG.catalogue(draft_config), "validation": validation.duplicate(true),
		"can_resume": mode == "paused" or (mode == "setup" and _setup_can_resume),
		"health": player.get_current_health() if is_instance_valid(player) else 0,
		"max_health": player.get_max_health() if is_instance_valid(player) else 0,
		"boss_health": health, "boss_max_health": maximum,
		"enemy_count": enemies.size(), "alive_count": living.size(),
		"attempt": attempt, "elapsed_seconds": elapsed_seconds, "detail": detail,
		"damage_dealt": damage_dealt, "objective_state": objective,
		"encounter_name": _encounter_name(String(current_config.get("encounter_id", draft_config.get("encounter_id", "warden")))),
		"encounter_status": _encounter_status(objective), "encounter_hint": _encounter_hint(objective), "remaining_enemy_count": active_room_enemy_count,
	}

func _refresh_ui() -> void:
	if is_instance_valid(ui):
		ui.present(presentation())

func _retire_attempt() -> void:
	if not is_instance_valid(player) and enemies.is_empty() and not is_instance_valid(encounter_profile_builder):
		return
	_set_combat_paused(false)
	combat_phase.end_combat_phase(player, get_tree())
	if is_instance_valid(player):
		player.discard_pending_combat_input()
		player.set_physics_process(false)
	for child in get_children():
		if child in [ui, renderer, music_system, power_registry]:
			continue
		child.set_physics_process(false)
		child.set_process(false)
		remove_child(child)
		child.queue_free()
	player = null
	boss = null
	enemies.clear()
	enemy_spawner = null
	environment = null
	encounter_profile_builder = null
	objective_manager = null
	objective_runtime = null
	objective_overlay = null
	hud = null
	current_profile.clear()
	active_room_enemy_count = 0
	choosing_next_room = true
	if is_instance_valid(renderer):
		renderer.set_obstacle_layout([] as Array[Dictionary])
		renderer.set_cover_rubble_layout([] as Array[Dictionary])
	if EnemyReplicationService.world_generator == self:
		EnemyReplicationService.clear_state()


func _party_is_active() -> bool:
	var context := get_node_or_null("/root/RunContext")
	return MultiplayerSessionManager.has_active_session_state() or (context != null and not String(context.multiplayer_session_id).is_empty())

func _update_camera_frame() -> void:
	if not is_inside_tree() or not is_instance_valid(player) or not is_instance_valid(ui):
		return
	var play_area: Rect2 = ui.get_gameplay_rect()
	if play_area.size.x <= 0.0 or play_area.size.y <= 0.0:
		return
	var camera := player.get_node("Camera2D") as Camera2D
	# Reserve the actual HUD/footer in viewport coordinates. The physical arena
	# and actors stay unchanged; only this camera's presentation is configured.
	var framed_size := current_effective_room_size + Vector2(80.0, 80.0)
	var fit_zoom := minf(play_area.size.x / framed_size.x, play_area.size.y / framed_size.y)
	var viewport_size := get_viewport_rect().size
	var center := (viewport_size * 0.5 - play_area.get_center()) / fit_zoom
	# Retain the real camera's processing and player feedback, but let this
	# fixed whole-arena frame own zoom instead of the full-viewport room fitter.
	camera.set("has_world_bounds", false)
	camera.set_static_mode(center)
	camera.set("target_zoom", Vector2.ONE * fit_zoom)
	camera.zoom = Vector2.ONE * fit_zoom
	camera.global_position = center
	camera.limit_left = -1000000
	camera.limit_top = -1000000
	camera.limit_right = 1000000
	camera.limit_bottom = 1000000
	camera.force_update_scroll()

func request_menu() -> void:
	if _transition_pending:
		return
	_transition_pending = true
	if is_instance_valid(player):
		_set_combat_paused(true)
	call_deferred("_return_to_menu")

func _return_to_menu() -> void:
	var menu_scene := load("res://scenes/Menu.tscn") as PackedScene
	if menu_scene == null:
		_transition_pending = false
		mode = "error"
		detail = "The main menu could not be opened."
		_refresh_ui()
		return
	var menu := menu_scene.instantiate()
	menu.set("practice_return_state", menu_return_state.duplicate(true))
	var tree := get_tree()
	_retire_attempt()
	EnemyReplicationService.unbind_world(self)
	tree.current_scene = null
	get_parent().remove_child(self)
	tree.root.add_child(menu)
	tree.current_scene = menu
	queue_free()

func _exit_tree() -> void:
	# Direct scene teardown exits child feedback before this callback. Normal
	# Retry/Menu already clear attached actors in _retire_attempt; do not ask an
	# exited feedback node to search a tree it no longer owns.
	if is_instance_valid(player) and player.is_inside_tree():
		player.discard_pending_combat_input()
		player.clear_lingering_combat_effects()
	EnemyReplicationService.unbind_world(self)

func _get_biome_objective_exclusions() -> Array[Dictionary]:
	var exclusions: Array[Dictionary] = []
	if not is_instance_valid(objective_manager):
		return exclusions
	var kind: String = objective_manager.active_objective_kind
	if kind == "relic_recovery":
		var recovery = objective_manager.relic_recovery
		exclusions.append({"kind": "circle", "center": recovery.receiver, "radius": recovery.RECEIVER_RADIUS + 24.0})
		for relic: Dictionary in recovery.relics:
			if not bool(relic.delivered) and int(relic.carrier_id) == 0:
				exclusions.append({"kind": "circle", "center": relic.position, "radius": recovery.PICKUP_RADIUS + 24.0})
		return exclusions
	if kind not in ["hold_the_line", "circuit_sweep", "intercept_run"]:
		return exclusions
	var overlay: Dictionary = objective_manager.get_control_overlay_state()
	if kind == "intercept_run":
		# Preserve a continuous escort route, including where the drone goes next.
		exclusions.append({"kind": "capsule", "start": overlay.drone_start, "end": overlay.drone_end, "radius": overlay.drone_radius})
	else:
		exclusions.append({"kind": "circle", "center": overlay.anchor, "radius": overlay.radius})
		if kind == "circuit_sweep" and is_instance_valid(objective_runtime):
			for node_position: Vector2 in objective_runtime.get_pending_sweep_node_positions():
				exclusions.append({"kind": "circle", "center": node_position, "radius": overlay.radius})
	return exclusions


func _set_combat_paused(paused: bool) -> void:
	combat_phase.set_combat_paused(player, get_tree(), paused)
	if is_instance_valid(enemy_spawner):
		enemy_spawner.wave_timer_paused = paused

func _clamp_position_to_current_room(point: Vector2, margin: float = 0.0) -> Vector2:
	var half := (current_effective_room_size * 0.5 - Vector2.ONE * margin).max(Vector2.ZERO)
	return point.clamp(-half, half)

func _objective_pressure_mult() -> float:
	return CONFIG.DIFFICULTY.get_objective_pressure_mult(current_difficulty_tier)

func _clear_all_enemies() -> void:
	if is_instance_valid(enemy_spawner):
		enemy_spawner.clear_all_enemies()
	for actor in enemies:
		if is_instance_valid(actor):
			EnemyReplicationService.enemy_nodes_by_id.erase(actor.get_instance_id())
	active_room_enemy_count = 0

func _on_room_cleared() -> void:
	_finish_attempt("victory")

func _encounter_name(id: String) -> String:
	for row: Dictionary in CONFIG.catalogue().encounters:
		if row.id == id:
			return row.name
	return "Encounter"

func _encounter_status(objective: Dictionary) -> String:
	var kind := String(objective.get("active_objective_kind", ""))
	match kind:
		"last_stand", "pulse_window":
			return "Kills %d / %d · %ds%s" % [objective.kills, objective.kill_target, ceili(objective.time_left), " · Overtime" if objective.overtime else ""]
		"cut_the_signal":
			return "Signal %d / %d HP · Escorts %d / %d" % [objective.hunt_target_health, objective.hunt_target_max_health, objective.hunt_target_kill_progress, objective.hunt_target_kill_goal]
		"hold_the_line":
			return "Control %.1f / %.1fs%s" % [objective.control_progress, objective.control_goal, " · Contested" if objective.control_contested else ""]
		"circuit_sweep":
			return "Nodes %d / %d · Capture %.1f / %.1fs" % [objective.sweep_nodes_completed, objective.sweep_node_count, objective.sweep_capture_progress, objective.sweep_capture_goal]
		"intercept_run":
			return "Drone %d%%%s" % [roundi(float(objective.intercept_drone_progress) * 100.0), " · Blocked" if objective.intercept_drone_stalled else ""]
		"relic_recovery":
			var recovery: Dictionary = objective.relic_recovery
			var delivered := 0
			for relic: Dictionary in recovery.get("relics", []):
				if bool(relic.get("delivered", false)):
					delivered += 1
			return "Relics delivered %d / %d" % [delivered, (recovery.get("relics", []) as Array).size()]
	if current_config.get("encounter_id", "") == "empty":
		return "Empty arena"
	return "%d foes remain%s" % [active_room_enemy_count, " · More waves pending" if is_instance_valid(enemy_spawner) and not enemy_spawner._pending_waves.is_empty() else ""]

func _encounter_hint(objective: Dictionary) -> String:
	match String(objective.get("active_objective_kind", "")):
		"pulse_window":
			if bool(objective.get("pulse_active", false)):
				return String((objective.pulse_active_mutator as Dictionary).get("name", "Pulse")) + ": " + String(objective.pulse_rule_text)
			return "Next pulse in %ds" % ceili(float(objective.get("pulse_next_timer", 0.0)))
		"cut_the_signal":
			if float(objective.get("exposure_left", 0.0)) > 0.0:
				return "Signal exposed for %.1fs" % float(objective.exposure_left)
			if float(objective.get("relocation_hint_left", 0.0)) > 0.0:
				return "Signal relocated · %d escorts moved" % int(objective.last_relocated_escort_count)
			return "Kill escorts to expose the marked target"
	return ""
