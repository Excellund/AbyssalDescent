---
name: menu-panel-layout
description: "Resize, add, or reposition panels in the main menu or pause menu in Godot. Use when changing panel dimensions, adding a new panel to the main menu, or fixing a panel that appears the wrong size or off-center. Enforces the two-place update rule: _build_* and _apply_menu_layout()."
argument-hint: "Panel name, new base size, and whether it's main menu or pause menu."
---

# Menu Panel Layout

Use this skill whenever you add, resize, or reposition a panel in `scripts/menu_controller.gd` or `scripts/pause_menu_controller.gd`.

## The Two-Place Rule (main menu only)

`menu_controller.gd` has a layout pass that runs after `_build_ui()` and on every window resize:

```
_ready() -> _build_ui() -> _apply_menu_layout()
```

`_apply_menu_layout()` calls `_set_centered_panel_layout(panel, base_size, fit_scale, viewport_size)` for every registered panel. This **completely overrides** whatever `position` and `size` were set during `_build_*`. If you only change `_build_*`, the layout pass silently restores the old dimensions.

**Any panel size change requires updates in exactly two places:**

1. `_build_*` function — `panel.size = Vector2(w, h)`
2. `_apply_menu_layout()` — the matching `_set_centered_panel_layout(panel, Vector2(w, h), ...)` call

### How `_set_centered_panel_layout` works

```gdscript
func _set_centered_panel_layout(panel, base_size, panel_scale, viewport_size):
    panel.set_anchors_preset(PRESET_TOP_LEFT)
    panel.size = base_size
    panel.scale = Vector2(panel_scale, panel_scale)
    panel.position = (viewport_size - base_size * panel_scale) * 0.5
```

- `base_size`: unscaled design size in the 2560×1440 base viewport.
- `fit_scale`: `min(1.0, viewport / MENU_LAYOUT_BASE_SIZE)` — panels shrink on small screens.
- Centering is automatic. Do **not** attempt manual position math or anchor-based centering; this function is the authority.

### Do not use `PRESET_CENTER` for main menu panels

`_set_centered_panel_layout` resets anchors to `PRESET_TOP_LEFT` and sets position directly. Any `PRESET_CENTER` + `offset_*` work done during build will be discarded.

## Panels registered in `_apply_menu_layout`

| Panel variable | Registered base size (May 2026) |
|---|---|
| `root_panel` | dynamic via `_root_panel_base_size()` |
| `options_panel` | 760 × 700 |
| `history_panel` | 980 × 680 |
| `leaderboard_panel` | 1080 × 700 |
| `ascension_panel` | 1520 × 920 |
| `glossary_panel` | 1360 × 900 |
| `multiplayer_panel` | 980 × 700 |
| `difficulty_selector_panel` | 1020 × 720 |
| `character_selector_panel` | dynamic via `_character_selector_panel_size()` |
| `atmosphere_band` | 620 × 660 |
| `lobby_modal_panel` | dynamic via `_lobby_modal_size()` |

To add a new panel: declare the variable, build it in `_build_*`, add it to the scene in `_build_ui`, and add a `_set_centered_panel_layout` call in `_apply_menu_layout`.

## Pause menu panels

`pause_menu_controller.gd` does **not** have an equivalent layout pass. Panels are positioned via containers (`VBoxContainer`, `MarginContainer`, `HBoxContainer`) with `PRESET_FULL_RECT` on the layout container. Use container-based sizing, not absolute position.

## Checklist for panel resize

- [ ] Updated `panel.size` in `_build_*`
- [ ] Updated the matching `Vector2(w, h)` in `_apply_menu_layout()` (main menu only)
- [ ] Ran `Validate GDScript Compile` — exit 0
