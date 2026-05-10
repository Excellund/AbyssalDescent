extends RefCounted
class_name MenuStyleFactory

## Stateless StyleBoxFlat builders shared by menu / pause-menu controllers.
## Both controllers previously carried byte-identical local copies of these
## two functions; any visual tweak had to be made twice or the surfaces
## drifted apart. Routing both controllers through this single source of
## truth removes that bug surface.
##
## Note: lobby_controller.gd has its own variants that intentionally differ
## (panel style adds content margins; button style defaults to corner_radius
## 16). Those are NOT duplicates and remain on the lobby controller.


static func make_panel_style(bg_color: Color, border_color: Color, corner_radius: int = 14, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style


static func make_button_style(bg_color: Color, border_color: Color, corner_radius: int = 14, border_width: int = 2) -> StyleBoxFlat:
	var style := make_panel_style(bg_color, border_color, corner_radius, border_width)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style
