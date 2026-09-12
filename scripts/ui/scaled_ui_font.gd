extends RefCounted
## Local font copy for panels that compensate for the game's canvas stretch.
## Raster font oversampling does not account for a Control's scale.

static func apply_to(control: Control) -> void:
	var source := ThemeDB.fallback_font
	var local_theme := control.theme.duplicate() as Theme if control.theme != null else Theme.new()
	local_theme.default_font = _copy_for_scale(source)
	# A default-font override otherwise replaces RichTextLabel's distinct faces.
	# Preserve authored bold/italic keyword spans, including FontVariation bases.
	for face in ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
		local_theme.set_font(face, "RichTextLabel", _copy_for_scale(control.get_theme_font(face, "RichTextLabel")))
	control.theme = local_theme

static func _copy_for_scale(source: Font, use_msdf: bool = true) -> Font:
	if source == null:
		return null
	var font := source.duplicate() as Font
	if font is FontVariation:
		# Synthetic emboldening can create intersecting outlines that MSDF
		# cannot represent. Keep these faces rasterized at a sufficient density.
		var variation := source as FontVariation
		font.base_font = _copy_for_scale(variation.base_font, use_msdf and is_zero_approx(variation.variation_embolden))
	elif font is FontFile or font is SystemFont:
		font.set("multichannel_signed_distance_field", use_msdf)
		if not use_msdf:
			font.set("oversampling", 4.0)
	return font
