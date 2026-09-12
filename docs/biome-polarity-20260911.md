# Biome help and danger

Feedback: FB-ec75c54759044549; visual refinement FB-4925274fc75a494b.

Helpful biome effects use a smooth pale mint double contour with a restrained inner glow. Harmful effects use an amber warning contour that turns red when active, with narrow diagonal scores facing into the affected floor. The silhouette and edge texture communicate polarity independently of color. A brighter portion of the actual contour drains during the warning, preserving the floor countdown. Biome identity drawings remain inside circles; no auxiliary shields, triangles or badges are added.

The shared contour helper follows circles, separate lane rectangles, annuli and sectors. All contour strokes are inset into the actual committed geometry and clipped to room bounds. Ring holes, split-lane gaps and sector openings stay unmarked. Edge widths follow the camera and viewport scale, with limits for small shapes. The controller caches contours until geometry, allegiance or screen scale changes. Foe-only Shatterfield pillar bursts use the same smooth double contour through their short fade.

The HUD explicitly says `HELP · FOES ONLY` or `DANGER · YOU + FOES`, with the phase underneath. Entry advice and contextual inspection use the same distinction. Automatic compact-room assistance updates the current message, inspection and edge style together. The regular warning/active/recovery lifecycle controls whether contours exist. Normal Shatterfield cover still creates its immediate, player-safe Burst only on a confirmed break.

Damage, Slow, targets, timing, geometry and replication are unchanged. Enemy ability warnings retain their own danger even beside a helpful biome zone.

Verification includes independent geometry sampling through contours and scores at multiple scales, native room phases and assistance promotion, scoped biome and Shatterfield mechanics, and GPU captures of the nine-biome matrix and real pillar bursts. Human playtest acceptance remains outstanding; the root task coordinates the combined build and board status.

Final isolated validation passed: 384-script compile and world/network contracts; biome clarity (640 checks), biome rules (498), real room context and Shatterfield break suites. The native RTX 4080 matrix passed 38 frames / 424 checks; the Shatterfield fixture passed 6 frames / 22 checks, including the live Burst at 960. Visual review covered all nine biome identities, clipped contours and safe gaps, boss/Apex coexistence, and complete 960-wide tooltips. A clipped-sector inset issue and tooltip overflow were corrected during verification.
