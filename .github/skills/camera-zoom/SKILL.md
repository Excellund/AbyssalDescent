---
name: camera-zoom
description: "Tune or fix Camera2D zoom and room-fit logic in Godot. Use when zoom feels wrong, the room doesn't fill the screen, camera limits are off, or viewport-resize behavior breaks. Enforces correct Godot zoom semantics: higher value = zoom in."
argument-hint: "Describe the symptom: too much dead space, wrong limits, zooming the wrong direction, or viewport resize breaking bounds."
---

# Camera Zoom — Room Fit System

Use this skill when working on camera zoom, room-fit zoom scaling, camera limits, or viewport-resize reactivity in [scripts/player_camera.gd](../../../scripts/player_camera.gd).

## Godot Camera2D Zoom Semantics

**Higher zoom value = zoom IN (smaller visible area).**

| `zoom` value | Effect |
|---|---|
| `Vector2(0.5, 0.5)` | Zoomed out — shows 2× more world |
| `Vector2(1.0, 1.0)` | Default — 1:1 pixels |
| `Vector2(2.0, 2.0)` | Zoomed in — shows area 4× smaller |

This is the most common source of bugs. A multiplier `> 1.0` zooms **in** (less visible), not out.

## Room-Fit Zoom Formula

To fit an entire room into the viewport:

```gdscript
var fit_zoom := minf(viewport_size.x / room_size.x, viewport_size.y / room_size.y)
fit_zoom *= room_fit_zoom_scale   # 1.0 = exact fit; < 1.0 = padding; > 1.0 = zoom in past fit
fit_zoom = clampf(fit_zoom, min_zoom, max_zoom)
target_zoom = Vector2(fit_zoom, fit_zoom)
```

`room_fit_zoom_scale = 0.95` is the current default — provides slight edge padding so the room boundary is visible.

## Half-View Calculation (Camera Limits)

To compute how much world area is visible from the camera center, always **divide** viewport by zoom:

```gdscript
var half_view := Vector2(
    viewport_size.x * 0.5 / maxf(0.001, fit_zoom),
    viewport_size.y * 0.5 / maxf(0.001, fit_zoom)
)
```

**Never multiply `viewport_size * zoom`.** That compounds instead of inverting and produces limits that are far too tight at `zoom > 1` and far too loose at `zoom < 1`.

## Camera Limit Computation

Limits pin the camera so it cannot scroll past room edges:

```gdscript
var left  := bounds_rect.position.x + half_view.x
var right := bounds_rect.position.x + bounds_rect.size.x - half_view.x
# Collapse to center when room is smaller than viewport at current zoom:
if left > right:
    var center_x := bounds_rect.position.x + bounds_rect.size.x * 0.5
    left = center_x ; right = center_x

limit_left   = int(floor(left))
limit_right  = int(ceil(right))
# same pattern for top/bottom
```

The collapse guard is required whenever `room_fit_zoom_scale < 1.0` or `min_zoom` allows showing more than the room.

## Viewport-Resize Reactivity

Cache the viewport size and re-apply bounds whenever it changes:

```gdscript
var cached_viewport_size: Vector2 = Vector2.ZERO

func _refresh_world_bounds_for_viewport_change() -> void:
    var viewport_size := get_viewport_rect().size
    if viewport_size.distance_to(cached_viewport_size) <= 0.1:
        return
    cached_viewport_size = viewport_size
    if has_world_bounds:
        _apply_zoom_and_limits_from_bounds(world_bounds_rect)
```

Call this at the top of `_physics_process()`.

## Player Visibility Clamp

When clamping the player to the visible area, use the **current live zoom** (not the target), and again divide:

```gdscript
var half_view := Vector2(
    viewport_size.x * 0.5 / maxf(0.001, zoom.x),
    viewport_size.y * 0.5 / maxf(0.001, zoom.y)
)
```

## Exposing the Tuning Knob

Keep a single top-level zoom scale in `world_generator.gd` rather than editing `player_camera.gd` properties directly:

```gdscript
@export_range(0.85, 2.0, 0.01) var camera_base_zoom_in: float = 0.95
```

Apply it in `_ready()` after the camera reference is obtained:

```gdscript
player_camera.call("set_room_fit_zoom_scale", camera_base_zoom_in)
```

`set_room_fit_zoom_scale` re-applies bounds immediately if bounds are already active, so changing the value at runtime is safe.

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| `half_view = viewport * zoom` | Limits way too tight when zoomed in | Use `viewport / zoom` |
| `min_zoom` set near `1.0` (e.g. `0.9`) | Fit zoom formula has no effect on small rooms | Lower `min_zoom` to `0.5` or less |
| Multiplier `> 1.0` for "more padding" | Actually zooms in further | `< 1.0` = zoom out / more padding |
| Limits not updated on resize | Bounds break on window resize | Add `_refresh_world_bounds_for_viewport_change()` |
