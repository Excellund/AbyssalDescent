# Threadbinder

Historical implementation record. The 11 September workday revision replaces this alternating-target passive with [Effigy Keeper](effigy-keeper.md), retaining the stable `threadbinder` character/save ID. The rules and earlier verification below describe the superseded version.

Feedback `FB-7295384767ec4441`, implemented on `codex/feedback-72953847-fifth-character` from committed main. This entry adds the fifth playable character; it does not change other queued features.

## Player experience

Threadbinder, **Keeper of Loose Ends**, rewards deliberate target changes. The coral body and paired ivory shuttles have distinct idle, movement, Attack and Dash poses. A fine thread points to the previous foe; its rim shows the remaining four-second window and dims when the foe moves beyond reach.

**Cross Stitch:** the first accepted foe per original Attack receives 12% Mark for four seconds and becomes the thread's endpoint. Switching foes with another Attack within four seconds releases a radius-48 Burst at the previous living foe, if within 240 range of the player. The Burst carries 60% of the new contact's unconditioned damage basis and Damage coefficient. Melee, Razor Wind and charged Blast contacts qualify. Same-target Attacks refresh the thread without bursting; misses, rejected contacts and automatic damage do not move it. A lethal switch can release the old endpoint but leaves no new thread.

Base stats: 90 health, 225 movement speed, 24 Damage, 96 Attack range, 75° Attack arc, 0.28s Attack cooldown and 0.42s Dash cooldown. The ordinary shared reward pools remain available.

Threadbinder unlocks after a Riftlancer clear and starts its own Bearing progression. Existing profiles retain their saved IDs and unlocks; their next Riftlancer clear unlocks Threadbinder. Normal menu, random selection, lobby selection, per-character progression, checkpoints and duplicate party palettes use the expanded registry.

## Runtime and integration

Cross Stitch consumes the existing accepted-attack boundary and original-action ledger. It never creates another Attack. Its Burst can feed damage receivers under their existing limits, with target conditions resolved independently. Marks benefit the whole party while each player keeps a separate thread.

The host resolves contacts, statuses and Burst damage. Packed shared state sends the remaining thread time and enemy network ID; reliable host-owned cues render one Burst on each observer. The new Mark source is appended to preserve existing packed indices.

Pause, Build Details, focus/input cancellation and live build updates preserve committed threads. Death, player removal, room exit, character changes and checkpoint restoration clear them. Temporary enemy references are not saved.

Likely integration overlaps are `player.gd`, `shared_build_runtime.gd`, `player_replication_service.gd`, the shared damage/interaction/status catalogues, `character_registry.gd`, the unlock chain and `combat-power-roster.md`. Preserve the sibling synergy changes when combining these hunks. The primary checkout's newer uncommitted work was not copied; its newer Build Details presentation should continue consuming the same shared passive catalogue. Keep new packed property/source ordering consistent across the combined build.

## Verification and playtest

All Godot automation uses disposable projects with isolated user data through the supplied helpers. Focused fixtures cover ordinary unlock/save/checkpoint/lobby paths, first-contact limits, actual Razor Wind, conditional scaling, shared Mark ownership, pause and cleanup, and real host/joiner damage and cue transport. The default gameplay runner includes the three new headless fixtures. Run `test_threadbinder_enet.gd` through `test_boss_combinations_enet.ps1 -FixtureScript`; render `render_threadbinder.gd` through `render_gameplay_fixture.ps1` with `threadbinder_frames` and nine expected frames. The passive UI fixture now produces 24 frames.

Verified September 10, 2026: 306 scripts compile; Threadbinder runtime 75 checks, lifecycle 31, progression/save/co-op package integration 49, menu layout/focus 211, and real ENet host/client 29/7, all passing. Existing passive, native producer, shared damage/status, wording, power-description, snapshot, reward-inspection, ownership and reward-layout suites passed. RTX 4080 rendering passed nine character/action frames (57 checks) and 24 passive UI frames (88 checks). Final local evidence is retained under temporary directories `abyssal-validation-2c00be6d843848b7a922b2d63e6f8c29`, `abyssal-validation-fd66f7d11cfc4a58ad653422a5d4c479`, `abyssal-validation-0c43c6d1e40e4ae894642bf125eb7daf`, `abyssal-enet-4956399f2713473f825210f8116f5ee3`, `abyssal-gameplay-render-7f8ab849a36b43988d9895e272c8fa30` and `abyssal-gameplay-render-8f0da497e3ef412d9841004df2f07cc3`.

The shared board entry is `awaiting_playtest`, pending user acceptance.

Human playtest should assess whether switching targets feels rewarding against crowds, whether the narrower Attack arc makes the first-target rule predictable, whether single-boss damage feels adequate, and whether the thread remains readable in a full party. Automated verification does not settle balance or enjoyment. This dispatch leaves changes reviewable without a commit, merge or desktop executable delivery.
