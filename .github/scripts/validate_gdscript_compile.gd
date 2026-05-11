#!/usr/bin/env -S godot -s
extends SceneTree

const SEARCH_ROOTS: Array[String] = [
	"res://scripts",
	"res://.github/scripts"
]

func _collect_live_script_paths() -> Dictionary:
	var live_paths: Dictionary = {}
	_collect_node_script_paths(get_root(), live_paths)
	return live_paths

func _collect_node_script_paths(node: Node, live_paths: Dictionary) -> void:
	if node == null:
		return
	var script_value: Variant = node.get_script()
	if script_value is Script:
		var script_path := String((script_value as Script).resource_path)
		if not script_path.is_empty():
			live_paths[script_path] = true
	for child in node.get_children():
		var child_node := child as Node
		if child_node != null:
			_collect_node_script_paths(child_node, live_paths)

func _initialize() -> void:
	call_deferred("_run_validation")

func _run_validation() -> void:
	print("[Validator] Starting GDScript compile validation")
	var script_paths: Array[String] = []
	for root in SEARCH_ROOTS:
		_collect_script_paths(root, script_paths)
	script_paths.sort()
	var live_script_paths := _collect_live_script_paths()

	var failures: Array[String] = []
	var skipped_in_use := 0
	for script_path in script_paths:
		var loaded: Variant = load(script_path)
		var script := loaded as Script
		if script == null:
			failures.append("Load failed: %s" % script_path)
			continue
		if bool(live_script_paths.get(script_path, false)):
			skipped_in_use += 1
			continue
		var reload_result := script.reload()
		if reload_result == ERR_ALREADY_IN_USE or reload_result == ERR_BUSY:
			skipped_in_use += 1
			continue
		if reload_result != OK:
			failures.append("Compile failed (%d): %s" % [reload_result, script_path])


	if failures.is_empty():
		print("[OK] Compiled %d GDScript files" % script_paths.size())
		if skipped_in_use > 0:
			print("[Validator] Skipped reload for %d in-use scripts" % skipped_in_use)
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
