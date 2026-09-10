extends RefCounted
## Decorative act identity only. No nodes, collision, timers or gameplay RNG.
## The continuous arena slab and its true boundary remain in WorldRenderer.

static func _tint(theme: Dictionary) -> Color:
	return theme.get("accent", Color(0.44, 0.74, 0.90)) as Color

static func _ink(accent: Color, strength: float, alpha: float = 1.0) -> Color:
	return Color(0.025 + accent.r * strength, 0.033 + accent.g * strength, 0.048 + accent.b * strength, alpha)

static func draw_surround(canvas: Node2D, arena: Rect2, act: int, theme: Dictionary) -> void:
	var accent := _tint(theme)
	match act:
		2: _draw_vault_surround(canvas, arena, accent)
		3: _draw_void_surround(canvas, arena, accent)
		_: _draw_ruin_surround(canvas, arena, accent)

static func draw_floor(canvas: Node2D, arena: Rect2, act: int, theme: Dictionary) -> void:
	var accent := _tint(theme)
	var inner := arena.grow(-22.0)
	match act:
		2: _draw_vault_floor(canvas, inner, accent)
		3: _draw_void_floor(canvas, inner, accent)
		_: _draw_ruin_floor(canvas, inner, accent)

static func _draw_ruin_surround(canvas: Node2D, arena: Rect2, accent: Color) -> void:
	# Broken masonry stays beyond the wall: it cannot be mistaken for cover.
	for side: float in [-1.0, 1.0]:
		for i in range(9):
			var along := lerpf(arena.position.x + 24.0, arena.end.x - 70.0, float(i) / 8.0)
			var height := 26.0 + float((i * 13) % 4) * 9.0
			var y := arena.get_center().y + side * (arena.size.y * 0.5 + 26.0)
			var block := Rect2(Vector2(along, y if side > 0.0 else y - height), Vector2(50.0 + float(i % 3) * 9.0, height))
			canvas.draw_rect(block, _ink(accent, 0.11))
			canvas.draw_line(block.position, block.position + Vector2(block.size.x * 0.78, 0.0), _ink(accent, 0.28), 2.0)
			canvas.draw_line(block.end, block.end - Vector2(block.size.x * 0.6, 0.0), Color(0.004, 0.008, 0.016, 0.8), 5.0)
		for i in range(5):
			var y := lerpf(arena.position.y + 35.0, arena.end.y - 64.0, float(i) / 4.0)
			var x := arena.get_center().x + side * (arena.size.x * 0.5 + 28.0)
			var points := PackedVector2Array([Vector2(x, y), Vector2(x + side * 47.0, y + 8.0), Vector2(x + side * 38.0, y + 54.0), Vector2(x, y + 42.0)])
			canvas.draw_colored_polygon(points, _ink(accent, 0.12))
			canvas.draw_line(points[0], points[3], _ink(accent, 0.31), 2.0)

static func _draw_ruin_floor(canvas: Node2D, arena: Rect2, accent: Color) -> void:
	canvas.draw_rect(arena, _ink(accent, 0.020))
	var row := 0
	var y := arena.position.y
	while y < arena.end.y:
		var x := arena.position.x
		var column := 0
		while x < arena.end.x:
			var width := 78.0 if row % 2 == 0 else 104.0
			var tile := Rect2(Vector2(x + 3.0, y + 3.0), Vector2(minf(width - 6.0, arena.end.x - x - 3.0), minf(66.0, arena.end.y - y - 3.0)))
			if tile.size.x > 2.0 and tile.size.y > 2.0:
				canvas.draw_rect(tile, _ink(accent, 0.025 + float((column + row * 3) % 4) * 0.004), true)
				canvas.draw_line(tile.position, Vector2(tile.end.x, tile.position.y), Color(accent.r, accent.g, accent.b, 0.055), 1.0)
				if (row * 5 + column * 3) % 7 == 0:
					var p := tile.position + tile.size * Vector2(0.57, 0.0)
					canvas.draw_polyline(PackedVector2Array([p, p + tile.size * Vector2(-0.15, 0.32), p + tile.size * Vector2(0.01, 0.63)]), Color(0.003, 0.008, 0.016, 0.7), 1.5)
			x += width
			column += 1
		y += 72.0
		row += 1

static func _draw_vault_surround(canvas: Node2D, arena: Rect2, accent: Color) -> void:
	# Nested lintels and deep exterior buttresses imply built space below us.
	for layer in range(3):
		var rim := arena.grow(30.0 + float(layer) * 28.0)
		canvas.draw_rect(rim, _ink(accent, 0.105 - float(layer) * 0.021), false, 13.0 - float(layer) * 3.0)
		canvas.draw_rect(rim.grow(9.0), Color(0.006, 0.01, 0.018, 0.82), false, 4.0)
	for side: float in [-1.0, 1.0]:
		for i in range(5):
			var x := lerpf(arena.position.x + 42.0, arena.end.x - 104.0, float(i) / 4.0)
			var y := arena.get_center().y + side * (arena.size.y * 0.5 + 44.0)
			var body := Rect2(Vector2(x, y if side > 0.0 else y - 118.0), Vector2(62.0, 118.0))
			canvas.draw_rect(body.grow(8.0), Color(0.003, 0.007, 0.014, 0.9))
			canvas.draw_rect(body, _ink(accent, 0.15))
			canvas.draw_rect(body.grow(-11.0), _ink(accent, 0.065))
			canvas.draw_line(body.position, body.position + Vector2(body.size.x, 0.0), _ink(accent, 0.38), 3.0)
		for i in range(3):
			var y := lerpf(arena.position.y + 18.0, arena.end.y - 96.0, float(i) / 2.0)
			var x := arena.get_center().x + side * (arena.size.x * 0.5 + 44.0)
			var body := Rect2(Vector2(x if side > 0.0 else x - 96.0, y), Vector2(96.0, 78.0))
			canvas.draw_rect(body, _ink(accent, 0.135))
			canvas.draw_rect(body.grow(-10.0), _ink(accent, 0.055))
			canvas.draw_rect(body.grow(-5.0), _ink(accent, 0.22), false, 1.0)

static func _draw_vault_floor(canvas: Node2D, arena: Rect2, accent: Color) -> void:
	canvas.draw_rect(arena, _ink(accent, 0.034))
	for inset in [6.0, 30.0, 52.0]:
		var band := arena.grow(-inset)
		if band.size.x > 0.0 and band.size.y > 0.0:
			canvas.draw_rect(band, Color(0.004, 0.01, 0.02, 0.62), false, 7.0)
			canvas.draw_rect(band.grow(-4.0), Color(accent.r, accent.g, accent.b, 0.08), false, 1.0)
	var y := arena.position.y + 80.0
	while y < arena.end.y - 70.0:
		canvas.draw_line(Vector2(arena.position.x + 62.0, y), Vector2(arena.end.x - 62.0, y), Color(0.003, 0.009, 0.018, 0.5), 2.0)
		y += 96.0
	var x := arena.position.x + 140.0
	while x < arena.end.x - 90.0:
		canvas.draw_line(Vector2(x, arena.position.y + 62.0), Vector2(x, arena.end.y - 62.0), Color(0.003, 0.009, 0.018, 0.5), 2.0)
		x += 158.0

static func _draw_void_surround(canvas: Node2D, arena: Rect2, accent: Color) -> void:
	# Distant broken forms are dark, static, and always outside the true arena.
	for side: float in [-1.0, 1.0]:
		for i in range(7):
			var x := lerpf(arena.position.x - 15.0, arena.end.x - 48.0, float(i) / 6.0)
			var depth := 40.0 + float((i * 7) % 5) * 16.0
			var y := arena.get_center().y + side * (arena.size.y * 0.5 + depth)
			var points := PackedVector2Array([Vector2(x, y), Vector2(x + 76.0, y + side * 8.0), Vector2(x + 55.0, y + side * 34.0), Vector2(x - 11.0, y + side * 22.0)])
			canvas.draw_colored_polygon(points, _ink(accent, 0.085))
			canvas.draw_line(points[0], points[1], _ink(accent, 0.22), 1.8)
			canvas.draw_line(points[2], points[2] + Vector2(0.0, side * 45.0), _ink(accent, 0.045), 4.0)
		for i in range(4):
			var x := arena.get_center().x + side * (arena.size.x * 0.5 + 46.0 + float(i % 2) * 26.0)
			var y := lerpf(arena.position.y, arena.end.y - 58.0, float(i) / 3.0)
			var points := PackedVector2Array([Vector2(x, y), Vector2(x + side * 60.0, y - 12.0), Vector2(x + side * 45.0, y + 54.0), Vector2(x + side * 8.0, y + 42.0)])
			canvas.draw_colored_polygon(points, _ink(accent, 0.07))
			canvas.draw_line(points[0], points[3], _ink(accent, 0.24), 2.0)

static func _draw_void_floor(canvas: Node2D, arena: Rect2, accent: Color) -> void:
	# Surface plates interrupt the paving, never the walkable slab beneath it.
	canvas.draw_rect(arena, _ink(accent, 0.018))
	var row := 0
	var y := arena.position.y
	while y < arena.end.y - 4.0:
		var x := arena.position.x
		var column := 0
		while x < arena.end.x - 4.0:
			var size := Vector2(minf(145.0, arena.end.x - x), minf(101.0, arena.end.y - y))
			if size.x > 20.0 and size.y > 20.0:
				var cut := minf(20.0 + float((row + column) % 3) * 6.0, size.x * 0.3)
				var p := Vector2(x, y)
				var points := PackedVector2Array([p + Vector2(5.0, 4.0), p + Vector2(size.x - cut, 4.0), p + Vector2(size.x - 5.0, size.y * 0.36), p + Vector2(size.x - 5.0, size.y - 5.0), p + Vector2(cut, size.y - 5.0), p + Vector2(5.0, size.y * 0.64)])
				canvas.draw_colored_polygon(points, _ink(accent, 0.038 + float((row * 3 + column) % 3) * 0.008))
				canvas.draw_line(points[0], points[1], Color(accent.r, accent.g, accent.b, 0.065), 1.0)
			x += 145.0
			column += 1
		y += 101.0
		row += 1

static func draw_boss_entrance(canvas: Node2D, arena: Rect2, boss_key: String, theme: Dictionary, visibility: float) -> void:
	if boss_key in ["kilnheart", "glassweaver", "null_archivist"]:
		_draw_alternative_boss_entrance(canvas, arena, boss_key, visibility)
		return
	if visibility <= 0.0 or boss_key not in ["warden", "sovereign", "lacuna"]:
		return
	var accent := _tint(theme)
	var line := Color(accent.r, accent.g, accent.b, 0.28 * visibility)
	var fill := _ink(accent, 0.13, visibility)
	for side: float in [-1.0, 1.0]:
		# Side motifs remain visible when the production camera fits the room
		# height tightly and the north/south architecture lies outside the view.
		var side_anchor := Vector2(arena.get_center().x + side * (arena.size.x * 0.5 + 26.0), arena.get_center().y)
		match boss_key:
			"warden":
				for i in range(3):
					var plate := Rect2(side_anchor + Vector2(0.0 if side > 0.0 else -38.0, -112.0 + float(i) * 80.0), Vector2(38.0, 62.0))
					canvas.draw_rect(plate, fill)
					canvas.draw_rect(plate.grow(-5.0), line, false, 2.0)
			"sovereign":
				for i in range(3):
					var frame := Rect2(side_anchor + Vector2(side * float(i) * 14.0 + (0.0 if side > 0.0 else -32.0), -102.0 - float(i) * 16.0), Vector2(32.0, 204.0 + float(i) * 32.0))
					canvas.draw_rect(frame, line, false, 3.0)
			"lacuna":
				for i in range(5):
					var p := side_anchor + Vector2(side * float(i % 2) * 14.0, -116.0 + float(i) * 52.0)
					var points := PackedVector2Array([p, p + Vector2(side * 31.0, 6.0), p + Vector2(side * 22.0, 36.0), p + Vector2(side * 4.0, 26.0)])
					canvas.draw_colored_polygon(points, fill)
					canvas.draw_line(points[0], points[1], line, 2.0)

		var anchor := Vector2(arena.get_center().x, arena.get_center().y + side * (arena.size.y * 0.5 + 30.0))
		match boss_key:
			"warden":
				for i in range(3):
					var plate := Rect2(anchor + Vector2(-111.0 + float(i) * 78.0, 0.0 if side > 0.0 else -40.0), Vector2(66.0, 40.0))
					canvas.draw_rect(plate, fill)
					canvas.draw_rect(plate.grow(-5.0), line, false, 2.0)
			"sovereign":
				for i in range(3):
					var frame := Rect2(anchor + Vector2(-106.0 - float(i) * 17.0, side * float(i) * 15.0 + (0.0 if side > 0.0 else -36.0)), Vector2(212.0 + float(i) * 34.0, 36.0))
					canvas.draw_rect(frame, line, false, 3.0)
			"lacuna":
				for i in range(5):
					var p := anchor + Vector2(-120.0 + float(i) * 54.0, side * float(i % 2) * 15.0)
					var points := PackedVector2Array([p, p + Vector2(32.0, side * 5.0), p + Vector2(19.0, side * 33.0), p + Vector2(-4.0, side * 22.0)])
					canvas.draw_colored_polygon(points, fill)
					canvas.draw_line(points[0], points[1], line, 2.0)


static func _draw_alternative_boss_entrance(canvas: Node2D, arena: Rect2, boss_key: String, visibility: float) -> void:
	if visibility <= 0.0:
		return
	var tint: Color = {"kilnheart": Color(1.0, 0.45, 0.16), "glassweaver": Color(0.4, 0.87, 1.0), "null_archivist": Color(0.79, 0.59, 1.0)}[boss_key]
	var line := Color(tint, 0.3 * visibility)
	var fill := Color(tint, 0.08 * visibility)
	for side: float in [-1.0, 1.0]:
		var anchor := arena.get_center() + Vector2(side * (arena.size.x * 0.5 + 20.0), 0.0)
		for i in range(3):
			var p := anchor + Vector2(0.0, float(i - 1) * 86.0)
			match boss_key:
				"kilnheart":
					canvas.draw_arc(p, 31.0, 0.0, TAU, 24, line, 4.0)
					canvas.draw_circle(p, 17.0, fill)
				"glassweaver":
					var points := PackedVector2Array([p + Vector2(0, -33), p + Vector2(24, 0), p + Vector2(0, 33), p + Vector2(-24, 0), p + Vector2(0, -33)])
					canvas.draw_polyline(points, line, 2.0)
				"null_archivist":
					canvas.draw_rect(Rect2(p - Vector2(21, 29), Vector2(42, 58)), fill)
					for row in range(4):
						canvas.draw_line(p + Vector2(-14, -18 + row * 12), p + Vector2(14 - row * 3, -18 + row * 12), line, 2.0)