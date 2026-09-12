extends "res://scripts/tests/test_unbroken_shared_attack.gd"
## Real deliberate inputs, accepted Effigy geometry and Oath's per-Attack bank.
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
var audio_retirement := AUDIO_RETIREMENT.new()

class OathFeedback extends "res://scripts/player_feedback.gd":
	var swords: Array[Dictionary] = []
	var fixture_audio_retirement: RefCounted
	# Repeated play() calls have distinct native playbacks. A tree-exit snapshot
	# sees only the newest one, so observe each actual sound at its source.
	func play_impact_sound() -> void:
		super.play_impact_sound()
		fixture_audio_retirement._capture_playback(impact_sound_player)
	func play_attack_swing_sound() -> void:
		super.play_attack_swing_sound()
		fixture_audio_retirement._capture_playback(attack_swing_sound_player)
	func play_boss_unbroken_retaliation(origin: Vector2, impact: Vector2, ratio: float) -> void:
		swords.append({"origin": origin, "impact": impact, "ratio": ratio})
		super.play_boss_unbroken_retaliation(origin, impact, ratio)

class Keeper extends OathPlayer:
	var packets: Array[Dictionary] = []
	var fixture_audio_retirement: RefCounted
	func _create_player_feedback() -> void:
		player_feedback = OathFeedback.new()
		player_feedback.fixture_audio_retirement = fixture_audio_retirement
		add_child(player_feedback)
		player_feedback.setup(max_health, get_current_health())
	func _broadcast_cue_event(event_name: String, payload: Dictionary, reliable: bool = false) -> void:
		if event_name == "unbroken_oath_retaliation":
			packets.append(payload.duplicate(true))
		super._broadcast_cue_event(event_name, payload, reliable)

func _make_world() -> void:
	super._make_world()
	player.upgrade_system.power_registry.free()
	player.free()
	player = Keeper.new()
	player.fixture_audio_retirement = audio_retirement
	_add_circle(player, 14.0)
	world.add_child(player)
	player.player_id = 1
	player.apply_character_package(player.CHARACTER_REGISTRY.get_character("threadbinder"))
	player.apply_upgrade("unbroken_oath")
	player.damage = 20
	player.arcana_motion.set_process(false)
	player.boss_combinations.set_process(false)

func _attack(direction: Vector2 = Vector2.RIGHT, blast: bool = false) -> void:
	player.attack_cooldown_left = 0.0
	player.attack_lock_time_left = 0.0
	if blast:
		player.perform_motion_blast(direction, 1.0)
	else:
		player._try_execute_attack(direction)

func _gain(count: int) -> float:
	var total := 0.0
	for index in count:
		total += (2.6 + player.indomitable_spirit_damage_reduction * 8.0) * pow(2.1, index)
	return minf(total, player._get_indomitable_fill_requirement())

func _run() -> void:
	node_added.connect(audio_retirement.observe_node)
	await _test_reused_audio_observation()
	await _test_fill_cycle()
	for blast in [false, true]:
		await _test_sword_origins(blast)
	await _test_interleaved_contacts()
	await _test_unique_contacts_and_cleanup()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await audio_retirement.wait_until_retired(self), "Released Effigy combat audio retires before fixture exits")
	print("[OathEffigy] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_reused_audio_observation() -> void:
	_make_world()
	await _settle()
	var feedback := player.player_feedback as OathFeedback
	feedback.play_attack_swing_sound()
	var first: WeakRef = weakref(feedback.attack_swing_sound_player.get_stream_playback())
	await physics_frame
	feedback.play_attack_swing_sound()
	var second: WeakRef = weakref(feedback.attack_swing_sound_player.get_stream_playback())
	_check(first.get_ref() != null and second.get_ref() != null and first.get_ref() != second.get_ref(), "Reusing the real swing player creates a distinct native playback")
	_check(_observes_playback(first) and _observes_playback(second), "Fixture observes both reused-player playbacks before the newest replaces its exit handle")
	_free_world()
	await process_frame
	_check(await audio_retirement.wait_until_retired(self), "Both replaced and final swing playbacks retire after their real owner is freed")

func _observes_playback(expected: WeakRef) -> bool:
	for observed in audio_retirement._playbacks:
		if expected.get_ref() != null and observed.get_ref() == expected.get_ref():
			return true
	return false

func _test_fill_cycle() -> void:
	_make_world()
	await _settle()
	_attack()
	_check(player.indomitable_damage_bank == 0.0 and player._effigy_attack_count == 1, "Missed deployment counts one deliberate Attack and earns no Oath")
	var targets: Array[ComboEnemy] = []
	for offset in [Vector2(32, 0), Vector2(42, 10), Vector2(42, -10), Vector2(60, 0)]:
		targets.append(_enemy(player.effigy_position + offset))
	await _settle()
	_attack()
	print("[OathEffigyRepro] cleave bank=%s expected=%s hits=%s" % [player.indomitable_damage_bank, _gain(4), targets.map(func(t: ComboEnemy): return t.hits.size())])
	_check(is_equal_approx(player.indomitable_damage_bank, _gain(4)), "Four accepted effigy victims earn exactly one four-contact Oath combo")
	_check(player._effigy_attack_count == 2, "Effigy cleave cannot count one deliberate Attack per victim")
	for attempt in 20:
		if player._indomitable_spirit_primed:
			break
		_attack()
	_check(player._indomitable_spirit_primed, "Repeated real cleaves reach the finite Oath cap")
	_check((player.player_feedback as OathFeedback).swords.is_empty(), "The Attack that fills Oath never spends it during its later contacts")
	var before := targets.map(func(t: ComboEnemy): return t.get_current_health())
	var bonus := int(round(player.damage * player._get_indomitable_retaliation_ratio()))
	_attack()
	var dealt := 0
	for index in targets.size():
		dealt += int(before[index]) - targets[index].get_current_health()
	_check(dealt == 80 + bonus, "The following cleave spends retaliation damage once across all four victims")
	_check(player.indomitable_damage_bank == 0.0 and not player._indomitable_spirit_primed, "Spending cleave cannot refill Oath")
	_attack()
	_check(is_equal_approx(player.indomitable_damage_bank, _gain(4)), "The next deliberate effigy Attack starts a fresh contact combo")
	_free_world()

func _test_sword_origins(blast: bool) -> void:
	_make_world()
	await _settle()
	_prime()
	var body := player.global_position
	_attack(Vector2.RIGHT, blast)
	var feedback := player.player_feedback as OathFeedback
	_check(feedback.swords.size() == 1 and feedback.swords.back().origin == body, "Deployment retaliation keeps the committed body origin; blast=%s" % blast)
	_check(player.effigy_deployed and player.indomitable_damage_bank == 0.0, "Primed deployment miss places the effigy and spends Oath; blast=%s" % blast)
	var anchor := player.effigy_position
	player.global_position = Vector2(-130, 160)
	_prime()
	_attack(Vector2.RIGHT, blast)
	_check(feedback.swords.size() == 2 and feedback.swords.back().origin == anchor, "Later retaliation launches from committed effigy; blast=%s" % blast)
	_check(feedback.swords.back().impact.is_equal_approx(anchor + Vector2.RIGHT * (feedback.swords.back().impact.x - anchor.x)), "Retaliation blade follows the actual effigy attack ray; blast=%s" % blast)
	var packet: Dictionary = (player as Keeper).packets.back()
	_check(packet.player_position == anchor, "Existing retaliation cue serializes the same committed effigy origin; blast=%s" % blast)
	player.global_position = Vector2(300, 200)
	player._recall_effigy()
	player._on_cue_unbroken_oath_retaliation(packet)
	_check(feedback.swords.back().origin == anchor, "A delayed observer cue cannot move its sword to the recalled effigy or walking body; blast=%s" % blast)
	_free_world()

func _test_interleaved_contacts() -> void:
	_make_world()
	await _settle()
	_attack()
	var anchor := player.effigy_position
	var first := _action()
	var later := _action()
	player.local_owner = false
	var a := _enemy(anchor + Vector2(40, 0))
	var b := _enemy(anchor + Vector2(50, 5))
	var c := _enemy(anchor + Vector2(60, -5))
	await _settle()
	_check(player._accept_shared_attack_start(first, {"body_origin": player.global_position, "direction": Vector2.RIGHT}), "Host accepts first effigy Attack start")
	var packet := {"raw_amount": 20.0, "damage_coefficient": 1.0, "attack_origin": anchor}
	DAMAGEABLE.apply_damage(a, 20, INTERACTIONS.damage_context(first, "melee", packet), 1)
	_check(player._accept_shared_attack_start(later, {"body_origin": player.global_position, "direction": Vector2.RIGHT}), "Host accepts following effigy Attack start before earlier cleave completes")
	DAMAGEABLE.apply_damage(a, 20, INTERACTIONS.damage_context(later, "melee", packet), 1)
	DAMAGEABLE.apply_damage(b, 20, INTERACTIONS.damage_context(first, "melee", packet), 1)
	DAMAGEABLE.apply_damage(c, 20, INTERACTIONS.damage_context(later, "melee", packet), 1)
	var expected := minf(player._get_indomitable_fill_requirement(), 2.0 * _gain(2))
	print("[OathEffigyRepro] interleaved bank=%s expected=%s" % [player.indomitable_damage_bank, expected])
	_check(is_equal_approx(player.indomitable_damage_bank, expected), "Interleaved accepted cleaves retain their own Oath contact index instead of sharing a player counter")
	player.local_owner = true
	_free_world()

func _test_unique_contacts_and_cleanup() -> void:
	_make_world()
	await _settle()
	_attack()
	player.apply_trial_power("razor_wind")
	var anchor := player.effigy_position
	var close := _enemy(anchor + Vector2(40, 0))
	var outer := _enemy(anchor + Vector2(135, 0))
	await _settle()
	_attack()
	_check(close.hits.size() == 1 and outer.hits.size() == 1 and outer.hits[0].type == "razor_wind", "Real effigy melee and outer Razor Wind contact two distinct victims")
	_check(is_equal_approx(player.indomitable_damage_bank, _gain(2)), "Melee and Razor Wind share one two-victim Oath combo")
	# Use the recorded accepted root rather than inventing another action.
	var seq: int = player.combat_interactions._roots.keys().back()
	var root_action := {"run": INTERACTIONS.current_run(), "room": INTERACTIONS.current_room(), "owner": 1, "seq": seq, "epoch": player.combat_interactions._epoch, "kind": "melee", "ancestry": 0}
	var bank := player.indomitable_damage_bank
	DAMAGEABLE.apply_damage(close, 20, INTERACTIONS.damage_context(root_action, "melee", {"raw_amount": 20.0, "damage_coefficient": 1.0, "attack_origin": anchor}), 1)
	DAMAGEABLE.apply_damage(outer, 11, INTERACTIONS.damage_context(root_action, "sovereigns_double", {"raw_amount": 11.0, "damage_coefficient": 0.55, "secondary": true}), 1)
	_check(player.indomitable_damage_bank == bank, "Duplicate victim packets and Double damage cannot add an Oath contact")
	player.combat_interactions.cancel()
	DAMAGEABLE.apply_damage(outer, 20, INTERACTIONS.damage_context(root_action, "razor_wind", {"raw_amount": 20.0, "damage_coefficient": 1.0, "attack_origin": anchor}), 1)
	_check(player.indomitable_damage_bank == bank and player.combat_interactions._roots.is_empty(), "Cancellation retires old contact indices with the bounded Attack ledger")
	player.indomitable_damage_bank = 0.0
	outer.position = Vector2(600, 300)
	await _settle()
	_attack()
	_attack()
	_check(is_equal_approx(player.indomitable_damage_bank, 2.0 * _gain(1)), "Separate single-victim Attacks restart the contact multiplier after cancellation")
	_free_world()
