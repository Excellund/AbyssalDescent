#!/usr/bin/env -S godot -s
## Multiplayer Config Sync Validator
## 
## Validates that multiplayer difficulty config is synced with singleplayer base definitions.
## Can be run from command line: godot -s validate_multiplayer_config_sync.gd
## 
## Returns: exit code 0 if valid, 1 if errors found

extends SceneTree

const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const MP_CONFIG_PATH := "res://scripts/encounter_difficulty_multiplayer_config.gd"

func _ready() -> void:
	print("\n=== Multiplayer Config Sync Validator ===\n")
	
	# Load multiplayer config
	var mp_config = load(MP_CONFIG_PATH)
	if not mp_config:
		push_error("Failed to load multiplayer config: %s" % MP_CONFIG_PATH)
		quit(1)
		return
	
	# Instantiate or access config
	var mp_instance: Node = null
	if mp_config is GDScript:
		mp_instance = mp_config.new()
	
	# Run validation
	var result = DIFFICULTY_CONFIG.validate_multiplayer_config_sync(mp_instance)
	
	# Report results
	print("Validation Results:")
	print("  Valid: %s" % result.valid)
	
	if result.errors.size() > 0:
		print("\n❌ ERRORS:")
		for error in result.errors:
			print("  - %s" % error)
	
	if result.warnings.size() > 0:
		print("\n⚠️  WARNINGS:")
		for warning in result.warnings:
			print("  - %s" % warning)
	
	if result.valid and result.warnings.size() == 0:
		print("\n✓ All checks passed. Multiplayer config is in sync.")
	
	quit(0 if result.valid else 1)
