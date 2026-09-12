# Returning Crescent recordings

Prepared from **Swishes Sound Pack** by **artisticdude**, offered under **CC0** on the creator's [OpenGameArt page](https://opengameart.org/content/swishes-sound-pack). The creator describes recording physical objects moving through air. No generated oscillator, flutter, pitch modulation or musical tone is layered over these recordings.

Source archive: [swishes.zip](https://opengameart.org/sites/default/files/swishes.zip). SHA256: `7980215241B739A787DCF26F660CE510BB237900968789395A86911619795693`. License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

The game uses prepared versions of swish-10, -11 and -12 for outbound gestures; -13 and -12 for returns; -13 for the short ricochet. Preparation converts to mono 48 kHz PCM, removes microphone rumble/hiss, applies short edge fades and bounds peaks. Constant tempo adjustments retain the recorded pitch. Separate recorded variants rotate in fixed order, avoiding identical repetition without consuming gameplay RNG. Source and output hashes are in `render-report.json`.

`tools/audio/render_crescent_audio.py --source <extracted swishes folder> --auditions <output folder>` reproduces these files and two 12-second auditions. It requires NumPy and FFmpeg, downloads nothing, and never plays audio. The optional weightier audition uses swish-9; only the lighter set is used by the game. Each audition has three dry throws followed by repeated throws over unchanged Riot Depth base/Drive music at the default game mix. The renderer's gain and return trim agree with the runtime controller.
