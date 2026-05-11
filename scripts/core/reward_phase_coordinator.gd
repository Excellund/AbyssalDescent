extends RefCounted

const ENUMS := preload("res://scripts/shared/enums.gd")

var _phase_active: bool = false
var _phase_is_initial: bool = false
var _phase_mode: int = ENUMS.RewardMode.NONE
var _phase_completed_peers: Dictionary = {}

func begin_phase(is_multiplayer: bool, is_initial: bool, mode: int, hud: Node) -> void:
	if not is_multiplayer:
		_phase_active = false
		_phase_is_initial = false
		_phase_mode = ENUMS.RewardMode.NONE
		_phase_completed_peers.clear()
		return
	_phase_active = true
	_phase_is_initial = is_initial
	_phase_mode = mode
	_phase_completed_peers.clear()
	if is_instance_valid(hud):
		hud.hide_persistent_banner()

func build_local_completion_request(is_multiplayer: bool, local_peer_id: int, is_initial: bool, mode: int, hud: Node) -> Dictionary:
	if not is_multiplayer:
		return {}
	if local_peer_id <= 0:
		return {}
	if is_instance_valid(hud):
		hud.show_persistent_banner("Reward Locked In", "Waiting for other player...", Color(0.78, 0.9, 1.0, 0.92))
	return {
		"peer_id": local_peer_id,
		"is_initial": is_initial,
		"mode": mode
	}

func register_peer_completion(is_multiplayer: bool, peer_id: int, is_initial: bool, mode: int) -> bool:
	if not is_multiplayer:
		return false
	if not _phase_active:
		return false
	if _phase_is_initial != is_initial or _phase_mode != mode:
		return false
	_phase_completed_peers[int(peer_id)] = true
	return true

func all_required_peers_completed(required_peers: Array) -> bool:
	if required_peers.is_empty():
		return false
	for peer_id_variant in required_peers:
		var peer_id := int(peer_id_variant)
		if not bool(_phase_completed_peers.get(peer_id, false)):
			return false
	return true

func finalize_phase(is_initial: bool, mode: int) -> Dictionary:
	if not _phase_active:
		return {"ok": false}
	_phase_active = false
	_phase_completed_peers.clear()
	_phase_mode = ENUMS.RewardMode.NONE
	_phase_is_initial = false
	return {
		"ok": true,
		"is_initial": is_initial,
		"mode": mode,
		"clear_boss_reward_pending": not is_initial and mode == ENUMS.RewardMode.BOSS
	}
