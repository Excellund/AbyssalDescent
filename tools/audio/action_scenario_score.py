"""Original, phase-aligned D-Dorian action cue for an offline audition.

The eight-bar harmonic cycle continues through exploration, combat, climax,
and reward. Every role spans the timeline so the renderer can demonstrate
scenario changes by fading aligned stems. Program numbers are zero-based GM.
"""

BPM = 132
BARS = 32

# channel, program, pan, reverb send, target active RMS in dBFS
SETTINGS = {
    "guitar_ostinato": (0, 28, 44, 8, -27.0),
    "bass": (1, 34, 64, 3, -27.0),
    "strings": (2, 48, 81, 25, -30.0),
    "violin_lead": (3, 40, 61, 22, -27.0),
    "overdrive": (4, 29, 83, 5, -32.0),
    "drums": (9, 0, 64, 3, -25.0),
    "toms": (9, 0, 61, 12, -31.0),
    "harmonics": (5, 31, 37, 28, -34.0),
}

# The original audition remains reproducible. The revision replaces its clipped
# muted guitar/picked bass and exposed solo violin while retaining stem IDs.
# 'violin_lead' is now the lower ensemble theme, not a solo violin preset.
RESTRAINED_SETTINGS = {
    **SETTINGS,
    "guitar_ostinato": (0, 29, 44, 7, -29.5),
    "bass": (1, 33, 64, 3, -28.0),
    "strings": (2, 48, 81, 25, -32.0),
    "violin_lead": (3, 48, 61, 24, -31.0),
    "overdrive": (4, 29, 83, 5, -33.0),
    "harmonics": (5, 31, 37, 28, -35.0),
}

# Dm(add9), Dm, G, G, C(add9), G, C(add9), Dm.
# F establishes minor character, while G's B-natural supplies Dorian lift.
ROOTS = (38, 38, 43, 43, 36, 43, 36, 38)
THIRDS = (3, 3, 4, 4, 4, 4, 4, 3)
COLORS = (10, 10, 10, 10, 14, 10, 14, 10)
VOICINGS = (
    (62, 65, 69, 76), (62, 65, 69, 74),
    (62, 67, 71, 76), (62, 67, 71, 74),
    (60, 64, 67, 74), (62, 67, 71, 76),
    (60, 64, 67, 74), (62, 65, 69, 76),
)

# One identity across the scenarios: D-E-A-G / A-E-D. Broad peaks alternate
# with shorter answers. B-natural and F-natural belong to the same mode.
THEME = (
    ((0, 74, .9, 86), (1, 76, .42, 77), (1.5, 81, 1.32, 95),
     (3, 79, .42, 83), (3.5, 76, .40, 78)),
    ((0, 81, 1.7, 96), (2, 79, .75, 85), (3, 76, .40, 78),
     (3.5, 74, .40, 85)),
    ((0, 74, .75, 84), (1, 79, .75, 90), (2, 83, 1.7, 97)),
    ((0, 81, 1.35, 93), (1.5, 79, .40, 85), (2, 76, .75, 81),
     (3, 74, .85, 86)),
    ((0, 76, .85, 87), (1, 79, .75, 92), (2, 84, 1.7, 98)),
    ((0, 83, 1.35, 94), (1.5, 81, .40, 87), (2, 79, .75, 89),
     (3, 74, .85, 82)),
    ((0, 79, .85, 90), (1, 76, .75, 83), (2, 74, .75, 85),
     (3, 76, .40, 80), (3.5, 79, .40, 87)),
    ((0, 77, .75, 92), (1, 76, .75, 84), (2, 74, 1.7, 92)),
)


def score():
    """Return stem names mapped to (beat, MIDI pitch, duration, velocity)."""
    parts = {name: [] for name in SETTINGS}

    def note(role, bar, beat, pitch, duration, velocity):
        parts[role].append((bar * 4 + beat, pitch, duration, velocity))

    for bar in range(BARS):
        cell = bar % 8
        cycle = bar // 8
        root = ROOTS[cell]
        guitar_root = root + 12
        third = THIRDS[cell]
        color = COLORS[cell]

        if bar == BARS - 1:
            # End the final reward phrase on open D, retaining rendered tails.
            for role, pitch, duration, velocity in (
                ("guitar_ostinato", 50, 2.7, 72),
                ("guitar_ostinato", 57, 2.7, 62),
                ("bass", 38, 2.7, 75),
                ("violin_lead", 74, 2.7, 82),
                ("overdrive", 50, 2.7, 67),
                ("overdrive", 57, 2.7, 61),
                ("harmonics", 74, 2.7, 69),
                ("drums", 36, .18, 67),
                ("drums", 42, .12, 40),
                ("toms", 45, .3, 57),
            ):
                note(role, bar, 0, pitch, duration, velocity)
            for pitch, velocity in ((62, 70), (69, 64), (76, 65)):
                note("strings", bar, 0, pitch, 2.7, velocity)
            continue

        # A low, repeated-note pick pattern: grounded attacks on the kick,
        # then seventh/third colors. The octave is an answer, not an oom-pah.
        guitar_pattern = (
            (0, 0, .33, 99), (.5, 0, .24, 69),
            (1, 7, .29, 80), (1.5, 0, .30, 90),
            (2, color, .33, 93), (2.5, 0, .25, 70),
            (3, third, .29, 83), (3.5, 7, .26, 75),
        )
        for onset, interval, duration, velocity in guitar_pattern:
            note("guitar_ostinato", bar, onset, guitar_root + interval,
                 duration, velocity)

        # Picked bass shares downbeats and gives the riff a little forward
        # motion without displacing its strong quarter-note frame.
        for onset, interval, duration, velocity in (
            (0, 0, .82, 97), (1, 0, .36, 78), (1.5, 7, .35, 83),
            (2, 0, .80, 91), (3, 0, .36, 79), (3.5, 12, .32, 85),
        ):
            note("bass", bar, onset, root + interval, duration, velocity)

        # The ensemble preset needs time to speak: these are broad bowed
        # gestures, not extremely short MIDI notes posing as spiccato.
        for onset, duration, velocity in ((0, 1.65, 73), (2, 1.60, 68)):
            for voice, pitch in enumerate(VOICINGS[cell]):
                note("strings", bar, onset, pitch, duration,
                     velocity - voice * 3)

        phrase = THEME[cell]
        if cycle == 2 and cell in (1, 3, 5, 6):
            # Climax elaborates the same register and hook with playable
            # eighth-note answers; it does not introduce a new tempo or tune.
            runs = {
                1: (81, 79, 76, 74),
                3: (79, 81, 83, 81),
                5: (83, 81, 79, 76),
                6: (76, 79, 81, 79),
            }
            phrase = ((0, phrase[0][1], 1.7, 99),) + tuple(
                (2 + index * .5, pitch, .40, 84 + (index % 2) * 5)
                for index, pitch in enumerate(runs[cell])
            )
        for onset, pitch, duration, velocity in phrase:
            note("violin_lead", bar, onset, pitch, duration, velocity)

        # Guitar stays in its physical low-mid register. Separated fifths
        # add weight behind the theme instead of becoming a GM guitar solo.
        for onset, duration, velocity in (
            (0, .72, 94), (1.5, .33, 81), (2, .75, 89), (3.5, .30, 80),
        ):
            for interval, adjustment in ((0, 0), (7, -8)):
                note("overdrive", bar, onset, guitar_root + interval,
                     duration, velocity + adjustment)

        # The backbeat remains legible throughout every layer change.
        for onset, velocity in ((0, 107), (2, 99)):
            note("drums", bar, onset, 36, .18, velocity)
        if bar % 2:
            note("drums", bar, 3.5, 36, .16, 84)
        for onset, velocity in ((1, 96), (3, 101)):
            note("drums", bar, onset, 38, .16, velocity)
        for index in range(8):
            velocity = (65, 41, 56, 44, 61, 40, 56, 46)[index]
            note("drums", bar, index * .5, 42, .12, velocity)
        if cell == 0:
            note("drums", bar, 0, 49, .8, 75)

        # Low tom anchors can stay quiet in exploration. Fill locations are
        # fixed to the phrase, so scenario gains never change the meter.
        note("toms", bar, 0, 45, .27, 69)
        note("toms", bar, 2, 47, .24, 56)
        if cell in (3, 7):
            for onset, pitch, velocity in (
                (3, 50, 70), (3.25, 48, 74),
                (3.5, 47, 80), (3.75, 45, 87),
            ):
                note("toms", bar, onset, pitch, .19, velocity)

        # A sparse high-register counterpart carries the harmonic color
        # when the renderer lowers the lead and rhythm for exploration.
        harmonic_notes = (74, 76) if cell in (0, 1, 7) else (
            (74, 71) if cell in (2, 3, 5) else (76, 74)
        )
        for onset, pitch, velocity in (
            (0, harmonic_notes[0], 72), (2, harmonic_notes[1], 62),
        ):
            note("harmonics", bar, onset, pitch, 1.6, velocity)

    return parts


def restrained_score():
    """Steadier rhythm and a lower ensemble theme for the second action study."""
    parts = score()
    for role in ("guitar_ostinato", "bass", "violin_lead", "overdrive"):
        parts[role] = []

    # Preserve the theme's contour an octave lower, allowing the ensemble to
    # speak in quarter/half-note phrases. No exposed upper-octave climax runs.
    theme = (
        ((0, 62, .88, 72), (1, 64, .88, 67), (2, 69, 1.78, 77)),
        ((0, 67, .88, 73), (1, 64, .88, 66), (2, 62, 1.78, 72)),
        ((0, 62, 1.78, 70), (2, 67, .88, 73), (3, 71, .88, 77)),
        ((0, 69, 1.78, 75), (2, 67, .88, 70), (3, 62, .88, 67)),
        ((0, 64, .88, 70), (1, 67, .88, 73), (2, 72, 1.78, 78)),
        ((0, 71, 1.78, 76), (2, 69, .88, 71), (3, 67, .88, 69)),
        ((0, 67, .88, 73), (1, 64, .88, 67), (2, 62, 1.78, 71)),
        ((0, 65, .88, 74), (1, 64, .88, 68), (2, 62, 1.78, 73)),
    )
    for bar in range(BARS):
        base = bar * 4
        root = ROOTS[bar % 8]
        if bar == BARS - 1:
            for role, pitches, velocity in (
                ("guitar_ostinato", (50, 57), 67),
                ("bass", (38,), 72),
                ("violin_lead", (62,), 70),
                ("overdrive", (50, 57), 67),
            ):
                for pitch in pitches:
                    parts[role].append((base, pitch, 2.7, velocity))
            continue

        # Straight repeated-root eighths replace the hopping third/seventh riff.
        # A quieter overdrive preset supplies body without the muted-guitar snap.
        for index in range(8):
            velocity = 85 if index in (0, 4) else (78 if index % 2 == 0 else 69)
            parts["guitar_ostinato"].append((base + index * .5, root + 12, .43, velocity))

        # Half-bar root holds remove the previous offbeat fifth/octave jumps.
        for onset, velocity in ((0, 83), (2, 78)):
            parts["bass"].append((base + onset, root, 1.82, velocity))
            for interval, adjustment in ((12, 0), (19, -7)):
                parts["overdrive"].append((base + onset, root + interval, 1.60,
                                           velocity + adjustment))

        for onset, pitch, duration, velocity in theme[bar % 8]:
            parts["violin_lead"].append((base + onset, pitch, duration, velocity))
    return parts
