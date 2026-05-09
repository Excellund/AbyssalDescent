extends RefCounted

# Phase: world-generator-decomposition / Task: extract-room-depth-bookkeeper
#
# Owns boss-target-depth math, boss-unlock predicates, depth clamping,
# and the throttled depth-sanity warning state. WG retains `room_depth`,
# `rooms_cleared`, `first_boss_defeated`, `second_boss_defeated`,
# `encounter_count`, `third_boss_encounter_count` (read by many other
# systems); this helper is the single owner of the math derived from
# them and the only writer of `room_depth` for sanity-clamp purposes.

var _world: Node2D
var _last_logged_depth: int = -1
var _last_log_usec: int = 0

func _init(world: Node2D) -> void:
	_world = world

func get_second_boss_target_depth() -> int:
	var encounter_count: int = _world.encounter_count
	return maxi(encounter_count + 1, encounter_count * 2)

func get_third_boss_target_depth() -> int:
	var second_target := get_second_boss_target_depth()
	return maxi(second_target + 1, second_target + int(_world.third_boss_encounter_count) + 1)

func get_max_sane_depth() -> int:
	return get_third_boss_target_depth() + 2

func is_second_boss_unlocked() -> bool:
	return _world.first_boss_defeated and not _world.second_boss_defeated and _world.room_depth >= get_second_boss_target_depth()

func is_third_boss_unlocked() -> bool:
	return _world.second_boss_defeated and _world.room_depth >= get_third_boss_target_depth()

func build_route_context(depth: int) -> Dictionary:
	var target_depth: int = _world.encounter_count
	if _world.second_boss_defeated:
		target_depth = get_third_boss_target_depth()
	elif _world.first_boss_defeated:
		target_depth = get_second_boss_target_depth()
	return {
		"depth": depth,
		"rooms_until_boss": maxi(0, target_depth - depth)
	}

func clamp_room_depth_to_sane_range() -> void:
	var max_sane := get_max_sane_depth()
	var room_depth: int = _world.room_depth
	if room_depth <= max_sane:
		return
	var now_usec := Time.get_ticks_usec()
	var should_log := room_depth != _last_logged_depth or now_usec - _last_log_usec >= 2000000
	if should_log:
		push_warning("[Depth Sanity] Clamping high room_depth %d -> %d (rooms_cleared=%d, bosses: 1st=%s, 2nd=%s, 3rd=%s)" % [
			room_depth, max_sane, _world.rooms_cleared,
			_world.first_boss_defeated, _world.second_boss_defeated, _world.second_boss_defeated
		])
		_last_logged_depth = room_depth
		_last_log_usec = now_usec
	_world.room_depth = max_sane
