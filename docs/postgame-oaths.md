# Postgame Oaths

**Superseded by [Oaths from first goals to postgame prestige](oath-progression.md).** The user clarified that approachable goals must remain available at every Bearing alongside harder and prestigious challenges. This file preserves the earlier universal-Forsworn design and its build evidence.

September 10, 2026. The user requested Oaths worth chasing after ordinary progression: deliberate restrictions that change a build or playstyle, and exceptional execution. Routine kill counts, Rest visits, boss progression and normal Arcana upgrades did not meet that purpose.

## Rules

- Every active Oath requires **Forsworn**, the highest Bearing. Pilgrim, Delver and Harbinger cannot award Oaths. Ordinary character/Bearing progression remains available at those difficulties.
- The menu states the common Forsworn requirement above the list and shows whether the selected Bearing qualifies. Individual cards explain the challenge without repeating category exceptions.
- The run must carry verified difficulty evidence. Changing a menu selection cannot upgrade an existing saved run's eligibility. Missing or contradictory saved evidence cannot award a new challenge.
- New constraints use evidence from actual play: accepted normal Dash starts, deliberate Attack uses, visited Rest Sites and frozen run loadouts. Failed Dash inputs do not count as Dashing; Recoil and Orbit are distinct actions under the combat wording guide.
- Existing completions, claimed rewards, equipped Catalysts and historical labels are preserved. Strengthened challenges use fresh IDs, so an old Pilgrim completion does not appear as a completed Forsworn challenge. Already-Forsworn Ascension milestones and Forsworn character clears retain their IDs.
- Unknown evidence in older saves keeps those saves playable but cannot certify the new restrictions. Human playtesting, especially challenge balance, remains separate from automated correctness.

## Active roster

All 21 Oaths below require Forsworn. Boss and Hold achievements can be earned even if the run later ends in defeat; every goal that says **clear** requires victory.

| Oath | Challenge | What it asks of the player | Reward |
|---|---|---|---|
| Untouched by the Warden | Defeat the Warden without taking damage. | Master a complete boss encounter. | Prismatic Arcana |
| Untouched by the Sovereign | Defeat the Sovereign without taking damage. | Master a complete boss encounter. | Reward Reroll |
| Untouched by Lacuna | Defeat Lacuna without taking damage. | Master the final boss encounter. | Lacuna's Veil |
| Untouched Crowns | Clear with no damage taken in any of the three boss fights. | Sustain boss execution across a full descent. | Calm Before Surge |
| Singular Focus | Clear with one Arcana, which may be upgraded. | Build around one chosen engine. | Prismatic Arcana |
| Unbroken Line | Hold the Line at full zone control for the whole encounter. | Maintain positioning under pressure. | Iron Vigil |
| Against the Clock | Clear in under eight minutes. | Fast decisions, aggressive routing and efficient damage. | Iron Vigil |
| Unbroken March | Clear without visiting Rest Sites. | Trade recovery opportunities for combat routes. | Pilgrim's Tonic |
| Unscathed | Clear without taking any damage. | Exceptional consistency across every encounter. | Prismatic Arcana |
| Closed Fist | Clear without using Attack. | Win through a passive, Dash and automatic-damage build. | Reward Reroll |
| **Unassisted** | Clear with no Catalysts equipped. | Give up both pre-run augment slots. | Draft Compass |
| **Grounded** | Clear without using Dash. | Commit to walking, positioning or earned alternative movement. | Iron Vigil |
| **Glass Pilgrimage** | Clear with Glass Descent and Pilgrim's Burden, without Rest Sites. | Survive increased incoming damage and reduced starting health without route healing. | Lacuna's Veil |
| First Ascension | Clear at Ascension rank 1+. | Start adding difficulty modifiers. | Mutator Storm and Specialist Pressure unlocks |
| Third Ascension | Clear at Ascension rank 3+. | Combine additional pressures. | Calm Before Surge; Crowned Bosses and Glass Descent unlocks |
| Fifth Ascension | Clear at Ascension rank 5+. | Sustain a more demanding modifier loadout. | Empty Vault, Razor Sigils and Pilgrim's Burden unlocks |
| Pact of the Abyss | Clear at Ascension rank 10. | Complete the maximum-rank challenge. | Cinder Aegis |
| Four Vessel Mastery Oaths | Clear Forsworn with each of the four characters. | Demonstrate mastery of every character's identity. | Completion record |

Glass Descent and Pilgrim's Burden contribute five Ascension rank together. Their unlocks are reachable before attempting Glass Pilgrimage: the initially available modifiers provide eight rank, so neither that Oath nor its reward blocks its own prerequisites. Glass Pilgrimage rewards Lacuna's Veil rather than the Tonic already awarded by its contained no-Rest challenge.

Retired from the active board: Hundredfold, Pilgrim's Road, Crown Breaker, Many Paths, Honed Art, lower-Bearing character clear Oaths and earlier difficulty-unrestricted versions of the strengthened challenges. Their historical records remain intact.

## Implementation and validation

The registry owns the roster and common Bearing requirement. The evaluator enforces it before dispatching any challenge. Tracker checkpoints retain difficulty, Dash and Catalyst evidence; joiners use their own action and equipment evidence. Existing Ascension loadout verification remains required for Glass Pilgrimage.

Validation covers all lower Bearings, missing/contradictory save evidence, accepted versus refused Dash attempts, movement distinctions, one-use disqualification, difficulty changes, Catalyst changes across resume, modifier requirements, personal co-op attribution, retired completion compatibility and reward reachability. Rendering preserves the production 2560×1440 logical canvas while varying the physical window size.

Focused verification passed compilation of 326 scripts and both world/network contract guards. Eight fixtures passed: Oath tracking (302 checks), Catalyst profile (89), Catalyst rewards (917), checkpoint lifecycle (175), menu fit (183), power snapshots (895), Ascension runtime and kill provenance. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-d25f1f3dcdc645b69a60996aad4e4383`.

The new movement fixture passed 57 checks with the same compilation and guards. It invokes actual successful/refused normal Dash starts, stored Dashes, Recoil and Orbit, then exercises checkpoint and joiner summary evidence. Its synthetic input initially ran at the wrong Godot frame boundary; that test harness was corrected to produce input edges on an idle frame. Production code was unchanged. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-9e6db540d3ce4355bbb887983fc30ca9`.

GPU verification passed 659 checks across 20 inspected frames at 1280×720 and 1920×1080. It covers the pinned requirement, Pilgrim/Forsworn eligibility, challenge text and wrapping, boss ordering, Vessel Mastery, legacy completion separation and a newly completed Grounded card. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-caae48438efd48518d9dce14e51181be/oaths_feedback_frames`.

The full isolated regression suite passed all 81 gameplay fixtures, compilation of 326 scripts and both contract guards. The corrected movement fixture was copied into the disposable suite before its first execution; all 326 GDScript files were compared with the final candidate and matched. The new fixture is included in the standard regression runner for future checkpoints. `git diff --check` passed. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-f3a023f8f0504b9982ab98e8f52a4ea4`.

## Normal desktop delivery

Source: `codex/encounter-evolution-20260910` at `b6b181937db95c8424ec8410682ad1ffb55bf048`, plus the uncommitted working-tree changes. This delivery preserves the preceding Build Details and reward/input fixes. No commit, push or release tag was requested.

- Executable: `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`.
- Internal build ID: `dev-20260910-172527647-75514ed9`.
- SHA256: `BC8332EF1E48C6FF82E6849391E7CCB4AB5905C615BF4CA4C1DDD080B910741F`.
- Normal export and package verification passed; production autoloads and build ID match, and tests, fixtures and feedback data/tooling are excluded. All staged GDScript sources match the candidate except the intended BuildInfo version stamp. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-playtest-export-d5decc833f2741119ade51d9839df12f`.
- The actual exported executable passed 27 package checks and 62 native checks for Menu, a first normal descent, movement, returning to Menu and starting again. The byte-identical temporary copy used an isolated profile with remote services disabled; its hash matches the desktop file. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-16aacf57008a4b3082b4be7cb94c16b2`.

Start a fresh Forsworn descent to attempt these challenges. Existing unlocks remain available, and older saved runs remain playable, but saves without the new difficulty evidence cannot award the postgame Oaths. Automation verifies eligibility and runtime behavior; human playtesting still decides whether the challenge balance is satisfying.
