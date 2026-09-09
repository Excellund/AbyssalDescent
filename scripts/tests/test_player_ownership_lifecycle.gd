extends SceneTree
## Real native peers retained on the MultiplayerAPI through close/reconnect.

const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
class Actor extends "res://scripts/player.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Player ownership lifecycle requires isolated user data")
		quit(1)
		return
	MultiplayerSessionManager.session_connected = false
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var local := Actor.new()
	local.player_id = 1
	world.add_child(local)
	var remote := Actor.new()
	remote.player_id = 2
	# Leave the provisional flag true to also prove peer ID authentication.
	world.add_child(remote)
	check(get_multiplayer().multiplayer_peer is OfflineMultiplayerPeer and local._is_local_control_owner(), "A real offline peer preserves the local solo avatar")
	check(not remote._is_local_control_owner(), "Offline peer ID does not adopt another provisionally local avatar")
	var host := ENetMultiplayerPeer.new()
	host.set_bind_ip("127.0.0.1")
	check(host.create_server(0) == OK, "Native loopback host opens on an ephemeral port")
	var host_port := host.host.get_local_port()
	get_multiplayer().multiplayer_peer = host
	check(local._is_local_control_owner() and not remote._is_local_control_owner(), "Connected native host authenticates the actual local and remote IDs")
	local.player_feedback.play_damage_flash()
	var old_layer: CanvasLayer = local.player_feedback.damage_flash_layer
	check(is_instance_valid(old_layer), "Connected owner creates its actual damage flash")
	host.close()
	check(get_multiplayer().multiplayer_peer == host and host.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED, "Real close leaves a closed assigned peer before scene teardown")
	check(not local._is_local_control_owner() and not remote._is_local_control_owner(), "Closed ENet cannot grant control to either surviving network avatar")
	local.player_feedback._process(0.0)
	check(local.player_feedback.damage_flash_layer == null and not old_layer.visible, "Losing transport retires the live flash immediately")
	local.player_feedback.play_damage_flash()
	remote.player_feedback.play_damage_flash()
	check(local.player_feedback.damage_flash_layer == null and remote.player_feedback.damage_flash_layer == null, "Closed-peer impacts cannot recreate owner screen layers")
	# Keep all real feedback, Double and motion observers alive for actual frames.
	await process_frame
	await process_frame
	check(local.player_id == 1 and remote.player_id == 2, "Closed-peer ownership checks preserve avatar identity")
	remote.is_local_player = false
	get_multiplayer().multiplayer_peer = null
	check(local._is_local_control_owner() and not remote._is_local_control_owner(), "Null-peer fallback preserves the local flag and rejects actual remote avatars")
	var connecting := ENetMultiplayerPeer.new()
	check(connecting.create_client("127.0.0.1", host_port) == OK, "Native client enters connecting state on the retired ephemeral endpoint")
	get_multiplayer().multiplayer_peer = connecting
	check(connecting.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING, "Connecting test exercises native transport before a connection can succeed")
	local.player_id = connecting.get_unique_id()
	check(not local._is_local_control_owner() and not remote._is_local_control_owner(), "Connecting transport grants no network-avatar control")
	local.player_feedback.play_damage_flash()
	check(local.player_feedback.damage_flash_layer == null, "Connecting cannot allocate an owner screen flash")
	connecting.close()
	var replacement := ENetMultiplayerPeer.new()
	replacement.set_bind_ip("127.0.0.1")
	check(replacement.create_server(0) == OK, "A new native peer reconnects without rebuilding avatars")
	get_multiplayer().multiplayer_peer = replacement
	local.player_id = 1
	check(local._is_local_control_owner() and not remote._is_local_control_owner(), "Connected replacement restores only the actual local owner")
	local.player_id = 2
	check(not local._is_local_control_owner(), "Connected mismatched ID remains a replica despite its local flag")
	local.player_id = 1
	local.player_feedback.play_impact_heavy(local.global_position)
	check(local.player_feedback.damage_flash_layer != null and is_equal_approx(local.player_feedback.damage_flash_rect.modulate.a, 0.585), "Reconnected owner restores the unchanged heavy flash")
	local.is_local_player = false
	local.player_feedback._process(0.0)
	check(not local._is_local_control_owner() and local.player_feedback.damage_flash_layer == null, "Explicit ownership reassignment still overrides an authenticated ID")
	replacement.close()
	get_multiplayer().multiplayer_peer = null
	for actor in [local, remote]:
		actor.upgrade_system.power_registry.free()
	current_scene = null
	world.free()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Player ownership lifecycle: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
