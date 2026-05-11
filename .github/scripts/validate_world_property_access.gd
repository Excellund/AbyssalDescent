#!/usr/bin/env -S godot -s
extends SceneTree

const SEARCH_ROOT := "res://scripts"
const FORBIDDEN_PATTERNS := {
	"world.run_cleared": "Use _run_outcome_coordinator.is_run_cleared() (or a local helper) instead of direct world.run_cleared access."
}

func _initialize() -> void:
	print("[Validator] Checking forbidden world property access")
	var script_paths: Array[String] = []
	_collect_script_paths(SEARCH_ROOT, script_paths)
	script_paths.sort()

	var failures: Array[String] = []
	for script_path in script_paths:
		var file := FileAccess.open(script_path, FileAccess.READ)
		if file == null:
			failures.append("Read failed: %s" % script_path)
			continue
		var content := file.get_as_text()
		for forbidden_key in FORBIDDEN_PATTERNS.keys():
			var start := 0
			while true:
				var index := content.find(String(forbidden_key), start)
				if index < 0:
					break
				var line := content.substr(0, index).count("\n") + 1
				failures.append("%s:%d -> %s" % [script_path, line, String(FORBIDDEN_PATTERNS[forbidden_key])])
				start = index + String(forbidden_key).length()

	if failures.is_empty():
		print("[OK] No forbidden world property access patterns found")
		quit(0)
		return

	print("[FAIL] %d forbidden world property access issue(s) found" % failures.size())
	for failure in failures:
		print(failure)
	quit(1)

func _collect_script_paths(root_path: String, output: Array[String]) -> void:
	var dir := DirAccess.open(root_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		var full_path := "%s/%s" % [root_path, name]
		if dir.current_is_dir():
			_collect_script_paths(full_path, output)
		elif name.ends_with(".gd"):
			output.append(full_path)
	dir.list_dir_end()
