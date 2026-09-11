# Static Wake damage reduction — September 11, 2026

The player requested less Static Wake damage after the combined playtest. The contact damage rate is reduced from 6.0 to 4.5 times the mapped Wake amount per second: a 25% reduction at every level, including Prismatic, before final whole-health rounding.

The same rate scales the unconditioned damage and its Damage coefficient. Conditional Damage bonuses and copied effects therefore use the reduced contribution. Integer mapping, fractional carry, the 0.25-second damage interval, two-trail overlap limit, lifetime, width, level-3 Slow and existing Electric/Field interaction rules are unchanged.

| Level | Previous Damage coefficient per second | Revised coefficient per second |
|---|---:|---:|
| 1 | 270% | 202.5% |
| 2 | 360% | 270% |
| 3 | 450% | 337.5% |
| Prismatic | 630% | 472.5% |

Reward previews and Build Details read the shared controller rate, with the existing whole-percent display rounding. Actual health loss also reflects the existing integer Wake mapping, enemy defenses and conditional bonuses.

For playtesting, compare sustained damage against a boss and a group of foes crossing the trail. The trail should retain its value for Electric/Field combinations and Slow while contributing less direct damage.

Feedback: `FB-d206128dc88648af`. All nine focused suites passed (24,881 checks), along with 365-script compilation and both contracts. This covers actual contact damage, all levels and Prismatic, fractional carry, overlap, Slow, reward text/layout and shared synergies. The existing display rounding shows Prismatic as 472%; its analytic coefficient is 472.5% per second.

The normal build `dev-20260911-150813181-4ec0f6c4` was delivered to `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe` at 17:13 local after the previous game closed. It passed 27 package checks plus 62 headless checks of the actual executable's menu, first descent, movement, return and reopening. All 560 production inputs match the export snapshot, and the delivered executable matches the verified hash. The feedback item is `awaiting_playtest`.

- Delivered executable SHA256: `58DDEA0164FC7554012AC10BFE7E4FECF74EC94E946B582D3E042597A4CE6251`.
- Static Wake verification: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-62162f0626a64bf0bbe9c4ec29f52ba8` (570 checks; the initially mismatched Prismatic text expectations were subsequently corrected and verified below).
- Remaining eight suites: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-54b6e8dccca74c97bff8a3c320378311` (24,311 checks).
- Actual executable evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-3e5eaab609eb48dfb4658b0e4281c714`.
- Source, targeted-validation, build and executable-verification receipts: `.feedback/static-wake-20260911/`.
