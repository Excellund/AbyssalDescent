---
name: power-description-sync
description: "Keep power descriptions synchronized across reward cards, build detail panel, and fallback text with strict visible-character caps."
argument-hint: "Power id(s), target cap, and surfaces to update"
---

# Power Description Sync

Use this skill whenever power description text changes or when UI wrapping/regression risk appears.

## Required Surfaces

- Reward card descriptions:
  - scripts/upgrade_system.gd `get_trial_power_card_description`
- Build detail descriptions:
  - scripts/build_detail_panel.gd `_get_power_current_desc`
- Fallback descriptions:
  - scripts/power_registry.gd `_get_trial_fallback_description`

## Hard Rules

1. Keep description semantics synchronized across all required surfaces.
2. Enforce visible-text caps, not raw BBCode length.
3. Visible character cap for this project workflow: 109.
4. Overflow must hard-fail in debug builds via assertion.
5. Keep implementation caveats implicit in player-facing text (for example, avoid explicit "does not chain" wording unless requested).
6. Keep a concise numeric stat line when the power has core quantitative levers (damage/length/lock/slow/etc).
7. Do not abbreviate stat labels in player-facing descriptions; prefer full words like "Damage", "Detonate", "Length", and "Lockout".

## Enforcement Pattern

- Use scripts/shared/description_cap_guard.gd.
- Call `assert_visible_cap(text, power_id, surface)` before returning description strings.
- Assertions should include power id and surface for fast diagnosis.

## Procedure

1. Update reward-card, build-detail, and fallback descriptions in the same change.
2. Keep wording precise and mechanics-first; avoid patch-note phrasing.
3. Keep lines compact enough to pass visible-length cap.
4. Validate changed files with diagnostics.
5. Do a quick UI sanity pass for wrapping risk on the touched powers.

## Done Criteria

- Updated powers are synchronized across all required surfaces.
- All updated descriptions pass visible-char cap checks.
- Debug assertions fail if future edits exceed cap.
- Diagnostics report no errors for touched scripts.
