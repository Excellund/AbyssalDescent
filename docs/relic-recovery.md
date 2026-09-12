# Relic Recovery

Implemented during the September 12 autonomous feature session on `codex/uncharted-descent-20260912`. This is new feature work authorized outside the feedback queue; it does not replace any awaiting-playtest feedback item.

Relic Recovery is a Mission available from depth 2. Three relics lie around an open arena. Walk over one to collect it and enter the central receiver to deliver it. Each living player can carry one; three shared deliveries complete the room. The first pickup of each relic summons two ordinary reinforcements. A party can retrieve different relics together or clear the initial enemies before awakening another relic.

Carrying preserves ordinary movement, Dash, Attack and all powers. Taking damage does not drop a relic. A fallen or disconnected carrier drops it at the last reachable position so a living teammate can recover it. Reclaiming a dropped relic does not summon another wave. There is no timer, carrying slowdown, damage penalty or indefinitely replenishing enemy stream.

## Route and reward

The existing Mission pool can select Recovery after the introductory rooms, and the existing entered-objective history prevents immediately repeating it. Generating or declining the door does not count as entering it. The two authored layouts mirror the three locations vertically; the offered profile stores the chosen positions.

The 1040×760 arena has no physical cover. Relics begin at `(-280, -170)`, `(280, -170)` and `(0, 260)`, or their vertical mirror, outside the central entry slots and receiver. Initial enemies use the existing Bearing and party scaling. Each first pickup adds two chasers/chargers, with chasers only on Pilgrim. Pending reinforcement requests use the existing spawn transport, queue and population cap.

Completing the objective uses the normal Mission reward: one Boon and **Fortified for three rooms**. The existing card and reward application own that benefit. It neither creates an extra reward type nor adds a permanent progression currency.

## Ownership and lifecycle

`scripts/core/relic_recovery_state.gd` owns the three relic records, carrying capacity, deterministic simultaneous pickup, drop/deposit transitions and one completion event. `objective_runtime.gd` calls it only on the authoritative host with the living player roster. Stable player IDs distinguish identical characters. A disappeared carrier releases cargo at its last observed clamped position.

`objective_manager.gd` carries a bounded Recovery-only snapshot on the existing ordered, room-scoped objective channel. Sending only the relevant fields avoids exceeding ENet's MTU. Replicas render those snapshots and cannot claim proximity pickups. Room reset, completion and terminal defeat clear the state. Completion uses the established objective cleanup and reward flow.

The ground relics and receiver participate in the existing compact-biome objective exclusions. Compact biome events retain their committed warnings and timing; exclusion zones do not grant player invulnerability. All physical retrieval routes remain open.

Continue retains the existing between-room checkpoint model. Native saved doors preserve their resolved relic layout and entered-objective history. Delivered cargo is not resurrected on Continue; entering the saved offer begins three fresh relics. No save-version change or midcombat persistence system is introduced.

## Presentation

Gold relics have a clear pickup boundary and a small carried marker; the mint receiver displays three delivery slots. World labels compensate for camera zoom and the actual window stretch. The HUD gives survey instructions, the shared delivered count and a carrying instruction tied to the locally owned avatar, including when a fallen owner spectates an ally. The generic glossary entry agrees with these rules.

## Verification

All unattended Godot work uses the existing disposable-project helpers and isolated user data. Relevant entry points:

- `test_relic_recovery.gd`: carrying and simultaneous pickup, defeat/disconnect recovery, malformed snapshots, four-player capacity, profile matrix, actual Main survey/entry/clear/reward, compact-biome exclusions and actual Continue.
- `test_relic_recovery_enet.ps1`: two real Main processes, native chosen-door/readiness/objective/health/reward RPCs, local-owner display, stale-packet rejection and a real transport disconnect followed by carrier removal and dropped-relic recovery. Actor positions are deliberately staged on both peers; this proves transport and authority rather than internet lobby behavior.
- `render_relic_recovery.ps1`: production 2560×1440 canvas at 960/1280 physical windows; survey, normal walking pickup/deposit, staged drop and actual Mission reward. Enemies are held idle for consistent visual inspection; it does not establish combat balance.

September 12 isolated verification passed:

| Verification | Result | Retained helper output |
| --- | --- | --- |
| Focused rules, real Main and Continue | 386 checks | `abyssal-validation-7203ed4145d646778ee6aafbe8073766` |
| Existing descent presentation and Mission bonus regressions | 191 and 224 checks, both regression guards clear | Same validation project; 421 scripts checked |
| Native two-process ENet | 75 host and 73 client checks | `abyssal-enet-cd856429188e4b67ab2b670f2128706d` |
| Production-canvas GPU render | 10 frames and 47 checks | `abyssal-gameplay-render-0a6b8d87af5948b0a4b0ffb20e544979` |

Helper output folders are under `%LOCALAPPDATA%/Temp`. Frames cover survey, carrying, delivery, a dropped relic and the revealed Mission cards in 960×720 and 1280×720 windows. Production aspect preservation yields captured game viewports of 960×540 and 1280×720 respectively. Receiver and pickup labels remain readable at the production camera zoom of 1.8. The fixtures deliberately freeze or stage some actors as described above; a separate active-combat smoke and human playtest assess encounter pressure.

The independent [live-combat smoke](relic-recovery-live-combat.md) also passed 14 checks using actual Main, base Bastion stats, normal Attack/movement/Dash and active enemies. Its deterministic depth-three Delver attempt completed in 12.68 seconds with seven kills and no health lost, then claimed the real Mission reward. This establishes one executable combat path, not balance acceptance across builds or parties.

## Human playtest

Can an ordinary build understand pickup and delivery without opening the glossary? Does deciding when to awaken a relic and choosing a return path remain engaging across repeated encounters? Is the pressure appropriate when solo, versus a party retrieving several relics at once? Does a dropped relic remain easy to find? Automation establishes the rules and lifecycle; these feel and balance questions remain open until the user's playtest.
