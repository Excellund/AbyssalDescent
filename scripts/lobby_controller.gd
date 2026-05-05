extends Control
## Lobby UI controller. Handles character selection, difficulty selection (host), ready state, and transition to main game.

const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")

@onready var room_code_label: Label = $VBoxContainer/RoomCodePanel/RoomCodeLabel
@onready var player_list: ItemList = $VBoxContainer/PlayerListPanel/VBoxContainer2/PlayerList
@onready var character_selector: TabContainer = $VBoxContainer/CharacterSelectorPanel/VBoxContainer3/CharacterTabs
@onready var difficulty_selector: OptionButton = $VBoxContainer/DifficultySelectorPanel/HBoxContainer/DifficultyDropdown
@onready var difficulty_panel: PanelContainer = $VBoxContainer/DifficultySelectorPanel
@onready var ready_button: Button = $VBoxContainer/ReadyButton
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
	if room_code_label == null or player_list == null or character_selector == null or difficulty_selector == null or ready_button == null or status_label == null:
		push_error("[LobbyController] Lobby scene UI node paths are invalid or missing")
		return

	available_characters = CHARACTER_REGISTRY.get_launch_character_ids()
	multiplayer_session_manager = get_node_or_null("/root/MultiplayerSessionManager")
	if multiplayer_session_manager == null:
		push_error("[LobbyController] MultiplayerSessionManager autoload is missing")
		return
	
	local_peer_id = int(multiplayer_session_manager.local_peer_id)
	
	## UI setup
	room_code_label.text = "Room Code: %s" % String(multiplayer_session_manager.room_code)
	
	## Character selector setup
	_populate_character_tabs()
	
	## Difficulty selector setup (host only)
	_setup_difficulty_selector()
	
	## Ready button
	ready_button.pressed.connect(_on_ready_button_pressed)
	
	## Connect to multiplayer signals
	multiplayer_session_manager.peer_connected.connect(_on_peer_connected)
	multiplayer_session_manager.peer_disconnected.connect(_on_peer_disconnected)
	
	## Initialize local peer state
	peer_state[local_peer_id] = { "character_id": "", "is_ready": false }
	_update_player_list()


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
	local_character_id = available_characters[tab_index]
	if bool(multiplayer_session_manager.is_host()):
		_sync_character_selection_to_peers(local_peer_id, local_character_id)
	else:
		_sync_character_selection_to_peers.rpc_id(1, local_peer_id, local_character_id)


## Called when host changes difficulty.
func _on_difficulty_selected(index: int) -> void:
	selected_difficulty_tier = difficulty_selector.get_item_id(index)
	if bool(multiplayer_session_manager.is_host()):
		_sync_difficulty_to_peers(selected_difficulty_tier)
	else:
		_sync_difficulty_to_peers.rpc_id(1, selected_difficulty_tier)


## Called when local player clicks Ready.
func _on_ready_button_pressed() -> void:
	local_is_ready = true
	peer_state[local_peer_id]["is_ready"] = true
	ready_button.disabled = true
	ready_button.text = "READY ✓"
	if bool(multiplayer_session_manager.is_host()):
		_sync_ready_state_to_peers(local_peer_id, true)
	else:
		_sync_ready_state_to_peers.rpc_id(1, local_peer_id, true)


## Called when a peer connects.
func _on_peer_connected(peer_id: int) -> void:
	if peer_id not in peer_state:
		peer_state[peer_id] = { "character_id": "", "is_ready": false }
	_update_player_list()


## Called when a peer disconnects.
func _on_peer_disconnected(peer_id: int) -> void:
	peer_state.erase(peer_id)
	_update_player_list()


## Update the player list UI.
func _update_player_list() -> void:
	player_list.clear()
	
	var peer_ids: Array = multiplayer_session_manager.get_peer_ids()
	for peer_id in peer_ids:
		var state: Dictionary = peer_state.get(peer_id, {})
		var char_name: String = state.get("character_id", "???")
		var is_ready: bool = state.get("is_ready", false)
		var status: String = "✓" if is_ready else "○"
		var label: String = "[Peer %d] %s %s" % [peer_id, char_name, status]
		
		player_list.add_item(label)


## RPC: Sync character selection to all peers via host.
@rpc("reliable", "authority")
func _sync_character_selection_to_peers(peer_id: int, character_id: String) -> void:
	if peer_id not in peer_state:
		return
	peer_state[peer_id]["character_id"] = character_id
	_update_player_list()


## RPC: Sync difficulty selection to all peers (host only).
@rpc("reliable", "authority")
func _sync_difficulty_to_peers(difficulty_tier: int) -> void:
	selected_difficulty_tier = difficulty_tier
	difficulty_selector.select(difficulty_tier)
	if not bool(multiplayer_session_manager.is_host()):
		status_label.text = "Host selected: %s" % difficulty_selector.get_item_text(difficulty_tier)


## RPC: Sync ready state to all peers.
@rpc("reliable", "authority")
func _sync_ready_state_to_peers(peer_id: int, is_ready: bool) -> void:
	if peer_id not in peer_state:
		return
	peer_state[peer_id]["is_ready"] = is_ready
	_update_player_list()
	_check_all_ready()


## Check if all players are ready; if so, transition to main game.
func _check_all_ready() -> void:
	var peer_ids: Array = multiplayer_session_manager.get_peer_ids()
	
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
	print_debug("[LobbyController] All players ready. Loading main game...")
	
	## Store session/difficulty in RunContext for world_generator to pick up
	RunContext.set_multiplayer_session(
		String(multiplayer_session_manager.session_id),
		bool(multiplayer_session_manager.is_host())
	)
	RunContext.set_multiplayer_difficulty_tier(selected_difficulty_tier)
	
	## Store each player's character selection (for later retrieval)
	for peer_id in peer_state:
		var char_id: String = peer_state[peer_id].get("character_id", "bastion")
		RunContext.set_peer_character_selection(peer_id, char_id)
	
	## Transition to main scene
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
