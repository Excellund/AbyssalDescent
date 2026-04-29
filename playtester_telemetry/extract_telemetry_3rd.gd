extends SceneTree

const INPUT_PATH := "res://playtester_telemetry/3rd_time_player_run_telemetry.save"
const OUTPUT_PATH := "res://playtester_telemetry/3rd_time_out.txt"

func _to_text_map(source: Dictionary) -> String:
	var keys := source.keys()
	keys.sort()
	var parts: Array[String] = []
	for key_variant in keys:
		var key := String(key_variant)
		parts.append("%s=%s" % [key, str(source.get(key_variant))])
	return ", ".join(parts)

func _inc(map: Dictionary, key: String, amount: int = 1) -> void:
	map[key] = int(map.get(key, 0)) + amount

func _init() -> void:
	var out := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if out == null:
		push_error("Cannot write output")
		quit()
		return

	var file := FileAccess.open(INPUT_PATH, FileAccess.READ)
	if file == null:
		out.store_line("ERROR: could not open input")
		out.close()
		quit()
		return

	var payload_raw: Variant = file.get_var()
	if not (payload_raw is Dictionary):
		out.store_line("ERROR: telemetry payload was not a dictionary")
		out.close()
		quit()
		return

	var payload := payload_raw as Dictionary
	var runs := payload.get("runs", []) as Array
	out.store_line("TOTAL_RUNS: %s" % str(runs.size()))

	var total_reward_picks: Dictionary = {}
	var total_reward_picks_by_mode: Dictionary = {}
	var total_initial_reward_picks: Dictionary = {}
	var total_reward_offers: Dictionary = {}
	var door_choices_by_bearing: Dictionary = {}
	var room_entries_by_bearing: Dictionary = {}
	var damage_by_bearing: Dictionary = {}
	var deaths_by_bearing: Dictionary = {}

	for i in range(runs.size()):
		var run := runs[i] as Dictionary
		out.store_line("--- RUN %s ---" % str(i + 1))
		out.store_line("id=%s" % String(run.get("id", "")))
		out.store_line("version=%s" % String(run.get("game_version", "")))
		out.store_line("difficulty_tier=%s" % str(run.get("difficulty_tier", -1)))
		out.store_line("outcome=%s" % String(run.get("outcome", "")))
		out.store_line("max_depth=%s rooms_cleared=%s is_debug=%s" % [str(run.get("max_depth", -1)), str(run.get("rooms_cleared", -1)), str(run.get("is_debug", false))])

		var death := run.get("death_event", {}) as Dictionary
		if not death.is_empty():
			var death_bearing := String(death.get("bearing_key", "unknown"))
			_inc(deaths_by_bearing, death_bearing)
			out.store_line("death=%s" % _to_text_map(death))

		var rewards := run.get("reward_choices", []) as Array
		for reward_variant in rewards:
			var reward := reward_variant as Dictionary
			var chosen_id := String(reward.get("choice_id", reward.get("chosen_id", "unknown")))
			var mode := int(reward.get("mode", -1))
			_inc(total_reward_picks, chosen_id)
			_inc(total_reward_picks_by_mode, "%s|%s" % [str(mode), chosen_id])
			if bool(reward.get("is_initial", false)):
				_inc(total_initial_reward_picks, chosen_id)
			var options := reward.get("options", []) as Array
			for opt_variant in options:
				var opt := opt_variant as Dictionary
				var opt_id := String(opt.get("id", "unknown"))
				_inc(total_reward_offers, opt_id)

		var doors := run.get("door_choices", []) as Array
		for door_variant in doors:
			var door := door_variant as Dictionary
			var bearing := String(door.get("bearing_key", "unknown"))
			_inc(door_choices_by_bearing, bearing)

		var entries := run.get("room_entries", []) as Array
		for entry_variant in entries:
			var entry := entry_variant as Dictionary
			var bearing := String(entry.get("bearing_key", "unknown"))
			_inc(room_entries_by_bearing, bearing)

		var damage_events := run.get("damage_events", []) as Array
		for damage_variant in damage_events:
			var damage := damage_variant as Dictionary
			var bearing := String(damage.get("bearing_key", "unknown"))
			_inc(damage_by_bearing, bearing)

	out.store_line("=== Aggregate ===")
	out.store_line("reward_picks: %s" % _to_text_map(total_reward_picks))
	out.store_line("reward_picks_by_mode: %s" % _to_text_map(total_reward_picks_by_mode))
	out.store_line("initial_reward_picks: %s" % _to_text_map(total_initial_reward_picks))
	out.store_line("reward_offers: %s" % _to_text_map(total_reward_offers))
	out.store_line("door_choices_by_bearing: %s" % _to_text_map(door_choices_by_bearing))
	out.store_line("room_entries_by_bearing: %s" % _to_text_map(room_entries_by_bearing))
	out.store_line("damage_by_bearing: %s" % _to_text_map(damage_by_bearing))
	out.store_line("deaths_by_bearing: %s" % _to_text_map(deaths_by_bearing))

	# Derived pick rates for options offered at least twice.
	var offer_keys := total_reward_offers.keys()
	offer_keys.sort()
	out.store_line("pick_rate_candidates:")
	for key_variant in offer_keys:
		var key := String(key_variant)
		var offered := int(total_reward_offers.get(key, 0))
		if offered < 2:
			continue
		var picked := int(total_reward_picks.get(key, 0))
		var rate := float(picked) / float(offered)
		out.store_line("  %s picked=%s offered=%s rate=%.2f" % [key, str(picked), str(offered), rate])

	out.close()
	quit()
