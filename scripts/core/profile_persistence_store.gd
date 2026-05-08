extends RefCounted
class_name ProfilePersistenceStore

const PLAYER_PROFILE_SCRIPT := preload("res://scripts/core/player_profile.gd")
const STORAGE_PATH := "user://godot_2026_profile.json"

var _cached_profile: RefCounted = null

func load_or_create_profile() -> RefCounted:
	if _cached_profile != null and _cached_profile.is_valid():
		return _cached_profile
	
	if FileAccess.file_exists(STORAGE_PATH):
		var loaded := _load_profile_from_file()
		if loaded != null and loaded.is_valid():
			_cached_profile = loaded
			return _cached_profile
	
	var new_profile := PLAYER_PROFILE_SCRIPT.create_new("Player")
	_cached_profile = new_profile
	return new_profile

func save_profile(profile: RefCounted) -> bool:
	if profile == null or not profile.is_valid():
		return false
	
	_cached_profile = profile
	
	var json_string := JSON.stringify(profile.to_dict())
	if json_string.is_empty():
		return false
	
	var file := FileAccess.open(STORAGE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[ProfilePersistence] Failed to open file for writing: %s" % STORAGE_PATH)
		return false
	
	file.store_string(json_string)
	print_debug("[ProfilePersistence] Profile saved: %s" % profile.player_id)
	return true

func get_cached_profile() -> RefCounted:
	if _cached_profile == null or not _cached_profile.is_valid():
		return load_or_create_profile()
	return _cached_profile

func clear_cache() -> void:
	_cached_profile = null

func _load_profile_from_file() -> RefCounted:
	if not FileAccess.file_exists(STORAGE_PATH):
		return null
	
	var file := FileAccess.open(STORAGE_PATH, FileAccess.READ)
	if file == null:
		push_error("[ProfilePersistence] Failed to open file for reading: %s" % STORAGE_PATH)
		return null
	
	var json_string := file.get_as_text()
	if json_string.is_empty():
		return null
	
	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		push_error("[ProfilePersistence] JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	
	var data := json.data as Dictionary
	if data.is_empty():
		return null
	
	var profile := PLAYER_PROFILE_SCRIPT.from_dict(data)
	print_debug("[ProfilePersistence] Profile loaded: %s" % profile.player_id)
	return profile
