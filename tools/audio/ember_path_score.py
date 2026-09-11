"""Original 128-second orchestral action suite on one adaptive musical clock.

All five roles share 64 bars at 120 BPM. The renderer can change their gains
for combat, rewards and doors without changing harmony or musical position.
The score itself has an opening theme, a changed answer, a quiet inner phrase,
a contrasting theme and a developed reprise. It is not an eight-bar loop
repeated with different instruments.

The horn has substantial written silence; viola answers occupy some of that
space. Motion uses at most four attacks per bar and stops at phrase endings.
There are no guitar, mallet, piano, pizzicato or exposed violin parts. The
final open D prepares the first D without a composed terminal fade.

Events are (absolute beat, MIDI pitch, duration in beats, velocity). Sustained
notes remain at or below 3.5 beats, leaving the sampler to preserve release
tails. Drum pitches are 36 bass drum, 38 orchestral snare, 49 suspended cymbal.
"""

from dataclasses import dataclass

BPM = 120
BARS = 64
BEATS_PER_BAR = 4


@dataclass(frozen=True)
class Chord:
    name: str
    root: int
    pitch_classes: tuple[int, ...]
    foundation: tuple[int, int]


_CHORDS = {
    "D": Chord("D(add9)", 50, (2, 6, 9, 4), (50, 57)),
    "C": Chord("C(add9)", 48, (0, 4, 7, 2), (48, 55)),
    "G": Chord("G(add6)", 55, (7, 11, 2, 4), (55, 62)),
    "D/F#": Chord("D/F#", 50, (2, 6, 9, 4), (54, 62)),
    "G/D": Chord("G/D", 55, (7, 11, 2, 4), (50, 55)),
    "G/B": Chord("G/B", 55, (7, 11, 2, 4), (59, 62)),
    "Em": Chord("Em7", 52, (4, 7, 11, 2), (52, 59)),
    "D/A": Chord("D/A", 50, (2, 6, 9, 4), (57, 62)),
    "As": Chord("A(sus4,add9)", 57, (9, 2, 4, 11), (52, 57)),
}

_HARMONIC_PHRASES = (
    ("D", "D", "C", "G", "D/F#", "G", "C", "As"),
    ("D", "G/D", "C", "G/B", "Em", "G", "As", "D"),
    ("G", "D/F#", "Em", "D/A", "C", "G/B", "As", "D"),
    ("C", "G", "D", "D", "C", "G", "As", "As"),
    ("Em", "G", "D", "As", "C", "G", "D/F#", "As"),
    ("D", "C", "G/B", "As", "D/F#", "G", "As", "D"),
    ("G", "D/F#", "Em", "G", "C", "G/B", "As", "D"),
    ("C", "G", "D/A", "D", "G", "C", "As", "D"),
)
HARMONY = tuple(_CHORDS[name] for phrase in _HARMONIC_PHRASES for name in phrase)

# Each entry is one bar: local beat, pitch, duration, velocity. Pitches are
# authored at D4-D5 for legibility, then the complete horn line is moved one
# octave down in score(). This keeps the real horn samples in their coherent
# D3-D4 range without folding individual melodic peaks into another octave.
# Empty bars are intentional breathing room, not a request to reuse a bar.
_THEME = (
    # 1-8: A. The rising D/F#/E/A gesture has a clear, unhurried landing.
    ((0, 62, .88, 77), (1, 66, .40, 73), (1.5, 64, .40, 69), (2, 69, 1.65, 82)),
    ((0, 66, 1.35, 77), (1.5, 64, .40, 70), (2, 62, .85, 74)),
    ((0, 64, .85, 75), (1, 67, .85, 78), (2, 69, 1.35, 80)),
    ((0, 71, 1.70, 84), (2, 67, .85, 75)),
    ((0, 69, 1.35, 79), (1.5, 66, .85, 75), (2.5, 62, .75, 72)),
    ((0, 67, 1.65, 76), (2, 71, .85, 80), (3, 69, .40, 73)),
    ((0, 67, .85, 76), (1, 64, 1.25, 72), (2.5, 62, .45, 68)),
    ((0, 64, 2.35, 74),),
    # 9-16: A answers itself with wider arcs and a new cadence.
    ((0, 62, 1.35, 77), (2, 69, 1.35, 82)),
    ((0, 67, .85, 79), (1, 69, .40, 75), (1.5, 71, .85, 80), (2.5, 74, .85, 85)),
    ((0, 72, 1.35, 84), (1.5, 67, .75, 78), (2.5, 64, .85, 74)),
    ((0, 71, 2.15, 82), (2.5, 69, .65, 75)),
    ((0, 64, .90, 75), (1, 67, .90, 79), (2, 71, .85, 83)),
    ((0, 69, .45, 77), (.5, 67, .85, 74), (1.5, 62, 1.40, 71)),
    ((0, 64, .90, 75), (1, 69, 1.75, 81)),
    ((0, 62, 2.65, 77),),
    # 17-24: The viola takes the foreground; the horn returns as a warm answer.
    (), (), (), (),
    ((.5, 64, 1.45, 66), (2, 67, 1.15, 71)),
    ((0, 62, .90, 66), (1, 67, .90, 68), (2, 71, .90, 72)),
    ((0, 64, 1.55, 68), (2, 62, .75, 65)),
    ((0, 66, .85, 72), (1, 64, .45, 67), (1.5, 62, 1.75, 70)),
    # 25-32: Short remembered fragments, with entire bars left open.
    (),
    ((.5, 62, 1.55, 64), (2.5, 67, .85, 68)),
    ((.5, 69, 2.05, 69),),
    (),
    ((.5, 67, 1.75, 67), (2.5, 64, .75, 63)),
    (),
    ((0, 69, .85, 70), (1, 64, 1.55, 66)),
    (),
    # 33-40: B enters from below, climbs through a new contour, then breathes.
    ((0, 62, .85, 77), (1, 64, .85, 81), (2, 67, 1.25, 85)),
    ((0, 62, .45, 77), (.5, 67, .85, 82), (1.5, 71, 1.45, 87)),
    ((0, 69, 1.75, 84), (2, 66, .85, 78)),
    ((0, 64, .85, 77), (1, 69, .85, 83), (2, 71, .85, 86)),
    ((0, 72, .95, 88), (1, 67, .45, 81), (1.5, 64, .45, 77), (2, 67, .85, 82)),
    ((0, 71, 1.45, 86), (1.5, 69, .45, 80), (2, 67, .85, 77)),
    ((0, 66, .85, 81), (1, 69, .85, 85), (2, 74, 1.45, 90)),
    ((0, 64, 2.75, 79),),
    # 41-48: A is recognizable, but its contour and answer reach a new peak.
    ((0, 62, .85, 79), (1, 66, .45, 76), (1.5, 64, .45, 72),
     (2, 69, .85, 85), (3, 74, .45, 88)),
    ((0, 72, 1.35, 86), (1.5, 69, .45, 79), (2, 67, .95, 77)),
    ((0, 71, 1.35, 84), (1.5, 69, .45, 77), (2, 67, .95, 75)),
    ((0, 69, .85, 81), (1, 64, .85, 75), (2, 69, 1.25, 84)),
    ((0, 74, 1.65, 91), (2, 69, .85, 83), (3, 66, .45, 77)),
    ((0, 71, .85, 84), (1, 69, .85, 80), (2, 67, 1.25, 78)),
    ((0, 69, 1.45, 82), (2, 64, .85, 75)),
    ((0, 62, 2.75, 79),),
    # 49-56: A second release has a different viola phrase and horn response.
    (), (), (), (),
    ((0, 67, 1.35, 70), (1.5, 64, .85, 66), (2.5, 62, .45, 63)),
    ((0, 62, 1.45, 66), (1.5, 67, .85, 68), (2.5, 71, .75, 71)),
    ((0, 64, 1.45, 68), (2, 69, .85, 73)),
    ((0, 66, .85, 71), (1, 64, .45, 66), (1.5, 62, 1.75, 69)),
    # 57-64: A poised, open ending which can meet bar one without a restart.
    (),
    ((.5, 62, 1.75, 64), (2.5, 67, .85, 68)),
    ((.5, 69, 2.45, 69),),
    (),
    ((.5, 67, 1.55, 67), (2.5, 62, .85, 63)),
    ((0, 64, 1.75, 65), (2, 62, .45, 62)),
    ((0, 64, 1.65, 66), (2, 69, .85, 70)),
    ((0, 62, 2.75, 68),),
)

# The counterline is deliberately not a chord arpeggiator. Longer phrases
# come forward when the horn rests; combat answers tend to occupy its gaps.
_ANSWER = {
    1: ((3, 69, .85, 57),),
    3: ((3, 62, .85, 56),),
    5: ((3.5, 67, .40, 56),),
    7: ((2.5, 69, .60, 58), (3.25, 64, .60, 54)),
    8: ((3.5, 66, .40, 56),),
    10: ((3.5, 67, .40, 57),),
    11: ((3.25, 67, .60, 56),),
    13: ((3, 67, .85, 58),),
    15: ((2.75, 69, 1.10, 59),),
    16: ((0, 67, 1.65, 68), (2, 71, 1.65, 72)),
    17: ((0, 69, 2.65, 70), (3, 66, .75, 65)),
    18: ((0, 67, 1.65, 67), (2, 71, 1.15, 71)),
    19: ((0, 69, 1.15, 68), (1.5, 66, .85, 65), (2.5, 64, .90, 62)),
    20: ((0, 60, 1.65, 56), (2.5, 64, 1.10, 58)),
    21: ((3, 62, .80, 55),),
    22: ((2.75, 69, 1.00, 60),),
    23: ((3.25, 69, .60, 56),),
    24: ((0, 64, 2.65, 62), (3, 67, .75, 60)),
    25: ((0, 71, 1.15, 60),),
    26: ((3, 66, .75, 57),),
    27: ((0, 64, 1.65, 59), (2, 69, 1.35, 63)),
    28: ((0, 60, 1.15, 57),),
    29: ((0, 62, 1.65, 58), (2, 67, 1.15, 62)),
    30: ((3, 69, .80, 59),),
    31: ((0, 64, 1.35, 60), (2, 62, 1.35, 57)),
    33: ((3.25, 67, .60, 61),),
    34: ((3, 62, .85, 59),),
    35: ((3, 64, .85, 60),),
    37: ((3, 62, .85, 60),),
    39: ((2.75, 69, 1.10, 63),),
    40: ((3.5, 66, .40, 60),),
    41: ((3.25, 64, .60, 59),),
    42: ((3.25, 62, .60, 60),),
    43: ((3.5, 64, .40, 59),),
    45: ((3.5, 62, .40, 58),),
    46: ((3, 69, .85, 63),),
    47: ((2.75, 69, 1.10, 61),),
    48: ((0, 71, 1.65, 73), (2, 67, 1.15, 68)),
    49: ((0, 66, 1.15, 67), (1.5, 69, 1.65, 71)),
    50: ((0, 71, 1.15, 71), (1.5, 67, 1.15, 67), (3, 64, .70, 63)),
    51: ((0, 62, 1.65, 65), (2, 67, 1.35, 69)),
    52: ((3, 60, .80, 57),),
    53: ((0, 62, 1.15, 56),),
    54: ((3, 64, .80, 59),),
    55: ((3.25, 69, .60, 57),),
    56: ((0, 67, 1.65, 63), (2, 64, 1.15, 59)),
    57: ((0, 71, 1.15, 60),),
    58: ((3, 66, .80, 58),),
    59: ((0, 64, 1.65, 59), (2, 69, 1.35, 63)),
    60: ((0, 71, 1.15, 60),),
    61: ((2.75, 67, 1.00, 60),),
    62: ((3, 64, .80, 58),),
    63: ((0, 69, 3.30, 59),),
}

# onset, duration, which foundation pitch, velocity accent. These are grounded
# quarter-note gestures, with changed lengths and real space between them.
_MOTION_CELLS = (
    ((0, .62, 0, 8), (1, .36, 0, -7), (2, .62, 1, 3), (3, .36, 0, -9)),
    ((0, .78, 0, 7), (2, .56, 0, 1), (3, .33, 1, -8)),
    ((0, .55, 0, 6), (1, .45, 1, -5), (2, .83, 0, 2)),
    ((0, .70, 0, 5), (2, .62, 1, -3)),
    ((0, .73, 0, 8), (1, .34, 1, -6), (2, .55, 0, 3), (3, .33, 0, -8)),
    ((0, .57, 0, 7), (1, .34, 1, -5), (2, .61, 0, 1)),
    ((0, .82, 0, 6), (2, .75, 1, -2)),
    (),
)


def score():
    """Return the five phase-aligned orchestral roles as plain note events."""
    parts = {name: [] for name in ("foundation", "motion", "theme", "answer", "drums")}

    def add(role, bar, onset, pitch, duration, velocity):
        parts[role].append((bar * BEATS_PER_BAR + onset, pitch, duration, velocity))

    for bar, chord in enumerate(HARMONY):
        cell = bar % 8
        section = bar // 8

        # Two separated cello voices leave room for the actual melodic color.
        # Their attacks breathe without an abrupt end-of-bar stop in the mix;
        # the natural release tails remain the renderer's responsibility.
        foundation_velocity = (60, 61, 54, 50, 64, 65, 55, 51)[section]
        duration = 3.5 if cell not in (3, 7) else (3.2 if cell == 3 else 3.0)
        add("foundation", bar, 0, chord.foundation[0], duration, foundation_velocity)
        add("foundation", bar, .12, chord.foundation[1], duration - .18,
            foundation_velocity - 7)

        pattern = _MOTION_CELLS[cell]
        # The inner phrases have more open space, not merely a lower velocity.
        if section in (2, 6) and cell not in (0, 4, 7):
            pattern = _MOTION_CELLS[6 if cell % 2 else 3]
        elif section in (3, 7) and cell != 7:
            pattern = _MOTION_CELLS[3] if cell % 2 == 0 else ((0, .72, 0, 4),)
        elif section == 5 and cell in (1, 5):
            pattern = _MOTION_CELLS[4]
        motion_velocity = (71, 74, 61, 57, 77, 80, 62, 58)[section]
        for onset, length, voice, accent in pattern:
            add("motion", bar, onset, chord.foundation[voice], length,
                motion_velocity + accent)

        for onset, pitch, length, velocity in _THEME[bar]:
            add("theme", bar, onset, pitch - 12, length, velocity)
        for onset, pitch, length, velocity in _ANSWER.get(bar, ()):
            add("answer", bar, onset, pitch, length, velocity)

        # Orchestral weight comes from downbeats, not a busy funk bass/drum
        # pocket. Snare answers vary across the arc, and cymbals mark arrivals.
        drum_velocity = (80, 83, 65, 60, 87, 90, 66, 61)[section]
        add("drums", bar, 0, 36, .72, drum_velocity)
        if cell not in (3, 7):
            add("drums", bar, 2, 36, .60, drum_velocity - 11)
        if cell in (0, 2, 4, 5):
            add("drums", bar, 3, 38, .36, drum_velocity - 20)
        if section in (0, 1, 4, 5) and cell in (1, 4):
            add("drums", bar, 1, 38, .30, drum_velocity - 27)
        if bar in (0, 8, 32, 40, 48):
            add("drums", bar, 0, 49, 3.20, drum_velocity - 23)
        if bar in (14, 30, 46, 62):
            # One modest final-beat lift per sixteen bars. The following bar
            # has a grounded arrival and then space instead of another fill.
            for index in range(4):
                add("drums", bar, 3 + index * .25, 38, .20,
                    drum_velocity - 32 + index * 5)

    return parts
