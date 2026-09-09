extends RefCounted
## Build provenance survives checkpoints; unknown or mixed origins stay local.

static func start(version: String, is_debug: bool = false) -> Dictionary:
	var clean := version.strip_edges()
	return {"origin_version": clean, "versions": [clean] if not clean.is_empty() else [], "origin_known": not clean.is_empty(), "is_debug": is_debug}

static func restore(saved: Variant, current_version: String) -> Dictionary:
	var result := start("", false)
	if saved is Dictionary:
		var origin := String(saved.get("origin_version", "")).strip_edges()
		result.origin_version = origin
		result.origin_known = saved.get("origin_known") is bool and bool(saved.origin_known) and not origin.is_empty() and saved.get("versions") is Array and saved.get("is_debug") is bool
		result.is_debug = bool(saved.get("is_debug", false))
		if saved.get("versions") is Array:
			for entry in saved.versions:
				var version := String(entry).strip_edges()
				if not version.is_empty() and not result.versions.has(version):
					result.versions.append(version)
		if not origin.is_empty() and not result.versions.has(origin):
			result.versions.push_front(origin)
	var current := current_version.strip_edges()
	if not current.is_empty() and not result.versions.has(current):
		result.versions.append(current)
	return result

static func merge(primary: Variant, other: Variant) -> Dictionary:
	var result := restore(primary, "")
	var additional := restore(other, "")
	result.origin_known = bool(result.origin_known) and bool(additional.origin_known)
	result.is_debug = bool(result.is_debug) or bool(additional.is_debug)
	for version in additional.versions:
		if not result.versions.has(version):
			result.versions.append(version)
	return result

static func is_upload_eligible(provenance: Variant) -> bool:
	if not (provenance is Dictionary):
		return false
	var normalized := restore(provenance, "")
	if not normalized.origin_known or normalized.is_debug or normalized.versions.size() != 1:
		return false
	var version := String(normalized.versions[0]).to_lower()
	return not version.is_empty() and not version.contains("dev") and not version.contains("debug") and version != "unknown"
