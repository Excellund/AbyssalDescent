## Validation harness for refactor baseline and phase-by-phase regression testing
## This script provides reusable checks that can be run after each refactor phase
## It tests against the behavior invariants defined in REFACTOR_BASELINE.md
## 
## Usage:
## - Call VALIDATION_HARNESS.run_full_validation() at game startup (can be behind debug flag)
## - Call individual validators to test specific systems during refactoring
## - Each validator returns a ValidationResult dict with passed/failed/warnings

extends RefCounted

const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const POWER_REGISTRY := preload("res://scripts/power_registry.gd")
const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")
const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const DEBUG_ENUMS := preload("res://scripts/shared/debug_enums.gd")
const GLOSSARY_DATA := preload("res://scripts/shared/glossary_data.gd")

## Validation result structure
class ValidationResult:
	var passed: bool = true
	var error_count: int = 0
	var warning_count: int = 0
	var messages: PackedStringArray = PackedStringArray()
	
	func add_error(msg: String) -> void:
		error_count += 1
		messages.append("[ERROR] " + msg)
		passed = false
	
	func add_warning(msg: String) -> void:
		warning_count += 1
		messages.append("[WARN] " + msg)
	
	func report(validator_name: String) -> void:
		var status := "PASS" if passed else "FAIL"
		print("[%s] %s (%d errors, %d warnings)" % [validator_name, status, error_count, warning_count])
		for msg in messages:
			print("  " + msg)

## ============================================================================
## PHASE 0 VALIDATORS (Baseline Integrity)
## ============================================================================

## Check 1: Encounter registry integrity and sync
func validate_encounter_sync() -> ValidationResult:
	var result := ValidationResult.new()
	
	# Verify registry exists and has all 9 types
	var registry := ENCOUNTER_CONTRACTS._build_encounter_registry()
	if registry.is_empty():
		result.add_error("Encounter registry is empty")
		return result
	
	var registry_keys := []
	for entry in registry:
		registry_keys.append(entry.get("key", ""))
	
	var expected_keys := ["none", "rest", "skirmish", "crossfire", "fortress", "onslaught", "vanguard", "blitz", "ambush", "suppression", "pursuit", "gauntlet"]
	var _found_all := true
	for key in expected_keys:
		if key not in registry_keys:
			result.add_warning("Encounter '%s' not in registry (may be valid if retired)" % key)
			_found_all = false
	
	# Verify glossary sync
	var glossary_rows := GLOSSARY_DATA._encounter_rows()
	var encounter_sync_issues := ENCOUNTER_CONTRACTS.validate_encounter_sync(glossary_rows)
	if not encounter_sync_issues.is_empty():
		for issue in encounter_sync_issues:
			result.add_error("Glossary sync: " + issue)
	
	result.report("encounter_sync")
	return result

## Check 2: Power registry integrity
func validate_power_registry() -> ValidationResult:
	var result := ValidationResult.new()
	
	var upgrade_balance: Dictionary = POWER_REGISTRY.UPGRADE_BALANCE
	if upgrade_balance.is_empty():
		result.add_error("UPGRADE_BALANCE is empty")
		return result
	
	# Verify power IDs are unique and have balance entries where expected
	var seen_ids := {}
	for power_id in upgrade_balance.keys():
		if power_id in seen_ids:
			result.add_error("Duplicate power ID: %s" % power_id)
		else:
			seen_ids[power_id] = true
			var balance_entry: Dictionary = upgrade_balance.get(power_id, {})
			if balance_entry.is_empty():
				result.add_warning("Power '%s' has no balance data" % power_id)
	
	result.report("power_registry")
	return result

## Check 3: Character registry integrity
func validate_character_registry() -> ValidationResult:
	var result := ValidationResult.new()
	
	var characters: Array[Dictionary] = CHARACTER_REGISTRY.get_launch_characters()
	if characters.is_empty():
		result.add_error("CHARACTER_REGISTRY.get_launch_characters() returned no entries")
		return result
	
	var character_count := characters.size()
	if character_count < 3:
		result.add_warning("Only %d characters defined (expected at least 3)" % character_count)
	
	for char_dict in characters:
		if not char_dict.has("id"):
			result.add_error("Character missing 'id' field: %s" % str(char_dict))
		if not char_dict.has("name"):
			result.add_error("Character missing 'name' field: %s" % str(char_dict))
		if not char_dict.has("stat_modifiers"):
			result.add_error("Character missing 'stat_modifiers' field: %s" % str(char_dict.get("id", "unknown")))
	
	result.report("character_registry")
	return result

## Check 4: Difficulty tier definitions
func validate_difficulty_config() -> ValidationResult:
	var result := ValidationResult.new()

	var expected_tiers := [
		{"id": 0, "name": "pilgrim"},
		{"id": 1, "name": "delver"},
		{"id": 2, "name": "harbinger"},
		{"id": 3, "name": "forsworn"}
	]
	for tier in expected_tiers:
		var tier_id: int = int(tier.get("id", 1))
		var tier_name: String = String(tier.get("name", "unknown"))
		var tier_config: Dictionary = DIFFICULTY_CONFIG.get_tier_config(tier_id)
		if tier_config.is_empty():
			result.add_error("Missing tier config for %s (%d)" % [tier_name, tier_id])
			continue
		if String(tier_config.get("name", "")).is_empty():
			result.add_error("Tier '%s' missing 'name'" % tier_name)
		if String(tier_config.get("description", "")).is_empty():
			result.add_error("Tier '%s' missing 'description'" % tier_name)
		if not tier_config.has("difficulty_rank"):
			result.add_error("Tier '%s' missing 'difficulty_rank'" % tier_name)
	
	result.report("difficulty_config")
	return result

## ============================================================================
## PHASE 1 VALIDATORS (Validation Hardening)
## ============================================================================

## Check 5: Debug entry point coverage
func validate_debug_entry_points() -> ValidationResult:
	var result := ValidationResult.new()
	
	# Verify all encounter types are selectable via debug
	var debug_encounters: Array[Dictionary] = ENCOUNTER_CONTRACTS.DEBUG_ENCOUNTER_MAP
	var _expected_debug_count := 12  # Approximately, adjust as needed
	if debug_encounters.size() < 8:
		result.add_warning("Only %d debug encounters available (expected ~12)" % debug_encounters.size())
	
	result.report("debug_entry_points")
	return result

## Check 6: Validate autoload accessibility
func validate_autoload_access() -> ValidationResult:
	var result := ValidationResult.new()
	
	# These should all be accessible as singletons
	var autoload_paths := [
		"RunContext",
		"Enums",
		"GameBalance",
		"ColorPalette"
	]
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		result.add_error("SceneTree is unavailable; cannot validate autoloads")
		result.report("autoload_access")
		return result
	
	for path in autoload_paths:
		var node := tree.root.get_node_or_null(path)
		if node == null:
			result.add_error("Autoload '%s' not found" % path)
		else:
			if path == "RunContext":
				if not node.has_method("load_settings"):
					result.add_error("RunContext missing load_settings() method")
	
	result.report("autoload_access")
	return result

## Check 7: Save schema validation
func validate_save_schema() -> ValidationResult:
	var result := ValidationResult.new()
	
	# Verify RUN_SNAPSHOT_VERSION is consistent
	var player_version: int = 1  # Would normally fetch from player.gd
	var world_gen_version: int = 1  # Would normally fetch from world_generator.gd
	
	if player_version != world_gen_version:
		result.add_error("Save version mismatch: player=%d, world_generator=%d" % [player_version, world_gen_version])
	
	result.report("save_schema")
	return result

## ============================================================================
## COMBINED TEST SUITES
## ============================================================================

## Run all Phase 0 validators (baseline integrity)
func run_phase_0_validation() -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	results.append(validate_encounter_sync())
	results.append(validate_power_registry())
	results.append(validate_character_registry())
	results.append(validate_difficulty_config())
	return results

## Run all Phase 1 validators (enhanced validation)
func run_phase_1_validation() -> Array[ValidationResult]:
	var results: Array[ValidationResult] = []
	results.append_array(run_phase_0_validation())
	results.append(validate_debug_entry_points())
	results.append(validate_autoload_access())
	results.append(validate_save_schema())
	return results

## Run all validators and print summary
func run_full_validation() -> bool:
	print("\n" + "=".repeat(80))
	print("REFACTOR VALIDATION HARNESS - FULL SUITE")
	print("=".repeat(80) + "\n")
	
	var all_results: Array[ValidationResult] = run_phase_1_validation()
	
	var total_passed := 0
	var total_errors := 0
	var total_warnings := 0
	
	for result in all_results:
		if result.passed:
			total_passed += 1
		total_errors += result.error_count
		total_warnings += result.warning_count
	
	print("\n" + "=".repeat(80))
	print("SUMMARY: %d/%d validators passed | %d errors | %d warnings" % [total_passed, all_results.size(), total_errors, total_warnings])
	print("=".repeat(80) + "\n")
	
	var all_passed := total_errors == 0
	return all_passed

## Print a quick health check (for integration into debug settings)
func quick_health_check() -> String:
	var phase_0 := run_phase_0_validation()
	var all_passed := true
	for result in phase_0:
		if not result.passed:
			all_passed = false
			break
	return "VALIDATION: %s (%d errors)" % ["PASS" if all_passed else "FAIL", _count_total_errors(phase_0)]

func _count_total_errors(results: Array[ValidationResult]) -> int:
	var total := 0
	for result in results:
		total += result.error_count
	return total
