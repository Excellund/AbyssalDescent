extends Node
## Only the staged debug export registers this autoload, after RunContext.
## Character access belongs to its separate profile; other progression is kept.

const META_PROGRESS := preload("res://scripts/meta_progress_store.gd")
const DEBUG_PROFILE := "AbyssalDescent Playtest Debug"
const PLAYTEST_CHARACTERS := ["bastion", "hexweaver", "veilstrider", "riftlancer"]

static func permits_profile(debug_feature: bool, version: Variant, custom_profile: Variant, profile_name: Variant) -> bool:
	return debug_feature and version is String and String(version).begins_with("dev-") and custom_profile is bool and custom_profile and profile_name is String and profile_name == DEBUG_PROFILE

func _ready() -> void:
	if not permits_profile(OS.has_feature("debug"), ProjectSettings.get_setting("application/config/version", ""), ProjectSettings.get_setting("application/config/use_custom_user_dir", false), ProjectSettings.get_setting("application/config/custom_user_dir_name", "")):
		return
	var context := get_node_or_null("/root/RunContext")
	if context == null or not context.is_node_ready():
		return
	var changed := false
	for character_id: String in PLAYTEST_CHARACTERS:
		changed = META_PROGRESS.unlock_character(context.meta_progress_profile, character_id) or changed
	context.get_unlocked_character_ids()
	if changed:
		context.save_meta_progress()
