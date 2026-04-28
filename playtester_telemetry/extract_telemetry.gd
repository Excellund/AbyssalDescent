extends SceneTree

func _init() -> void:
	var file := FileAccess.open("res://playtester_telemetry/new_player_run_telemetry.save", FileAccess.READ)
	if file == null:
		print("ERROR: could not open file")
		quit()
		return
	var payload_raw: Variant = file.get_var()
	if not (payload_raw is Dictionary):
		print("ERROR: not a dictionary")
		quit()
		return
	var payload := payload_raw as Dictionary
	var runs := payload.get("runs", []) as Array
	print("TOTAL_RUNS: ", runs.size())
	for run_index in range(runs.size()):
		var run := runs[run_index] as Dictionary
		print("---RUN ", run_index, "---")
		print("outcome=", run.get("outcome", "?"))
		print("difficulty_tier=", run.get("difficulty_tier", "?"))
		print("max_depth=", run.get("max_depth", "?"))
		print("rooms_cleared=", run.get("rooms_cleared", "?"))
		print("is_debug=", run.get("is_debug", "?"))
		var death := run.get("death_event", {}) as Dictionary
		if not death.is_empty():
			print("death_source=", death.get("source", "?"), " ability=", death.get("ability", "?"), " bearing=", death.get("bearing_key", "?"), " depth=", death.get("depth", "?"))
		var damage_events := run.get("damage_events", []) as Array
		var damage_by_bearing: Dictionary = {}
		var damage_by_source: Dictionary = {}
		for ev in damage_events:
			var e := ev as Dictionary
			var bk := String(e.get("bearing_key", "unknown"))
			var src := String(e.get("source", "unknown"))
			var amt := float(e.get("amount", 0))
			damage_by_bearing[bk] = float(damage_by_bearing.get(bk, 0.0)) + amt
			damage_by_source[src] = float(damage_by_source.get(src, 0.0)) + amt
		print("damage_by_bearing=", damage_by_bearing)
		print("damage_by_source=", damage_by_source)
		var door_choices := run.get("door_choices", []) as Array
		var doors_by_bearing: Dictionary = {}
		for dc in door_choices:
			var d := dc as Dictionary
			var bk := String(d.get("bearing_key", "unknown"))
			doors_by_bearing[bk] = int(doors_by_bearing.get(bk, 0)) + 1
		print("door_choices_by_bearing=", doors_by_bearing)
		var reward_choices := run.get("reward_choices", []) as Array
		for rc in reward_choices:
			var r := rc as Dictionary
			print("  reward: mode=", r.get("mode","?"), " name=", r.get("chosen_name","?"), " initial=", r.get("is_initial","?"))
		var room_entries := run.get("room_entries", []) as Array
		var rooms_by_bearing: Dictionary = {}
		for re in room_entries:
			var r := re as Dictionary
			var bk := String(r.get("bearing_key", "unknown"))
			rooms_by_bearing[bk] = int(rooms_by_bearing.get(bk, 0)) + 1
		print("room_entries_by_bearing=", rooms_by_bearing)
	quit()
