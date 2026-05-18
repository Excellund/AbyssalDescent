#!/usr/bin/env -S godot -s
extends SceneTree

const VALIDATION_HARNESS := preload("res://scripts/validation_harness.gd")

func _initialize() -> void:
	print("\n=== Power Parity Validator ===\n")
	var harness := VALIDATION_HARNESS.new()
	var result = harness.validate_power_parity_gate()
	print("\nPower parity gate result: %s" % ("PASS" if result.passed else "FAIL"))
	print("Errors: %d | Warnings: %d" % [result.error_count, result.warning_count])
	quit(0 if result.error_count == 0 else 1)
