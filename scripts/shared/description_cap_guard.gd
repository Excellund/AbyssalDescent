extends RefCounted

const MAX_VISIBLE_DESC_CHARS := 109

static func strip_bbcode(text: String) -> String:
	var out := ""
	var inside_tag := false
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		if ch == "[":
			inside_tag = true
			continue
		if inside_tag:
			if ch == "]":
				inside_tag = false
			continue
		out += ch
	return out

static func visible_length(text: String) -> int:
	return strip_bbcode(text).length()

static func assert_visible_cap(text: String, power_id: String, surface: String) -> String:
	if OS.is_debug_build():
		var visible_len := visible_length(text)
		assert(
			visible_len <= MAX_VISIBLE_DESC_CHARS,
			"Description cap exceeded (%s:%s): %d > %d" % [power_id, surface, visible_len, MAX_VISIBLE_DESC_CHARS]
		)
	return text
