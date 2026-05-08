extends RefCounted
class_name PlayerProfile

var player_id: String = ""
var profile_name: String = ""
var created_at_unix: int = 0
var profile_version: int = 1

static func generate_uuid() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var time_part := int(Time.get_unix_time_from_system())
	var random_part := rng.randi()
	return "%d_%x" % [time_part, random_part]

static func create_new(profile_name_arg: String = "Player") -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.player_id = generate_uuid()
	profile.profile_name = profile_name_arg.strip_edges()
	if profile.profile_name.is_empty():
		profile.profile_name = "Player"
	profile.created_at_unix = int(Time.get_unix_time_from_system())
	profile.profile_version = 1
	return profile

static func from_dict(data: Dictionary) -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.player_id = String(data.get("player_id", "")).strip_edges()
	profile.profile_name = String(data.get("profile_name", "Player")).strip_edges()
	profile.created_at_unix = int(data.get("created_at_unix", 0))
	profile.profile_version = int(data.get("profile_version", 1))
	if profile.player_id.is_empty():
		profile.player_id = generate_uuid()
	return profile

func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"profile_name": profile_name,
		"created_at_unix": created_at_unix,
		"profile_version": profile_version,
	}

func is_valid() -> bool:
	return not player_id.is_empty() and not profile_name.is_empty()
