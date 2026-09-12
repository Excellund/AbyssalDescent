# Relic Recovery live combat smoke

This focused check complements the Recovery rules, ENet and native presentation fixtures. It runs actual `Main.tscn`, its normal world and actor frame loops, and active enemies in a disposable project with isolated user data. It establishes that a simple scripted combat route can complete an early Recovery and claim its ordinary Mission reward; it is not human balance acceptance.

## Reproduction

From the project root:

```powershell
& .github/scripts/run_gameplay_regressions.ps1 -TestScripts 'res://scripts/tests/test_relic_recovery_live_combat.gd' -FixtureTimeoutSeconds 130
```

The shared helper imports a disposable copy, compiles all scripts, checks the world and network contracts, and runs the smoke. The fixture permits at most 5,400 physics frames (90 seconds at the normal 60 Hz). The fixed encounter seed is `12092026`; successful runs take about 13 seconds of simulation. It remains an explicitly selected smoke rather than part of the default regression list.

Setup selects Delver, depth 3, The Shatterfield and base Bastion: 130 HP, 25 Damage, 188 movement speed and the ordinary Iron Retort passive. The initial Arcana is skipped, and the preceding rooms are not played. The selected Recovery profile and door then follow the real entry path. Normal movement answers the survey gate. The fixture restores the world, player and existing enemies' normal processing before combat; later reinforcements use the normal spawner.

The driver approaches the nearest enemy, aims through synthetic mouse motion, presses Attack under its normal cooldown and uses normal movement and Dash. It clears present enemies before the next pickup, fights while carrying when enemies are present, and returns cargo to the receiver. No retrieval teleports, health restoration, granted powers, combat stat changes, idle enemies or disabled combat damage are used. The final delivery may finish before the final reinforcement pair is defeated, as the ordinary objective permits.

Each aim sample is checked against the intended direction. Every live frame must retain enabled combat damage. The receipt records attacks, Dash actions, enemy hits and defeats, observed spawns, enemy movement, continuous player travel, HP, and completion. After the final deposit, the normal reward guard elapses; pointer motion selects an actual card and Attack claims its Boon and Fortified benefit. Normal next doors must open.

## Display limitation

This smoke intentionally requires the headless driver. In Godot 4.6, a native root window obtains its mouse position from the desktop cursor; injected viewport events do not replace that cursor. The headless path supports the emulated mouse through `Input.parse_input_event`. See the engine's [viewport mouse implementation](https://github.com/godotengine/godot/blob/4.6/scene/main/viewport.cpp#L1339).

An exploratory native wrapper was removed: moving Main into a SubViewport changes the scene ownership required by production combat context. The existing `render_relic_recovery.ps1` provides separate native presentation evidence with enemies held idle. Its images must not be described as screenshots of this live-combat run.

## Verification receipt

September 12 final focused run: **14 checks, zero failures**, preceded by compilation of 423 scripts and the world/network contract checks. The same seeded route had also passed the preceding 13-check version before the every-frame damage-enabled assertion was added.

- Simulation: 12.7 seconds; 130/130 HP remaining, with no accepted player damage in this correctly aimed run.
- Combat: 14 ordinary Attacks, 14 enemy hits, 7 enemy defeats, 7 Dashes and 9 observed spawns. The final two reinforcements were not required to die before the final deposit.
- Outcome: actual Mission card claimed, one permanent Boon plus Fortified, normal next doors open.
- Final isolated project: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-1e6e7e41db30437fb3a55b1eb7dc2209`.
- Session log: `.feedback/uncharted-descent-20260912/relic-live-combat-final-headless.log`.
- Structured receipt: `.feedback/uncharted-descent-20260912/relic-live-combat-receipt.json` (also `relic_recovery_live_combat.json` in the isolated project).

Earlier exploratory fixture failures are retained in ignored session logs and are not gameplay balance findings. Accurate scripted aim and a selected early room do not establish appropriate human difficulty, later-depth pressure, or co-op combat balance.
