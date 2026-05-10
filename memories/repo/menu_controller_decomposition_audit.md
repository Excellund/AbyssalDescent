# Menu controller decomposition audit (May 2026)

`scripts/menu_controller.gd` (~3,180 lines) and
`scripts/pause_menu_controller.gd` (~860 lines) build menus
imperatively in code. Audited for cohesive islands.

## Established pattern

- Stateless `RefCounted` helper under `scripts/core/` with `static`
  methods. Pass `self` (the `Control` parent) only when actually needed.
- For tiny (~5 line) helpers shared across multiple controllers, prefer
  a **1-line wrapper** on each controller that delegates to the shared
  static method. Eliminates duplicate logic without churning ~80 call
  sites or breaking local Find-Refs.

## Existing extraction

- `MenuStyleFactory` (`scripts/core/menu_style_factory.gd`) — owns
  `make_panel_style` and `make_button_style`. Both `menu_controller.gd`
  and `pause_menu_controller.gd` previously had byte-identical local
  copies (`_make_panel_style` / `_make_pause_panel_style` etc.). Both
  controllers now keep 1-line `_make_*_style` wrappers that forward to
  the factory; call sites unchanged. Future style tweaks (StyleBoxFlat
  default width/radius defaults, anti-aliasing toggles, etc.) are made
  in one place.

## Intentional divergences (do NOT mechanically merge)

- `scripts/lobby_controller.gd` has its own `_make_panel_style` and
  `_make_button_style`. They differ from the shared factory:
  - `_make_panel_style` adds `content_margin_left/right = 14.0` and
    `top/bottom = 10.0` (the shared panel style has no margins).
  - `_make_button_style` defaults `corner_radius = 16` (shared = 14).
  These differences ship today's lobby visuals. Treat them as variants,
  not duplicates. If future visual unification is desired, do it as a
  deliberate behavior change with a screenshot diff — not as part of a
  refactor.
- `pause_menu_controller._apply_pause_option_selector_theme` is NOT
  byte-identical to `menu_controller._apply_option_selector_theme`. The
  pause variant uses `corner_radius = 10` and constructs hover/pressed
  via `style.duplicate()` instead of fresh `make_button_style` calls.
  Different implementation strategy, slightly different output. Skip.

## Audited and rejected (would be trampolines)

- **Update service handlers** (~150 lines, ~12 functions): each method
  reads/writes `Player`-owned widget refs (`update_prompt_layer`,
  `update_action_button`, `update_status_label`) and binds to the
  `UpdateService` autoload via signals connected in `_ready`. Moving
  the methods to a helper still requires those widget references to
  travel back to the helper for every state mutation. Net cognitive
  load: same. Net file count: +1.
- **Profile name prompt** (~100 lines): same shape as update handlers —
  owns `profile_name_prompt_layer` widget, mutates it from many call
  sites scattered through the controller's lifecycle.
- **Multiplayer host/join flow** (`_create_multiplayer_room`,
  `_join_multiplayer_room`, `_await_multiplayer_join_result`,
  `_format_multiplayer_room_error`, lobby modal helpers, ~280 lines):
  the strongest candidate by LOC, but the methods read RUN_CONTEXT,
  call `_change_to_lobby_scene`, mutate `lobby_modal_layer`, gate on
  `_should_autostart_debug_encounter`, and emit menu state transitions
  via `_show_root_panel`. Extracting just the protocol code requires
  passing back a long fan-out of menu mutations. Re-evaluate only if
  multiplayer flow gets a dedicated UI path (separate scene), at
  which point it becomes a real island.
- **`_make_menu_button` / `_make_panel_back_button` /
  `_apply_difficulty_button_theme`**: identical color palette to pause
  variants but the widget assembly differs (size, alignment, position
  flags). Not byte-equivalent. Hoisting the palette as named constants
  would help readability but the win is small and the file is already
  consistent within itself.

## Reject any future "extract another helper from menu_controller.gd"

unless the candidate satisfies all three:
1. Reads/writes only its arguments, not controller widget fields.
2. Does not connect signals to the controller.
3. Has byte-equivalent (or near-byte) logic in another controller, OR
   has many call sites within one controller AND a clear single
   responsibility.
