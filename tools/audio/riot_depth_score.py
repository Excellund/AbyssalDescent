"""Original dark industrial action cue: a shared 48-bar adaptive timeline.

The identity is a brash bass call with short, clipped lead replies. D power
fifths anchor the piece; C, brief Eb and E challenges add danger without a
lyrical minor-key lament. The first fight is heavy half-time. The second
introduces a new rising hook, denser bass answers and brief double-time snare
passages before recalling the opening gesture.

Bars 0-11 combat; 12-15 reward; 16-19 doors; 20-35 developed combat;
36-41 reward; 42-47 doors. These are composed chapters on one continuous
clock, not independently started tracks. A renderer can mix the same aligned
roles differently for any scenario. The final D leads back to the first D.

Events are (absolute beat, MIDI pitch, duration in beats, velocity).
"""

BPM = 140
BARS = 48
BEATS_PER_BAR = 4

# The center can hold for several bars. Harmonic rhythm is deliberately not a
# regular succession of one bright chord per bar. Eb's flat second is a short
# interruption; E is a harder neighboring power chord, not a major cadence.
ROOTS = (
    38, 38, 38, 38, 36, 38, 38, 39, 38, 40, 38, 38,
    38, 38, 36, 38, 38, 39, 38, 40,
    38, 38, 39, 38, 36, 36, 38, 40, 38, 38, 39, 40, 38, 36, 38, 38,
    38, 38, 36, 38, 39, 38,
    38, 40, 38, 39, 40, 38,
)
_DYADS = {38: (38, 45), 36: (43, 48), 39: (39, 46), 40: (40, 47)}
HARMONY = tuple(_DYADS[root] for root in ROOTS)

# onset, pitch role, written gate, velocity. r=root, f=fifth, n=the D/C
# neighboring answer, b=brief flat-second challenge. The groove uses mostly
# quarter-note anchors; the few offbeat pickups have a specific destination.
_BASS_CELLS = {
    "A": ((0, "r", .58, 96), (1, "r", .28, 81), (1.5, "r", .24, 77),
          (2, "f", .55, 90), (3, "r", .28, 84), (3.5, "n", .20, 79)),
    "B": ((0, "r", .78, 94), (1.5, "r", .25, 79), (2, "r", .62, 91),
          (3, "f", .28, 83), (3.5, "r", .20, 80)),
    "C": ((0, "r", .75, 96), (1, "r", .28, 82), (2, "r", .55, 91),
          (3, "n", .22, 81), (3.5, "r", .22, 86)),
    "D": ((0, "r", 1.0, 95), (2, "f", .60, 88), (3, "r", .25, 82)),
    "E": ((0, "r", .55, 95), (1, "f", .30, 82), (2, "r", .65, 91),
          (3.5, "b", .18, 78)),
    "F": ((0, "r", .55, 95), (.75, "r", .22, 76), (1, "r", .35, 83),
          (2, "r", .55, 91), (3, "f", .28, 82)),
    "G": ((0, "r", .70, 95), (1, "r", .27, 82), (2, "f", .58, 90),
          (3, "r", .40, 83)),
    "H": ((0, "r", .72, 94), (2, "r", .55, 88)),
    "I": ((0, "r", .35, 98), (.5, "r", .20, 80), (1, "r", .35, 87),
          (2, "f", .65, 92), (3, "n", .20, 82), (3.5, "r", .25, 88)),
    "J": ((0, "r", .85, 97), (1.5, "n", .25, 82), (2, "r", .45, 93),
          (2.5, "f", .20, 80), (3, "r", .25, 84), (3.5, "r", .20, 79)),
    "K": ((0, "r", .55, 96), (1, "r", .28, 83), (2, "n", .28, 86),
          (2.5, "r", .55, 91), (3.5, "f", .20, 81)),
    "L": ((0, "r", .40, 98), (.5, "f", .20, 83), (1, "r", .40, 88),
          (2, "r", .55, 92), (3, "b", .20, 81), (3.5, "r", .20, 87)),
    "M": ((0, "r", .80, 97), (2, "r", .35, 90), (2.5, "r", .25, 80),
          (3, "f", .30, 84)),
    "N": ((0, "r", .80, 96), (1, "f", .35, 84), (2, "r", .55, 91),
          (3, "n", .25, 80)),
    "O": ((0, "r", .70, 84), (2, "f", .40, 74), (3.5, "r", .20, 77)),
    "P": ((0, "r", 1.25, 94),),
    "Q": ((0, "r", .60, 77), (2.5, "f", .35, 66)),
    "R": ((1, "r", .60, 72), (3, "n", .25, 65)),
    "S": ((0, "r", 1.20, 78), (3, "f", .30, 66)),
    "T": ((2, "r", .65, 71),),
    "U": ((0, "r", .70, 80), (1.5, "n", .25, 68), (2, "r", .55, 75)),
    "V": ((0, "r", 1.0, 76),),
}
_BASS_FORM = (
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "P",
    "Q", "R", "S", "V", "T", "Q", "R", "H",
    "L", "M", "J", "N", "I", "E", "K", "F", "A", "B", "L", "J", "I", "N", "K", "P",
    "U", "Q", "R", "S", "Q", "V",
    "T", "R", "Q", "T", "O", "V",
)

# Short, mid-register lead gestures leave far more than half the timeline
# unoccupied. The bass gets to answer; the lead never becomes an endless siren.
_HOOK = {
    # First identity: D / A / C / Eb / D, clipped and slightly insolent.
    0: ((0, 62, .32, 90), (.75, 57, .22, 77), (1, 60, .32, 83),
        (1.5, 63, .18, 80), (2, 62, .70, 93)),
    2: ((.5, 62, .32, 87), (1, 62, .22, 78), (1.5, 60, .22, 81),
        (2, 57, .65, 84), (3.5, 63, .16, 77)),
    3: ((0, 62, .55, 88),),
    4: ((0, 60, .32, 87), (.75, 55, .22, 75), (1.25, 62, .30, 82),
        (2, 64, .28, 85), (3, 60, .45, 88)),
    6: ((0, 62, .25, 88), (.5, 63, .18, 79), (.75, 62, .35, 84),
        (1.5, 57, .35, 79), (2.5, 60, .25, 82)),
    7: ((0, 63, .45, 87), (1.5, 62, .30, 81)),
    8: ((0, 62, .40, 90), (1, 57, .22, 78), (1.5, 60, .30, 84),
        (2, 62, .60, 92)),
    9: ((0, 64, .35, 89), (.75, 62, .35, 82), (2, 57, .30, 79),
        (2.5, 55, .30, 76), (3, 52, .25, 80)),
    10: ((0, 62, .25, 91), (.5, 65, .25, 87), (1, 64, .25, 81),
         (1.5, 62, .60, 90)),
    11: ((0, 62, .50, 86),),
    # Reward keeps its swagger in three small acknowledgments, then space.
    12: ((1, 62, .50, 73), (2, 60, .20, 65), (3, 57, .25, 66)),
    14: ((.5, 60, .50, 71), (2, 55, .35, 64)),
    15: ((0, 62, .70, 74),),
    # Door choice is tense and unfinished; the flat second is a brief glance.
    16: ((2, 57, .25, 63), (3, 62, .25, 67)),
    18: ((0, 62, .25, 67), (1, 63, .18, 62), (3, 62, .30, 66)),
    19: ((2, 64, .35, 69), (3.5, 62, .20, 66)),
    # Second fight: new upward A/C/D/F/D call, then a different bass answer.
    20: ((0, 57, .32, 87), (.5, 60, .20, 81), (1, 62, .35, 89),
         (2, 65, .35, 92), (3, 62, .35, 88)),
    22: ((0, 63, .35, 91), (.5, 62, .18, 80), (1, 55, .40, 81),
         (2, 63, .35, 90), (3, 62, .25, 84)),
    23: ((0, 62, .60, 90), (1.5, 57, .25, 79), (3, 60, .25, 83)),
    24: ((0, 60, .35, 89), (.5, 55, .25, 78), (1, 60, .30, 85),
         (2, 62, .30, 88), (3, 64, .25, 91)),
    25: ((0, 55, .60, 84), (2, 60, .40, 88)),
    26: ((0, 62, .25, 92), (.5, 65, .25, 90), (1, 64, .25, 84),
         (1.5, 62, .25, 87), (2, 57, .60, 83)),
    27: ((0, 64, .25, 91), (.5, 65, .18, 83), (.75, 64, .25, 87),
         (1.5, 59, .35, 81), (3, 52, .35, 80)),
    # Opening identity returns, but a shorter answer pushes toward the peak.
    28: ((0, 62, .35, 93), (.75, 57, .20, 81), (1, 60, .32, 86),
         (1.5, 63, .18, 83), (2, 62, .60, 95)),
    29: ((0, 60, .25, 84), (.5, 62, .60, 90)),
    30: ((0, 63, .35, 91), (.75, 62, .35, 85), (1.5, 60, .25, 81),
         (3, 55, .40, 79)),
    31: ((0, 64, .25, 92), (.5, 65, .25, 88), (1, 67, .40, 95),
         (2.5, 64, .40, 88), (3.5, 62, .25, 83)),
    32: ((0, 62, .35, 93), (.75, 65, .22, 89), (1.5, 62, .35, 87),
         (2, 57, .40, 81), (3, 60, .25, 84)),
    33: ((0, 60, .50, 87), (2, 55, .35, 79)),
    34: ((0, 62, .35, 92), (.75, 60, .25, 83), (1.5, 57, .35, 80),
         (2.5, 62, .65, 93)),
    35: ((0, 62, .60, 88),),
    # The second reward remembers the new call instead of repeating the first.
    36: ((.5, 57, .50, 69), (1.5, 60, .30, 71), (2.5, 62, .60, 77)),
    38: ((1, 60, .45, 70), (3, 55, .25, 64)),
    39: ((0, 62, .70, 74),),
    40: ((1, 63, .25, 66), (2, 62, .35, 69)),
    41: ((0, 62, .65, 71),),
    # Sparse fragments keep the final corridor alive without a high chime.
    42: ((2, 57, .35, 62),),
    43: ((0, 52, .45, 64), (3, 64, .20, 67)),
    44: ((1, 62, .30, 66), (3, 57, .25, 62)),
    45: ((2, 63, .40, 66),),
    46: ((1, 64, .30, 67), (3.5, 62, .18, 64)),
    47: ((0, 62, .65, 69),),
}

_DEBRIS = {
    3: ((3.5, 37, .18, 53),),
    7: ((0, 39, .30, 66),),
    11: ((3.5, 46, .45, 57),),
    19: ((3, 37, .20, 55),),
    23: ((3.5, 39, .25, 58),),
    27: ((3.75, 37, .20, 58),),
    31: ((0, 39, .30, 70),),
    35: ((3, 46, .55, 61),),
    41: ((3, 37, .20, 49),),
    47: ((3, 46, .50, 50),),
}


def score():
    """Return the five aligned original performance roles."""
    parts = {role: [] for role in ("base", "bass", "hook", "drums", "debris")}

    def add(role, bar, onset, pitch, duration, velocity):
        parts[role].append((bar * BEATS_PER_BAR + onset, pitch, duration, velocity))

    base_next_bar = 0
    for bar, root in enumerate(ROOTS):
        fighting = bar < 12 or 20 <= bar < 36
        second_fight = 20 <= bar < 36
        reward = 12 <= bar < 16 or 36 <= bar < 42

        # Renew the texture on a change, a chapter entrance, or after two
        # unchanged bars. Sparse low fifths create grit, not a chordal wash.
        entrance = bar in (0, 12, 16, 20, 36, 42)
        changed = bar == 0 or ROOTS[bar - 1] != root
        refresh = bar >= base_next_bar
        if entrance or changed or refresh:
            available = 1
            while (bar + available < BARS
                   and ROOTS[bar + available] == root
                   and bar + available not in (12, 16, 20, 36, 42)):
                available += 1
            duration = min(available * 4 - .40, 6.0)
            base_next_bar = bar + min(available, 2)
            velocity = 53 if fighting else (45 if reward else 41)
            for voice, pitch in enumerate(_DYADS[root]):
                add("base", bar, voice * .06, pitch, duration - voice * .08,
                    velocity - voice * 8)

        pitches = {"r": root, "f": root + 7,
                   "n": 36 if root == 38 else 38, "b": root + 1}
        for onset, pitch_name, duration, velocity in _BASS_CELLS[_BASS_FORM[bar]]:
            add("bass", bar, onset, pitches[pitch_name], duration, velocity)

        for onset, pitch, duration, velocity in _HOOK.get(bar, ()):
            add("hook", bar, onset, pitch, duration, velocity)

        # A solid half-time beat: snare on beat 2, with a few grounded kick
        # answers. Quieter chapters have their own sparse performance; the
        # renderer can also remove this role entirely in a selection scene.
        phrase_stop = bar in (11, 19, 35, 41, 47)
        kick_velocity = 108 if second_fight else (102 if fighting else 72)
        snare_velocity = 101 if second_fight else (95 if fighting else 65)
        add("drums", bar, 0, 36, .30, kick_velocity)
        if not phrase_stop:
            if fighting and bar % 8 in (0, 2, 4, 6):
                add("drums", bar, 1, 36, .24, kick_velocity - 15)
            if fighting and bar % 8 in (1, 2, 4, 5):
                add("drums", bar, 3, 36, .24, kick_velocity - 12)
            if bar in (6, 10, 26, 34):
                add("drums", bar, 3.5, 36, .20, kick_velocity - 19)
            if bar in (22, 23, 30, 31):
                for onset in (1, 3):
                    add("drums", bar, onset, 38, .24, snare_velocity - 6)
            else:
                add("drums", bar, 2, 38, .28, snare_velocity)

            if fighting:
                hat_beats = (0, .5, 1, 1.5, 2, 2.5, 3, 3.5) if bar in (
                    0, 8, 20, 24, 28, 32) else (0, 1, 2, 3)
                for index, onset in enumerate(hat_beats):
                    add("drums", bar, onset, 42, .09, 46 if index % 2 == 0 else 34)
            elif reward and bar % 2 == 0:
                add("drums", bar, 3, 42, .10, 30)

        if bar in (0, 20, 28):
            add("drums", bar, 0, 49, 1.35, 64 if bar != 28 else 69)
        if bar in (10, 34):
            add("drums", bar, 3.5, 38, .15, snare_velocity - 24)
            add("drums", bar, 3.75, 38, .15, snare_velocity - 17)

        for onset, pitch, duration, velocity in _DEBRIS.get(bar, ()):
            add("debris", bar, onset, pitch, duration, velocity)

    return parts
