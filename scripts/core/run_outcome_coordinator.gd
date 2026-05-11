extends RefCounted

const ENUMS := preload("res://scripts/shared/enums.gd")

var _player_defeated: bool = false
var _run_cleared: bool = false
var _last_victory_unlocked_tier: int = -1

## Multiplayer retry voting state
var _multiplayer_retry_votes: Dictionary = {}  ## peer_id -> true (yes vote)
var _multiplayer_retry_in_progress: bool = false

func reset_for_new_run() -> void:
	_player_defeated = false
	_run_cleared = false
	_last_victory_unlocked_tier = -1
	_multiplayer_retry_votes.clear()
	_multiplayer_retry_in_progress = false

func is_player_defeated() -> bool:
	return _player_defeated

func is_run_cleared() -> bool:
	return _run_cleared

func get_victory_unlocked_tier() -> int:
	return _last_victory_unlocked_tier

func is_retry_in_progress() -> bool:
	return _multiplayer_retry_in_progress

## Called when player dies; decides if this is a terminal outcome.
## Caller is responsible for ensuring no allies remain alive (multiplayer revive logic).
## Returns: {"ok": true/false, "should_broadcast": bool, "outcome": "death"}
func register_player_death(is_multiplayer: bool) -> Dictionary:
	if _player_defeated:
		return {"ok": false, "reason": "already_defeated"}
	_player_defeated = true
	_run_cleared = true
	return {
		"ok": true,
		"should_broadcast": is_multiplayer,
		"outcome": "death"
	}

## Called when victory condition is met (third boss cleared).
## Returns: {"ok": true/false, "should_broadcast": bool, "outcome": "clear"}
func register_victory(is_multiplayer: bool, unlocked_tier: int) -> Dictionary:
	if _run_cleared:
		return {"ok": false, "reason": "run_already_cleared"}
	
	_run_cleared = true
	_last_victory_unlocked_tier = unlocked_tier
	return {
		"ok": true,
		"should_broadcast": is_multiplayer,
		"outcome": "clear",
		"unlocked_tier": unlocked_tier
	}

## Called when joiner receives outcome sync from host.
func apply_synced_outcome(outcome: String) -> Dictionary:
	if outcome == "clear":
		if not _run_cleared:
			_run_cleared = true
			_player_defeated = false
		return {"ok": true, "outcome": "clear"}
	elif outcome == "death":
		if not _player_defeated:
			_player_defeated = true
			_run_cleared = true
		return {"ok": true, "outcome": "death"}
	return {"ok": false, "reason": "unknown_outcome"}

## Retry voting: register a vote from a peer.
## Returns: {"all_voted": bool, "votes_yes": int, "total_peers": int}
func register_retry_vote(peer_id: int, expected_voters: Array) -> Dictionary:
	if _multiplayer_retry_in_progress:
		return {"all_voted": false, "votes_yes": 0, "total_peers": expected_voters.size()}
	
	if peer_id <= 0:
		return {"all_voted": false, "votes_yes": 0, "total_peers": expected_voters.size()}
	
	if not int(peer_id) in expected_voters:
		return {"all_voted": false, "votes_yes": 0, "total_peers": expected_voters.size()}
	
	_multiplayer_retry_votes[int(peer_id)] = true
	
	var votes_yes := 0
	for voter in expected_voters:
		if bool(_multiplayer_retry_votes.get(int(voter), false)):
			votes_yes += 1
	
	var all_voted := votes_yes >= expected_voters.size()
	return {
		"all_voted": all_voted,
		"votes_yes": votes_yes,
		"total_peers": expected_voters.size()
	}

## Retry voting: apply local vote (caller marks itself as voting yes).
func apply_local_retry_vote(local_peer_id: int) -> Dictionary:
	if _multiplayer_retry_in_progress:
		return {"ok": false, "reason": "retry_in_progress"}
	_multiplayer_retry_votes[local_peer_id] = true
	return {"ok": true}

## Retry voting: check local vote status.
func has_local_voted(local_peer_id: int) -> bool:
	return bool(_multiplayer_retry_votes.get(local_peer_id, false))

## Retry voting: finalize and start retry.
func finalize_retry(expected_voters: Array) -> Dictionary:
	var votes_yes := 0
	for voter in expected_voters:
		if bool(_multiplayer_retry_votes.get(int(voter), false)):
			votes_yes += 1
	
	if votes_yes < expected_voters.size():
		return {"ok": false, "reason": "not_all_voted"}
	
	_multiplayer_retry_in_progress = true
	_multiplayer_retry_votes.clear()
	return {"ok": true}

## Retry voting: clear retry state (e.g., after scene change).
func clear_retry_state() -> void:
	_multiplayer_retry_votes.clear()
	_multiplayer_retry_in_progress = false

## Retry voting: handle peer disconnect during voting.
func on_peer_disconnected(peer_id: int, expected_voters: Array) -> Dictionary:
	if _multiplayer_retry_in_progress:
		return {"ok": false, "reason": "retry_in_progress"}
	
	if int(peer_id) in _multiplayer_retry_votes:
		_multiplayer_retry_votes.erase(int(peer_id))
	
	var votes_yes := 0
	for voter in expected_voters:
		if bool(_multiplayer_retry_votes.get(int(voter), false)):
			votes_yes += 1
	
	var all_voted := votes_yes >= expected_voters.size() and votes_yes > 0
	return {
		"all_voted": all_voted,
		"votes_yes": votes_yes,
		"total_peers": expected_voters.size()
	}

## Query: get vote status for UI.
func get_retry_vote_status(expected_voters: Array, local_peer_id: int) -> Dictionary:
	var local_voted := bool(_multiplayer_retry_votes.get(local_peer_id, false))
	var votes_yes := 0
	for voter in expected_voters:
		if bool(_multiplayer_retry_votes.get(int(voter), false)):
			votes_yes += 1
	
	return {
		"local_voted": local_voted,
		"votes_yes": votes_yes,
		"total_peers": expected_voters.size()
	}
