extends SceneTree
## Real local RPC delivery and native Player life callbacks. The paired ENet
## fixture covers remote sender identities and the same-turn clear/revive race.

const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")

class Replication extends "res://scripts/player_replication_service.gd":
	func _ready() -> void:
		super._ready()
		set_process(false)

class Actor extends "res://scripts/player.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)

var checks := 0
var failures: Array[String] = []
var audio_retirement := RETIREMENT.new()
var service: Replication
var actors: Array[Actor] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _make_service(local_id: int, connected: bool) -> void:
	MultiplayerSessionManager.local_peer_id = local_id
	MultiplayerSessionManager.is_host_peer = local_id == 1
	MultiplayerSessionManager.session_connected = connected
	service = Replication.new()
	root.add_child(service)
	check(service.local_peer_id == local_id and service.multiplayer_session_manager == MultiplayerSessionManager, "Native service setup retains the current session identity: %d" % local_id)
	for peer_id in [1, 2]:
		var actor := Actor.new()
		actor.player_id = peer_id
		actor.is_local_player = peer_id == local_id
		root.add_child(actor)
		actor.set_max_health_and_current(100, 100)
		service.register_player(peer_id, actor)
		actors.append(actor)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Player life authority requires disposable profile isolation")
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	_make_service(1, true)
	await _test_host_life_cycles()
	await _cleanup()
	_make_service(2, true)
	_test_joiner_life_gates()
	await _cleanup()
	_make_service(1, false)
	_test_solo_life()
	await _cleanup()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Player life fixture retires native audio")
	print("[OK] Player life authority: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_host_life_cycles() -> void:
	for cached_id in [1, 2]:
		service.local_peer_id = cached_id
		check(service._is_host_life_state_sender(), "Current host remains locally authoritative with cached ID %d" % cached_id)
		for actor in actors:
			var label := "host/cache%d/player%d" % [cached_id, actor.player_id]
			var deaths: Array[int] = []
			var death_listener := func(): deaths.append(actor.get_current_health())
			actor.died.connect(death_listener)
			for cycle in 3:
				actor.set_health(0)
				service.broadcast_player_died(actor.player_id)
				check(actor.is_dead() and not actor._is_alive_state and actor._combat_removed and not actor.visible, label + ": native host death removes the actor")
				check(deaths.size() == cycle + 1, label + ": native health death signal remains once per cycle")
				service.broadcast_player_revived(actor.player_id)
				check(actor.get_current_health() == 1 and actor._is_alive_state and not actor._combat_removed and actor.visible, label + ": native host revival retains ordinary 1HP and visibility")
				actor.set_physics_process(false)
				await process_frame
			actor.died.disconnect(death_listener)
			# Direct local delivery is also role-based when there is no RPC sender.
			service._sync_player_alive_status(actor.player_id, false)
			service._sync_player_revived(actor.player_id)
			check(actor.get_current_health() == 1 and actor._is_alive_state and not actor._combat_removed, label + ": direct host life delivery does not depend on the cached identity")
			actor.set_physics_process(false)

func _test_joiner_life_gates() -> void:
	for cached_id in [2, 1]:
		service.local_peer_id = cached_id
		check(not service._is_host_life_state_sender(), "Current joiner cannot claim local host delivery with cached ID %d" % cached_id)
		for actor in actors:
			actor.revive_with_health(30.0)
			actor.set_physics_process(false)
			service.broadcast_player_died(actor.player_id)
			service.broadcast_player_revived(actor.player_id, 70.0)
			check(actor.get_current_health() == 30 and actor._is_alive_state and not actor._combat_removed and actor.visible, "Joiner broadcasts cannot echo another death/revival locally")
			service._sync_player_alive_status(actor.player_id, false)
			service._sync_player_revived(actor.player_id, 70.0)
			check(actor.get_current_health() == 30 and actor._is_alive_state and not actor._combat_removed and actor.visible, "Unattributed local joiner delivery cannot alter host life state")
	service.local_peer_id = 2
	check(service._is_authority_for_peer(2) and not service._is_authority_for_peer(1), "Generic owner authority remains independent of host-only life state")
	service.broadcast_cue_event(2, "attack_feedback", {"strength": 1})
	service.broadcast_cue_event(1, "attack_feedback", {"strength": 1})
	check(service._pending_cue_events_by_peer.has(2) and not service._pending_cue_events_by_peer.has(1), "Joiner-owned action feedback still queues through the unchanged owner path")
	# The ordinary local death callback still runs even though its outbound
	# life echo is suppressed; sounds/stats continue to receive native signals.
	var deaths: Array[int] = []
	actors[1].died.connect(func(): deaths.append(actors[1].get_current_health()))
	actors[1].set_health(0)
	check(actors[1].is_dead() and deaths == [0], "Joiner's native local death signal is preserved")

func _test_solo_life() -> void:
	var actor := actors[0]
	var deaths: Array[int] = []
	actor.died.connect(func(): deaths.append(actor.get_current_health()))
	actor.set_health(0)
	check(actor.is_dead() and deaths == [0], "Solo retains its native local death signal")
	actor.revive_with_health()
	actor.set_physics_process(false)
	check(actor.get_current_health() == 1 and actor._is_alive_state and not actor._combat_removed, "Solo explicit local revival is unchanged")
	for missing_manager in [false, true]:
		if missing_manager:
			service.multiplayer_session_manager = null
		check(not service._is_host_life_state_sender(), "No-session/missing-manager state is not a connected host")
		service.broadcast_player_died(1)
		service.broadcast_player_revived(1, 75.0)
		check(actor.get_current_health() == 1 and actor._is_alive_state and not actor._combat_removed, "No-session/missing-manager broadcasts leave local life handling unchanged")

func _cleanup() -> void:
	MultiplayerSessionManager.session_connected = false
	for actor in actors:
		service.unregister_player(actor.player_id)
		actor.upgrade_system.power_registry.free()
		actor.queue_free()
	actors.clear()
	service.queue_free()
	await process_frame
	await process_frame
