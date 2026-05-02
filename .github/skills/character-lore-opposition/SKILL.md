---
name: character-lore-opposition
description: Write or revise playable character lore/archetypes so each character has a clear gameplay promise, abyssal identity, and explicit opposition to a boss pillar.
---

# Character Lore Opposition

Use this skill when adding or revising playable character identities, names, blurbs, character cards, or selection copy.

## Core Rule
Every character entry must include all three:
1. A one-line gameplay promise that communicates how the character changes play.
2. A boss-opposition statement that names the opposed boss or pillar.
3. At least three future design lanes to preserve expansion space.

When implementation includes runtime visuals, each character must also have a unique silhouette language (not palette-only changes).

## Writing Checklist
- Keep identity concise and actionable: player should know how to pilot the character in one sentence.
- Tie fantasy to Abyssal Descent language: throne, abyss, descent, oaths, collapse, fracture, hunt, etc.
- Encode opposition mechanically, not just narratively.
- Avoid generic class text like "strong knight" or "fast assassin" without combat intent.
- Ensure names and taglines differ clearly from boss names to reduce UI confusion.

## Design-Lane Template
For each character, define:
- Survivability lane: how this archetype stabilizes under pressure.
- Expression lane: what advanced play feels like.
- Mastery lane: what late-run optimization revolves around.

## Visual Identity Pattern
- Keep a shared base readability shell, then add per-character shape signatures.
- Bastion-style identities should read armored/anchored: heavier frontal geometry, shield or plate motifs, fewer delicate ornaments.
- Hexweaver-style identities should read arcane/control: orbitals, sigils, split-glyph motifs, ritual symmetry.
- Veilstrider-style identities should read execution/tempo: blade-forward forms, asymmetric slashes, lean trailing accents.
- Avoid only swapping colors; a screenshot in grayscale should still communicate which character is being played.

## Opposition Mapping Pattern
- Warden-opposed character: counters brute momentum and frontal pressure.
- Sovereign-opposed character: counters control geometry, zoning, and forced positioning.
- Boss III-opposed character: define pillar first (attrition, summoning, denial, etc.), then anchor character identity against it.

## Worked Boss III Example
- Lacuna: tempo denial and missing-beat pressure. This boss opposes characters that rely on clean disengage windows, execution tempo, or living inside the seam between attacks.
- Veilstrider vs Lacuna pattern: the boss owns the silence between actions; the character survives by severing that silence before it closes.
- Mechanical test: the opposition should show up in boss pacing, not only in lore copy. If the character's strength is precise tempo control, the boss must contest prediction windows, escape seams, or reset timing.

## UI Copy Pattern
Use this format for selection cards:
- Name
- Archetype
- Opposes: <Boss/Pillar>
- Tagline (single line)

## Anti-Patterns
- Lore-only flavor with no gameplay implication.
- Gameplay-only text with no abyssal identity.
- Character identity that overlaps another character's core loop.
- Opposition that contradicts encounter identity (for example, reducing a control boss to a pure damage race).

## Validation Before Ship
- Character cards remain readable at menu target resolutions.
- Each character’s one-line promise is distinguishable at a glance.
- Opposition mapping is still correct after boss or encounter reworks.
- In-motion gameplay silhouette test passes: each character is identifiable within ~1 second even with color desaturated.
