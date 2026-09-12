# Returning Crescent sound

Feedback: `FB-f8e95846889846c2`, reopened after the player said the synthesized revision sounded worse. The prior playback and mixer checks established technical behavior, not sound quality.

Crescent now uses short recorded air swishes from artisticdude's CC0 [Swishes Sound Pack](https://opengameart.org/content/swishes-sound-pack). Three slightly different outbound recordings last about 0.10–0.13s; two returns last about 0.07–0.08s. The return sits 8 dB below the throw. A brief recorded air flick accompanies the level-three ricochet at 6 dB below the throw. The former oscillator, rising-pitch return, synthesized metal and repeating flutter are removed. Overall base gain is -21.5 dB rather than -17 dB: the player selected the lighter -20 dB audition and requested a slight reduction, applied as another 1.5 dB.

Fixed audio voices let overlapping blades finish their short tails while variants rotate in order. No gameplay RNG or random pitch shifting is used. Cached/imported samples cost no runtime synthesis. SFX controls reach all six voices, and cancellation stops every variant. Real outbound, return and bounce events still drive the cues; remote deduplication and gameplay movement/damage are unchanged.

Two 12-second comparisons were prepared: light recorded swishes and a weightier recording. Each begins with three dry throws, then normal cadence and level-two overlap against the existing game music at its default mix. The player selected the lighter swish and asked for slightly less volume. The integrated lighter set is 1.5 dB below that audition; the original preview is retained unchanged. No direct listening tool is available in this session, so measured peak/RMS values are mix checks, not a claim that the sound is enjoyable.

Sources, license and preparation are recorded in [sounds/crescent/README.md](../sounds/crescent/README.md). The reproducible renderer and hash report preserve the selected recordings. Scoped controller, sample-import and native voice/mixer verification are recorded in the combined delivery report after they pass. Playtest repeated throws with normal attack impacts, two overlapping blades, a wall bounce, SFX controls and room/pause cancellation.

## Verification of the selected revision

- 387 GDScript files compile; world-property and multiplayer contracts pass. Imported-recording/controller checks: 23; existing Returning Crescent gameplay checks: 86. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-b12fabb7a5a542329094b939af85549e`.
- Native engine mixer checks pass for recorded variants, SFX gain with quieter return, true phase cues, overlapping voices and cancellation of every variant. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-2980bd5ba83c48de976e7fadecd23615/crescent_sound_frames`. The dummy output remained silent during automation; an actual mixed recording is retained.
- Verification caught Godot's default lossy WAV import and the GPU helper retaining older audio import settings. All six short recordings now explicitly retain 16-bit mono PCM without normalization or looping, and the helper refreshes source sound assets/import settings alongside scripts. This keeps the native test on the same audio revision being delivered.
- User audition feedback: “Lighter swish, but lower volume ever so slightly.” The original -20 dB preview stays in `.feedback/auditions`; `.feedback/auditions/final` reflects the selected -21.5 dB mix. Final game acceptance remains a playtest decision.
