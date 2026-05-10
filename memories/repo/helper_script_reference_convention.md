# Helper script reference convention

When extracting a new helper script (RefCounted or otherwise) under
`scripts/core/` or anywhere in the project, **reference it by `preload`
constant**, not by `class_name`.

## Why

Godot's global class registry is rebuilt asynchronously when scripts are
added or renamed. Until the editor finishes rescanning, every consumer
of a freshly-added `class_name` reports `Identifier "Foo" not declared
in the current scope.` even though the file exists and parses fine.
This shows up as red squiggles in the editor and breaks `get_errors`
diagnostics during the same session that introduced the helper.

`preload(...)` resolves at parse time from the file path and never
depends on the registry, so it's stable across editor reloads, project
re-imports, and CI script-only runs.

## Pattern

In the helper:

    extends RefCounted
    class_name FooHelper  # optional, kept for potential editor inspector use

In the consumer:

    const FOO_HELPER := preload("res://scripts/core/foo_helper.gd")
    ...
    FOO_HELPER.do_thing(args)

The codebase's existing helpers (`HEALTH_STATE_SCRIPT`, `ENEMY_BASE`,
`POWER_REGISTRY_SCRIPT`, `META_PROGRESS`, `DIFFICULTY_CONFIG`, etc.)
all follow this pattern. Match it.

## Recovered cases (May 2026)

- `PlayerIdentitySilhouette` referenced from `player.gd` → switched to
  `PLAYER_IDENTITY_SILHOUETTE` const.
- `MenuStyleFactory` referenced from `menu_controller.gd` and
  `pause_menu_controller.gd` → switched to `MENU_STYLE_FACTORY` const.

Both originally compiled in some passes and failed in others depending
on registry state. The preload form is the only one that compiles
deterministically.
