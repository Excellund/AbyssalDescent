# Soundtrack direction and lessons

Updated 2026-09-11. **Riot Depth is the user-approved creative reference** for
AbyssalDescent's soundtrack. After hearing this audition, the user said:
"Yooooo this is sick! Note down our learnings so far".

Latest correction after integration: the user likes the soundtrack changing
through the run and wants stronger boss/encounter variation, but reward and
door reductions feel like someone randomly adjusting the volume. **Keep the
current arrangement and its presence through selection UI.** Put musical
changes at chamber entry, boss encounters and within composed phrases instead.

Use the approved layers and [production notes](../music/riot-depth/README.md)
as the reference for future cues. The [score source](../tools/audio/riot_depth_score.py)
preserves the composition. This approval establishes the musical direction;
listening against actual gameplay, SFX and repeated runs remains part of playtest.

## The identity to carry forward

Dark dungeon action with brash, explosive, mischievous, rebellious energy.
The user's Bakugo and Jinx references clarified the character more precisely
than the earlier broad anime / Hades / action RPG references. Keep compositions
original; those references describe attitude.

The working palette is distorted bass with audible midrange grit, hard drums,
short electronic hooks, a subdued atmospheric bed and occasional noise accents.
Keep a grounded pulse and a clear backbeat. Let aggression come from rhythm,
articulation and sound design. Leave room between gestures and preserve impact
without relying on a piercing high lead or incessant bright attacks.

Darkness should carry confidence, danger and anticipation. Earlier versions
drifted toward sadness, pastoral comfort or scenic heroic adventure, which did
not fit the requested character. Selection UI does not imply a quiet music
state. Let the composition breathe without automatically reducing its level
when a reward card or door choice appears.

## What the listening feedback taught us

| Iteration | User feedback | Lesson to retain |
| --- | --- | --- |
| Initial generated descent tracks | Instrument sounds / overall texture were the main problem. | More notes or more tracks cannot repair an unconvincing palette. Establish sound character early. |
| Sampled piano and strings | Better, but the rhythm felt off and the mood was too sad. | Instrument fidelity, groove and emotional direction are separate decisions. |
| Piano groove revision | "MUCH better", but too Stardew Valley; wanted anime / Hades / action RPG. | Retain rhythmic clarity while changing the dramatic identity. A pleasant cue can still belong to the wrong game. |
| Action scenario study | Too funky; violin cut too deeply. | Avoid a bouncy groove as the default. A cutting lead does not establish the requested aggression. |
| Refined action study | Loud repeating pling was rough; the track remained repetitive. | Address the actual recurring timbre and phrase design. Lowering a lead or changing its instrument is insufficient if the irritating pattern remains. |
| Ember Path | Too much travel in the highlands; wanted dungeon-dwelling rebel badass. | Better orchestral recordings and smooth transitions did not solve identity. Sweeping strings and horns pushed this example toward scenic adventure. |
| Riot Depth | "Yooooo this is sick!" | Preserve this industrial/electronic direction as the approved reference. Develop it without resetting the palette on the next cue. |
| Integrated Riot Depth | Likes variation through the run, but low reward/door audio feels like random volume adjustment. | A lower gain is not sufficient musical variation. Preserve the arrangement through choices; use composed chamber and boss variations with comparable loudness. |

These are lessons from these auditions, not a universal prohibition on strings,
horns, melody or syncopation. Any future use should serve the established
character and avoid the specific problems above.

## Features of the successful example

Riot Depth combines the following choices. The user approved the overall
result; they did not separately evaluate each choice, so the explanation of
why each helped remains our working interpretation.

- A 140 BPM score with a heavy half-time backbeat gives the music a firm center.
  Bass calls and short lead replies provide movement around that center.
- Distorted mid-bass supplies character as well as weight. The final revision
  reduced excess fundamental energy and brought forward rougher harmonics and
  snare attack. Bass briefly ducks around kick hits to preserve their definition.
- Short, restrained electronic gestures replace the earlier exposed violin and
  recurring pling. Written hook notes occupy about 23% of the timeline before
  release tails, leaving substantial space for percussion and bass answers.
- D-centered power fifths, held harmony and brief neighboring tensions support
  menace without depending on a lyrical, melancholy progression.
- The 48-bar form develops: the second fight introduces a new rising gesture,
  different bass answers and brief faster drum passages before recalling the
  opening. Variation changes phrases, rhythm, density and articulation.
- Processed recorded percussion and authored electronic voices work together.
  Source quality and suitable sound design both matter; sample realism alone
  was not the answer, and synthesis itself was not the original problem.

140 BPM, D, 48 bars and the precise silence percentage describe this reference.
They are not mandatory settings for every future track.

## One musical world across gameplay states

| State | Intended feeling | Arrangement behavior |
| --- | --- | --- |
| Chamber entry | Defiant momentum with changing musical character | Rotate Drive, Pursuit and Pressure using the chamber's act/depth, on the shared bar clock. |
| Boss chamber | A recognizably stronger confrontation | Dedicated Boss arrangement with different drum/bass/lead writing at comparable loudness. |
| Reward and door selection | Continue the musical journey | Preserve the current chamber arrangement, master level and any blend already underway. |
| Rest site | A new passage in the run | Select a chamber arrangement without applying a quiet-state volume trim. |

Use a shared musical timeline. The current revision starts five aligned layers
together: a continuous base plus Drive, Pursuit, Pressure and Boss additions.
Actual arrangement changes begin at the next bar and blend over a bar without
restarting the phrase. Pause preserves the clock. Keep phase, harmony and tempo
aligned across loops; opening or closing choices must not reset the blend.

The game uses a private native synchronized stream. Chamber identity comes from
existing act/depth and the presented boss chamber, including Continue and both
network peers. See the [variance revision](riot-depth-variance-20260911.md).

## A better process for future music work

1. Start from the approved audio and describe the scene's emotional job. Use
   character and situation references to narrow a broad genre label.
2. Audition the palette and groove early. A technically correct render or an
   impressive instrument name does not establish suitable sound.
3. Identify the audible complaint precisely: timbre, register, attack, repetition,
   groove, mood or scene identity. Fix that cause, then retain what already worked.
4. Provide a complete fight → reward → door → second-fight example, plus manual
   switching. Short excerpts cannot establish development or transition behavior.
5. Use measurements to find mix and transport defects: clipping, bass masking,
   alignment, loop boundaries and gains during transitions. Spectral percentages,
   loudness and passing tests are not musical-quality scores.
6. Preserve the approved render as a comparison when making further versions.
   Record the user's exact response and distinguish approval of an audition from
   verification of the integrated game. The agent has no direct listening tool
   in this session; user feedback supplies the perceptual evidence.

Before shipping, listen in real combat with SFX and across longer repeated runs.
Verify reward/door timing, rapid state changes, pause, loops and existing volume
controls in the game. Further acts, bosses and other scene identities have not
yet received separate approval.

Earlier auditions and the original texture diagnosis are retained in the
audio-development worktree. The feedback table above is the durable record of
their musical lessons; the approved runtime exports are under `music/riot-depth`.
