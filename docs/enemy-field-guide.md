# Enemy Field Guide

The Glossary now includes an always-available **Enemy Field Guide** from both the main menu and Pause. Four short groups cover all 14 ordinary and support spawn types. Each entry gives the enemy's threat and a practical response. The four Apex types remain under Encounters. No unlocks, progression records, combat mechanics, rewards or feedback-board priorities change.

`scripts/shared/glossary_data.gd` owns both the rows and their BBCode presentation. Existing navigation and scrolling display the same content in both places. The guide describes ordinary enemy patterns and points to Mutators for altered pressure. It avoids brittle health/damage statistics and does not label hostile abilities with player power properties.

Native verification exposed an existing readability problem: both glossary panels inherited the game's 2560×1440 canvas shrink, taking 18-point body text down to about 9 screen pixels at 1280×720. Their layout now cancels that stretch for the glossary and fits the available physical screen with a 24-pixel outer margin. Body text remains at least 18 screen pixels; narrower pages wrap and scroll. Both sidebars scroll with keyboard focus on short screens. A local font theme from `scripts/ui/scaled_ui_font.gd` keeps compensated text sharp. Pause refreshes the layout on resize and when opening its glossary. Other Menu and Pause panels retain their own layout behavior.

The local theme preserves all RichTextLabel faces. Normal faces use MSDF; artificially boldened variants use oversampled raster bases, avoiding the self-intersecting outline artifacts described in [Godot's FontVariation documentation](https://docs.godotengine.org/en/stable/classes/class_fontvariation.html#class-fontvariation-property-variation-embolden). Native keyword captures confirm distinct bold weight and the canonical keyword colors in both panels.

## Behavior sources

Every claim was checked against the executable behavior, rather than design comments. In particular, the Weaver's old comment says six projectiles while its current default is eight; the guide deliberately describes the radial pattern without copying that stale count.

| Entry | Implementation checked | Guide's actionable distinction |
|---|---|---|
| Chaser | `enemy_chaser.gd`: `_get_desired_velocity`, `_try_attack_target` | Repeated close contact, keep an exit open. |
| Charger | `enemy_charger.gd`: `_enter_windup_state`, `_process_charge_state`, `_enter_recover_state` | Direction locks at warning start; step across the lane. |
| Lurker | `enemy_lurker.gd`: `_process_lurk`, `_enter_strike_state`, `_process_strike` | The pause continues aiming; the pounce then commits. |
| Ram | `enemy_ram.gd`: `charge_count`, `_process_charge`, `_process_charge_pause` | Three short charges with new aim between them. |
| Spectre | `enemy_spectre.gd`: `_update_blink_target`, `_process_commit`, `_execute_blink`, `_is_point_in_strike_lance` | Movement prediction locks before the blink; a warned forward strike follows. |
| Archer | `enemy_archer.gd`: `_enter_windup_state`, `_process_fire_state`, `_process_projectiles` | Three arrows share the locked direction; real cover blocks them. |
| Lancer | `enemy_lancer.gd`: `_get_facing_lead_point`, `_land_bolt`, `_process_zones` | Aims ahead of facing, not velocity; landing leaves a damaging zone. |
| Drifter | `enemy_drifter.gd`: `_emit_ring`, `_get_ring_node_world_position` | Each expanding pellet ring omits a node; gaps can change between waves. |
| Pyre | `enemy_pyre.gd`: `_on_health_state_died`, `_spawn_death_field`; `pyre_field.gd` | Melee pursuer whose death leaves independent expanding fire. |
| Weaver | `enemy_weaver.gd`: `_launch_burst`, `_process_projectiles`; `web_zone.gd` | Outward webs produce damaging landing zones; no invented Slow effect. |
| Tether | `enemy_tether.gd`: `_enter_windup_state`, `_process_beam`, `_committed_partner_valid` | A warned beam sweeps between a live pair; losing an end clears it. |
| Sentinel | `enemy_sentinel.gd`: `_process_behavior`, `_try_cone_damage` | The rotating cone deals damage while the body slowly advances. |
| Shielder | `enemy_shielder.gd`: `_update_shield_facing`, `take_damage`, slam state handlers | Directional protection and a warned circular slam; flank and leave the ring. |
| Keeper | `enemy_keeper.gd`: `_update_wards`, `_valid_ward_ally`, `_ward_line_visible`; `enemy_base.gd`: `_apply_keeper_ward_health_floor` | Two eligible allies can resist damage and survive lethally damaging blows at 1 HP. Killing the Keeper or blocking links exposes them. |

## Verification

- `test_enemy_field_guide.gd` checks roster completeness against the actual spawner, preservation of Apex entries, native Menu/Pause selection, complete body contents, keyboard scrolling, Back-button bounds and physical font size at 960×540, 960×720, 1280×720 and 1920×1080.
- Existing `test_glossary_readability.gd` exercises every glossary section, including the new page, at those widths.
- `render_enemy_field_guide.gd` captures all four guide groups plus lower entries through both actual glossary panels, captures every enemy separately on the shortest screen, and checks canonical keyword typography in both panels, producing 74 GPU frames. Both use the production 2560×1440 canvas stretch; frames retain native output dimensions. The 960×540 case also covers the usable canvas of a letterboxed 960×720 window.
- Run automation only through the disposable validation and render helpers. No tests use the player's profile.

Commands:

```powershell
& .github/scripts/run_gameplay_regressions.ps1 -TestScripts @('res://scripts/tests/test_enemy_field_guide.gd', 'res://scripts/tests/test_glossary_readability.gd', 'res://scripts/tests/test_combat_pause.gd', 'res://scripts/tests/test_shared_power_wording.gd')
& .github/scripts/render_gameplay_fixture.ps1 -ValidationProject '<disposable validation project>' -FixtureScript res://scripts/tests/render_enemy_field_guide.gd -FrameFolder enemy_guide_frames -ExpectedFrames 74 -MaxFrames 2400
```

The final isolated run compiled 421 scripts and passed the field guide (260 checks), all glossary pages (231), combat pause (36) and shared power wording (1,779). The final RTX 4080 render passed 344 checks across 74 frames with no failures. Native frames were inspected for text sharpness, preserved keyword weight/color, scrolling and complete enemy explanations at the short-screen size. Evidence is retained in `.feedback/uncharted-descent-20260912/enemy-field-guide/`.
