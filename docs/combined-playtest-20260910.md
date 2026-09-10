# Combined playtest — September 10, 2026

`codex/combined-playtest-20260910` combines the four requested features with `main` at `531eb02`. The audio-variety branch remains separate. Feature commits are preserved as merge parents; `main` is unchanged.

| Feature | Branch | Feature commit |
|---|---|---|
| Biome terrain and tactics | `codex/feedback-196f4f3b-biome-identity` | `fe52575` |
| Threadbinder, fifth character | `codex/feedback-72953847-fifth-character` | `735bd89` |
| Alternative bosses | `codex/feedback-7acc891d-alternative-bosses` | `4025f72` |
| Boss reward synergies | `codex/feedback-b05971e5-synergies` | `9f0dea0` |

Integration preserves the newer checkpoint, Oath, HUD and co-op fixes from `main`. Shatterfield Crossfire keeps its two cracked inner columns alongside the new biome layouts. Entry banners retain both cover instructions and biome hints. Room-entry networking covers the escort, terrain and boss scenarios together.

The boss checkpoint now tolerates configuration-only setup without a RunSession. Synergy glossary rules use authored line breaks. Integration fixtures account for five characters and distinguish geometry from optional brittle-cover metadata; the HUD movement fixture stages a clear arena. Oath progression contains 37 goals, including 20 character/Bearing clears. Named boss Oaths retain their existing targets, including the original trio required by Untouched Crowns.

`test_combined_feature_synergies.gd` exercises native Cross Stitch Marks feeding Sigil/Crescent damage into Sovereign Tempo, repeated-damage limits, fresh actions, and switching Attack/Burst/Crown descendants sharing reward allowances. It is registered in the full isolated gameplay suite. Brittle-cover checks now exercise every playable character.

Checkpoint verification uses the full pre-commit hook and the isolated room-entry, Threadbinder, alternative-boss, boss-reward-synergy and shared-build ENet helpers. GPU checks cover 19 biome frames and 14 Oath frames, including the five-character roster and expanded Threadbinder progression. Normal export and native executable smoke use the existing package-verification and isolated-profile helpers.

The playtest is delivered to `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe` with a unique internal `dev-*` identifier, normal Menu startup and normal progression. Threadbinder retains its Riftlancer-clear unlock. Feature acceptance and balance remain subject to human playtesting; feedback queue order and acceptance status are unchanged.
