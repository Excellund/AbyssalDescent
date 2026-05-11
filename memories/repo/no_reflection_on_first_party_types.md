# No reflection on first-party types

Project rule: do not use `has_method`, `call(string)`, or `get(string)` reflection
when the receiver is a first-party type (Player, enemies, coordinators,
autoloads with known scripts). The compiler must be able to verify member
access.

## Pattern

Preload the script as a const, then cast and use typed access:

```gdscript
const PLAYER_SCRIPT := preload("res://scripts/player.gd")

func do_thing(node: Node) -> void:
	var typed_player := node as PLAYER_SCRIPT
	if typed_player == null:
		return
	if typed_player.is_dead():
		return
	typed_player.apply_character_package(data)
```

This works for any GDScript file even when it has no `class_name`. The cast
expression `node as PRELOADED_SCRIPT_CONST` is statically type-checked and
returns the typed reference (or `null`). After the null check, all field and
method access is type-safe and refactor-safe.

## When reflection is acceptable

Only at true dynamic boundaries:

- Third-party nodes you do not own.
- Optional/duck-typed plugin contracts that are designed to be opt-in.
- Editor tooling reading `@export`-style metadata.

Inside the gameplay codebase (Player, enemies, world coordinators, autoloads
with known scripts) — never. Preload the script and cast.

## What this replaces

Anti-patterns to remove on sight:

- `node.has_method("foo")` followed by `node.call("foo")`.
- `node.has_method("get")` (every Object has `get` — the guard is meaningless).
- `int(node.get("player_id"))` when the receiver has a known script.
- Defensive `if node.has_method("X"):` chains around what is already a
  contractually-required method on the receiver type.

## Validated locations following this pattern

- `scripts/core/player_roster_helpers.gd` — uses `PLAYER_SCRIPT` and
  `MULTIPLAYER_SESSION_MANAGER_SCRIPT` consts; all `has_method`/`call` purged.
