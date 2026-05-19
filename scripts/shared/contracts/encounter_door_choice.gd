extends RefCounted
class_name EncounterDoorChoice

const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

var action_id: int = ENUMS.EncounterAction.ENCOUNTER
var action: String = "encounter"
var profile: Dictionary = {}
var reward: int = ENUMS.RewardMode.NONE

func _init(
	action_id_value: int = ENUMS.EncounterAction.ENCOUNTER,
	profile_value: Dictionary = {},
	reward_value: int = ENUMS.RewardMode.NONE
):
	action_id = ENCOUNTER_CONTRACTS.normalize_action(action_id_value)
	action = _action_legacy_name(action_id)
	profile = profile_value.duplicate(true) if action_id == ENUMS.EncounterAction.ENCOUNTER else {}
	reward = ENCOUNTER_CONTRACTS.normalize_reward_mode(reward_value)

static func from_values(action_id_value: int, profile_value: Dictionary, reward_value: int = ENUMS.RewardMode.NONE) -> EncounterDoorChoice:
	return EncounterDoorChoice.new(action_id_value, profile_value, reward_value)

func _action_legacy_name(action_id_value: int) -> String:
	match action_id_value:
		ENUMS.EncounterAction.BOSS:
			return "boss"
		ENUMS.EncounterAction.REST:
			return "rest"
		_:
			return "encounter"

func to_dict() -> Dictionary:
	return {
		"action_id": action_id,
		"action": action,
		"profile": profile.duplicate(true),
		"reward": reward
	}
