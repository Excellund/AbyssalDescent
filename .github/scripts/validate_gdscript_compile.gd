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

	var failures: Array[String] = []
	for script_path in script_paths:
		# Force parse/compile from disk without mutating cached in-use script resources.
		var loaded: Variant = ResourceLoader.load(script_path, "", 1)
		var script := loaded as Script
		if script == null:
			failures.append("Load failed: %s" % script_path)
			continue


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
