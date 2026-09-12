# Boss variety feedback — September 11, 2026

Feedback: FB-8c29f0b2b5c244cf. Development owner: 01a09209-8771-78f3-9df0-b49907c3df66/boss-variety. Branch: codex/feedback-20260911-boss-variety. This is an implementation/verification record, not user acceptance or a commit/build checkpoint.

Kilnheart and Glassweaver select root attacks from host-owned weighted bags: every move appears once per bag, consecutive roots never repeat, and current spacing affects the odds. Kilnheart favors Slam at range and Halo nearby; Glassweaver favors Loom at range and Cage nearby. The Archivist retains the complete Record/Revision alternation.

The previously single-step moves now ask for different second decisions:

- **Cinder Pursuit:** after Cinderfall, a new 1.65-second warning leads the aimed player's current velocity by 1.2 seconds, capped at speed 210 and clamped inside the arena. The fixed 108-radius disk catches continued ordinary walking along its captured direction; stopping or changing course can avoid it.
- **Turning Stitch:** a new 1.10-second cross warning rotates 45 degrees through Cross Stitch's earlier diagonal escapes. The remembered center stays fixed.
- **Closing Margin:** after Final Margin, four 108-radius disks close its inner quadrants. The old crossing lanes and outer floor become safe during the new 1.65-second warning.
- **Backwash:** Breakwater's missed charge keeps its 0.55-second recovery, then warns a fixed ring of radii 135–245 for 1.8 seconds. Enter the inner pocket or leave the outer edge. It resolves once, then gives another 0.55-second recovery before the normal cooldown. Baiting a wall prevents Backwash and preserves the complete 1.8-second wall punish window.

Base health, damage, charge speed, charge reach, original warning lengths and final alternative-boss recovery values are unchanged. Each new impact has its own full warning and one-hit boundary. Death/cancellation/authority changes retire pending warnings. Breakwater's already locked charge still follows its committed lane after target death. Its new ring center uses packed geometry to bypass generic runtime coordinate rounding.

The owned enemy scripts expose get_attack_callout() and call the shared presentation helper from the parallel move-callout task. That task owns scripts/shared/enemy_attack_callout.gd; do not overwrite its final helper with the temporary copy in this worktree. The glossary change is confined to Breakwater's description and should be merged with other glossary edits.

## Verification

All automation used disposable projects, suppressed profile/telemetry startup and isolated user data with Godot 4.6.2. No desktop export was performed here.

- Final scoped regressions: all 366 scripts compile; alternative combat **4,517 checks**, Breakwater runtime **313**, Breakwater combinations **29**, Breakwater encounter **2,397**, alternative selection/Continue **254**, glossary readability **189**. Zero failures. Evidence: C:/Users/mikel/AppData/Local/Temp/abyssal-validation-b5feac471ef343f08e5e77131df6d678.
- Alternative native ENet: **391 host / 103 joiner checks**, zero failures, covering all seven queued sequences, exact shapes and move identities, independent warning serials, stale packets, one-hit resolution, cancellation and shared-damage authorization. Evidence: C:/Users/mikel/AppData/Local/Temp/abyssal-enet-fbdc834091bd41149623a31f75d452df.
- Breakwater native ENet: **43 host / 8 joiner checks**, zero failures. Includes actual missed-charge Backwash, replicated geometry/name, generic quantization, host-only ring damage, safe inner pocket, stale warning retirement, and existing co-op power damage. The older fixture was updated to establish the current real run/provenance handshake and send an authored primary Attack context; it previously used a legacy context that could not authorize a descendant Ruinous Burst. Evidence: C:/Users/mikel/AppData/Local/Temp/abyssal-enet-8bad5737f8b7448db25e79ac92dfc3a4.
- RTX 4080 GPU: **23 alternative frames / 10 Breakwater frames**, zero failures. Manually reviewed Cinder Pursuit, Turning Stitch, Closing Margin and host/joiner Backwash. Fixed boundaries, empty pockets and readable move labels are visible. Alternative frames: C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-dcd5694284a64dd994d80556c0593b88/alternative_boss_frames. Breakwater frames: C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-13be36ecd66f4760bb97aefecb3b588f/breakwater_frames. The later Turning Stitch duration extension and Cinder lead adjustment do not change the stationary-target geometry in these captures; the final values passed the final runtime and native ENet runs above.

Expanded tests include no-repeat/no-starvation selection, a real CharacterBody2D velocity capture, committed geometry after reversal, actual damage across the new sequences, finite wall/body escape sampling with Slow plus Attack lock/acceleration allowances, Backwash inner/outer danger boundaries, lost packets and authority cancellation. Sampling cannot prove every possible gameplay position. Human playtesting remains necessary to judge encounter enjoyment, pressure and whether the new positioning decisions feel sufficiently distinct.

For focused retesting, use the existing scoped regression runner with test_alternative_bosses.gd, test_breakwater_runtime.gd, test_breakwater_combinations.gd, test_breakwater_encounter.gd, test_alternative_boss_selection.gd and test_glossary_readability.gd. Use test_boss_combinations_enet.ps1 with each corresponding ENet fixture and a 60-second fixture timeout. render_alternative_bosses.ps1 expects 23 frames; render_gameplay_fixture.ps1 with render_breakwater.gd and breakwater_frames expects 10.
