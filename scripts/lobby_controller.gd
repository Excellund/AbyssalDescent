extends Control
## Lobby UI controller. Handles character selection, difficulty selection (host), ready state, and transition to main game.

const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")
const MENU_SCENE_PATH := "res://scenes/Menu.tscn"
const RUN_CONTEXT_PATH := "/root/RunContext"
const MENU_MUSIC := preload("res://music/msx1.mp3")
const AUDIO_LEVELS := preload("res://scripts/shared/audio_levels.gd")

signal leave_lobby_requested

@onready var room_code_label: Label = $VBoxContainer/RoomCodePanel/RoomCodeLabel
@onready var player_list: VBoxContainer = $VBoxContainer/PlayerListPanel/VBoxContainer2/PlayerList
@onready var character_selector: TabContainer = $VBoxContainer/CharacterSelectorPanel/VBoxContainer3/CharacterTabs
@onready var difficulty_selector: OptionButton = $VBoxContainer/DifficultySelectorPanel/HBoxContainer/DifficultyDropdown
@onready var difficulty_panel: PanelContainer = $VBoxContainer/DifficultySelectorPanel
@onready var ready_button: Button = $VBoxContainer/ReadyButton
@onready var leave_lobby_button: Button = $VBoxContainer/LeaveLobbyButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var background: ColorRect = $Background

var available_characters: Array = []

## Local player state
var local_character_id: String = ""
var local_peer_id: int = 0
var local_is_ready: bool = false
var local_player_name: String = "Player"

## Multiplayer state (peer_id -> { character_id, is_ready, join_index })
var peer_state: Dictionary = {}
var _next_join_index: int = 0

## Difficulty state (host only)
var selected_difficulty_tier: int = 1  ## Default: Delver
var multiplayer_session_manager
var _host_connectivity_warning: String = ""
var lobby_music_player: AudioStreamPlayer
var lobby_background_layer: Control
var _embedded_in_menu: bool = false


func set_embedded_in_menu(enabled: bool) -> void:
	_embedded_in_menu = enabled


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
	if bool(multiplayer_session_manager.is_host()) and multiplayer_session_manager.has_method("get_last_host_connectivity_warning"):
		_host_connectivity_warning = String(multiplayer_session_manager.get_last_host_connectivity_warning())

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
	ready_button.disabled = false  ## Ensure ready button is enabled
	ready_button.text = "READY"  ## Reset ready button text
	leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)
	print("[Lobby] Leave button connected to _on_leave_lobby_pressed")
	
	## Connect to multiplayer signals
	multiplayer_session_manager.peer_connected.connect(_on_peer_connected)
	multiplayer_session_manager.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer_session_manager.session_joined.connect(_on_session_joined)
	if not multiplayer_session_manager.is_host():
		multiplayer_session_manager.host_left.connect(_on_host_left)
	print("[Lobby] Connected to multiplayer signals")
	
	## Initialize local peer state
	local_character_id = available_characters[0] if not available_characters.is_empty() else "bastion"
	local_is_ready = false  ## Reset ready state when re-entering lobby
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null and run_context.has_method("get_profile_name_or_default"):
		local_player_name = String(run_context.get_profile_name_or_default()).strip_edges()
	if local_player_name.is_empty():
		local_player_name = "Player"
	_ensure_local_peer_state(local_character_id)
	print("[Lobby] After _ensure_local_peer_state in _ready, peer_state: %s" % [str(peer_state)])
	
	## HOST: Clear stale state and register self + any already-connected peers with authoritative join_index.
	if bool(multiplayer_session_manager.is_host()):
		peer_state.clear()
		_next_join_index = 0
		_ensure_local_peer_state(local_character_id)
		var existing_peers: Array = (multiplayer_session_manager.get_peer_ids() as Array).duplicate()
		existing_peers.sort()
		print("[Lobby] HOST: Querying existing peers from manager: %s" % [str(existing_peers)])
		for peer_id in existing_peers:
			if int(peer_id) != local_peer_id and int(peer_id) not in peer_state:
				var idx := _consume_next_join_index()
				_broadcast_peer_register.rpc(int(peer_id), idx)
				print("[Lobby] HOST: Registered existing peer %d with join_index=%d" % [int(peer_id), idx])
	else:
		## CLIENT: ask host for the authoritative roster (host owns join order).
		if _client_can_send_rpcs():
			_request_lobby_roster.rpc_id(1)

	_broadcast_local_player_name()
	
	_apply_lobby_style()
	if not _embedded_in_menu:
		_start_lobby_music()
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
	
	## Check if we're missing any peers that connected without firing signal.
	## Host registers and broadcasts join_index; clients re-request roster from host.
	var is_host_peer := bool(multiplayer_session_manager.is_host())
	for peer_id in actual_peers:
		if peer_id not in peer_state:
			print("[Lobby] SYNC: Found peer %d that's not in peer_state." % peer_id)
			if is_host_peer:
				var idx := _consume_next_join_index()
				_broadcast_peer_register.rpc(int(peer_id), idx)
			elif _client_can_send_rpcs():
				_request_lobby_roster.rpc_id(1)
				break
	
	## Check if we have stale peers that disconnected without firing signal
	for peer_id in state_peers:
		if peer_id == local_peer_id:
			continue
		if peer_id not in actual_peers:
			print("[Lobby] SYNC: Peer %d no longer connected. Removing from peer_state..." % peer_id)
			peer_state.erase(peer_id)
			_update_player_list()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_lobby_layout()


func _exit_tree() -> void:
	if _embedded_in_menu:
		return
	if lobby_music_player != null and lobby_music_player.playing:
		var run_context := get_node_or_null(RUN_CONTEXT_PATH)
		if run_context != null and run_context.has_method("set_menu_music_resume_position"):
			run_context.set_menu_music_resume_position(lobby_music_player.get_playback_position())
		lobby_music_player.stop()


func _tree_or_null() -> SceneTree:
	if not is_inside_tree():
		return null
	return get_tree()


func _client_can_send_rpcs() -> bool:
	if multiplayer_session_manager == null or not multiplayer_session_manager.session_connected:
		return false
	if bool(multiplayer_session_manager.is_host()):
		return true
	var tree := _tree_or_null()
	if tree == null:
		return false
	var multiplayer_api := tree.get_multiplayer()
	if multiplayer_api == null:
		return false
	var active_peer: MultiplayerPeer = multiplayer_api.multiplayer_peer
	if active_peer == null:
		return false
	return active_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Populate character tabs (one per character).
func _populate_character_tabs() -> void:
	for child in character_selector.get_children():
		child.queue_free()
	
	for char_id in available_characters:
		var char_data: Dictionary = CHARACTER_REGISTRY.get_character(String(char_id))
		var page := MarginContainer.new()
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.add_theme_constant_override("margin_left", 14)
		page.add_theme_constant_override("margin_right", 14)
		page.add_theme_constant_override("margin_top", 12)
		page.add_theme_constant_override("margin_bottom", 12)
		page.name = String(char_data.get("name", char_id))

		var stack := VBoxContainer.new()
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_theme_constant_override("separation", 8)
		page.add_child(stack)

		var name_label := Label.new()
		name_label.text = String(char_data.get("name", char_id))
		name_label.add_theme_font_size_override("font_size", 24)
		name_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
		stack.add_child(name_label)

		var archetype_label := Label.new()
		archetype_label.text = String(char_data.get("archetype", ""))
		archetype_label.add_theme_font_size_override("font_size", 16)
		archetype_label.add_theme_color_override("font_color", Color(0.72, 0.86, 1.0, 0.90))
		stack.add_child(archetype_label)

		var tagline_label := Label.new()
		tagline_label.text = String(char_data.get("tagline", ""))
		tagline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tagline_label.add_theme_font_size_override("font_size", 15)
		tagline_label.add_theme_color_override("font_color", Color(0.84, 0.92, 1.0, 0.90))
		stack.add_child(tagline_label)

		character_selector.add_child(page)

	var random_page := MarginContainer.new()
	random_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	random_page.add_theme_constant_override("margin_left", 14)
	random_page.add_theme_constant_override("margin_right", 14)
	random_page.add_theme_constant_override("margin_top", 12)
	random_page.add_theme_constant_override("margin_bottom", 12)
	random_page.name = "?"

	var random_stack := VBoxContainer.new()
	random_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	random_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	random_stack.add_theme_constant_override("separation", 8)
	random_page.add_child(random_stack)

	var random_glyph := Label.new()
	random_glyph.text = "?"
	random_glyph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	random_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	random_glyph.add_theme_font_size_override("font_size", 36)
	random_glyph.add_theme_color_override("font_color", Color(0.70, 0.76, 0.86, 0.88))
	random_stack.add_child(random_glyph)

	var random_label := Label.new()
	random_label.text = "Let the abyss decide"
	random_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	random_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	random_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	random_label.add_theme_font_size_override("font_size", 15)
	random_label.add_theme_color_override("font_color", Color(0.60, 0.66, 0.76, 0.78))
	random_stack.add_child(random_label)

	character_selector.add_child(random_page)

	if not character_selector.tab_changed.is_connected(_on_character_tab_changed):
		character_selector.tab_changed.connect(_on_character_tab_changed)
	if not available_characters.is_empty():
		var selected_index := maxi(0, available_characters.find(local_character_id))
		character_selector.current_tab = selected_index


## Setup difficulty selector (host only, disabled for clients).
func _setup_difficulty_selector() -> void:
	difficulty_selector.add_item("Pilgrim", 0)
	difficulty_selector.add_item("Delver", 1)
	difficulty_selector.add_item("Harbinger", 2)
	difficulty_selector.add_item("Forsworn", 3)
	
	difficulty_selector.select(selected_difficulty_tier)
	difficulty_selector.item_selected.connect(_on_difficulty_selected)
	
	## If not host, disable selector and show as read-only
	if not bool(multiplayer_session_manager.is_host()):
		difficulty_selector.disabled = true
		status_label.text = "Waiting for host to select difficulty..."


## Called when local player changes character tab.
func _on_character_tab_changed(tab_index: int) -> void:
	var random_tab_index := available_characters.size()
	if tab_index == random_tab_index:
		local_character_id = "random"
		if bool(multiplayer_session_manager.is_host()):
			_broadcast_character_selection.rpc(local_peer_id, "random")
		else:
			if not _client_can_send_rpcs():
				status_label.text = "Still connecting to host..."
				return
			_request_character_selection.rpc_id(1, "random")
		return
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
	if bool(multiplayer_session_manager.is_host()):
		## Host first sends the late-joiner the existing roster, then announces them to everyone.
		_sync_lobby_roster.rpc_id(peer_id, peer_state.duplicate(true))
		if peer_id not in peer_state:
			var idx := _consume_next_join_index()
			_broadcast_peer_register.rpc(int(peer_id), idx)
			print("[Lobby] HOST: Registered new peer %d with join_index=%d" % [peer_id, idx])
	else:
		## Client: rely on host's roster broadcast for join order; just request to ensure sync.
		if _client_can_send_rpcs():
			_request_lobby_roster.rpc_id(1)
	_update_player_list()


## Called when a peer disconnects.
func _on_peer_disconnected(peer_id: int) -> void:
	peer_state.erase(peer_id)
	_update_player_list()

## Called when the host closes the session (clients only).
func _on_host_left() -> void:
	_disable_lobby_controls()
	status_label.text = "The host has ended the session. Returning to menu..."
	var tree := _tree_or_null()
	if tree == null:
		return
	var timer := tree.create_timer(2.5)
	timer.timeout.connect(_leave_after_host_disconnect)

func _disable_lobby_controls() -> void:
	ready_button.disabled = true
	leave_lobby_button.disabled = true
	if difficulty_selector != null:
		difficulty_selector.disabled = true

func _leave_after_host_disconnect() -> void:
	var run_context = get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null and run_context.has_method("clear_multiplayer_session"):
		run_context.clear_multiplayer_session()
	if _embedded_in_menu:
		emit_signal("leave_lobby_requested")
	else:
		var tree := _tree_or_null()
		if tree == null:
			return
		tree.change_scene_to_file(MENU_SCENE_PATH)


func _on_session_joined(_session_id: String) -> void:
	print("[Lobby] Signal: session_joined received. session_id=%s" % _session_id)
	local_peer_id = int(multiplayer_session_manager.local_peer_id)
	if local_peer_id <= 0:
		var tree := _tree_or_null()
		if tree != null:
			local_peer_id = int(tree.get_multiplayer().get_unique_id())
	print("[Lobby] Local peer ID confirmed: %d" % local_peer_id)
	_ensure_local_peer_state(local_character_id)
	print("[Lobby] After _ensure_local_peer_state, peer_state: %s" % [str(peer_state)])

	## Client: ask host for authoritative roster (includes host + all peers + join indices).
	if not bool(multiplayer_session_manager.is_host()):
		print("[Lobby] This is a CLIENT peer. Requesting lobby roster from host.")
		if _client_can_send_rpcs():
			_request_lobby_roster.rpc_id(1)
	else:
		print("[Lobby] This is a HOST peer")
	_broadcast_local_player_name()
	
	_update_player_list()


## Update the player list UI.
func _update_player_list() -> void:
	for child in player_list.get_children():
		child.free()

	var peer_ids: Array = peer_state.keys()
	peer_ids.sort_custom(func(a, b):
		var ai := int((peer_state.get(a, {}) as Dictionary).get("join_index", 0))
		var bi := int((peer_state.get(b, {}) as Dictionary).get("join_index", 0))
		if ai == bi:
			return int(a) < int(b)
		return ai < bi
	)
	for peer_id in peer_ids:
		var state: Dictionary = peer_state.get(peer_id, {})
		var char_id_raw: String = state.get("character_id", "???")
		var char_display: String = "?" if char_id_raw == "random" else char_id_raw.capitalize()
		var is_ready: bool = state.get("is_ready", false)
		var status_icon: String = "  ✓" if is_ready else "  ○"
		var display_name := String(state.get("player_name", "")).strip_edges()
		if display_name.is_empty():
			display_name = "Player"
		if peer_id == local_peer_id:
			display_name = "%s (You)" % display_name
		var row := Label.new()
		row.text = "%s  -  %s%s" % [display_name, char_display, status_icon]
		row.add_theme_font_size_override("font_size", 18)
		if peer_id == local_peer_id:
			row.add_theme_color_override("font_color", Color(0.72, 0.86, 1.0, 1.0))
		else:
			row.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.80))
		player_list.add_child(row)

	_update_player_status()


func _update_debug_status() -> void:
	pass


func _update_player_status() -> void:
	if bool(multiplayer_session_manager.is_host()):
		status_label.text = ""
		return
	var all_ready := true
	for state in peer_state.values():
		if not (state as Dictionary).get("is_ready", false):
			all_ready = false
			break
	if all_ready and not peer_state.is_empty():
		status_label.text = "All players ready - waiting to begin..."
	else:
		status_label.text = "Waiting for all players to ready up..."


func _ensure_local_peer_state(default_character_id: String = "bastion") -> void:
	print("[Lobby] _ensure_local_peer_state called with local_peer_id=%d, default_char=%s" % [local_peer_id, default_character_id])
	if local_peer_id <= 0:
		print("[Lobby] WARNING: local_peer_id is invalid (%d), cannot ensure state" % local_peer_id)
		return
	if local_peer_id not in peer_state:
		peer_state[local_peer_id] = {
			"character_id": default_character_id,
			"is_ready": local_is_ready,
			"player_name": local_player_name,
			"join_index": _consume_next_join_index()
		}
		print("[Lobby] Created new local peer_state entry: peer %d = %s" % [local_peer_id, peer_state[local_peer_id]])
	elif String(peer_state[local_peer_id].get("character_id", "")).is_empty():
		peer_state[local_peer_id]["character_id"] = default_character_id
		print("[Lobby] Updated character_id for peer %d: now %s" % [local_peer_id, peer_state[local_peer_id]])
	else:
		print("[Lobby] Local peer_state already exists, no change needed")
	peer_state[local_peer_id]["player_name"] = local_player_name


func _consume_next_join_index() -> int:
	var index := _next_join_index
	_next_join_index += 1
	return index


## RPC: Host -> all (incl. self). Authoritative announcement of a peer + its join_index.
@rpc("reliable", "authority", "call_local")
func _broadcast_peer_register(peer_id: int, join_index: int) -> void:
	if peer_id <= 0:
		return
	if peer_id not in peer_state:
		peer_state[peer_id] = {
			"character_id": "bastion",
			"is_ready": false,
			"player_name": "Player",
			"join_index": join_index,
		}
	else:
		peer_state[peer_id]["join_index"] = join_index
	if join_index >= _next_join_index:
		_next_join_index = join_index + 1
	_update_player_list()


## RPC: Client -> Host. Request the current authoritative roster.
@rpc("reliable", "any_peer")
func _request_lobby_roster() -> void:
	if not bool(multiplayer_session_manager.is_host()):
		return
	var tree := _tree_or_null()
	if tree == null:
		return
	var sender_peer_id := tree.get_multiplayer().get_remote_sender_id()
	if sender_peer_id <= 0:
		return
	## If the requester isn't yet registered, register them now so they get a stable join_index.
	if sender_peer_id not in peer_state:
		var idx := _consume_next_join_index()
		_broadcast_peer_register.rpc(sender_peer_id, idx)
	_sync_lobby_roster.rpc_id(sender_peer_id, peer_state.duplicate(true))


## RPC: Host -> specific peer. Replace local peer_state with the host's snapshot.
@rpc("reliable", "authority")
func _sync_lobby_roster(roster: Dictionary) -> void:
	for peer_id_key in roster.keys():
		var entry: Dictionary = roster[peer_id_key]
		var pid := int(peer_id_key)
		var join_index := int(entry.get("join_index", 0))
		var existing: Dictionary = peer_state.get(pid, {})
		peer_state[pid] = {
			"character_id": String(entry.get("character_id", existing.get("character_id", "bastion"))),
			"is_ready": bool(entry.get("is_ready", existing.get("is_ready", false))),
			"player_name": String(entry.get("player_name", existing.get("player_name", "Player"))),
			"join_index": join_index,
		}
		if join_index >= _next_join_index:
			_next_join_index = join_index + 1
	if local_peer_id > 0 and local_peer_id in peer_state:
		peer_state[local_peer_id]["character_id"] = local_character_id
		peer_state[local_peer_id]["player_name"] = local_player_name
		peer_state[local_peer_id]["is_ready"] = local_is_ready
	_update_player_list()


func _ensure_remote_peer_state(peer_id: int, default_character_id: String = "bastion") -> void:
	if peer_id == local_peer_id or peer_id <= 0:
		return
	if peer_id in peer_state:
		return
	peer_state[peer_id] = {
		"character_id": default_character_id,
		"is_ready": false,
		"player_name": "Player",
		"join_index": _consume_next_join_index()
	}


func _apply_character_selection(peer_id: int, character_id: String) -> void:
	if peer_id not in peer_state:
		peer_state[peer_id] = {
			"character_id": character_id,
			"is_ready": false,
			"player_name": "Player",
			"join_index": _consume_next_join_index()
		}
	peer_state[peer_id]["character_id"] = character_id
	if peer_id == local_peer_id:
		local_character_id = character_id
		if character_id == "random":
			var random_tab_index := available_characters.size()
			if random_tab_index < character_selector.get_tab_count():
				character_selector.current_tab = random_tab_index
		else:
			var tab_index := available_characters.find(character_id)
			if tab_index >= 0 and tab_index < character_selector.get_tab_count():
				character_selector.current_tab = tab_index
	_update_player_list()


## RPC: Client -> Host request to change character.
@rpc("reliable", "any_peer")
func _request_character_selection(character_id: String) -> void:
	if not bool(multiplayer_session_manager.is_host()):
		return
	var tree := _tree_or_null()
	if tree == null:
		return
	var sender_peer_id := tree.get_multiplayer().get_remote_sender_id()
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
		status_label.text = ""


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
		peer_state[peer_id] = { "character_id": "bastion", "is_ready": is_ready, "player_name": "Player" }
	peer_state[peer_id]["is_ready"] = is_ready
	if peer_id == local_peer_id:
		local_is_ready = is_ready
		ready_button.disabled = is_ready
		ready_button.text = "READY ✓" if is_ready else "READY?"
		_apply_ready_button_style(is_ready)
	_update_player_list()
	if bool(multiplayer_session_manager.is_host()):
		_check_all_ready()

func _apply_player_name(peer_id: int, player_name: String) -> void:
	var normalized_name := player_name.strip_edges()
	if normalized_name.is_empty():
		normalized_name = "Player"
	if peer_id not in peer_state:
		peer_state[peer_id] = { "character_id": "bastion", "is_ready": false, "player_name": normalized_name }
	else:
		peer_state[peer_id]["player_name"] = normalized_name
	if peer_id == local_peer_id:
		local_player_name = normalized_name
	_update_player_list()

func _broadcast_local_player_name() -> void:
	if multiplayer_session_manager == null:
		return
	if local_peer_id <= 0:
		return
	_apply_player_name(local_peer_id, local_player_name)
	if bool(multiplayer_session_manager.is_host()):
		_broadcast_player_name.rpc(local_peer_id, local_player_name)
		return
	if _client_can_send_rpcs():
		_request_player_name.rpc_id(1, local_player_name)

@rpc("reliable", "any_peer")
func _request_player_name(player_name: String) -> void:
	if not bool(multiplayer_session_manager.is_host()):
		return
	var tree := _tree_or_null()
	if tree == null:
		return
	var sender_peer_id := tree.get_multiplayer().get_remote_sender_id()
	if sender_peer_id <= 0:
		return
	_broadcast_player_name.rpc(sender_peer_id, player_name)

@rpc("reliable", "authority", "call_local")
func _broadcast_player_name(peer_id: int, player_name: String) -> void:
	_apply_player_name(peer_id, player_name)


## RPC: Client -> Host request to toggle ready.
@rpc("reliable", "any_peer")
func _request_ready_state(is_ready: bool) -> void:
	if not bool(multiplayer_session_manager.is_host()):
		return
	var tree := _tree_or_null()
	if tree == null:
		return
	var sender_peer_id := tree.get_multiplayer().get_remote_sender_id()
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


func _resolve_random_character() -> String:
	var launch_ids: Array = CHARACTER_REGISTRY.get_launch_character_ids()
	if launch_ids.is_empty():
		return "bastion"
	return String(launch_ids[randi() % launch_ids.size()])


## Transition to main game.
func _launch_main_game() -> void:
	if not bool(multiplayer_session_manager.is_host()):
		return

	print("[LobbyController] All players ready. Loading main game...")
	var host_peer_id := local_peer_id
	var session_identifier := String(multiplayer_session_manager.session_id)
	var synced_peer_state := peer_state.duplicate(true)
	for peer_id_key in synced_peer_state.keys():
		var state := synced_peer_state[peer_id_key] as Dictionary
		if String(state.get("character_id", "")) == "random":
			state["character_id"] = _resolve_random_character()
	_start_game.rpc(host_peer_id, session_identifier, selected_difficulty_tier, synced_peer_state)


## RPC: Host -> All transition to main scene with synced lobby state.
@rpc("reliable", "authority", "call_local")
func _start_game(host_peer_id: int, session_identifier: String, difficulty_tier: int, synced_peer_state: Dictionary) -> void:
	peer_state = synced_peer_state.duplicate(true)
	var tree := _tree_or_null()
	if tree == null:
		return
	var multiplayer_api := tree.get_multiplayer()
	if multiplayer_api != null:
		var active_peer_id := int(multiplayer_api.get_unique_id())
		if active_peer_id > 0:
			local_peer_id = active_peer_id
	if local_peer_id <= 0:
		local_peer_id = int(multiplayer_session_manager.local_peer_id)
	RunContext.set_multiplayer_session(session_identifier, local_peer_id == host_peer_id)
	RunContext.set_multiplayer_difficulty_tier(difficulty_tier)
	for peer_id_key in peer_state.keys():
		var peer_id := int(peer_id_key)
		var state := peer_state.get(peer_id_key, {}) as Dictionary
		var char_id: String = String(state.get("character_id", "bastion")).strip_edges().to_lower()
		if char_id.is_empty():
			char_id = "bastion"
		RunContext.set_peer_character_selection(peer_id, char_id)
	var local_char_id := String(peer_state.get(local_peer_id, {}).get("character_id", local_character_id)).strip_edges().to_lower()
	if local_char_id.is_empty():
			local_char_id = String(peer_state.get(str(local_peer_id), {}).get("character_id", local_character_id)).strip_edges().to_lower()
	if local_char_id.is_empty():
		local_char_id = "bastion"
	local_character_id = local_char_id
	RunContext.set_selected_character_id(local_char_id)
	tree.change_scene_to_file("res://scenes/Main.tscn")


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
	
	if _embedded_in_menu:
		emit_signal("leave_lobby_requested")
		return

	print("[Lobby] Changing scene to Menu")
	var tree := _tree_or_null()
	if tree == null:
		return
	tree.change_scene_to_file(MENU_SCENE_PATH)


func _make_panel_style(bg_color: Color, border_color: Color, corner_radius: int = 14, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _make_button_style(bg_color: Color, border_color: Color, corner_radius: int = 16, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style


func _apply_ready_button_style(is_ready: bool) -> void:
	if is_ready:
		ready_button.add_theme_stylebox_override("normal", _make_button_style(Color(0.08, 0.20, 0.12, 0.95), Color(0.40, 0.88, 0.56, 0.92)))
		ready_button.add_theme_stylebox_override("hover", _make_button_style(Color(0.10, 0.24, 0.15, 0.98), Color(0.52, 0.96, 0.66, 1.0)))
		ready_button.add_theme_stylebox_override("disabled", _make_button_style(Color(0.07, 0.16, 0.10, 0.85), Color(0.30, 0.68, 0.42, 0.72)))
	else:
		ready_button.add_theme_stylebox_override("normal", _make_button_style(Color(0.16, 0.27, 0.42, 0.95), Color(0.76, 0.90, 1.0, 0.92)))
		ready_button.add_theme_stylebox_override("hover", _make_button_style(Color(0.19, 0.32, 0.50, 0.98), Color(0.86, 0.96, 1.0, 1.0)))
		ready_button.add_theme_stylebox_override("disabled", _make_button_style(Color(0.08, 0.10, 0.14, 0.82), Color(0.22, 0.26, 0.32, 0.54)))
	ready_button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.12, 0.22, 0.34, 0.98), Color(0.92, 0.98, 1.0, 1.0)))
	ready_button.add_theme_stylebox_override("focus", _make_button_style(Color(0.13, 0.20, 0.29, 0.98), Color(0.86, 0.96, 1.0, 1.0)))


func _apply_lobby_style() -> void:
	if _embedded_in_menu:
		if background != null:
			background.visible = false
	else:
		_apply_lobby_background()
	_apply_lobby_layout()

	var panel_bg := Color(0.06, 0.09, 0.13, 0.94)
	var panel_border := Color(0.34, 0.56, 0.84, 0.76)
	var label_color := Color(0.95, 0.98, 1.0, 0.98)
	var section_color := Color(0.72, 0.86, 1.0, 0.82)
	var status_color := Color(0.72, 0.86, 1.0, 0.62)

	## Panel backgrounds
	var room_code_panel: PanelContainer = $VBoxContainer/RoomCodePanel
	var player_list_panel: PanelContainer = $VBoxContainer/PlayerListPanel
	var char_selector_panel: PanelContainer = $VBoxContainer/CharacterSelectorPanel
	var difficulty_panel_node: PanelContainer = $VBoxContainer/DifficultySelectorPanel
	char_selector_panel.custom_minimum_size = Vector2(0.0, 190.0)
	for panel_node in [room_code_panel, player_list_panel, char_selector_panel, difficulty_panel_node]:
		panel_node.add_theme_stylebox_override("panel", _make_panel_style(panel_bg, panel_border, 16, 2))

	## Room code label
	room_code_label.add_theme_font_size_override("font_size", 26)
	room_code_label.add_theme_color_override("font_color", label_color)
	room_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	## Section header labels
	var player_header: Label = $VBoxContainer/PlayerListPanel/VBoxContainer2/Label
	player_header.text = "PLAYERS"
	player_header.add_theme_font_size_override("font_size", 13)
	player_header.add_theme_color_override("font_color", section_color)

	var char_header: Label = $VBoxContainer/CharacterSelectorPanel/VBoxContainer3/Label
	char_header.text = "SELECT CHARACTER"
	char_header.add_theme_font_size_override("font_size", 13)
	char_header.add_theme_color_override("font_color", section_color)

	character_selector.add_theme_font_size_override("font_size", 15)
	character_selector.add_theme_color_override("font_selected_color", Color(0.96, 0.99, 1.0, 1.0))
	character_selector.add_theme_color_override("font_unselected_color", Color(0.74, 0.84, 0.94, 0.82))
	character_selector.add_theme_color_override("font_hovered_color", Color(0.90, 0.97, 1.0, 1.0))
	character_selector.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.08, 0.12, 0.95), Color(0.22, 0.36, 0.52, 0.40), 14, 1))
	character_selector.add_theme_stylebox_override("tab_selected", _make_button_style(Color(0.16, 0.27, 0.42, 0.95), Color(0.76, 0.90, 1.0, 0.92), 12, 2))
	character_selector.add_theme_stylebox_override("tab_unselected", _make_button_style(Color(0.08, 0.12, 0.18, 0.96), Color(0.30, 0.48, 0.68, 0.64), 12, 1))
	character_selector.add_theme_stylebox_override("tab_hovered", _make_button_style(Color(0.13, 0.19, 0.28, 0.98), Color(0.62, 0.82, 0.98, 0.88), 12, 2))

	var difficulty_header: Label = $VBoxContainer/DifficultySelectorPanel/HBoxContainer/Label
	difficulty_header.text = "DIFFICULTY"
	difficulty_header.add_theme_font_size_override("font_size", 13)
	difficulty_header.add_theme_color_override("font_color", section_color)

	## Difficulty dropdown
	difficulty_selector.add_theme_font_size_override("font_size", 18)
	difficulty_selector.add_theme_color_override("font_color", label_color)
	difficulty_selector.add_theme_color_override("font_hover_color", Color(0.98, 1.0, 1.0, 1.0))
	difficulty_selector.add_theme_stylebox_override("normal", _make_button_style(Color(0.10, 0.15, 0.22, 0.95), Color(0.34, 0.56, 0.84, 0.72), 14, 2))
	difficulty_selector.add_theme_stylebox_override("hover", _make_button_style(Color(0.13, 0.19, 0.28, 0.98), Color(0.62, 0.82, 0.98, 0.88), 14, 2))
	difficulty_selector.add_theme_stylebox_override("pressed", _make_button_style(Color(0.08, 0.12, 0.18, 0.98), Color(0.74, 0.90, 1.0, 0.92), 14, 2))
	difficulty_selector.add_theme_stylebox_override("focus", _make_button_style(Color(0.13, 0.20, 0.29, 0.98), Color(0.86, 0.96, 1.0, 1.0), 14, 2))
	difficulty_selector.add_theme_stylebox_override("disabled", _make_button_style(Color(0.08, 0.10, 0.14, 0.82), Color(0.22, 0.26, 0.32, 0.54), 14, 2))

	## Ready button
	ready_button.add_theme_font_size_override("font_size", 22)
	ready_button.add_theme_color_override("font_color", label_color)
	ready_button.add_theme_color_override("font_hover_color", Color(0.98, 1.0, 1.0, 1.0))
	ready_button.add_theme_color_override("font_disabled_color", Color(0.52, 0.60, 0.68, 0.90))
	ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_ready_button_style(local_is_ready)

	## Leave button
	leave_lobby_button.add_theme_font_size_override("font_size", 18)
	leave_lobby_button.add_theme_color_override("font_color", label_color)
	leave_lobby_button.add_theme_color_override("font_hover_color", Color(0.98, 1.0, 1.0, 1.0))
	leave_lobby_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave_lobby_button.add_theme_stylebox_override("normal", _make_button_style(Color(0.10, 0.15, 0.22, 0.95), Color(0.34, 0.56, 0.84, 0.72)))
	leave_lobby_button.add_theme_stylebox_override("hover", _make_button_style(Color(0.13, 0.19, 0.28, 0.98), Color(0.62, 0.82, 0.98, 0.88)))
	leave_lobby_button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.08, 0.12, 0.18, 0.98), Color(0.74, 0.90, 1.0, 0.92)))
	leave_lobby_button.add_theme_stylebox_override("focus", _make_button_style(Color(0.13, 0.20, 0.29, 0.98), Color(0.86, 0.96, 1.0, 1.0)))

	## Status label
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", status_color)
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	status_style.set_content_margin_all(8.0)
	status_label.add_theme_stylebox_override("normal", status_style)


func _apply_lobby_layout() -> void:
	var content: VBoxContainer = $VBoxContainer
	if content == null:
		return
	var available_size := size
	if available_size.x <= 0.0 or available_size.y <= 0.0:
		available_size = get_viewport_rect().size
	if available_size.x <= 0.0 or available_size.y <= 0.0:
		return
	var base_size := Vector2(880.0, 560.0)
	var fit_scale := minf(available_size.x / base_size.x, available_size.y / base_size.y)
	fit_scale = clampf(fit_scale, 0.80, 1.0)
	var target_size := base_size * fit_scale
	content.set_anchors_preset(Control.PRESET_TOP_LEFT)
	content.custom_minimum_size = target_size
	content.size = target_size
	content.position = (available_size - target_size) * 0.5


func _start_lobby_music() -> void:
	if MENU_MUSIC == null:
		return
	if lobby_music_player != null:
		return
	var resume_position := 0.0
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null and run_context.has_method("consume_menu_music_resume_position"):
		resume_position = float(run_context.consume_menu_music_resume_position())
	lobby_music_player = AudioStreamPlayer.new()
	lobby_music_player.stream = MENU_MUSIC
	lobby_music_player.bus = "Master"
	lobby_music_player.finished.connect(_on_lobby_music_finished)
	add_child(lobby_music_player)
	lobby_music_player.play(maxf(resume_position, 0.0))
	if run_context != null:
		lobby_music_player.volume_db = AUDIO_LEVELS.menu_music_db(float(run_context.music_volume_db))


func _on_lobby_music_finished() -> void:
	if lobby_music_player == null:
		return
	if AUDIO_LEVELS.is_muted_db(lobby_music_player.volume_db):
		return
	lobby_music_player.play(0.0)


func _apply_lobby_background() -> void:
	if background != null:
		background.color = Color(1.0, 1.0, 1.0, 1.0)
		background.material = _make_lobby_background_material()
	if lobby_background_layer != null:
		return
	lobby_background_layer = Control.new()
	lobby_background_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_background_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lobby_background_layer)
	move_child(lobby_background_layer, 1)

	var glow_a := Panel.new()
	glow_a.set_anchors_preset(Control.PRESET_CENTER)
	glow_a.position = Vector2(-520.0, -280.0)
	glow_a.custom_minimum_size = Vector2(380.0, 380.0)
	glow_a.add_theme_stylebox_override("panel", _make_panel_style(Color(0.16, 0.33, 0.52, 0.16), Color(0.16, 0.33, 0.52, 0.0), 190, 0))
	lobby_background_layer.add_child(glow_a)

	var glow_b := Panel.new()
	glow_b.set_anchors_preset(Control.PRESET_CENTER)
	glow_b.position = Vector2(220.0, -340.0)
	glow_b.custom_minimum_size = Vector2(460.0, 460.0)
	glow_b.add_theme_stylebox_override("panel", _make_panel_style(Color(0.11, 0.24, 0.40, 0.14), Color(0.11, 0.24, 0.40, 0.0), 230, 0))
	lobby_background_layer.add_child(glow_b)

	var glow_c := Panel.new()
	glow_c.set_anchors_preset(Control.PRESET_CENTER)
	glow_c.position = Vector2(-80.0, 140.0)
	glow_c.custom_minimum_size = Vector2(320.0, 320.0)
	glow_c.add_theme_stylebox_override("panel", _make_panel_style(Color(0.20, 0.38, 0.56, 0.12), Color(0.20, 0.38, 0.56, 0.0), 160, 0))
	lobby_background_layer.add_child(glow_c)

	var float_tween := create_tween()
	float_tween.set_loops()
	float_tween.set_parallel(true)
	float_tween.tween_property(glow_a, "position", glow_a.position + Vector2(46.0, 22.0), 8.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.tween_property(glow_b, "position", glow_b.position + Vector2(-52.0, 26.0), 10.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.tween_property(glow_c, "position", glow_c.position + Vector2(36.0, -18.0), 7.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.chain().tween_property(glow_a, "position", glow_a.position, 8.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.parallel().tween_property(glow_b, "position", glow_b.position, 10.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.parallel().tween_property(glow_c, "position", glow_c.position, 7.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _make_lobby_background_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4 deep_color : source_color = vec4(0.020, 0.035, 0.060, 1.0);
uniform vec4 mid_color : source_color = vec4(0.060, 0.150, 0.250, 1.0);
uniform vec4 accent_color : source_color = vec4(0.220, 0.450, 0.640, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amplitude * noise(p);
		p = p * 2.02 + vec2(9.2, 7.4);
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	vec2 centered_uv = uv * 2.0 - 1.0;
	float t = TIME * 0.11;

	vec2 drift = vec2(t * 0.55, -t * 0.34);
	vec2 warp = vec2(sin(uv.y * 7.2 + t * 3.8), cos(uv.x * 6.1 - t * 3.2)) * 0.10;
	float mist = fbm(uv * 3.2 + drift + warp);
	float band = 0.5 + 0.5 * sin((centered_uv.x * 2.2 - centered_uv.y * 1.25) * 3.6 + t * 4.8 + mist * 3.0);
	float radial = smoothstep(1.22, 0.08, length(centered_uv));

	vec3 color_mix = mix(deep_color.rgb, mid_color.rgb, clamp(mist * 0.75 + band * 0.22, 0.0, 1.0));
	color_mix = mix(color_mix, accent_color.rgb, clamp(radial * 0.32 + band * 0.12, 0.0, 1.0));
	float vignette = smoothstep(1.42, 0.35, length(centered_uv));
	color_mix *= mix(0.58, 1.0, vignette);

	COLOR = vec4(color_mix, base_alpha);
}
"""
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	return shader_material
