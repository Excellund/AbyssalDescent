extends Control
## Lobby UI controller. Handles character selection, difficulty selection (host), ready state, and transition to main game.

const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")
const MENU_SCENE_PATH := "res://scenes/Menu.tscn"

@onready var room_code_label: Label = $VBoxContainer/RoomCodePanel/RoomCodeLabel
@onready var player_list: ItemList = $VBoxContainer/PlayerListPanel/VBoxContainer2/PlayerList
@onready var character_selector: TabContainer = $VBoxContainer/CharacterSelectorPanel/VBoxContainer3/CharacterTabs
@onready var difficulty_selector: OptionButton = $VBoxContainer/DifficultySelectorPanel/HBoxContainer/DifficultyDropdown
@onready var difficulty_panel: PanelContainer = $VBoxContainer/DifficultySelectorPanel
@onready var ready_button: Button = $VBoxContainer/ReadyButton
@onready var leave_lobby_button: Button = $VBoxContainer/LeaveLobbyButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

var available_characters: Array = []

## Local player state
var local_character_id: String = ""
var local_peer_id: int = 0
var local_is_ready: bool = false

## Multiplayer state (peer_id -> { character_id, is_ready })
var peer_state: Dictionary = {}

## Difficulty state (host only)
var selected_difficulty_tier: int = 1  ## Default: Delver
var multiplayer_session_manager


func _ready() -> void:
	print("[Lobby] === LOBBY CONTROLLER READY START ===")
	if room_code_label == null or player_list == null or character_selector == null or difficulty_selector == null or ready_button == null or leave_lobby_button == null or status_label == null:
		push_error("[LobbyController] Lobby scene UI node paths are invalid or missing")
		return

	available_characters = CHARACTER_REGISTRY.get_launch_character_ids()
	multiplayer_session_manager = get_node_or_null("/root/MultiplayerSessionManager")
	if multiplayer_session_manager == null:
		push_error("[LobbyController] MultiplayerSessionManager autoload is missing")
		return

	local_peer_id = int(multiplayer_session_manager.local_peer_id)
	if local_peer_id <= 0:
		local_peer_id = int(get_tree().get_multiplayer().get_unique_id())
	
	print("[Lobby] Local peer ID at _ready: %d, is_host: %s" % [local_peer_id, multiplayer_session_manager.is_host()])
	print("[Lobby] multiplayer_session_manager.get_peer_ids() at _ready: %s" % [str(multiplayer_session_manager.get_peer_ids())])
	
	## UI setup
	room_code_label.text = "Room Code: %s" % String(multiplayer_session_manager.room_code)
	
	## Character selector setup
	_populate_character_tabs()
	
	## Difficulty selector setup (host only)
	_setup_difficulty_selector()
	
	## Ready button
	ready_button.pressed.connect(_on_ready_button_pressed)
	leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)
	print("[Lobby] Leave button connected to _on_leave_lobby_pressed")
	
	## Connect to multiplayer signals
	multiplayer_session_manager.peer_connected.connect(_on_peer_connected)
	multiplayer_session_manager.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer_session_manager.session_joined.connect(_on_session_joined)
	print("[Lobby] Connected to multiplayer signals")
	
	## Initialize local peer state
	local_character_id = available_characters[0] if not available_characters.is_empty() else "bastion"
	_ensure_local_peer_state(local_character_id)
	print("[Lobby] After _ensure_local_peer_state in _ready, peer_state: %s" % [str(peer_state)])
	
	## HOST: Query existing connected peers from MultiplayerSessionManager
	if bool(multiplayer_session_manager.is_host()):
		var existing_peers = multiplayer_session_manager.get_peer_ids()
		print("[Lobby] HOST: Querying existing peers from manager: %s" % [str(existing_peers)])
		for peer_id in existing_peers:
			if peer_id != local_peer_id and peer_id not in peer_state:
				peer_state[peer_id] = { "character_id": "bastion", "is_ready": false }
				print("[Lobby] HOST: Added existing peer %d to peer_state" % peer_id)
	
	_update_player_list()
	print("[Lobby] === LOBBY CONTROLLER READY END ===")
	
	## Enable periodic sync
	set_process(true)


func _process(_delta: float) -> void:
	## Periodically sync peer_state with actual connected peers (especially for host)
	if multiplayer_session_manager == null or not multiplayer_session_manager.session_connected:
		return
	
	var actual_peers = multiplayer_session_manager.get_peer_ids()
	var state_peers = peer_state.keys()

	## Client can remain in a pre-connect state briefly; do not purge local UI state yet.
	if not bool(multiplayer_session_manager.is_host()) and actual_peers.is_empty():
		return
	
	## Check if we're missing any peers that connected without firing signal
	for peer_id in actual_peers:
		if peer_id not in peer_state:
			print("[Lobby] SYNC: Found peer %d that's not in peer_state. Adding..." % peer_id)
			peer_state[peer_id] = { "character_id": "bastion", "is_ready": false }
			_update_player_list()
	
	## Check if we have stale peers that disconnected without firing signal
	for peer_id in state_peers:
		if peer_id == local_peer_id:
			continue
		if peer_id not in actual_peers:
			print("[Lobby] SYNC: Peer %d no longer connected. Removing from peer_state..." % peer_id)
			peer_state.erase(peer_id)
			_update_player_list()


func _client_can_send_rpcs() -> bool:
	if multiplayer_session_manager == null or not multiplayer_session_manager.session_connected:
		return false
	if bool(multiplayer_session_manager.is_host()):
		return true
	var actual_peers = multiplayer_session_manager.get_peer_ids()
	return 1 in actual_peers


## Populate character tabs (one per character).
func _populate_character_tabs() -> void:
	for child in character_selector.get_children():
		child.queue_free()
	
	for char_id in available_characters:
		var char_data: Dictionary = CHARACTER_REGISTRY.get_character(String(char_id))
		var page := Control.new()
		page.name = String(char_data.get("name", char_id))
		character_selector.add_child(page)
	
	character_selector.tab_changed.connect(_on_character_tab_changed)


## Setup difficulty selector (host only, disabled for clients).
func _setup_difficulty_selector() -> void:
	difficulty_selector.add_item("Pilgrim (Easy)", 0)
	difficulty_selector.add_item("Delver (Normal)", 1)
	difficulty_selector.add_item("Harbinger (Hard)", 2)
	difficulty_selector.add_item("Forsworn (Extreme)", 3)
	
	difficulty_selector.select(selected_difficulty_tier)
	difficulty_selector.item_selected.connect(_on_difficulty_selected)
	
	## If not host, disable selector and show as read-only
	if not bool(multiplayer_session_manager.is_host()):
		difficulty_selector.disabled = true
		status_label.text = "Waiting for host to select difficulty..."


## Called when local player changes character tab.
func _on_character_tab_changed(tab_index: int) -> void:
	if tab_index < 0 or tab_index >= available_characters.size():
		return
	local_character_id = available_characters[tab_index]
	if bool(multiplayer_session_manager.is_host()):
		_broadcast_character_selection.rpc(local_peer_id, local_character_id)
	else:
		if not _client_can_send_rpcs():
			status_label.text = "Still connecting to host..."
			return
		_request_character_selection.rpc_id(1, local_character_id)


## Called when host changes difficulty.
func _on_difficulty_selected(index: int) -> void:
	selected_difficulty_tier = difficulty_selector.get_item_id(index)
	if bool(multiplayer_session_manager.is_host()):
		_broadcast_difficulty.rpc(selected_difficulty_tier)
	else:
		if not _client_can_send_rpcs():
			status_label.text = "Still connecting to host..."
			return
		_request_difficulty_change.rpc_id(1, selected_difficulty_tier)


## Called when local player clicks Ready.
func _on_ready_button_pressed() -> void:
	if not bool(multiplayer_session_manager.is_host()) and not _client_can_send_rpcs():
		status_label.text = "Still connecting to host..."
		return
	local_is_ready = true
	ready_button.disabled = true
	ready_button.text = "READY ✓"
	if bool(multiplayer_session_manager.is_host()):
		_broadcast_ready_state.rpc(local_peer_id, true)
	else:
		_request_ready_state.rpc_id(1, true)


## Called when a peer connects.
func _on_peer_connected(peer_id: int) -> void:
	print("[Lobby] Signal: Peer %d connected. Current peer_state: %s" % [peer_id, peer_state.keys()])
	if peer_id not in peer_state:
		peer_state[peer_id] = { "character_id": "bastion", "is_ready": false }
		print("[Lobby] Added peer %d to peer_state. Now: %s" % [peer_id, peer_state.keys()])
	else:
		print("[Lobby] Peer %d already in peer_state (no change)" % peer_id)
	_update_player_list()


## Called when a peer disconnects.
func _on_peer_disconnected(peer_id: int) -> void:
	peer_state.erase(peer_id)
	_update_player_list()


func _on_session_joined(_session_id: String) -> void:
	print("[Lobby] Signal: session_joined received. session_id=%s" % _session_id)
	local_peer_id = int(multiplayer_session_manager.local_peer_id)
	if local_peer_id <= 0:
		local_peer_id = int(get_tree().get_multiplayer().get_unique_id())
	print("[Lobby] Local peer ID confirmed: %d" % local_peer_id)
	_ensure_local_peer_state(local_character_id)
	print("[Lobby] After _ensure_local_peer_state, peer_state: %s" % [str(peer_state)])
	
	## Client: also initialize host (peer 1) in peer_state so player list isn't empty
	if not bool(multiplayer_session_manager.is_host()):
		print("[Lobby] This is a CLIENT peer. Host is peer: 1")
		if 1 not in peer_state:
			peer_state[1] = { "character_id": "bastion", "is_ready": false }
			print("[Lobby] CLIENT: Added host (peer 1) to peer_state. Now: %s" % [str(peer_state)])
		else:
			print("[Lobby] CLIENT: Host (peer 1) already in peer_state")
	else:
		print("[Lobby] This is a HOST peer")
	
	_update_player_list()


## Update the player list UI.
func _update_player_list() -> void:
	print("[Lobby] === UPDATE PLAYER LIST START ===")
	print("[Lobby] peer_state keys: %s" % [str(peer_state.keys())])
	print("[Lobby] multiplayer_session_manager.get_peer_ids(): %s" % [str(multiplayer_session_manager.get_peer_ids())])
	print("[Lobby] Is host: %s" % multiplayer_session_manager.is_host())
	player_list.clear()

	var peer_ids: Array = peer_state.keys()
	peer_ids.sort()
	print("[Lobby] Building player list with peer_ids: %s" % [str(peer_ids)])
	for peer_id in peer_ids:
		var state: Dictionary = peer_state.get(peer_id, {})
		var char_name: String = state.get("character_id", "???")
		var is_ready: bool = state.get("is_ready", false)
		var status: String = "✓" if is_ready else "○"
		var label: String = "[Peer %d] %s %s" % [peer_id, char_name, status]
		print("[Lobby] Adding item: %s" % label)
		player_list.add_item(label)
	
	## Update on-screen debug status
	_update_debug_status()
	
	print("[Lobby] === UPDATE PLAYER LIST END (total items: %d) ===" % player_list.item_count)


func _update_debug_status() -> void:
	var is_connected = multiplayer_session_manager.session_connected
	var is_host = multiplayer_session_manager.is_host()
	var peer_count = peer_state.keys().size()
	var role = "HOST" if is_host else "CLIENT"
	var status_text = "Role: %s | Peer ID: %d | Connected Players: %d | Session: %s" % [
		role,
		local_peer_id,
		peer_count,
		"YES" if is_connected else "NO"
	]
	status_label.text = status_text
	print("[Lobby] Debug status: %s" % status_text)


func _ensure_local_peer_state(default_character_id: String = "bastion") -> void:
	print("[Lobby] _ensure_local_peer_state called with local_peer_id=%d, default_char=%s" % [local_peer_id, default_character_id])
	if local_peer_id <= 0:
		print("[Lobby] WARNING: local_peer_id is invalid (%d), cannot ensure state" % local_peer_id)
		return
	if local_peer_id not in peer_state:
		peer_state[local_peer_id] = {
			"character_id": default_character_id,
			"is_ready": local_is_ready
		}
		print("[Lobby] Created new local peer_state entry: peer %d = %s" % [local_peer_id, peer_state[local_peer_id]])
	elif String(peer_state[local_peer_id].get("character_id", "")).is_empty():
		peer_state[local_peer_id]["character_id"] = default_character_id
		print("[Lobby] Updated character_id for peer %d: now %s" % [local_peer_id, peer_state[local_peer_id]])
	else:
		print("[Lobby] Local peer_state already exists, no change needed")


func _apply_character_selection(peer_id: int, character_id: String) -> void:
	if peer_id not in peer_state:
		peer_state[peer_id] = { "character_id": character_id, "is_ready": false }
	peer_state[peer_id]["character_id"] = character_id
	if peer_id == local_peer_id:
		local_character_id = character_id
	_update_player_list()


## RPC: Client -> Host request to change character.
@rpc("reliable", "any_peer")
func _request_character_selection(character_id: String) -> void:
	if not bool(multiplayer_session_manager.is_host()):
		return
	var sender_peer_id := get_tree().get_multiplayer().get_remote_sender_id()
	if sender_peer_id <= 0:
		return
	_broadcast_character_selection.rpc(sender_peer_id, character_id)


## RPC: Host -> All broadcast for character updates.
@rpc("reliable", "authority", "call_local")
func _broadcast_character_selection(peer_id: int, character_id: String) -> void:
	_apply_character_selection(peer_id, character_id)


func _apply_difficulty_selection(difficulty_tier: int) -> void:
	selected_difficulty_tier = difficulty_tier
	difficulty_selector.select(difficulty_tier)
	if not bool(multiplayer_session_manager.is_host()):
		status_label.text = "Host selected: %s" % difficulty_selector.get_item_text(difficulty_tier)


## RPC: Client -> Host request to change difficulty.
@rpc("reliable", "any_peer")
func _request_difficulty_change(difficulty_tier: int) -> void:
	if not bool(multiplayer_session_manager.is_host()):
		return
	_broadcast_difficulty.rpc(difficulty_tier)


## RPC: Host -> All broadcast for difficulty updates.
@rpc("reliable", "authority", "call_local")
func _broadcast_difficulty(difficulty_tier: int) -> void:
	_apply_difficulty_selection(difficulty_tier)


func _apply_ready_state(peer_id: int, is_ready: bool) -> void:
	if peer_id not in peer_state:
		peer_state[peer_id] = { "character_id": "bastion", "is_ready": is_ready }
	peer_state[peer_id]["is_ready"] = is_ready
	if peer_id == local_peer_id:
		local_is_ready = is_ready
		ready_button.disabled = is_ready
		ready_button.text = "READY ✓" if is_ready else "READY?"
	_update_player_list()
	if bool(multiplayer_session_manager.is_host()):
		_check_all_ready()


## RPC: Client -> Host request to toggle ready.
@rpc("reliable", "any_peer")
func _request_ready_state(is_ready: bool) -> void:
	if not bool(multiplayer_session_manager.is_host()):
		return
	var sender_peer_id := get_tree().get_multiplayer().get_remote_sender_id()
	if sender_peer_id <= 0:
		return
	_broadcast_ready_state.rpc(sender_peer_id, is_ready)


## RPC: Host -> All broadcast for ready updates.
@rpc("reliable", "authority", "call_local")
func _broadcast_ready_state(peer_id: int, is_ready: bool) -> void:
	_apply_ready_state(peer_id, is_ready)


## Check if all players are ready; if so, transition to main game.
func _check_all_ready() -> void:
	if not bool(multiplayer_session_manager.is_host()):
		return

	var peer_ids: Array = peer_state.keys()
	
	if peer_ids.is_empty():
		return
	
	for peer_id in peer_ids:
		var state: Dictionary = peer_state.get(peer_id, {})
		if not state.get("is_ready", false):
			return  ## Not all ready yet
	
	## All ready; transition to main game
	_launch_main_game()


## Transition to main game.
func _launch_main_game() -> void:
	if not bool(multiplayer_session_manager.is_host()):
		return

	print("[LobbyController] All players ready. Loading main game...")
	var host_peer_id := local_peer_id
	var session_identifier := String(multiplayer_session_manager.session_id)
	var synced_peer_state := peer_state.duplicate(true)
	_start_game.rpc(host_peer_id, session_identifier, selected_difficulty_tier, synced_peer_state)


## RPC: Host -> All transition to main scene with synced lobby state.
@rpc("reliable", "authority", "call_local")
func _start_game(host_peer_id: int, session_identifier: String, difficulty_tier: int, synced_peer_state: Dictionary) -> void:
	peer_state = synced_peer_state.duplicate(true)
	if local_peer_id <= 0:
		local_peer_id = int(multiplayer_session_manager.local_peer_id)
	RunContext.set_multiplayer_session(session_identifier, local_peer_id == host_peer_id)
	RunContext.set_multiplayer_difficulty_tier(difficulty_tier)
	for peer_id in peer_state:
		var char_id: String = peer_state[peer_id].get("character_id", "bastion")
		RunContext.set_peer_character_selection(peer_id, char_id)
	var local_char_id := String(peer_state.get(local_peer_id, {}).get("character_id", local_character_id)).strip_edges().to_lower()
	if local_char_id.is_empty():
		local_char_id = "bastion"
	local_character_id = local_char_id
	RunContext.set_selected_character_id(local_char_id)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_leave_lobby_pressed() -> void:
	print("[Lobby] Leave button pressed - attempting to leave lobby")
	if multiplayer_session_manager != null:
		print("[Lobby] Calling multiplayer_session_manager.leave_room()")
		multiplayer_session_manager.leave_room()
		print("[Lobby] leave_room() completed")
	else:
		print("[Lobby] WARNING: multiplayer_session_manager is null")
	
	var run_context = get_node_or_null("/root/RunContext")
	if run_context != null:
		print("[Lobby] Calling RunContext.clear_multiplayer_session()")
		if run_context.has_method("clear_multiplayer_session"):
			run_context.clear_multiplayer_session()
	else:
		print("[Lobby] WARNING: RunContext not found")
	
	print("[Lobby] Changing scene to Menu")
	get_tree().change_scene_to_file(MENU_SCENE_PATH)
