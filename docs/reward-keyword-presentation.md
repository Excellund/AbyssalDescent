# Reward keyword distinction

Feedback `FB-36d6bb321b184a1a`: distinguish keywords without turning the reward screen into a rainbow.

The earlier style gave almost every effect the same cyan accent, including Electric, Field, Burst, movement effects and Echo. Slow and Mark also shared one color. The revised catalogue uses a warm neutral and five muted accents, chosen around commonly adjacent terms:

| Terms | Accent |
|---|---|
| Attack, attack hit, Kill, Projectile, Echo | Bone `DFDACE` |
| Dash, Recoil, Orbit, Slow, Push, Pull, Launch | Blue `AFC8D8` |
| Mark | Mauve `D3B6D1` |
| Electric | Gold `E0CB8D` |
| Field | Sage `ACCBB5` |
| Burst, Impact | Peach `DFB6A2` |

All keep the same-size bold treatment. The shared authoring catalogue styles only explicit semantic spans, preserving ordinary text, power names, Damage and numerical comparisons. It applies consistently in selection, reward cards, Build Details, the biome explanation and the glossary. No gameplay properties, triggers or reward wording change as part of this item.

For playtesting, compare Static Wake's Electric Field, a Slowing Burst, Mark-based rewards and movement conversions. Check whether the terms are easier to identify at a glance and whether a screen with several offers still feels coherent. Hovered and selected cards should remain readable.

Verified in isolated project `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-d496af16637f4bc39fba049ad4620c44`: 350 scripts compile; 1,645 shared wording, 465 power description, 21,269 reward layout, 467 Build Details and 189 glossary checks pass. The wording suite evaluates every accent against the actual Boon, Arcana and boss card backgrounds at idle and full hover, including their opacity; all exceed 4.5:1 in that conservative check.

Native before/after comparison covers 144 frames and 2,165 checks: every unowned Arcana/boss offer, all upgrade and Prismatic pages, three/four cards, Build Details and glossary at 960/1280/1920. After frames are in `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-c4b3bd06b81f46e7af7d2cc771750f2e/reward_build_frames` and `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-9dac6aabbc72400abdb04e491638d649/reward_upgrade_frames`. Visual review found no clipping and retained title/body hierarchy. These captures cover idle cards and focused build entries; full-hover contrast is checked against production styles, rather than claimed as screenshot evidence.
