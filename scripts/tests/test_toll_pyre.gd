extends "res://scripts/tests/test_live_arena_edges.gd"
const TOLL := preload("res://scripts/enemy_toll.gd")
const FIELD := preload("res://scripts/pyre_field.gd")
const FLOW := preload("res://scripts/core/player_flow_coordinator.gd")
const PHASE := preload("res://scripts/core/combat_phase_coordinator.gd")
var toll: TOLL

func _setup_toll() -> void:
	_setup()
	actor.player_id = 0
	toll = TOLL.new()
	_circle(toll, 34.0)
	room.add_child(toll)
	toll.set_physics_process(false)
	toll.target = actor
	toll.target_candidates = [actor]

func _begin(radius_start: float = 0.0) -> void:
	toll._begin_pulse_telegraph()
	toll._begin_pulse_expand()
	toll._pulse_radius = radius_start
	toll._pulse_phase_left = toll.pulse_expand_duration * (1.0 - radius_start / toll.pulse_max_radius)

func _done() -> void:
	_clear()
	await process_frame

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	await _test_pyre_lifetime()
	await _test_pyre_visibility_lifecycle()
	await _test_all_bearings()
	await _test_motion()
	await _test_history_boundaries()
	await _test_sectors_and_resets()
	await _test_pause_and_cleanup()
	await _test_replica()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Toll/Pyre: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_pyre_lifetime() -> void:
	for remaining in [0.0, 0.01, 0.1, 0.15]:
		_setup_toll()
		actor.global_position = Vector2.ZERO
		var field := FIELD.new()
		room.add_child(field)
		field.set_process(false)
		field.initialize(actor, 94.0, 6.5, 0.42, 7)
		field.time_left = remaining
		field.tick_left = 0.1
		field._process(0.2)
		_check(actor.get_current_health() == (93 if remaining > 0.1 else 100), "Pyre applies only a due tick strictly before its active lifetime ends")
		_check(not field.get_visual_state().active, "Pyre stops damage after its final partial step")
		field._process(FIELD.EXPIRY_FADE_DURATION)
		_check(field.is_queued_for_deletion(), "Pyre completes its short cosmetic fade")
		await _done()
	_setup_toll()
	room._spawn_synced_pyre_death_field({"radius": 94.0, "duration": 6.5, "tick_interval": 0.42})
	var remote_field: Node2D = get_nodes_in_group("enemy_lingering_effects").back()
	remote_field.set_process(false)
	remote_field._process(0.5)
	_check(remote_field.target == null and remote_field.tick_damage == 0 and actor.get_current_health() == 100, "Real World replica Pyre path keeps null target and zero damage")
	remote_field.queue_free()
	await _done()

func _test_pyre_visibility_lifecycle() -> void:
	_setup_toll()
	actor.global_position = Vector2(400.0, 0.0)
	var field := FIELD.new()
	room.add_child(field)
	field.set_process(false)
	field.initialize(actor, 94.0, 6.5, 0.42, 7)
	var previous_elapsed := 0.0
	var previous_ratio := 1.0
	for elapsed: float in [0.0, 0.8, 3.25, 5.5, 6.0, 6.49]:
		if elapsed > previous_elapsed:
			field._process(elapsed - previous_elapsed)
		var visual: Dictionary = field.get_visual_state()
		_check(visual.active and field.visible and not field.is_queued_for_deletion(), "Pyre remains visibly active at %.2fs while its lifetime permits damage" % elapsed)
		_check(float(visual.fill_alpha) >= 0.14 and float(visual.inner_alpha) > 0.0 and float(visual.boundary_alpha) >= 0.7, "Pyre keeps readable fill and boundary at %.2fs, including after flashes and near expiry" % elapsed)
		_check(float(visual.remaining_ratio) > 0.0 and float(visual.remaining_ratio) <= previous_ratio, "Pyre countdown decreases without fading its active danger at %.2fs" % elapsed)
		if elapsed <= 5.5:
			_check(not visual.expiry_warning, "Pyre does not signal imminent expiry during its main active lifetime")
		elif elapsed >= 6.0:
			_check(visual.expiry_warning, "Pyre gives a cosmetic countdown warning while late damage remains active")
		previous_elapsed = elapsed
		previous_ratio = float(visual.remaining_ratio)
	_check(actor.get_current_health() == 100 and is_equal_approx(field.current_radius, 94.0), "Pyre retains its full damage radius without reaching a player outside it")
	actor.global_position = Vector2(field.current_radius, 0.0)
	field.tick_left = 0.001
	field._process(0.005)
	var late_visual: Dictionary = field.get_visual_state()
	_check(actor.get_current_health() == 93 and late_visual.active and float(late_visual.boundary_alpha) >= 0.7, "A due tick on Pyre's exact radius remains visibly advertised during its final active interval")
	field._process(0.01)
	var expired_visual: Dictionary = field.get_visual_state()
	_check(not field.is_queued_for_deletion() and field.visible and not expired_visual.active, "Pyre starts a visible harmless fade when its damage lifetime ends")
	var initial_opacity := float(expired_visual.opacity)
	field.tick_left = 0.0
	field._process(FIELD.EXPIRY_FADE_DURATION * 0.5)
	var fading_visual: Dictionary = field.get_visual_state()
	_check(not fading_visual.active and float(fading_visual.opacity) > 0.0 and float(fading_visual.opacity) < initial_opacity, "Pyre smoothly dims halfway through its short harmless fade")
	_check(actor.get_current_health() == 93, "Even an overdue tick cannot damage during the fade")
	field._process(FIELD.EXPIRY_FADE_DURATION)
	expired_visual = field.get_visual_state()
	_check(field.is_queued_for_deletion() and not field.visible and not expired_visual.visible, "Pyre hides completely after its rapid fade")
	_check(float(expired_visual.fill_alpha) == 0.0 and float(expired_visual.inner_alpha) == 0.0 and float(expired_visual.boundary_alpha) == 0.0 and float(expired_visual.remaining_ratio) == 0.0, "Expired Pyre has no lingering danger fill, boundary or countdown")
	_check(actor.get_current_health() == 93, "Visual expiry does not add a damage tick")
	field._process(1.0)
	_check(actor.get_current_health() == 93 and not field.get_visual_state().active, "Deferred deletion cannot reactivate expired Pyre damage or presentation")
	await _done()
	_setup_toll()
	var cancelled := FIELD.new()
	room.add_child(cancelled)
	cancelled.set_process(false)
	cancelled.initialize(actor, 94.0, 6.5, 0.42, 7)
	cancelled.queue_free()
	_check(cancelled.time_left > 0.0 and not cancelled.get_visual_state().active, "Room cleanup cancels Pyre presentation even when its lifetime has time remaining")
	await _done()

func _test_all_bearings() -> void:
	for tier in range(4):
		_setup_toll()
		room.difficulty_provider = preload("res://scripts/core/difficulty_scaling_provider.gd").new(room)
		room._apply_difficulty_tier_bonuses(tier, false)
		var builder := preload("res://scripts/encounter_profile_builder.gd").new()
		room.add_child(builder)
		builder.set_difficulty_tier(tier)
		var spawner := preload("res://scripts/enemy_spawner.gd").new()
		room.add_child(spawner)
		spawner.scripts = {"toll": TOLL}
		spawner.current_room_enemy_mutator = builder._build_apex_toll_mutator()
		spawner._apply_enemy_mutator(toll, TOLL)
		_check(toll.pulse_damage == 18 and toll.pulse_max_radius == 380.0 and toll.pulse_band_thickness == 64.0 and toll.pulse_expand_duration == 1.1 and toll.pulse_telegraph_duration == 0.55, "Bearing%d real spawner retains original ring damage, geometry and windows" % tier)
		actor.global_position = Vector2(50,0)
		_begin()
		toll._tick_pulse(0.4)
		_check(actor.get_current_health() == 100 - [15,17,18,18][tier], "Bearing%d swept hit uses actual incoming-damage scaling" % tier)
		if not (builder.multiplayer_difficulty_config is RefCounted):
			builder.multiplayer_difficulty_config.free()
		await _done()

func _test_history_boundaries() -> void:
	for reposition in ["anchor", "bounds", "room"]:
		_setup_toll()
		actor.global_position = Vector2(250,0)
		_begin(350)
		actor.global_position = Vector2(450,0)
		if reposition == "anchor":
			toll.anchor_world_position = Vector2(0,10)
		elif reposition == "bounds":
			room.current_effective_room_size *= 0.95
		else:
			room._world_multiplayer_sync_state.current_room_sync_id += 1
		toll._tick_pulse(0.01)
		_check(actor.get_current_health() == 100, "Changing "+reposition+" cannot invent a historical pulse crossing")
		if reposition == "anchor":
			_check(toll.get_pulse_geometry().origin == toll.anchor_world_position, "Pulse follows an explicitly changed anchor after reseeding")
		if reposition == "room":
			_check(toll.get_pulse_geometry().is_empty(), "Old-room pulse cancels before dealing damage")
		await _done()
	_setup_toll()
	actor.global_position = Vector2(50,0)
	_begin()
	toll.global_position = Vector2(200,80)
	toll._tick_pulse(0.4)
	_check(actor.get_current_health() == 82 and toll.get_pulse_geometry().origin == Vector2.ZERO, "Displacing the body cannot displace its anchored pulse")
	await _done()
	_setup_toll()
	actor.global_position = Vector2(250,0)
	toll._begin_pulse_telegraph()
	actor.global_position = Vector2(450,0)
	toll._tick_pulse(toll.pulse_telegraph_duration)
	_check(toll._pulse_player_positions[actor.get_instance_id()] == actor.global_position, "Telegraph completion seeds current positions without replaying windup movement")
	for cycle in range(2):
		toll._end_pulse()
		toll._begin_pulse_telegraph()
	_check(toll._pulse_count == 3 and toll._pulse_is_directed, "Every third pulse keeps its directed spoke identity")
	await _done()
	_setup_toll()
	var pyre := preload("res://scripts/enemy_pyre.gd").new()
	room.add_child(pyre)
	pyre.set_physics_process(false)
	pyre.target = actor
	pyre.take_damage(10000)
	var field: Node2D = get_nodes_in_group("enemy_lingering_effects").back()
	field.set_process(false)
	_check(field.target == actor and field.tick_damage == 7, "Actual Pyre death preserves the existing single target and field damage")
	await process_frame
	_check(not is_instance_valid(pyre) and is_instance_valid(field) and field.time_left > 6.0, "Pyre field retains its intended lifetime after its owner disappears")
	await _done()

func _test_motion() -> void:
	for hitch in [false, true]:
		_setup_toll()
		actor.global_position = Vector2(50.0, 0.0)
		_begin()
		if hitch:
			toll._tick_pulse(0.4)
		else:
			for step in range(24):
				toll._tick_pulse(1.0 / 60.0)
		_check(actor.get_current_health() == 82, "Normal steps and a hitch accept the same original18-damage pulse once")
		_check(toll._pulse_marked_ids.size() == 1, "Each player is marked once for the whole pulse")
		await _done()
	for directed in [false, true]:
		_setup_toll()
		actor.global_position = Vector2(50.0, 0.0)
		_begin()
		toll._pulse_is_directed = directed
		toll._directed_spoke_angle = 0.0
		actor._set_dash_phasing(true)
		toll._tick_pulse(0.4)
		_check(actor.get_current_health() == (82 if directed else 100), "Regular pulse dash bypass and directed phase resistance are preserved")
		await _done()
	_setup_toll()
	actor.global_position = Vector2(100.0, 0.0)
	_begin(170.0)
	actor.apply_trial_power("blast_drive")
	actor.aim = Vector2.LEFT
	actor.arcana_motion.tick(0.02)
	actor.arcana_motion.release_blast(1.0)
	actor.arcana_motion.process_movement(0.2, Vector2.ZERO)
	toll._tick_pulse(0.2)
	_check(actor.get_current_health() == 82 and actor.global_position.x > 260.0, "Actual recoil crossing resolves at the same time as the moving band")
	_check(is_equal_approx(actor.velocity.length(), 360.0), "Pulse nudge remains exactly360 using the current outward direction")
	await _done()
	_setup_toll()
	actor.global_position = Vector2(250.0, 0.0)
	_begin(380.0 * (1.0 - 0.05 / 1.1))
	actor.global_position.x = 450.0
	toll._tick_pulse(0.2)
	_check(actor.get_current_health() == 100 and toll._pulse_phase == TOLL.PULSE_PHASE_NONE, "Movement after a pulse's final partial lifetime cannot invent a hit")
	await _done()

func _test_sectors_and_resets() -> void:
	_check(is_inf(TOLL._first_pulse_contact_fraction(Vector2(-90,100), Vector2(180,0), 100,100,64,true,0)), "An outer tangent at the exact spoke boundary remains safe")
	_check(is_inf(TOLL._first_pulse_contact_fraction(Vector2(0,150), Vector2(150,-150), 100,200,20,true,0)), "Entering a spoke only after the band passed is safe")
	_check(not is_inf(TOLL._first_pulse_contact_fraction(Vector2(150,0), Vector2(-150,150), 100,200,20,true,0)), "A true spoke contact still hits when the player ends in a safe gap")
	for distance in [80.0,100.0]:
		_check(TOLL._first_pulse_contact_fraction(Vector2(distance,0), Vector2.ZERO,100,100,20,false,0) == 0.0, "Both closed radial boundaries remain included")
	_check(is_inf(TOLL._first_pulse_contact_fraction(Vector2.RIGHT.rotated(PI/6.0)*90, Vector2.ZERO,100,100,20,true,0)), "Exact angular boundary remains outside the strict spoke")
	_check(TOLL._first_pulse_contact_fraction(Vector2.ZERO, Vector2.ZERO,0,0,64,true,0) == 0.0, "Center retains the existing angle-zero convention when covered")
	_check(is_inf(TOLL._first_pulse_contact_fraction(Vector2.ZERO, Vector2.ZERO,0,0,64,true,PI/3)), "Center remains safe when angle zero lies in a gap")
	_setup_toll()
	actor.global_position = Vector2(250,0)
	_begin(350)
	FLOW.new().reset_player_position(actor,Vector2(450,0))
	toll._tick_pulse(0.01)
	_check(actor.get_current_health() == 100, "Explicit reset never creates a crossing through the pulse")
	actor.global_position.x = 350
	toll._tick_pulse(0.01)
	_check(actor.get_current_health() == 82, "Normal movement after a reset keeps its real crossing")
	await _done()
	_setup_toll()
	actor.global_position = Vector2(50,0)
	_begin()
	actor.set_combat_removed(true)
	toll._tick_pulse(0.4)
	_check(actor.get_current_health() == 100 and toll._pulse_player_positions.is_empty(), "Departed player is excluded and its history removed")
	await _done()

func _test_pause_and_cleanup() -> void:
	_setup_toll()
	actor.global_position = Vector2(50,0)
	_begin()
	var coordinator := PHASE.new()
	coordinator.set_combat_paused(actor,self,true)
	var life := toll._pulse_phase_left
	await create_timer(0.05).timeout
	_check(not toll.is_physics_processing() and toll._pulse_phase_left == life, "Real modal pause freezes Toll's pulse clock")
	coordinator.set_combat_paused(actor,self,false)
	actor.damage_taken.connect(func(_raw:int,_final:int,_context:Dictionary): toll.take_damage(10000))
	toll._tick_pulse(0.4)
	_check(toll.is_queued_for_deletion() and toll._pulse_phase == TOLL.PULSE_PHASE_NONE, "Synchronous owner death clears the pulse during a hit callback")
	_check(actor.external_slow_left == 0.0, "Owner death prevents posthumous slow application")
	await _done()

func _test_replica() -> void:
	_setup_toll()
	actor.global_position = Vector2(200,0)
	_begin()
	var packet := toll._get_custom_network_runtime_state().duplicate(true)
	var replica := TOLL.new()
	room.add_child(replica)
	replica.set_physics_process(false)
	replica.set_network_simulation_enabled(false)
	replica._apply_custom_network_runtime_state(packet)
	_check(not replica.get_pulse_geometry().is_empty(), "Replica receives host pulse geometry")
	replica._process_network_visuals(TOLL.PULSE_VISUAL_LEASE+0.01)
	_check(replica.get_pulse_geometry().is_empty(), "A lost final pulse packet expires presentation")
	replica._apply_custom_network_runtime_state(packet)
	_check(replica.get_pulse_geometry().is_empty(), "Equal stale packet cannot revive expired presentation")
	var malformed := toll._get_custom_network_runtime_state().duplicate(true)
	malformed.pc[0] += 1000
	malformed.pc[6][0] = Vector2.INF
	replica._apply_custom_network_runtime_state(malformed)
	replica._apply_custom_network_runtime_state(toll._get_custom_network_runtime_state())
	_check(not replica.get_pulse_geometry().is_empty(), "Malformed high revision cannot poison the next valid snapshot")
	replica.target = actor
	replica.target_candidates = [actor]
	replica._tick_pulse(0.4)
	replica._apply_pulse_hit(actor,200.0)
	_check(actor.get_current_health() == 100 and actor.external_slow_left == 0.0, "Replica helper paths cannot author pulse damage or slow")
	await _done()
