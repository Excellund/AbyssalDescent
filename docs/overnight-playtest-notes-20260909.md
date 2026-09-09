# Overnight playtest notes — September 9

Development is on `codex/overnight-buildcraft-20260909`. The existing desktop **AbyssalDescent Playtest.exe** is replaced at verified checkpoints with a normal build: regular menu, progression and rewards. `main` and the original desktop executable are preserved. The exact current build and verification evidence are in [the development log](overnight-development-20260909.md).

## New things to try

- **Returning Crescent:** attacks send a blade outward and back. Reposition to change its return path. Level 2 supports two blades; level 3 adds an outward ricochet from cover or the arena edge. Returning blades dissolve against cover.
- **Apex Breakwater:** an optional single-enemy fight. Bait its clearly locked charge into an edge or cover to earn a longer opening, then decide whether to attack or reposition.
- **Ruinous Impact:** launches, compression and bursts now have distinct feedback at their actual positions and damage radius. It also works against the real arena perimeter.
- **Warden and Lacuna:** their charge warnings now show the full committed path. Watch the warning and compare the charge with it, including while using recoil or Orbit nearby.
- **Hazard clarity, next checkpoint:** Tether shows its full beam width and breaks when either enemy is launched. Seamlock bands expire correctly. Damage flashes move toward the screen edges to keep the next warning visible.

## Reliability and clarity

Held attack input survives the dash-to-Orbit handoff and charges Blast only after the attack succeeds. Reward descriptions use actual build values. Resume preserves Surge Step and Voidfire movement bonuses. Co-op departure, reward readiness and retry have coverage with four real local network processes; co-op defeat preserves an unrelated suspended solo run.

Sovereign's Double keeps its current damage and proc rules. Development runs remain local and do not enter remote telemetry or leaderboards. There are no new combat prompts or Oath checklists.

## Useful feedback

The main questions are whether Crescent changes where you move, whether Breakwater's charge and recovery feel fair, and whether the combat remains readable when movement powers and enemy warnings overlap. Normal play is the most useful test; there is no need to work through a checklist.

Automated fixtures cover behavior, saves, rendered geometry and local networking. They cannot judge enjoyment or real internet conditions. The [systems review](systems-and-visual-review.md) records the ongoing implementation and visual work.
