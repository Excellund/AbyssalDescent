extends RefCounted

# Phase: world-generator-decomposition / Task: extract-difficulty-scaling-provider
#
# Owns the single-vs-multiplayer difficulty config provider lookup, the
# multiplayer party-size scaling math, and the co-op enemy durability
# mutator construction. Holds the lazy `DIFFICULTY_CONFIG_MULTIPLAYER`
# cache instance. Wide-read WG state (`current_difficulty_tier`,
# `current_difficulty_config`) stays on WG; this helper is the single
# writer-helper for tier-config resolution and the single source of
# party-size/health-scaling reads.

const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const DIFFICULTY_CONFIG_MULTIPLAYER := preload("res://scripts/encounter_difficulty_multiplayer_config.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

var _world: Node2D
var _multiplayer_config: Object = null

func _init(world: Node2D) -> void:
	_world = world

func get_config_provider() -> Object:
	if _world.is_multiplayer:
		if _multiplayer_config == null:
			_multiplayer_config = DIFFICULTY_CONFIG_MULTIPLAYER.new()
		return _multiplayer_config
	return DIFFICULTY_CONFIG

func resolve_tier_config(tier: int) -> Dictionary:
	var provider: Object = get_config_provider()
	var base_config: Dictionary = {}
	if provider != null and provider.has_method("get_tier_config"):
		base_config = provider.get_tier_config(tier)
	else:
		base_config = DIFFICULTY_CONFIG.get_tier_config(tier)
	var loadout: Array[String] = _get_active_ascension_loadout()
	if loadout.is_empty():
		return base_config
	var ascension_config: Dictionary = DIFFICULTY_CONFIG.get_tier_config_with_ascension(tier, loadout)
	# Re-layer multiplayer-only keys that the singleplayer ascension resolver
	# doesn't know about (party-size scaling, etc.).
	for key in base_config.keys():
		if not ascension_config.has(key):
			ascension_config[key] = base_config[key]
	return ascension_config

func _get_active_ascension_loadout() -> Array[String]:
	var run_context := _world.get_node_or_null("/root/RunContext")
	if run_context == null or not run_context.has_method("get_active_ascension_loadout"):
		return []
	var raw: Variant = run_context.get_active_ascension_loadout()
	var out: Array[String] = []
	if raw is Array:
		for entry in raw:
			out.append(String(entry))
	return out

func get_party_size() -> int:
	if not _world.is_multiplayer:
		return 1
	if not MultiplayerSessionManager.is_session_connected():
		return 1
	var session_info := MultiplayerSessionManager.get_session_info() if MultiplayerSessionManager.has_method("get_session_info") else {}
	var peer_count := int(session_info.get("connected_peer_count", 0))
	if peer_count <= 0 and MultiplayerSessionManager.has_method("get_peer_ids"):
		peer_count = (MultiplayerSessionManager.get_peer_ids() as Array).size()
	if peer_count <= 0:
		peer_count = _world._get_multiplayer_player_nodes().size()
	return clampi(peer_count, 1, MultiplayerSessionManager.MAX_PARTY_SIZE)

func get_health_scaling_mult(is_boss: bool) -> float:
	var party_size := get_party_size()
	if party_size <= 1:
		return 1.0
	var difficulty_config: Dictionary = _world.current_difficulty_config
	var per_extra_key := "coop_boss_health_per_extra_player" if is_boss else "coop_enemy_health_per_extra_player"
	var curve_power_key := "coop_boss_health_curve_power" if is_boss else "coop_enemy_health_curve_power"
	var cap_key := "coop_boss_health_max_mult" if is_boss else "coop_enemy_health_max_mult"
	var per_extra := maxf(0.0, float(difficulty_config.get(per_extra_key, 0.0)))
	if per_extra <= 0.0:
		return 1.0
	var curve_power := maxf(0.01, float(difficulty_config.get(curve_power_key, 1.0)))
	var cap_mult := maxf(1.0, float(difficulty_config.get(cap_key, 4.0)))
	var extras := float(party_size - 1)
	var health_mult := 1.0 + per_extra * pow(extras, curve_power)
	return clampf(health_mult, 1.0, cap_mult)

func build_enemy_durability_mutator() -> Dictionary:
	if not _world.is_multiplayer:
		return {}
	var health_mult := get_health_scaling_mult(false)
	if health_mult <= 1.001:
		return {}
	return {
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_ID: "coop_durability_scaling",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME: "Co-op Fortification",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_TARGET_SCOPE: "enemy",
		ENCOUNTER_CONTRACTS.MUTATOR_STAT_ENEMY_HEALTH_MULT: health_mult
	}
