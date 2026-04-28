extends SceneTree

const OUT_PATH := "res://playtester_telemetry/p2_out.txt"

func w(out: FileAccess, line: String) -> void:
	out.store_line(line)

func _init() -> void:
	var out := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if out == null:
		print("ERROR: cannot write output file")
		quit()
		return
	var file := FileAccess.open("res://playtester_telemetry/new_player_2_run_telemetry.save", FileAccess.READ)
	if file == null:
		w(out, "ERROR: could not open file")
		out.close()
		quit()
		return
	var payload_raw: Variant = file.get_var()
	if not (payload_raw is Dictionary):
		w(out, "ERROR: not a dictionary")
		out.close()
		quit()
		return
	var payload := payload_raw as Dictionary
	var runs := payload.get("runs", []) as Array
	w(out, "TOTAL_RUNS: " + str(runs.size()))
	for run_index in range(runs.size()):
		var run := runs[run_index] as Dictionary
		w(out, "---RUN " + str(run_index) + "---")
		w(out, "outcome=" + str(run.get("outcome", "?")))
		w(out, "difficulty_tier=" + str(run.get("difficulty_tier", "?")))
		w(out, "max_depth=" + str(run.get("max_depth", "?")))
		w(out, "rooms_cleared=" + str(run.get("rooms_cleared", "?")))
		w(out, "is_debug=" + str(run.get("is_debug", "?")))
		var death := run.get("death_event", {}) as Dictionary
		if not death.is_empty():
			w(out, "death_source=" + str(death.get("source","?")) + " ability=" + str(death.get("ability","?")) + " bearing=" + str(death.get("bearing_key","?")) + " depth=" + str(death.get("depth","?")))
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
		w(out, "damage_by_bearing=" + str(damage_by_bearing))
		w(out, "damage_by_source=" + str(damage_by_source))
		var door_choices := run.get("door_choices", []) as Array
		var doors_by_bearing: Dictionary = {}
		for dc in door_choices:
			var d := dc as Dictionary
			var bk := String(d.get("bearing_key", "unknown"))
			doors_by_bearing[bk] = int(doors_by_bearing.get(bk, 0)) + 1
		w(out, "door_choices_by_bearing=" + str(doors_by_bearing))
		var reward_choices := run.get("reward_choices", []) as Array
		for rc in reward_choices:
			var r := rc as Dictionary
			w(out, "  reward: mode=" + str(r.get("mode","?")) + " chosen=" + str(r.get("chosen_name","?")) + " id=" + str(r.get("chosen_id","?")) + " initial=" + str(r.get("is_initial","?")))
		var room_entries := run.get("room_entries", []) as Array
		var rooms_by_bearing: Dictionary = {}
		for re in room_entries:
			var r := re as Dictionary
			var bk := String(r.get("bearing_key", "unknown"))
			rooms_by_bearing[bk] = int(rooms_by_bearing.get(bk, 0)) + 1
		w(out, "room_entries_by_bearing=" + str(rooms_by_bearing))
	out.close()
	quit()
