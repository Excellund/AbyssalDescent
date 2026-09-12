# Practice with an unlocked Vessel

> Superseded interface: the current [generic Practice sandbox](warden-practice.md) includes all Vessels and full build/encounter setup. These earlier implementation receipts are preserved as historical evidence. Recent damage has been removed from Practice.

Warden Practice still starts as base Bastion. In Pause, victory or defeat, **Next attempt** offers the Vessels already unlocked in the normal profile. Selecting one prepares a later attempt. Resume keeps the current actor and the pending choice; Retry creates a fresh actor with the selected Vessel's ordinary base stats and passive. Leaving Practice discards both choices.

The selector grants no powers, Catalysts, Ascension modifiers or extra protection. Each Vessel uses its existing Player implementation, including Iron Retort, Sigil Burst, Veilstep Rhythm, Farline Focus and Effigy Command. The Warden, arena, combat rules and shared music timeline remain unchanged. Recent damage and attempt counters clear on Retry.

## Isolation and lifecycle

`practice_arena.gd` reads canonical unlocks through `available_characters_for_profile(profile)`, which deep-copies its argument before the existing progress store normalizes it. It does not call the normal character selector, mutate RunContext's unlock cache or save a selection. Missing and malformed optional character state falls back to Bastion; unknown IDs and duplicate unlocks never produce extra options.

The scene accepts `request_vessel(id)` only in Pause or terminal states, while no party or transition is active. Retry validates the pending ID against the current unlocks both when requested and at its deferred commit. A revoked choice is reconciled to an available current Vessel or Bastion; the rejected commit does not replace the actor. A valid commit retires the old actor and interaction generation before applying the next package to a newly instantiated Player. This prevents omitted package properties, passive resources, Effigies and buffered inputs from carrying into another Vessel.

Presentation returns detached option dictionaries with canonical `id` and display `name`, the actual `character_id`/`character_name`, and `next_character_id`. Refresh does not reset a valid pending choice. The UI keeps its options and selection stable through periodic updates, and the selector is absent during active combat so it cannot consume Attack or Dash controls.

## Verification scope

`test_practice_vessels.gd` uses the actual Practice scene, Player and Warden. It stages actor positions, freezes autonomous movement and advances ordinary action timing to verify each unchanged base passive through accepted damage. It grants no power or passive state. This is deterministic integration evidence, not a live-combat or human-balance claim.

The fixture verifies every base package, one real passive per Vessel, accepted damage accounting, Effigy placement/anchor delivery/recall/retirement, paused and active deferred cancellation, stale and locked choices, singleton recovery after unlock revocation, held-input release, fresh health and recap, duplicate Retry rejection and the same native score playback. It compares normal checkpoint/backup/temp, profile, progress, History, telemetry/upload queues and settings bytes, as well as cached selection, unlocks, Bearing, loadouts and launch requests. An actual Menu roundtrip and normal Continue restore the original depth-seven descent at 77 HP.

The [companion UI/native fixture](practice-vessel-ui.md) covers all five names, selector keyboard input, popup Escape handling, pending choice across Resume, focus and full six-row recap at 960×540, 1280×720 and 1920×1080 using the production canvas.

## Core prototype receipt — 2026-09-12

The final focused source snapshot `abyssal-validation-192161877c724913852115958c6a845f` compiles 454 GDScript files and passes both source guards. It passes 326 new Practice Vessel checks, 106 existing Practice lifecycle checks, 52 existing character-passive runtime checks and 68 Effigy runtime checks: 552 assertions across four suites, with no script errors or teardown leaks.

With controlled geometry, the Warden loses 70 HP from Bastion's empowered Attack and Retort together, 48 HP from Hexweaver's Attack and Sigil Burst, 35 HP from Veilstrider's Surge wave, and 24 HP from Effigy Keeper's anchor-delivered Attack. Riftlancer's Attack removes 14 HP at close range and 34 HP in its precision band. These observations assert the existing rules; no mechanic or tuning was changed to make the tests pass.

The direct active-scene teardown check also caught a pre-existing late cleanup call after child PlayerFeedback had left the tree. Practice now skips that redundant call for an exited Player while retaining normal attached Retry/Menu cleanup and unconditional owned-service unbinding. The test destroys a live deployed Effigy scene and verifies retired actors, controller, groups, combat action and service ownership without profile changes.

The isolated core fixture's first runs exposed a missing seeded character-state assumption and input timing errors in the test. Their logs remain preserved. The final fixture advances real idle and physics boundaries for release/press handling and drives the ordinary Dash implementation; it never removes the player's held-input guard. Core source hashes, raw logs and the integration patch are retained in `.feedback/uncharted-descent-20260912/practice-vessel-prototype/`.
