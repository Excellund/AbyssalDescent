"""Four original Riot Depth performances on one shared harmonic timeline.

``drive`` preserves the approved score exactly. ``pursuit``, ``pressure`` and
``boss`` compose new bass, lead and percussion parts over its unchanged base.
Every variant retains the same 48 bars, 140 BPM and D/C/Eb/E harmonic events,
so a room-entry crossfade does not change the underlying musical position.

The new performances are complete room cues. Bars 12-19 and 36-47 receive
full rhythmic writing rather than inherited reward/door reductions. Dynamics
come from the phrase, not a scenario gain map. One- or two-beat breaths remain
at phrase endings, and the lead leaves space for bass answers throughout.

Pursuit: clipped double attacks, angular replies, mostly half-time drums.
Pressure: longer low gates, weighty spaced hits, slower midrange responses.
Boss: backbeat passages trade with half-time counterattacks; a short sustained
lead identity distinguishes it without raising the register or velocities.

The renderer owns timbre and loudness matching. This module performs no audio
rendering, gain automation, file I/O, randomization or game-state switching.
"""

from riot_depth_score import BPM, BARS, HARMONY, ROOTS, score as approved_score

Event = tuple[float, int, float, int]
Parts = dict[str, list[Event]]


# Local beat, pitch symbol, duration, velocity. All bass parts stay in MIDI
# 36-47. There are at most six attacks per bar and no uninterrupted ostinato.
_BASS = {
    "pursuit": (
        ((0, "r", .32, 94), (.5, "r", .22, 79), (1, "r", .38, 85),
         (2, "f", .62, 90), (3, "r", .32, 84), (3.5, "n", .22, 79)),
        ((0, "r", .68, 94), (1, "r", .36, 82), (2, "r", .48, 90),
         (2.75, "r", .20, 77), (3, "f", .35, 83)),
        ((0, "r", .35, 94), (.5, "n", .20, 78), (1, "r", .58, 87),
         (2, "f", .58, 90), (3, "r", .34, 84)),
        ((0, "r", .92, 95), (2, "r", .50, 89), (3, "f", .30, 82)),
        ((0, "r", .45, 95), (1, "f", .35, 83), (1.5, "r", .24, 78),
         (2, "r", .50, 91), (3, "n", .24, 80), (3.5, "r", .22, 84)),
        ((0, "r", .66, 95), (1, "r", .28, 82), (2, "f", .48, 90),
         (2.5, "r", .22, 79), (3, "r", .32, 84)),
        ((0, "r", .40, 94), (.5, "r", .20, 78), (1, "n", .28, 81),
         (2, "r", .65, 91), (3.5, "b", .18, 79)),
        ((0, "r", 1.08, 95), (2, "f", .70, 89)),
    ),
    "pressure": (
        ((0, "r", 1.12, 95), (1.5, "r", .33, 81),
         (2, "r", .88, 90), (3, "f", .50, 84)),
        ((0, "r", .80, 95), (1, "f", .55, 84),
         (2, "r", 1.12, 91), (3.5, "r", .22, 79)),
        ((0, "r", 1.65, 94), (2, "f", .62, 88), (3, "r", .60, 86)),
        ((0, "r", .75, 95), (1, "r", .62, 85),
         (2, "n", .40, 81), (2.5, "r", .95, 91)),
        ((0, "r", .95, 95), (1.5, "f", .32, 81),
         (2, "r", .95, 91), (3.5, "b", .18, 78)),
        ((0, "r", .65, 94), (1, "r", .36, 83),
         (2, "f", .75, 89), (3, "r", .64, 85)),
        ((0, "r", 1.30, 95), (1.5, "n", .28, 81),
         (2, "r", .55, 90), (3, "f", .55, 84)),
        ((0, "r", 1.25, 95), (2, "r", 1.08, 88)),
    ),
    "boss": (
        ((0, "r", .30, 95), (.5, "r", .25, 81), (1, "f", .48, 87),
         (2, "r", .30, 91), (2.5, "r", .22, 79), (3, "n", .30, 83)),
        ((0, "r", .80, 95), (1, "r", .30, 83), (1.5, "f", .20, 79),
         (2, "r", .80, 91), (3.5, "b", .18, 79)),
        ((0, "r", .35, 94), (.5, "n", .22, 80), (1, "r", .38, 86),
         (2, "f", .36, 90), (2.5, "r", .22, 79), (3, "r", .55, 86)),
        ((0, "r", 1.15, 95), (2, "f", .55, 88), (3, "r", .40, 84)),
        ((0, "r", .55, 95), (1, "r", .30, 83), (1.5, "n", .22, 79),
         (2, "r", .40, 91), (2.5, "f", .22, 80), (3, "r", .40, 86)),
        ((0, "r", .35, 95), (.5, "f", .20, 80), (1, "r", .55, 87),
         (2, "r", .35, 91), (2.5, "r", .22, 80), (3, "b", .18, 81)),
        ((0, "r", .68, 95), (1, "n", .28, 81), (2, "r", .68, 91),
         (3, "f", .30, 85), (3.5, "r", .20, 80)),
        ((0, "r", 1.40, 95), (2, "r", .62, 88)),
    ),
}


def _form(text: str) -> tuple[int, ...]:
    return tuple(int(cell) for cell in text.split())


# Six independently ordered eight-bar phrases. The repeated phrase-ending
# cell provides a breath, while the intervening calls and answers develop.
_BASS_FORM = {
    "pursuit": _form("""
        0 1 2 3 4 5 6 7
        4 0 5 3 2 1 6 7
        6 2 0 3 5 4 1 7
        2 4 1 3 0 6 5 7
        5 1 4 3 6 0 2 7
        1 6 2 3 4 5 0 7
    """),
    "pressure": _form("""
        0 2 1 3 4 5 6 7
        5 1 4 3 0 6 2 7
        6 0 2 3 5 4 1 7
        1 4 6 3 2 0 5 7
        4 5 0 3 6 1 2 7
        2 6 4 3 1 5 0 7
    """),
    "boss": _form("""
        0 1 2 3 4 5 6 7
        4 2 5 3 6 0 1 7
        1 6 0 3 5 2 4 7
        2 4 1 3 0 6 5 7
        5 0 6 3 2 1 4 7
        6 1 4 3 5 2 0 7
    """),
}

# Fixed registral palettes follow the exact original chord at every bar.
# Brief non-chord neighbors are the same D-centered grit as the approved cue.
# Nothing exceeds G4=67; sustained boss notes are lower roots or fifths.
_LEAD_PITCHES = {
    38: {"r": 62, "f": 57, "n": 60, "b": 63, "t": 65},
    36: {"r": 60, "f": 55, "n": 62, "b": 63, "t": 63},
    39: {"r": 63, "f": 58, "n": 62, "b": 64, "t": 65},
    40: {"r": 64, "f": 59, "n": 62, "b": 65, "t": 67},
}
_HOOK = {
    "pursuit": (
        ((0, "r", .28, 87), (.5, "f", .20, 75), (1, "n", .25, 81),
         (1.5, "b", .16, 77), (2, "r", .50, 89)),
        (),
        ((0, "f", .35, 78), (1, "r", .28, 86),
         (1.5, "n", .24, 79), (2, "r", .58, 89)),
        ((0, "r", .60, 86), (2, "f", .32, 77)),
        ((0, "n", .28, 81), (.5, "r", .28, 87), (1, "b", .15, 77),
         (1.5, "r", .28, 84), (2, "f", .50, 80)),
        (),
        ((0, "r", .28, 87), (1, "f", .25, 76),
         (2, "n", .30, 81), (2.5, "r", .55, 89)),
        ((0, "r", .72, 86),),
    ),
    "pressure": (
        ((0, "f", .75, 80), (1.25, "n", .28, 77), (2, "r", .72, 88)),
        ((1, "r", .42, 85), (2.5, "f", .45, 78)),
        (),
        ((0, "n", .35, 80), (.5, "r", 1.15, 88)),
        ((.5, "r", .35, 86), (1, "f", .45, 77),
         (2, "n", .32, 80), (3, "r", .55, 87)),
        (),
        ((0, "f", .55, 79), (1.5, "n", .25, 77), (2, "r", .85, 88)),
        ((0, "r", 1.05, 86), (2, "n", .40, 78)),
    ),
    "boss": (
        ((0, "r", 1.08, 89), (1.5, "b", .18, 78),
         (2, "r", .55, 87), (3, "f", .38, 79)),
        ((0, "f", .30, 78), (.5, "n", .25, 81), (1, "r", .80, 88),
         (2.5, "t", .48, 87), (3.5, "r", .25, 83)),
        (),
        ((0, "r", 1.32, 89), (2, "f", .45, 79)),
        ((0, "n", .30, 80), (.5, "r", .30, 87), (1, "t", .72, 89),
         (2, "r", .50, 85), (3, "f", .32, 78)),
        ((0, "r", .65, 88), (1.5, "n", .25, 79),
         (2, "b", .17, 77), (2.5, "r", .72, 89)),
        (),
        ((0, "f", .48, 78), (1, "r", 1.12, 88)),
    ),
}
_HOOK_FORM = {
    "pursuit": _form("""
        0 1 2 3 4 5 6 7
        2 5 0 3 6 1 4 7
        4 1 6 3 2 5 0 7
        6 5 4 3 0 1 2 7
        0 1 4 3 2 5 6 7
        2 5 6 3 4 1 0 7
    """),
    "pressure": _form("""
        0 1 2 3 4 5 6 7
        6 2 4 1 0 5 3 7
        4 5 0 3 6 2 1 7
        3 2 6 1 4 5 0 7
        0 5 4 3 6 2 1 7
        6 2 0 1 4 5 3 7
    """),
    "boss": _form("""
        0 1 2 3 4 5 6 7
        4 2 5 3 1 6 0 7
        1 6 0 3 5 2 4 7
        5 2 4 3 0 6 1 7
        0 6 1 3 4 2 5 7
        4 2 5 3 1 6 0 7
    """),
}

_KICKS = {
    "pursuit": ((0, 1, 3), (0, 1, 3.5), (0, 1, 3), (0, 3),
                (0, 1, 2.5), (0, 1, 3), (0, 1, 3.5), (0,)),
    "pressure": ((0, 1, 3), (0, 1, 3), (0, 3), (0, 1, 3.5),
                 (0, 1, 3), (0, 1, 3), (0, 1, 2.75), (0,)),
    "boss": ((0, .5, 2, 2.5), (0, 1.5, 2, 3.5), (0, 1, 2, 2.5), (0, 2),
             (0, .5, 2, 3), (0, 1, 2, 3.5), (0, 2, 2.5), (0, 2)),
}


def _new_performance(name: str, base: list[Event]) -> Parts:
    parts: Parts = {role: [] for role in ("base", "bass", "hook", "drums", "debris")}
    parts["base"] = list(base)

    def add(role: str, bar: int, onset: float, pitch: int,
            duration: float, velocity: int) -> None:
        parts[role].append((bar * 4 + onset, pitch, duration, velocity))

    for bar, root in enumerate(ROOTS):
        cell, phrase = bar % 8, bar // 8
        bass_pitches = {"r": root, "f": root + 7,
                        "n": 36 if root == 38 else 38,
                        "b": 38 if root == 36 else root + 1}
        bass_cell = _BASS[name][_BASS_FORM[name][bar]]
        for onset, symbol, duration, velocity in bass_cell:
            add("bass", bar, onset, bass_pitches[symbol], duration, velocity)

        hook_cell = _HOOK[name][_HOOK_FORM[name][bar]]
        for onset, symbol, duration, velocity in hook_cell:
            add("hook", bar, onset, _LEAD_PITCHES[root][symbol], duration, velocity)

        # Keep a musical floor throughout all six phrases. The old selection
        # chapter indices have no bearing on these performances' intensity.
        kick_cell = (cell + (2 if phrase in (2, 4) and cell not in (3, 7) else 0)) % 8
        # Do not rotate the phrase-ending breath into an unrelated middle bar.
        if kick_cell == 7 and cell != 7:
            kick_cell = 5
        for index, onset in enumerate(_KICKS[name][kick_cell]):
            add("drums", bar, onset, 36, .28, 100 if index == 0 else 86 + index % 2 * 3)

        double_time = name == "boss" and cell in (
            (0, 1, 2, 4, 5) if phrase % 2 == 0 else (0, 1, 4, 5, 6)
        )
        if double_time:
            for onset in (1, 3):
                add("drums", bar, onset, 38, .25, 89)
        else:
            add("drums", bar, 2, 38, .29, 94)

        if cell == 7:
            hats = (0, 1)
        elif name == "boss" and double_time and cell in (0, 1, 4, 5):
            hats = (0, .5, 1, 1.5, 2, 2.5, 3, 3.5)
        elif name == "pursuit" and cell in (0, 4):
            hats = (0, .5, 1, 1.5, 2, 2.5, 3, 3.5)
        else:
            hats = (0, 1, 2, 3)
        for index, onset in enumerate(hats):
            add("drums", bar, onset, 42, .08, 43 if index % 2 == 0 else 32)

        crash_bars = {"pursuit": (0, 16, 32), "pressure": (0, 24),
                      "boss": (0, 8, 20, 28, 40)}[name]
        if bar in crash_bars:
            add("drums", bar, 0, 49, 1.20, 60)
        if name == "boss" and bar in (14, 30, 46):
            # A rare short challenge before the next phrase's spacious answer.
            add("drums", bar, 3.5, 38, .12, 66)
            add("drums", bar, 3.75, 38, .12, 74)

        # Industrial punctuation, not a repeating pitched top-line ostinato.
        if cell == 7:
            pitch = 39 if name == "pressure" else (37 if phrase % 2 == 0 else 39)
            add("debris", bar, 3.5, pitch, .25, 54)
        if cell == 3 and phrase % 2 == (0 if name == "pressure" else 1):
            add("debris", bar, 3.25, 46, .40, 50)

    return parts


def variants() -> dict[str, Parts]:
    """Return independent score lists; ``drive`` equals the approved score."""
    drive = approved_score()
    result = {"drive": drive}
    for name in ("pursuit", "pressure", "boss"):
        result[name] = _new_performance(name, drive["base"])
    return result
