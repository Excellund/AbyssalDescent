# Oaths from first goals to postgame prestige

September 10, 2026. This revision supersedes the universal Forsworn requirement in the [previous postgame revision](postgame-oaths.md). The user wants worthwhile goals for players at every skill level, a visible sense of progression, and prestigious postgame challenges. Pilgrim should offer achievable Oaths; it should not award the challenges reserved for harder Bearings.

## Progression ladder

September 12 menu correction: Vessel Progression follows the actual unsealing chain: Bastion, Hexweaver, Veilstrider, Riftlancer, then Effigy Keeper. Each vessel keeps its Pilgrim, Delver, Harbinger and Forsworn goals in that order. The list reads the shared unlock chain; completion IDs and saved progress are unchanged.

With Threadbinder integrated, the active roster contains 37 Oaths: four Journey goals available on any Bearing, five Challenges requiring Delver or higher, eight Prestige goals requiring Forsworn, and twenty character/Bearing clears. Harder Bearings also qualify for the lower minimum requirements. Character-clear Oaths continue to name an exact Bearing, preserving their original meaning and completion IDs.

| Tier | Oath | Goal | Reward |
|---|---|---|---|
| Journey · Any Bearing | Untouched by the Warden | Defeat the Warden without taking damage during the fight. | Prismatic Arcana |
| Journey · Any Bearing | Unbroken Line | Hold the Line at full zone control for the whole encounter. | Iron Vigil |
| Journey · Any Bearing | Singular Focus | Clear with one Arcana; upgrades are allowed. | Prismatic Arcana |
| Journey · Any Bearing | Unbroken March | Clear without visiting Rest Sites. | Pilgrim's Tonic |
| Challenge · Delver+ | Untouched by the Sovereign | Defeat the Sovereign without taking damage during the fight. | Reward Reroll |
| Challenge · Delver+ | Untouched by Lacuna | Defeat Lacuna without taking damage during the fight. | Lacuna's Veil |
| Challenge · Delver+ | Grounded | Clear without using Dash. | Iron Vigil |
| Challenge · Delver+ | Closed Fist | Clear without using Attack. | Reward Reroll |
| Challenge · Delver+ | Against the Clock | Clear in under eight minutes. | Iron Vigil |
| Prestige · Forsworn | Unassisted | Clear at Ascension rank 1 or higher with no Catalysts equipped. | Draft Compass |
| Prestige · Forsworn | Untouched Crowns | Clear after defeating the Warden, Sovereign and Lacuna without taking damage during those fights. Damage elsewhere is allowed. | Calm Before Surge |
| Prestige · Forsworn | Unscathed | Clear without taking any damage. | Prismatic Arcana |
| Prestige · Forsworn | Glass Pilgrimage | Clear with Glass Descent and Pilgrim's Burden, without Rest Sites. | Lacuna's Veil |
| Prestige · Forsworn | First Ascension | Clear at Ascension rank 1+. | Mutator Storm and Specialist Pressure unlocks |
| Prestige · Forsworn | Third Ascension | Clear at Ascension rank 3+. | Calm Before Surge; Crowned Bosses and Glass Descent unlocks |
| Prestige · Forsworn | Fifth Ascension | Clear at Ascension rank 5+. | Empty Vault, Razor Sigils and Pilgrim's Burden unlocks |
| Prestige · Forsworn | Pact of the Abyss | Clear at Ascension rank 10. | Cinder Aegis |
| Vessel Progression | Four Bearings for each of five characters | Clear Pilgrim, Delver, Harbinger and Forsworn with each character. | Completion records |

Journey includes encounter goals that can be earned before a complete clear and restrictions that encourage experimentation even on Pilgrim. Delver introduces more demanding execution and movement/build constraints. Forsworn keeps the sustained mastery and Ascension chase. Unassisted now requires a positive Ascension rank: the solo setup that offers Catalysts only opens after a character's first Forsworn clear, so an ordinary first clear is not a meaningful no-Catalyst challenge. Ordinary kill-count and reward-upgrade milestones remain retired; approachability comes from meaningful goals at a suitable difficulty.

Boss no-hit and full-control Hold achievements remain earned if the run later ends in defeat. Goals that say **clear** require victory. Grounded counts accepted normal Dash starts; Recoil and Orbit remain distinct movement actions. The compact Oaths menu groups the ladder, states each card's Bearing requirement and keeps future goals readable. The user-requested removal of the entire Selected Bearing banner gives the list more room; per-card requirements and completion marks remain.

## Evidence and compatibility

Each definition declares its own minimum Bearing. The evaluator checks the actual run Bearing and, for restricted goals, the lowest verified Bearing encountered during the run. Difficulty changes, resume and co-op outcome merging cannot promote easier or unknown history into a harder completion. Any-Bearing goals still require their actual encounter, action, equipment or build evidence, but do not need to prove a difficulty restriction they do not have. Debug runs award no Oaths.

Special Oath IDs are retained even where their historical `forsworn_` prefix no longer describes the requirement, except strengthened Unassisted, which uses the fresh `unassisted_ascension` ID. Earlier `forsworn_unassisted` completions, claimed rewards and earned Catalysts remain in history without granting the Ascension challenge. Data fields determine eligibility; IDs are stable save keys. Original lower-Bearing character-clear IDs are restored, so their previous completion marks reappear. The four restored Any-Bearing goals identical to older Warden, Unbroken Line, Singular Focus and Unbroken March achievements also recognize those older completion IDs. This recognition is read-only and applies only to equivalent goals; an easier old completion does not satisfy an elevated Delver or Forsworn challenge. Existing Catalyst unlocks, equipment and history remain intact.

Older saves without a recorded minimum Bearing cannot certify a new restricted challenge. The previous build's explicit verified Forsworn evidence remains sufficient for a minimum of Forsworn. Valid old encounter and action evidence can still earn Any-Bearing goals. This preserves useful progress while preventing menu changes from upgrading an old run's difficulty history.

## Verification and delivery

The following records describe the initial progression build. The final Unassisted/banner polish and its delivery evidence are recorded below them.

All nine focused fixtures passed in one isolated run without retries: Oath tracking (893 checks), movement and difficulty evidence (199), Catalyst profile (89), Catalyst rewards (917), checkpoint lifecycle (175), menu fit (183), power snapshots (895), Ascension runtime and kill provenance. Compilation of all 326 GDScript files and both world/network contract guards passed. Every candidate GDScript file matched the isolated validation input. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-107c59434c754e54a0a1cbf57e766813`.

GPU validation passed 1,329 checks across 28 inspected captures at physical 1280×720 and 1920×1080, preserving the production 2560×1440 canvas. It covers all progression groups, Pilgrim/Delver/Forsworn eligibility (9/14/21 matching Oaths), Harbinger eligibility (14), readable future goals, restored completion marks and exact-Bearing character clears. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-6af19946a6214e0f9d3a7aeda1481c19/oaths_feedback_frames`.

This bounded follow-up uses the focused checks above; the preceding full 81-fixture run remains recorded in the earlier revision. The full checkpoint hook is unchanged. Human playtesting determines whether the three tiers offer a satisfying pace of progression.

Normal desktop delivery:

- Source: `codex/encounter-evolution-20260910` at `b6b181937db95c8424ec8410682ad1ffb55bf048`, plus the uncommitted working-tree changes. No commit, push or tag was requested.
- Executable: `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`.
- Internal build ID: `dev-20260910-175609942-a548d2d4`.
- SHA256: `6EDABFA5E0CBAC6465618C37DB574FE057A6A9FAAC37A526EC4F425DDAA4C9EA`.
- Normal export and package verification passed, including production autoloads, matching build ID and exclusion of tests, fixtures and feedback data/tooling. Exported scripts match the candidate except the intended BuildInfo version stamp. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-playtest-export-ea3cb971e1d44aa2894f99a5464e3992`.
- The byte-identical temporary executable passed 27 package checks and 62 native checks for normal Menu, first descent, movement, returning to Menu and starting again. Verification used isolated user data and disabled remote services. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-7034237f30e94c8e8d5dac7b73ac6f64`.

Final whitespace and desktop-file hash checks passed. The feedback board records this revision as awaiting playtest; queue priorities are unchanged.

## Final Unassisted and menu polish

The user accepted the progression direction and requested two corrections. Unassisted now requires a victorious Ascension rank 1+ run with no Catalysts equipped. This places the restriction after Catalyst setup becomes available, rather than awarding it during a first Forsworn clear. The new `unassisted_ascension` completion ID does not inherit an easier Unassisted completion; existing history, claimed rewards and Catalyst unlocks remain intact. The entire Selected Bearing box is removed and its space goes to the scrolling Oath list. Individual card requirements and completion states remain visible.

Four focused fixtures passed: Oath tracking (921 checks), Catalyst profile (89), menu fit (183), and Ascension runtime. All 326 GDScript files compiled and the world/network contract guards passed. Production GDScript matched the isolated validation input. Coverage includes positive Ascension ranks, rejection of base Forsworn and malformed rank/proof values, and preservation of previous Unassisted history without granting the new mark. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-f41611bfd89743c4ac0f39d3f4f06b0b`.

The focused GPU fixture passed 1,354 checks with zero failures across ten inspected captures at 1280×720 and 1920×1080. It verifies the reclaimed list space, all four progression groups, per-card eligibility, the new Unassisted requirement, and its unearned state with an old Unassisted completion. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-1ba2f759cd1243b58f1267ad65268509/oaths_feedback_frames`.

Updated normal desktop delivery:

- Source remains `codex/encounter-evolution-20260910` at `b6b181937db95c8424ec8410682ad1ffb55bf048`, plus uncommitted working-tree changes. No commit, push or tag was requested.
- Executable: `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`.
- Internal build ID: `dev-20260910-180809861-17644df3`.
- SHA256: `44BC0C3D03E910EBC9D7C013FA6FD6AE1B2D4B4AD68E7481BE36422F97AC5C6D`.
- Normal export and package verification passed, including exclusion of tests, fixtures and feedback data/tooling. Exported production scripts match the candidate except the intended BuildInfo stamp. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-playtest-export-e7af5745253949a58315e9e24f5feb11`.
- A byte-identical temporary executable passed 27 package checks and 62 native checks covering the normal menu, first descent, movement, return and reopening. Verification used isolated user data. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-4f1c9accd934482ca8604af9f8f2800f`.

The bounded correction uses these focused checks; the earlier full checkpoint run remains historical evidence. Both Oath feedback entries await playtesting of this build. Other explicitly parallel feedback claims remain independent.
