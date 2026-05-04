extends RefCounted

var boons_taken: Array[String] = []
var arcana_rewards_taken: Array[String] = []

func reset_for_new_run() -> void:
	boons_taken.clear()
	arcana_rewards_taken.clear()

func record_boon(name: String) -> void:
	boons_taken.append(name)

func record_arcana(name: String) -> void:
	arcana_rewards_taken.append(name)
