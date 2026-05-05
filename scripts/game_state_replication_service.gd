extends Node
## Service for syncing game state (room progression, boss status, encounter seed) across multiplayer peers.
## Host broadcasts authoritative state; clients receive and apply it.

signal room_depth_changed(new_depth: int)
signal room_cleared()
signal boss_unlocked()
signal boss_defeated()

## Reference to world_generator (populated by caller)
var world_generator: Node = null

## Internal state
var local_room_depth: int = 0
var local_rooms_cleared: int = 0
var local_boss_unlocked: bool = false


func _ready() -> void:
	set_process(false)  ## Only host needs to broadcast; clients listen via RPCs


## Initialize the service (called from world_generator).
func initialize(world_gen: Node) -> void:
	world_generator = world_gen


## Called by world_generator when a new room is entered.
## Host broadcasts this to all peers.
func on_room_entered(depth: int, encounter_seed: int) -> void:
	if not MultiplayerSessionManager.is_session_connected():
		return
	
	if MultiplayerSessionManager.is_host():
		_sync_room_entered.rpc(depth, encounter_seed)
	else:
		pass


## Called by world_generator when a room is cleared.
## Host broadcasts this to all peers.
func on_room_cleared(new_depth: int, new_rooms_cleared: int) -> void:
	if not MultiplayerSessionManager.is_session_connected():
		return
	
	if MultiplayerSessionManager.is_host():
		_sync_room_cleared.rpc(new_depth, new_rooms_cleared)
	else:
		pass


## Called by world_generator when boss is unlocked.
func on_boss_unlocked() -> void:
	if not MultiplayerSessionManager.is_session_connected():
		return
	
	if MultiplayerSessionManager.is_host():
		_sync_boss_unlocked.rpc()
	else:
		pass


## Called by world_generator when boss is defeated (run clear).
func on_boss_defeated() -> void:
	if not MultiplayerSessionManager.is_session_connected():
		return
	
	if MultiplayerSessionManager.is_host():
		_sync_boss_defeated.rpc()
	else:
		pass


## RPC: Sync room entry (with encounter seed for deterministic generation).
@rpc("reliable")
func _sync_room_entered(depth: int, encounter_seed: int) -> void:
	local_room_depth = depth
	room_depth_changed.emit(depth)
	print_debug("[GameStateReplication] Room entered at depth %d, seed %d" % [depth, encounter_seed])


## RPC: Sync room clear.
@rpc("reliable")
func _sync_room_cleared(new_depth: int, new_rooms_cleared: int) -> void:
	local_room_depth = new_depth
	local_rooms_cleared = new_rooms_cleared
	room_cleared.emit()
	print_debug("[GameStateReplication] Room cleared. Depth: %d, Rooms: %d" % [new_depth, new_rooms_cleared])


## RPC: Sync boss unlock.
@rpc("reliable")
func _sync_boss_unlocked() -> void:
	local_boss_unlocked = true
	boss_unlocked.emit()
	print_debug("[GameStateReplication] Boss unlocked")


## RPC: Sync boss defeat (run completion).
@rpc("reliable")
func _sync_boss_defeated() -> void:
	boss_defeated.emit()
	print_debug("[GameStateReplication] Boss defeated - run complete")


## Get current local state snapshot.
func get_state() -> Dictionary:
	return {
		"room_depth": local_room_depth,
		"rooms_cleared": local_rooms_cleared,
		"boss_unlocked": local_boss_unlocked
	}
