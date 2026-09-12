# Biome, build and boss feedback follow-ups

The four September 11 playtest observations were appended in the user's order and explicitly claimed for parallel development. Each was implemented in its own `codex/feedback-20260911-*` branch and worktree under `.feedback/development-20260911/`. Their changes are integrated into the primary checkout, based on `d3a82a2`, without a commit or push. No previous queue entry was reopened or reordered.

| Feedback | Result |
|---|---|
| `FB-b1829200f6f647c3` | Live biome phases and affected-target labels, clearer practical advice, visible hover affordance and detailed contextual rule inspection. |
| `FB-0fd0a74f41a7491c` | Persistent top keyword counts and a full Build Details overview with inspectable contributing powers, levels and producer/receiver roles. |
| `FB-f54479e18abf4a7a` | Move callouts for all six bosses and four Apex variants, with readable size, HUD avoidance and host/joiner lifecycle coverage. |
| `FB-8c29f0b2b5c244cf` | Varied boss move selection, distinct Cinder Pursuit/Turning Stitch/Closing Margin follow-ups, and Breakwater's avoidable missed-charge Backwash. |

Keyword counts measure distinct contributing powers plus the character passive. Hybrid powers count for each relevant keyword; levels are visible in the contributor list. Counts are not damage-share percentages. Stable HUD frames reuse the existing ownership/level cache. Temporary mission amplification does not inflate the permanent build overview.

Boss health and base damage remain unchanged. Every new impact has a separately committed warning. Baiting Breakwater into a wall retains its long recovery and prevents Backwash. Seamlock announces False Reflections before the split and clears the name when decoys appear.

## Verification and delivery

The individual task reports contain focused gameplay, native ENet and GPU evidence:

- [Biome clarity](biome-clarity-20260911.md)
- [Build keyword overview](build-keyword-overview.md)
- [Boss callouts](boss-move-callouts-20260911.md)
- [Boss combat variety](feedback-boss-variety-20260911.md)

Combined native Main presentation passed 24 GPU frames and 235 checks with the complete new HUD at 960 and 1920 widths. Warden, Sovereign and Lacuna callouts avoid occupied HUD rectangles and disappear on local replica expiry without another snapshot. Representative combined frames were reviewed. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-72f60ae76f7d4b9bb272f760fcca5b72/boss_callout_hud_frames`.

The local coordination folder `.feedback/development-20260911/` retains per-task integration manifests, source hashes and delivery logs. The source manifest records the uncommitted build inputs; no release tag is created. All automated gameplay uses disposable projects and isolated profiles.

Human playtest should assess whether biome effects are now understandable during combat, whether the keyword overview communicates build direction, and whether the new boss positioning decisions feel sufficiently different and challenging. No player acceptance is inferred from automated checks.

Final combined source verification passed all **18 selected suites**, **374-script compilation** and both world/network contracts. Validation project: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-0304d451f04b4a28a509ffe239324f59`. No full checkpoint/commit suite was requested.

Normal desktop build **`dev-20260911-201549449-7260b30a`** was delivered to `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`. Exported-package inspection passed **27 checks**; the byte-identical executable passed **62 native checks** covering Menu, tutorial/gameplay movement, Pause, return to Menu and a second run. No debug grants, resume from the isolated test profile or shutdown warnings were present. Native evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-999665ae4bf94a2dabfdf93593848e93`.

Final SHA256: `DD6D79DB2FA8165D09113899418C3CFB8B3280F69A2E40247DE27328CBAE2C25`. All four feedback items are now **Awaiting playtest**.
