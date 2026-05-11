#!/usr/bin/env -S godot -s
extends SceneTree

const SEARCH_ROOTS: Array[String] = [
	"res://scripts",
	"res://.github/scripts"
]

func _initialize() -> void:
	print("[Validator] Starting GDScript compile validation")
	var script_paths: Array[String] = []
	for root in SEARCH_ROOTS:
		_collect_script_paths(root, script_paths)
	script_paths.sort()

	var failures: Array[String] = []
	for script_path in script_paths:
		var loaded: Variant = load(script_path)
		if not (loaded is Script):
			failures.append("Load failed: %s" % script_path)


	if failures.is_empty():
		print("[OK] Compiled %d GDScript files" % script_paths.size())
		quit(0)
		return

	print("[FAIL] %d compile issue(s) found" % failures.size())
	for entry in failures:
		print(entry)
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
