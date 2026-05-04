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
