extends RefCounted
## One local Rest visit: preserve recovery or invest in an owned Boon.
## The World owns entry, peer readiness and the post-choice checkpoint.

const RECOVER_ID := "rest_recover"
const MAX_UPGRADE_OFFERS := 2

var active := false
var offers: Array[Dictionary] = []

func reset() -> void:
	active = false
	offers.clear()

func begin(registry: Node, target_player: Node2D, rng: RandomNumberGenerator, heal_amount: int) -> Array[Dictionary]:
	reset()
	if not _is_living(target_player):
		return []
	active = true
	offers.append(_recovery_offer(target_player, heal_amount))
	var eligible: Array[Dictionary] = []
	if is_instance_valid(registry):
		for candidate: Dictionary in registry.get_upgrade_pool(target_player):
			if is_upgrade_eligible(registry, target_player, String(candidate.get("id", ""))):
				var offer := candidate.duplicate(true)
				offer["rest_action"] = "upgrade"
				eligible.append(offer)
	for _index in mini(MAX_UPGRADE_OFFERS, eligible.size()):
		var selected := rng.randi_range(0, eligible.size() - 1)
		offers.append(eligible[selected])
		eligible.remove_at(selected)
	return offers.duplicate(true)

func current_offers(registry: Node, target_player: Node2D, heal_amount: int) -> Array[Dictionary]:
	if not active or not _is_living(target_player):
		return []
	# Refresh health and remove invalidated choices without rolling replacements.
	for index in range(offers.size() - 1, -1, -1):
		var id := String(offers[index].get("id", ""))
		if id == RECOVER_ID:
			offers[index] = _recovery_offer(target_player, heal_amount)
		elif not is_upgrade_eligible(registry, target_player, id):
			offers.remove_at(index)
	return offers.duplicate(true)

func resolve(choice_id: String, registry: Node, target_player: Node2D, heal_amount: int) -> Dictionary:
	if not active or not _is_living(target_player):
		return {"ok": false}
	var selected: Dictionary = {}
	for offer in current_offers(registry, target_player, heal_amount):
		if String(offer.get("id", "")) == choice_id:
			selected = offer
			break
	if selected.is_empty():
		return {"ok": false}
	# Health callbacks can run immediately; make this visit unavailable first.
	active = false
	var health_before := int(target_player.get_current_health())
	if choice_id == RECOVER_ID:
		target_player.heal(heal_amount)
		target_player.play_rest_site_heal_feedback()
	else:
		var previous_stack := int(target_player.get_upgrade_stack_count(choice_id))
		target_player.apply_upgrade(choice_id)
		if int(target_player.get_upgrade_stack_count(choice_id)) != previous_stack + 1:
			active = true
			return {"ok": false}
	return {
		"ok": true,
		"choice": selected.duplicate(true),
		"health_before": health_before,
		"health_after": int(target_player.get_current_health()),
		"restored_health": maxi(0, int(target_player.get_current_health()) - health_before),
	}

static func is_upgrade_eligible(registry: Node, target_player: Node2D, id: String) -> bool:
	if not is_instance_valid(registry) or not _is_living(target_player):
		return false
	# Boss rewards also pass registry.is_upgrade(), so use the Boon pool itself.
	if not registry.UPGRADE_POOL_IDS.has(id):
		return false
	if String(target_player.active_character_id) == "riftlancer" and id == "wide_arc":
		return false
	var current := int(target_player.get_upgrade_stack_count(id))
	var limit := int(registry.get_power_stack_limit(id))
	return current > 0 and limit > current

static func _is_living(target_player: Node2D) -> bool:
	return is_instance_valid(target_player) and not target_player.is_dead()

static func _recovery_offer(target_player: Node2D, heal_amount: int) -> Dictionary:
	var current := int(target_player.get_current_health())
	var maximum := int(target_player.get_max_health())
	var restored := mini(maxi(0, heal_amount), maxi(0, maximum - current))
	var description := "Restore %d health.\nHealth: %d → %d / %d" % [restored, current, current + restored, maximum]
	if restored == 0:
		description = "No health to restore.\nContinue at %d / %d health." % [current, maximum]
	return {"id": RECOVER_ID, "name": "Recover", "desc": description, "rest_action": "recover", "stack_limit": 0}
