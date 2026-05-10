# Smoke Test Scenarios for Refactor Regression Testing

## Purpose

These are manual and automated test paths that verify the behavior invariants defined in [REFACTOR_BASELINE.md](REFACTOR_BASELINE.md). Each scenario is designed to be repeatable and to catch regressions after refactor phases.

**Execution**: These tests should be run after completing each phase. Automate where practical; manual verification for complex scenarios is acceptable.

---

## Quick Test (Smoke Matrix)

A minimal set of quick checks that can be run between commits to catch major breakage.

### QT1: Startup Validation

- **Trigger**: Start the game normally
- **Expected**: "Encounter Sync" validation runs silently (no console errors)
- **Actual**: Check console for `[Encounter Sync] error` messages
- **Pass Criteria**: No sync errors

### QT2: Debug Boot

- **Trigger**: Enable DebugSettings.enabled = true, select Crossfire encounter, Pilgrim bearing, start game
- **Expected**: Game boots with Crossfire encounter
- **Check**: Confirm correct encounter label in HUD, correct enemy types spawned
- **Pass Criteria**: Correct encounter appears, no spawning errors

### QT3: Player Movement

- **Trigger**: In any active room, move player around
- **Expected**: Movement is smooth, dash works, no input lag
- **Check**: Test movement in all directions, use dash, confirm no glitches
- **Pass Criteria**: All movement inputs respond correctly

### QT4: Enemy Combat

- **Trigger**: Attack 1-2 enemies
- **Expected**: Damage dealt, hit feedback works, enemy health decreases
- **Check**: Verify damage numbers, VFX, sound effects
- **Pass Criteria**: Combat mechanics functional

### QT5: Power Application

- **Trigger**: New run → take first boon → observe effect
- **Expected**: Power applied to player, stat/effect visible
- **Check**: Open Tab to see build detail, verify power listed
- **Pass Criteria**: Power available and described in build detail

---

## Standard Test Paths (Regression Suite)

### S1: New Standard Run (Normal Game Flow)

**Objective**: Verify a complete standard game flow works end-to-end.

**Steps**:

1. Start new run (Pilgrim bearing, Bastion character, no debug overrides)
2. Enter first encounter (Skirmish)
3. Take the first boon offered
4. Enter second room
5. Take a trial power (e.g., Razor Wind)
6. Complete at least 1-2 rooms
7. Either win (reach boss and defeat) or lose intentionally

**Verification**:

- Encounters load correctly with expected enemy types
- HUD shows correct stats, bearing badge, mutator indicators
- Power application works (damage changes, special effects activate)
- Defeat or victory screen appears correctly
- No console errors or stuck states

**Pass Criteria**:

- Game completes a full run (min 3 rooms) without crashes or hang
- Encounter labels, power descriptions, HUD display are correct
- Defeat/victory flow completes normally

**Regression Risk**: Highest. Any core gameplay change will break this.

---

### S2: Debug Encounter Boot

**Objective**: Verify all debug entry points allow forced encounter/bearing/power selection.

**Steps**:

1. Enable DebugSettings.enabled = true
2. Set debug_settings.start_encounter to each encounter type (Skirmish, Crossfire, Fortress, etc.)
3. For each encounter, select 2-3 bearings (Pilgrim, Delver, Harbinger, Forsworn)
4. Start game
5. Verify correct encounter + bearing combination loaded
6. Disable debug settings before exiting

**Verification per encounter**:

- Correct enemy types spawn (e.g., Crossfire = ranged + chargers)
- Correct count of each enemy type matches bearing definition
- Room size and static camera setting correct
- Mutator applied (if any for that bearing)
- Door presentation shows correct encounter label/icon/color

**Pass Criteria**:

- All 9 encounter types + 4 bearings boot without errors
- Enemy counts and types match encounter_contracts registry
- Debug enum covers all encounter types

**Regression Risk**: Medium. Encounter identity drift or registry misalignment caught here.

---

### S3: Resume Saved Run

**Objective**: Verify save/resume cycle preserves run state faithfully.

**Steps**:

1. Start new run
2. Take 1 boon and 1 trial power
3. Complete 1 room successfully
4. Pause (ESC) and close game without finishing the run
5. Restart game
6. Select "Resume"
7. Verify run loads correctly
8. Play through 1 more room to confirm state integrity

**Verification**:

- Same run ID shown
- Same powers shown in build detail (boon + trial power)
- Same stats (damage, health, etc.) as when paused
- Room progression counter matches
- Can continue play normally

**Pass Criteria**:

- Resume loads exact player state (all stats, powers, position approximately)
- No stat duplication or loss
- Game continues playable after resume

**Regression Risk**: Medium-High. Save format or player.gd snapshot changes will break this.

---

### S4: Telemetry On/Off

**Objective**: Verify telemetry collection respects consent setting and doesn't break gameplay.

**Steps**:

1. Verify RunContext.telemetry_upload_enabled setting in project settings
2. New run with telemetry enabled:
   - Play 1-2 rooms and defeat
   - Check RunContext.get_pending_telemetry_upload_count() (should be > 0)
3. Quit, disable telemetry in RunContext
4. New run with telemetry disabled:
   - Play 1-2 rooms and defeat
   - Check RunContext.get_pending_telemetry_upload_count() (should be 0)

**Verification**:

- Gameplay functions identically with/without telemetry enabled
- Payload is queued when enabled, not queued when disabled
- No gameplay lag or UI lockups from telemetry operations

**Pass Criteria**:

- Telemetry collection respects consent flag
- Gameplay performance unaffected by telemetry setting
- No errors in telemetry uploader logs

**Regression Risk**: Medium. Telemetry payload versioning or upload logic changes caught here.

---

### S5: Character Selection & Meta-Progression

**Objective**: Verify character unlocking and stat baselines work correctly.

**Steps**:

1. Check initial unlocked characters (should be Bastion by default)
2. Play and win as Bastion (complete Pilgrim tier)
3. Verify Delver tier unlocked
4. Play and win as another character (e.g., Hexweaver)
5. Verify their stat baselines are correct (different from Bastion)
6. Check build detail shows correct archetype abilities

**Verification**:

- Character unlock progression follows expected tier rules
- Each character has correct starting stats
- Character-specific powers (trial powers, boss rewards) are available
- No stat carryover between characters

**Pass Criteria**:

- All unlockable characters are accessible after meeting unlock conditions
- Character stat baselines match character_registry definitions
- Meta-progression state saves/loads correctly

**Regression Risk**: Low-Medium. Character registry changes or progression state corruption caught here.

---

### S6: Bearing Progression & Difficulty Scaling

**Objective**: Verify bearing unlock rules and difficulty scaling changes are applied correctly.

**Steps**:

1. Ensure starting bearing is Pilgrim
2. Defeat Pilgrim run (3-4 rooms + boss)
3. Check that Delver is now available
4. Switch to Delver, start new run
5. Verify enemy counts are higher than Pilgrim
6. Repeat for Harbinger and Forsworn
7. Compare enemy stats (health, damage) scaling between bearings

**Verification**:

- Bearing unlock condition is met (previous tier victory)
- Difficulty config values (enemy health mult, spawn counts) applied correctly
- Each bearing feels progressively harder (subjective but noticeable)
- HUD bearing badge shows correct tier

**Pass Criteria**:

- All 4 bearings unlock in sequence
- Difficulty scaling is applied (min 10% difference per tier)
- No stat anomalies or scaling errors

**Regression Risk**: Medium. Difficulty config or bearing label changes caught here.

---

### S7: Objective Encounter (Last Stand / Hold the Line)

**Objective**: Verify objective mechanics spawn, progress, and complete correctly.

**Steps**:

1. Enable DebugSettings.enabled = true
2. Set start_encounter to an objective encounter (e.g., "last_stand")
3. Start game
4. Observe objective HUD (kill quota, progress bar, timer)
5. Kill enemies and observe quota decrease
6. Either complete objective (kill quota met) or lose (time expires)

**Verification per objective type**:

- Objective HUD shows correct labels and progress indicators
- Spawn timing matches profile definition (every N seconds, batch size)
- Progress updates in real-time
- Objective completion or timeout triggers correctly
- Reward offered after objective completes

**Pass Criteria**:

- All objective types (last_stand, cut_the_signal, hold_the_line) spawn and behave correctly
- Objective completion logic is sound (no premature/late triggering)
- HUD updates accurately during objective

**Regression Risk**: Medium. Objective state ownership changes or runtime changes caught here.

---

### S7b: Hold the Line — Perimeter-Clear Oath ("Oath of the Unbroken Line")

**Objective**: Verify the `hold_full_control` tracker only fires on a clean Hold the Line clear (no decay), and that the **Oath of the Unbroken Line** credits only when the player also clears the run.

**Important pre-knowledge** — read this first:

- The runtime tracker is set in [scripts/objective_runtime.gd](scripts/objective_runtime.gd#L493) and the decay branches that clear `control_unbroken` are at [L448 and L452](scripts/objective_runtime.gd#L448).
- The tracker only writes `hold_full_control_achieved = true` into the run summary; it does NOT grant the oath by itself.
- Per [oaths_evaluator.gd](scripts/progression/oaths_evaluator.gd#L75) every oath also requires `_is_clear(run_summary)` (outcome `clear`/`victory`/`win`). **A successful Hold the Line objective inside a run that you abandon or die in will NOT credit the oath.** This is intentional.

**One-time temporary instrumentation (recommended)** — none of the relevant fields are normally logged. Add three temporary `print()` calls so you can see them in the Output panel, then revert before committing:

```gdscript
# scripts/objective_runtime.gd, inside _apply_control_progress, both decay branches:
if objective_manager.control_progress > 0.0:
    objective_manager.control_unbroken = false
    print("[S7b] control_unbroken -> false (decay branch)")
```

```gdscript
# scripts/core/run_summary_recorder.gd, top of record_hold_full_control_for_tracker:
print("[S7b] record_hold_full_control_for_tracker called")
```

```gdscript
# scripts/core/run_summary_recorder.gd, inside the function that calls
# OATHS_EVALUATOR.evaluate_run (around line 832), right after the call:
print("[S7b] oath results: ", results)
```

**Setup**: Open **Ascension & Oaths** from the main menu and note whether `oath_of_the_unbroken_line` (label "Oath of the Unbroken Line") is currently in the completed list `[X]`. We're watching for it to flip to `[X]` after Run B/C only.

---

**Run A — Decay path (tracker MUST stay false; oath MUST NOT credit)**:

1. Set `DebugSettings.enabled = true` and `start_encounter = "Objective - Hold the Line"` (Pilgrim, no ascension modifiers equipped).
2. In the Hold the Line zone, wait until `control_progress` starts climbing (the bar fills).
3. **Force a decay** — either step fully outside the ring for ~1 s, or stand still and let an enemy enter the ring with you so `control_contested` becomes true. You should see the bar tick down.
4. **Expected console**: `[S7b] control_unbroken -> false (decay branch)` fires at least once.
5. Re-enter and finish the objective.
6. **Expected console**: `record_hold_full_control_for_tracker` is **NOT** printed.
7. Continue the run to a full clear (boss kill).
8. **Expected console**: `oath results` shows `completed_oath_ids` does **not** contain `oath_of_the_unbroken_line`.
9. **Expected UI**: After return-to-menu, the oath in the panel is still `[ ]` (or whatever it was before).

**Run B — Clean clear inside a full run (tracker fires; oath credits)**:

1. Same debug start as Run A. Stay inside the zone for the entire objective; never let it be contested-while-inside or out-of-zone.
2. **Expected console**: NO `[S7b] control_unbroken -> false` lines, and `record_hold_full_control_for_tracker called` fires exactly once at completion.
3. Finish the rest of the run normally and defeat the boss (run outcome must be `clear`).
4. **Expected console**: `oath results` `completed_oath_ids` contains `oath_of_the_unbroken_line` (only on the first qualifying run; on subsequent runs it stays in the persisted list but isn't re-emitted).
5. **Expected UI**: Re-open **Ascension & Oaths** — Oath of the Unbroken Line is now `[X]` (green tint).

**Run C — Rank 3 sanity (modifiers don't suppress the tracker)**:

1. In the Ascension panel, equip ~3 modifiers totaling rank ≥ 3 for your character. Confirm the lobby/header rank label shows `Ascension Rank: 3`.
2. Repeat Run B end-to-end.
3. **Expected**: Same console + UI signals as Run B. Rank-scaled difficulty does not change which branch of `_apply_control_progress` runs.

**Multiplayer spot-check (optional, if Run B passed)**:

1. Host + 1 joiner via `launch_local_mp_pair.bat`. Both pick any character, host configures Hold the Line via debug.
2. Only the host needs the print statements (host is authoritative for objective state — see [objective_runtime.gd](scripts/objective_runtime.gd#L475) `is_remote_replica()` early-out).
3. Run a clean clear; verify host console matches Run B and that the joiner's Ascension panel also shows `[X]` after the run (joiner profile is updated via the persisted run summary on their own machine, not via RPC).

---

**Pass Criteria**:

- Run A: tracker print does **not** appear; oath does **not** appear in `completed_oath_ids`; panel unchanged.
- Run B: tracker print appears exactly once; oath appears in `completed_oath_ids` for the run; panel flips to `[X]`.
- Run C: identical signals to Run B.
- No double-credit on a second clean run (oath is already `[X]`; not re-emitted).
- No `[S7b]` prints during non-Hold-the-Line encounters.

**Cleanup**: Delete the three temporary `print()` lines and run script diagnostics on `objective_runtime.gd` and `run_summary_recorder.gd` before committing.

**Regression Risk**: Medium. Future changes to `_apply_control_progress` decay branches, `apply_control_setup` initialization, or the `_is_clear` gate in `oaths_evaluator.gd` can silently break this oath without any compile error.

---

### S8: Boss Fight

**Objective**: Verify boss encounters spawn and fight mechanics work.

**Steps**:

1. Play through enough rooms to unlock and enter boss room
2. Observe boss spawn and transport animation
3. Deal damage to boss
4. Observe boss attacks and behavior
5. Either defeat boss or lose

**Verification**:

- Correct boss spawned for current progression (Warden → Sovereign → Lacuna)
- Boss health bar and damage feedback work
- Boss attack patterns activate and hit player
- Boss phase transitions (if any) work correctly
- Victory/defeat outcome triggers correctly

**Pass Criteria**:

- Boss encounter spawns with correct identity
- Boss combat mechanics are responsive and challenging
- Boss defeat triggers victory screen
- No boss AI anomalies or stuck states

**Regression Risk**: Medium-High. Enemy behavior, boss-specific AI, or victory condition changes caught here.

---

### S9: Build Detail Panel & Power Description Display

**Objective**: Verify UI text fits, no overflow, descriptions are accurate.

**Steps**:

1. New run, take several powers (boons, trial powers, boss rewards)
2. Press Tab to open build detail panel
3. Scroll through all sections (passives, boons, trial powers, boss rewards if any)
4. Verify all power descriptions are visible and readable
5. Check description text caps (should fit within panel bounds)

**Verification**:

- No text wrapping/overflow issues
- Descriptions match power_registry definitions
- Power names, counts, and stat changes accurately displayed
- UI layout doesn't break with many powers (test with full build)

**Pass Criteria**:

- Build detail panel displays all active powers without text overflow
- Descriptions match registry exactly (no corruption)
- UI is responsive and readable

**Regression Risk**: Low-Medium. UI layout changes or description sync changes caught here.

---

### S10: Settings Persistence

**Objective**: Verify audio, display, and consent settings save and load correctly.

**Steps**:

1. Open settings menu
2. Change audio levels (master, music, SFX)
3. Change display mode (windowed/fullscreen, resolution)
4. Change telemetry consent to opposite setting
5. Exit to main menu
6. Return to settings and verify all changes are retained
7. Quit game completely
8. Restart game and re-check settings

**Verification**:

- All settings reappear when reopening settings menu (same session)
- Settings persist after quit and restart
- Audio levels apply immediately
- Display/resolution changes apply correctly

**Pass Criteria**:

- All user settings persist across session
- No settings data corruption
- Settings menu loads and applies correctly on every boot

**Regression Risk**: Low. Persistence and serialization logic caught here.

---

## Automated vs. Manual Breakdown

**Fully Automatable (Headless Mode)**:

- QT1, QT2: Startup and debug boot
- S2: Debug encounter boot (iterate all encounters/bearings)
- S10: Settings persistence

**Partially Automatable**:

- S1, S3, S4: Can automate the flow but benefit from manual spot-checking
- S8: Boss fight can validate spawn but combat is complex

**Requires Manual Play**:

- S5, S6: Character/bearing progression (requires multiple wins)
- S7: Objective subjective feel and timing

---

## Test Execution Checklist (Per Refactor Phase)

- [ ] Run startup validation (QT1)
- [ ] Run debug boot (QT2)
- [ ] Play one quick run (S1) end-to-end
- [ ] Test resume (S3) with multi-room save
- [ ] Check telemetry on/off (S4)
- [ ] Verify UI text (S9)
- [ ] Verify settings persist (S10)
- [ ] If encounter changes: Run all bearings for each encounter (S2)
- [ ] If objective changes: Test each objective type (S7)
- [ ] If boss changes: Run boss encounter (S8)
- [ ] If difficulty changes: Verify bearing progression (S6)
- [ ] If character changes: Verify character registry (S5)

---

## Regression Detection Template

If a test fails after a refactor phase, use this template to report:

```
Phase: [X] / Scenario: [SX]
Test Name: [What failed]
Expected: [What should happen]
Actual: [What happened]
Console Errors: [Any stack traces or error messages]
Impact: [Severe / Medium / Low]
Suspected Cause: [Which refactor change likely caused this]
```

---

## Reference Links

- [REFACTOR_BASELINE.md](REFACTOR_BASELINE.md) — Behavior invariants
- [validation_harness.gd](scripts/validation_harness.gd) — Automated validator script
- [debug_settings.gd](scripts/debug_settings.gd) — Debug entry points
- [scripts/world_generator.gd](scripts/world_generator.gd) — Startup sequence
