shader_type canvas_item;
render_mode unshaded;

void fragment() {
	// Equal-width edges at every aspect ratio; the center remains unobscured.
	vec2 viewport_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 edge_pixels = min(UV, vec2(1.0) - UV) * viewport_size;
	float edge_distance = min(edge_pixels.x, edge_pixels.y);
	float band_width = min(viewport_size.x, viewport_size.y) * 0.22;
	COLOR.a *= 1.0 - smoothstep(0.0, band_width, edge_distance);
}
