# Multiplayer Content Integration

**When to use**: Adding new arcana, encounters, characters, or difficulty tuning to the codebase when multiplayer mode exists. Ensures content stays automatically synced across singleplayer and co-op without manual divergence.

---

## Architecture Overview

### Content Auto-Sync (Preloaded Constants)

All **content** (powers, encounters, characters, mutators) is **already auto-synced** because it's preloaded as Godot constants at startup. All peers load identical code, so:

- New power added to `power_registry.gd` → automatically available in multiplayer
- New character added to `character_registry.gd` → automatically available in multiplayer  
- New encounter added to `encounter_definition_data.gd` → automatically available in multiplayer
- New arcana pool entry → automatically inherited by multiplayer

**Why?** Because both singleplayer and multiplayer modes load the same GDScript files with the same constant definitions. No RPC or manual sync needed.

### Difficulty Config Inheritance (Base + Override Layer)

**Difficulty tuning** is handled via explicit architecture:

1. **Base Definitions** (source of truth, in `difficulty_config.gd`):
   - `get_base_encounter_count_before_boss()` — shared across modes
   - `get_base_progression_ranks()` — difficulty rank per bearing (Pilgrim/Delver/Harbinger/Forsworn)
   - Per-bearing config: enemy pressure multipliers, mutator frequency, player affordances, etc.

2. **Multiplayer Override Layer** (in `encounter_difficulty_multiplayer_config.gd`):
   - Inherits base encounter count and difficulty rank from singleplayer (no duplication)
   - Applies multiplayer-specific tuning: higher enemy pressure (co-op needs more challenging spawns), per-enemy specialist offsets, co-op player multipliers
   - Clear comments show which fields are "BASE (from singleplayer)" vs. "MULTIPLAYER OVERRIDE"

3. **Sync Validator** (runs at editor/build time):
   - `difficulty_config.validate_multiplayer_config_sync(multiplayer_config)` checks that base fields match
   - `encounter_difficulty_multiplayer_config.validate_config_sync()` verifies internal consistency
   - Catches drift early if someone accidentally misses a value

**Why this structure?** Prevents accidental duplicates (like manually copying `encounter_count_before_boss` = 8 in both files). If singleplayer encounters 10 rooms before boss, multiplayer auto-inherits the change; no manual sync needed.

---

## How Content Auto-Syncs: The Flow

```
Developer adds new power to power_registry.gd
    ↓
GDScript preloads power_registry.gd at startup (happens for all peers)
    ↓
Both singleplayer and multiplayer code see the new power in their loaded constant
    ↓
✓ Power appears in reward screens, scales correctly, works in both modes
✓ No RPC, no manual registry update needed
```

---

## When You Need to Manually Intervene

### Scenario 1: Adding New Arcana / Power

**What syncs automatically:**
- Power registered in `power_registry.gd` UPGRADE_BALANCE or trial section
- Power appears in reward card pools in both modes
- Power scales with player stats in both modes

**What you verify manually:**
1. Power shows up on reward screens in **singleplayer** at its target difficulty
2. Power shows up on reward screens in **multiplayer co-op** at the same difficulty (run same seeds/scenarios)
3. Power's effect (damage, healing, cooldown) behaves identically in both modes

**Checklist:**
```
□ Add power to power_registry.gd UPGRADE_BALANCE or trial section
□ If character-specific arcana: verify character_registry.gd arcana pool includes new power
□ Test singleplayer: reward screen shows power, effect works as intended
□ Test multiplayer: reward screen shows power, effect works identically
□ Run validator: scripts/validate_multiplayer_content_sync.gd passes
```

### Scenario 2: Adding New Encounter

**What syncs automatically:**
- Encounter definition in `encounter_definition_data.gd` (enemy counts, spawner types, etc.)
- Encounter glossary in `glossary_data.gd` (display name, description, icon)
- Encounter debug entry in `encounter_contracts.gd` (if added)

**What you tune explicitly:**
- **Singleplayer difficulty** in `difficulty_config.gd` per bearing (Pilgrim, Delver, Harbinger, Forsworn)
- **Multiplayer difficulty** in `encounter_difficulty_multiplayer_config.gd` — already tuned as override layer; no duplication needed

**Checklist:**
```
□ Add encounter to encounter_definition_data.gd with enemy counts per bearing
□ Add glossary entry to glossary_data.gd (display name, description, icon)
□ Update encounter_contracts.gd if adding debug entry point
□ Difficulty already synced: base encounter_count in both configs points to get_base_encounter_count_before_boss()
□ Test singleplayer: encounter appears at correct depth in Pilgrim, Delver, Harbinger, Forsworn
□ Test multiplayer: same encounter appears at correct depths; player pressure feels balanced
□ Verify: run validator passes (base fields match)
□ Sanity check: hand-test all 4 bearings at target difficulty (can player win? Does difficulty match expectation?)
```

### Scenario 3: Tuning Difficulty (e.g., Increase Forsworn Pressure)

**Single-player only:** Edit `difficulty_config.gd` bearing definition (e.g., increase `base_enemy_pressure_mult`).

**Multiplayer adjustments:** 
- If you want multiplayer to scale proportionally, **you only need to adjust the override layer** in `encounter_difficulty_multiplayer_config.gd`
- Example: Singleplayer Forsworn `base_enemy_pressure_mult` 1.5 → 1.6; multiplayer auto-inherits but applies its override multiplier (1.7), so effective is 1.7 × (1.6/1.5) scaling preserved
- **Or** make explicit tuning if co-op needs different scaling (e.g., co-op players are more skilled, so keep multiplayer override at 1.7 but tone down other multipliers)

**Checklist:**
```
□ Adjust difficulty_config.gd for singleplayer change
□ If multiplayer needs tuning: adjust encounter_difficulty_multiplayer_config.gd override values
□ Run validator: confirms base fields still sync
□ Test singleplayer: sanity-check all 4 bearings (time to kill, player survival rate)
□ Test multiplayer: sanity-check all 4 bearings (same scaling, balanced co-op pressure)
```

### Scenario 4: Adding New Character

**What syncs automatically:**
- Character registry entry in `character_registry.gd` (name, arcana pool, stats, color)
- Character arcana pool entries (powers that come from preloaded `power_registry.gd`)

**What you verify manually:**
- Lobby character selection syncs to all peers (network RPC handled by `lobby_controller.gd`)
- Character build snapshots replicate correctly in multiplayer (handled by `player_replication_service.gd`)

**Checklist:**
```
□ Add character to character_registry.gd with name, stats, arcana pool, color
□ Verify arcana pool references powers that exist in power_registry.gd
□ Test singleplayer: character selectable, powers appear in runs
□ Test multiplayer: lobby shows new character, joiner can select, build replicates correctly
□ Sanity check: character playstyle feels distinct and balanced vs. other characters
```

---

## Existing Repo Guardrails

These documented patterns ensure multiplayer stays stable when adding content:

- **`multiplayer_sync_authority_baseline.md`** — Authority rules: host validates all state changes before broadcasting; clients ignore stale room_sync_id in objective spawns
- **`multiplayer_peer_ownership_guardrails.md`** — Peer ID reconciliation: never cache peer_id alone; refresh `MultiplayerSessionManager.local_peer_id` during process
- **`same_frame_destination_reservation.md`** — Entity serialization: ensure player/enemy position updates don't create impossible states
- **`enemy_runtime_delta_semantics.md`** — Enemy sync: projectiles and state deltas replicate correctly across peers
- **`trial_arcana_flow.md`** — Power application lifecycle: powers (trial or otherwise) apply consistently regardless of mode
- **SceneTree lifecycle safety** — Any multiplayer UI or session flow that uses `await ...process_frame`, delayed timers, or scene transitions must guard `get_tree()` access with `is_inside_tree()`/null checks. If the node exits tree mid-await (menu close, lobby teardown, scene swap), stale callbacks must bail early instead of calling `get_tree()`.

**When adding content**, if your feature touches any of these systems (e.g., new power with projectile sync, new objective with spawn state), cross-reference the guardrails to avoid violations.

---

## Validation Script

Before marking content as "done," run the sync validator:

```gdscript
var validator_result = difficulty_config.validate_multiplayer_config_sync(
    encounter_difficulty_multiplayer_config
)
if not validator_result.valid:
    for error in validator_result.errors:
        print("ERROR: %s" % error)
else:
    print("✓ Multiplayer config sync validated")
```

Or invoke from command line (documented in `command-list.md`):
```
Validate multiplayer config sync
```

---

## Quick-Reference: Adding New Arcana

1. **Add to registry**: `power_registry.gd` → UPGRADE_BALANCE or trial section
2. **Verify auto-sync**: Open multiplayer build, same reward screen shows new power? ✓
3. **Run validator**: `validate_multiplayer_content_sync.gd` passes? ✓
4. **Manual test**: Singleplayer and multiplayer at same bearing show power with same stats? ✓

Result: New arcana is now live in both modes, balanced consistently, no duplicate registration.

---

## Related Skills

- **`boon-design`** — When designing new powers/upgrades; includes multiplayer note
- **`encounter-content-sync`** — When adding new encounter types; includes multiplayer verification
- **`character-lore-opposition`** — When designing new characters; includes multiplayer pool sync check
- **`difficulty-config`** (future) — If depth tuning and multiplayer scaling needs refactoring

---

## When to Update This Skill

Update this skill when:
- A new content type is added (e.g., "modifiers that affect only multiplayer")
- The base config inheritance structure changes (e.g., new base function added to `difficulty_config.gd`)
- Sync validator moves to a new location or changes behavior
- A common multiplayer integration mistake is discovered and documented as an anti-pattern
