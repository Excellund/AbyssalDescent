class_name PlayerRosterHelpers
extends RefCounted

## Pure helpers for player-roster bring-up and queries used by world_generator.
## These functions take their inputs explicitly (no hidden world state) so the
## same logic powers both single-player and multiplayer paths and can be
## reasoned about in isolation from the World scene.

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const MULTIPLAYER_SESSION_MANAGER_SCRIPT := preload("res://scripts/multiplayer_session_manager.gd")
const REMOTE_PLAYER_SPAWN_RADIUS_PX: float = 80.0

## Slot 0 (host) stays at the spawn anchor; remaining slots fan around it on a
## ring of radius REMOTE_PLAYER_SPAWN_RADIUS_PX.
static func player_fan_offset(slot: int, total: int) -> Vector2:
	if total <= 1 or slot <= 0:
		return Vector2.ZERO
	var ring_count := total - 1
	var angle := TAU * float(slot - 1) / float(ring_count)
	return Vector2(cos(angle), sin(angle)) * REMOTE_PLAYER_SPAWN_RADIUS_PX

## Disable physics collision between two player bodies in both directions.
static func disable_player_collision_pair(primary_player: Node, secondary_player: Node) -> void:
	var primary_body := primary_player as PhysicsBody2D
	var secondary_body := secondary_player as PhysicsBody2D
	if primary_body == null or secondary_body == null:
		return
	primary_body.add_collision_exception_with(secondary_body)
	secondary_body.add_collision_exception_with(primary_body)

static func is_player_alive(player_node: Node) -> bool:
	var player := player_node as PLAYER_SCRIPT
	if player == null:
		return false
	return not player.is_dead()

static func is_local_control_owner(player_node: Node) -> bool:
	var player := player_node as PLAYER_SCRIPT
	if player != null:
		return player._is_local_control_owner()
	if player_node == null:
		return false
	return player_node.is_multiplayer_authority()

## Find the best candidate to bind the local camera/input to:
## prefer a locally-controlled, alive player; fall back to alive-only,
## then locally-controlled-only, then the first node in the roster.
static func find_local_player_node(party_nodes: Array) -> Node2D:
	for party_node in party_nodes:
		if is_local_control_owner(party_node) and is_player_alive(party_node):
			return party_node
	for party_node in party_nodes:
		if is_player_alive(party_node):
			return party_node
	for party_node in party_nodes:
		if is_local_control_owner(party_node):
			return party_node
	if not party_nodes.is_empty():
		return party_nodes[0] as Node2D
	return null

## Find the locally-owned player even if dead. Used by callers that must
## address actions back to the local peer's avatar regardless of liveness.
static func find_local_owned_player_node(party_nodes: Array) -> Node2D:
	for party_node in party_nodes:
		if is_local_control_owner(party_node):
			return party_node
	return find_local_player_node(party_nodes)

## Resolve the local peer id, preferring the active SceneTree multiplayer peer
## over any cached id on MultiplayerSessionManager. Falls back to the local
## player node's `player_id` property when no peer info is available.
static func resolve_local_peer_id(tree: SceneTree, mp_session_manager: Node, fallback_player: Node) -> int:
	if tree != null:
		var active_multiplayer := tree.get_multiplayer()
		if active_multiplayer != null:
			var active_peer_id := int(active_multiplayer.get_unique_id())
			if active_peer_id > 0:
				return active_peer_id
	if mp_session_manager != null:
		var session_manager := mp_session_manager as MULTIPLAYER_SESSION_MANAGER_SCRIPT
		if session_manager != null:
			return session_manager.local_peer_id
	var fallback := fallback_player as PLAYER_SCRIPT
	if fallback != null:
		return fallback.player_id
	return 0

## Resolve the active local character id, honoring the per-peer selection
## stored in run_context when it agrees with the global selected character.
static func resolve_local_character_id(run_context: Node, fallback_character_id: String, local_peer_id: int) -> String:
	if run_context == null:
		return fallback_character_id
	var resolved_character_id := fallback_character_id
	var selected_character_id := String(run_context.get_selected_character_id()).strip_edges().to_lower()
	if not selected_character_id.is_empty():
		resolved_character_id = selected_character_id
	if local_peer_id > 0:
		var peer_character_id := String(run_context.get_peer_character_selection(local_peer_id)).strip_edges().to_lower()
		if not peer_character_id.is_empty() and peer_character_id == selected_character_id:
			resolved_character_id = peer_character_id
	if resolved_character_id.is_empty():
		resolved_character_id = fallback_character_id
	return resolved_character_id

## Returns peer_id -> variant_index for all party peers.
## Peers sharing a character get distinct variants; the lowest peer_id (host = 1)
## keeps variant 0. Pure function over (run_context, party_nodes).
static func build_duplicate_variant_map(run_context: Node, party_nodes: Array) -> Dictionary:
	var variant_by_peer: Dictionary = {}
	if run_context == null:
		return variant_by_peer
	var peers_by_character: Dictionary = {}
	for party_node in party_nodes:
		var player := party_node as PLAYER_SCRIPT
		if player == null:
			continue
		var peer_id := player.player_id
		if peer_id <= 0:
			continue
		var character_id := String(run_context.get_peer_character_selection(peer_id)).strip_edges().to_lower()
		if character_id.is_empty():
			continue
		if not peers_by_character.has(character_id):
			peers_by_character[character_id] = []
		(peers_by_character[character_id] as Array).append(peer_id)
	for character_key in peers_by_character.keys():
		var peer_list: Array = peers_by_character[character_key]
		peer_list.sort()
		for index in peer_list.size():
			variant_by_peer[int(peer_list[index])] = index
	return variant_by_peer

## Debug print of per-player runtime stats. No-op when not in multiplayer.
static func log_multiplayer_player_stats(stage: String, party_nodes: Array, is_multiplayer: bool) -> void:
	if not is_multiplayer:
		return
	for player_node in party_nodes:
		var player := player_node as PLAYER_SCRIPT
		if player == null:
			continue
		print_debug("[Multiplayer][%s] %s peer=%d local_owner=%s character=%s range=%.1f arc=%.1f" % [
			stage,
			String(player.name),
			player.player_id,
			str(is_local_control_owner(player)),
			player.active_character_id,
			player.attack_range,
			player.attack_arc_degrees
		])
