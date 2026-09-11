# Enemy silhouettes at gameplay distance

Feedback `FB-89f2017d5e6547cc`: improve enemy visuals without overcomplicating them.

The seven established roles previously shared bright concentric circles, a horn and side spikes. At the ordinary camera distance, their small role-specific appendages competed with the same round centre. The new opt-in body profiles use broad colored planes, a dark shell and a small luminous aperture. Existing role colors remain the strongest cue; the shape supplies a second cue.

| Enemy | Body and retained role cue |
|---|---|
| Chaser | Narrow red wedge with its paired forward claws. |
| Charger | Broad amber plow behind its ram plate. |
| Archer | Swept cyan body between its bow fins. |
| Shielder | Ochre armored shell behind its original shield. |
| Weaver | Faceted violet abdomen and paired eyes, with all eight tracked legs. |
| Drifter | Teal vessel with its three satellites and faint wave ripples. |
| Sentinel | Planted green diamond; its aperture follows the turning cone. |

`enemy_base.gd` accepts an optional explicit profile in `_draw_common_body`. Other enemies and bosses retain their bespoke presentation. Geometry is cached per profile; no new scene nodes, textures, animation clocks or particles are added. The existing high-load threshold omits the fine rim while retaining each silhouette and aperture.

Only body drawing changes. Spawn transport, hit response, Slow/Mark/Dread indicators, mutator overlays and blocked-damage cues retain their existing owners and timing. The shared renderer restores local drawing coordinates before any appendage, overlay or attack warning. Shielder's shield polygon remains shared with its real damage-blocking geometry and is unchanged. Health, movement, collision, attack ranges, warning durations, damage and replication are unchanged.

## Verification

361 scripts compile and the project contracts pass. The new behavior fixture passes 106 checks, including real spawns, collision sizes, Slow/Mark persistence, native directional shield mitigation, slam boundaries and warning activity. The existing hit-origin fixture passes 64 checks. Snapshot: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-b344c1c53dc74b7f9ad2b5e73bae881a`.

Native comparison passes 239 checks and 12 paired frames in the actual Main backdrop: 960/1280 rosters, frontline and specialist warnings, statuses/spawn and a 28-enemy crowd at 0.58 co-op zoom. Root inspected the normal roster, frontline warnings and distant crowd; the independent reviewers inspected the crowd, specialist and status pairs. Charger/Archer/Shielder warnings remain readable; Drifter's safe ring gap, Sentinel's cone and Weaver's legs retain their geometry. Slow/Mark and transport cues remain visible; Pyre and Warden controls retain their prior presentation. Sentinel's body has less luminous mass inside its diamond; the frame and cone remain its strongest distant cues. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-e1cbeabdbecf44b39589472bb6dc98fb/enemy_visual_frames`.

Frozen pre-art source is retained in `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-5ebfd6d17cde4c15bb550f95b3ef6817`; the native manifest records source hashes. An initial native fixture incorrectly disabled the enclosing physics space and omitted Weaver foot initialization. These fixture defects were corrected before final capture; production mechanics required no changes.

After 60 warmup frames, each variant collected 8,400 actor draw samples over 300 rendered crowd frames. Mean command-submission time for the 28 actors was 3.331ms before and 2.961ms after. Per-actor median was 100→77µs; p95 was 240→260µs. This comparison found no average rendering-script regression, with some tail variation. It measures frozen-simulation drawing work, not whole-frame/GPU time, and does not establish an FPS gain.

## Player checks

- Identify a Chaser, Charger, Archer and Shielder in a mixed room before their first attack. Their silhouettes should help without requiring close inspection.
- Check Weaver, Drifter and Sentinel at your normal camera distance. Their legs, satellites and cone should remain easy to connect to the right enemy.
- Look at overlapping enemies, active attack warnings and status effects. Body detail should remain subordinate to the information needed to dodge.
- If playing co-op, check the wider camera and a crowded room. Role shapes should remain recognizable as detail reduces.
