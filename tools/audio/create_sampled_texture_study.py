#!/usr/bin/env python3
"""Original short piano/strings audition, rendered with a supplied SF2 + FluidSynth.

This produces review artifacts under tools/audio/examples, never game assets.
Requires NumPy, FFmpeg, and a portable FluidSynth >= 2.3 renderer.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import re
import shutil
import struct
import subprocess
import tempfile
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
BPM = 92
BEAT = 60 / BPM
TICKS = 960
RATE = 48000
DURATION = 48 * BEAT + 3.0


def variable_length(value):
    result = [value & 127]
    while value >> 7:
        value >>= 7
        result.insert(0, (value & 127) | 128)
    return bytes(result)


def midi_file(events, channel, program, pan, reverb, bpm=BPM):
    tempo = round(60_000_000 / bpm)
    messages = [(0, b'\xff\x51\x03' + tempo.to_bytes(3, 'big')),
                (0, bytes([0xB0 | channel, 0, 0])),
                (0, bytes([0xC0 | channel, program]))]
    for control, value in [(7, 100), (11, 100), (10, pan), (91, reverb), (93, 0)]:
        messages.append((0, bytes([0xB0 | channel, control, value])))
    for beat, note, length, velocity in events:
        start = max(1, round(beat * TICKS))
        end = start + max(1, round(length * TICKS))
        messages.append((start, bytes([0x90 | channel, note, velocity])))
        messages.append((end, bytes([0x80 | channel, note, 0])))
    messages.append((48 * TICKS, b'\xff\x2f\x00'))
    messages.sort(key=lambda event: event[0])
    body = bytearray()
    previous = 0
    for tick, message in messages:
        body.extend(variable_length(tick - previous))
        body.extend(message)
        previous = tick
    return b'MThd' + struct.pack('>IHHH', 6, 0, 1, TICKS) + b'MTrk' + struct.pack('>I', len(body)) + body


def score():
    # An authored D-minor question/answer: a lift in bars 5–8, then a quieter
    # return and A7–Dm cadence. Lead melody is independent of the accompaniment.
    melody = [
        [(0,74,.8,70),(1,69,.55,57),(1.75,77,1.3,72),(3.25,76,.6,60)],
        [(0,74,1.4,68),(2,69,.55,55),(3,65,.7,50)],
        [(.5,77,.75,66),(1.5,74,.65,60),(2.5,70,1,59)],
        [(.25,67,.65,55),(1,72,.6,60),(2,76,.7,65),(3.25,74,.55,57)],
        [(0,81,.7,74),(.875,77,.625,67),(1.75,76,.7,61),(2.75,74,.9,67)],
        [(0,70,.9,60),(1.25,74,.55,66),(2,79,.8,69),(3.125,77,.625,57)],
        [(.25,74,.7,65),(1.25,77,.65,70),(2.5,81,.9,74)],
        [(0,76,.8,67),(1.125,73,.625,58),(2,69,.65,62),(3.125,73,.6,63)],
        [(0,74,1.5,73),(2,77,.75,62),(3,76,.65,57)],
        [(.5,74,1,63),(2,70,.75,58),(3,65,.55,50)],
        [(.75,76,1,62),(2.25,73,.6,54),(3.125,69,.7,50)],
        [(0,74,3,65),(.035,65,2.8,44),(.06,69,2.7,42)],
    ]
    roots = [50,50,46,48,50,43,46,45,50,46,45,50]
    # Bowed bed occupies a different register from the piano melody; its short
    # releases avoid carrying the preceding harmony into the next chord.
    harmony = [[57,62,65],[57,62,65],[58,62,65],[55,60,64],
               [57,62,65],[55,58,62],[58,62,65],[55,61,64],
               [57,62,65],[58,62,65],[55,61,64],[57,62,65]]
    parts = {'piano': [], 'bowed_strings': [], 'pizzicato': [], 'percussion': []}
    rng = random.Random(581352)
    for bar, notes in enumerate(melody):
        for onset, note, duration, velocity in notes:
            offset = rng.uniform(-.009, .009) / BEAT
            parts['piano'].append((max(0, bar*4+onset+offset), note, duration, velocity))
        if bar >= 2:
            for voice, note in enumerate(harmony[bar]):
                velocity = (40 if bar < 4 else 47 if bar < 8 else 38) + voice*2
                parts['bowed_strings'].append((bar*4+.04+voice*.018, note, 3.48, velocity))
        # Low plucked strings have short purposeful accents and gaps. No sub
        # oscillator or sustained bass is added beneath the sampled instruments.
        if 1 <= bar < 11:
            pattern = [(0,.48,57),(1.5,.32,41),(2.75,.4,48)] if bar % 2 == 0 else [(0,.55,53),(2,.35,43)]
            for index, (onset, duration, velocity) in enumerate(pattern):
                parts['pizzicato'].append((bar*4+onset+.008/BEAT,
                                          roots[bar] + (7 if index == 1 else 0), duration,
                                          velocity + (4 if 4 <= bar < 8 else 0)))
        if 4 <= bar < 8:
            parts['percussion'].append((bar*4, 45, .16, 32 if bar % 2 == 0 else 25))
            parts['percussion'].append((bar*4+2.5, 37, .10, 25))
            if bar == 7:
                parts['percussion'].append((bar*4+3.25, 48, .14, 22))
    return parts


def groove_score():
    # A shared pulse from bar one. The piano uses a recurring eighth-note
    # vocabulary over quarter-note pizzicato and a consistent restrained beat.
    # D-centred open voicings and G major's B-natural replace the earlier Bb/A7
    # minor cadence. This is a separate audition, preserving the first example.
    melody = [
        [(0,74,.38,75),(.5,69,.32,55),(1,74,.38,67),(1.5,76,.38,62),(2,81,.65,77),(3,79,.36,61),(3.5,76,.32,56)],
        [(0,74,.65,71),(1,71,.34,58),(1.5,74,.35,64),(2,79,.65,75),(3,81,.32,61),(3.5,79,.32,66)],
        [(0,79,.38,73),(.5,76,.32,57),(1,74,.38,66),(1.5,76,.38,62),(2,79,.65,74),(3,76,.36,61),(3.5,74,.32,56)],
        [(0,74,.85,73),(1,69,.34,55),(1.5,76,.35,64),(2,74,.65,70),(3,76,.32,59),(3.5,69,.32,54)],
        [(0,74,.38,76),(.5,76,.32,61),(1,81,.38,73),(1.5,79,.38,65),(2,81,.65,79),(3,79,.36,65),(3.5,76,.32,59)],
        [(0,79,.65,75),(1,74,.34,58),(1.5,79,.35,67),(2,83,.65,77),(3,81,.32,64),(3.5,79,.32,61)],
        [(0,79,.38,75),(.5,76,.32,60),(1,74,.38,68),(1.5,76,.38,64),(2,79,.65,76),(3,81,.36,66),(3.5,79,.32,60)],
        [(0,79,.65,74),(1,74,.34,57),(1.5,71,.35,62),(2,74,.65,72),(3,76,.32,61),(3.5,74,.32,57)],
        [(0,74,.38,73),(.5,69,.32,54),(1,74,.38,66),(1.5,76,.38,61),(2,81,.65,75),(3,79,.36,62),(3.5,76,.32,57)],
        [(0,74,.65,70),(1,71,.34,57),(1.5,74,.35,63),(2,79,.65,73),(3,81,.32,60),(3.5,79,.32,63)],
        [(0,79,.38,70),(.5,76,.32,54),(1,74,.38,64),(1.5,76,.38,58),(2,79,.65,71),(3,76,.36,57),(3.5,74,.32,54)],
        [(0,74,.85,70),(1.5,76,.35,56),(2,74,1.4,66),(2,69,1.4,42)],
    ]
    roots = [50,43,48,50,50,43,48,43,50,43,48,50]
    harmony = [[57,62,64],[55,59,62],[55,60,64],[57,62,64],
               [57,62,64],[55,59,62],[55,60,64],[55,59,62],
               [57,62,64],[55,59,62],[55,60,64],[57,62,64]]
    parts = {'piano': [], 'bowed_strings': [], 'pizzicato': [], 'percussion': []}
    for bar, notes in enumerate(melody):
        for onset, note, duration, velocity in notes:
            parts['piano'].append((bar*4+onset,note,duration,velocity))
        # Keep the accompaniment's four-quarter pattern identical across bars;
        # velocity supplies strong/weak accents without displacing the beat.
        if bar < 11:
            for beat, interval, velocity in [(0,0,65),(1,7,43),(2,0,57),(3,7,46)]:
                parts['pizzicato'].append((bar*4+beat,roots[bar]+interval,.34,velocity))
            for beat, note, velocity in [(0,45,38),(1,37,29),(2,45,31),(3,37,33)]:
                parts['percussion'].append((bar*4+beat,note,.15,velocity))
            if bar >= 2:
                for beat, velocity in [(.5,18),(1.5,22),(2.5,17),(3.5,21)]:
                    parts['percussion'].append((bar*4+beat,42,.1,velocity))
        else:
            parts['pizzicato'].append((bar*4,50,.45,57))
            parts['pizzicato'].append((bar*4+2,57,.45,47))
            parts['percussion'].append((bar*4,45,.15,29))
        # Short bowed responses leave room for the rhythm. The first example's
        # sustained wash is not used here, even though the sampled preset stays.
        if 2 <= bar < 11:
            onset = 0 if bar % 2 == 0 else 2
            for voice, note in enumerate(harmony[bar]):
                parts['bowed_strings'].append((bar*4+onset,note,1.45,40+voice*2))
    return parts


def run(command):
    result = subprocess.run([str(value) for value in command], capture_output=True, check=True)
    return result


def loudness(ffmpeg, path):
    result = run([ffmpeg, '-hide_banner', '-nostdin', '-i', path, '-af',
                  'loudnorm=I=-18:TP=-2.3:LRA=11:print_format=json', '-f', 'null', '-'])
    return json.loads(re.findall(rb'\{[^{}]+\}', result.stderr)[-1])


def write_wav(path, samples):
    with wave.open(str(path), 'wb') as stream:
        stream.setnchannels(2)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes((np.clip(samples, -1, 1)*32767).astype('<i2').tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fluidsynth', required=True, type=Path)
    parser.add_argument('--soundfont', required=True, type=Path)
    parser.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
    parser.add_argument('--study', choices=['texture', 'groove'], default='texture')
    args = parser.parse_args()
    is_groove = args.study == 'groove'
    bpm = 108 if is_groove else BPM
    duration = 48 * 60 / bpm + 3.0
    name_prefix = 'piano-strings-groove' if is_groove else 'piano-strings-study'
    output = ROOT / 'tools/audio/examples' / name_prefix
    output.mkdir(parents=True, exist_ok=True)
    (output.parent / '.gdignore').write_text('')
    parts = groove_score() if is_groove else score()
    # GM program indices; individual pan/reverb and intentional relative levels.
    settings = {'piano': (0,0,59,24,-23.5), 'bowed_strings': (1,48,78,42,-31.0),
                'pizzicato': (2,45,47,9,-29.0), 'percussion': (9,0,67,3,-35.0)}
    if is_groove:
        settings = {'piano': (0,0,59,15,-24.0), 'bowed_strings': (1,48,78,25,-32.5),
                    'pizzicato': (2,45,47,5,-27.5), 'percussion': (9,0,67,2,-32.5)}
    mix = np.zeros((round(duration*RATE),2), dtype=np.float64)
    report = {'study': args.study, 'bpm': bpm, 'bars': 12, 'duration_seconds': round(duration,3),
              'soundfont_sha256': hashlib.sha256(args.soundfont.read_bytes()).hexdigest(),
              'parts': {}}
    with tempfile.TemporaryDirectory(prefix='abyssal-sampled-stems-') as temporary:
        temporary = Path(temporary)
        for name, events in parts.items():
            channel, program, pan, reverb, target_rms = settings[name]
            midi = output / (name + '.mid')
            midi.write_bytes(midi_file(events, channel, program, pan, reverb, bpm))
            rendered = temporary / (name + '.wav')
            result = run([args.fluidsynth, '-ni', '-C', '0', '-R', '1', '-g', '.5',
                          '-r', str(RATE), '-T', 'wav', '-O', 'float',
                          '-o', 'synth.reverb.room-size=0.38', '-o', 'synth.reverb.damp=0.65',
                          '-o', 'synth.reverb.level=0.32', '-o', 'synth.reverb.width=0.8',
                          '-F', rendered, args.soundfont, midi])
            (output / (name + '-render.log')).write_bytes(result.stdout + result.stderr)
            decoded = run([args.ffmpeg, '-v', 'error', '-nostdin', '-i', rendered,
                           '-ar', str(RATE), '-ac', '2', '-f', 'f32le', '-']).stdout
            samples = np.frombuffer(decoded,dtype='<f4').reshape(-1,2)
            energy = np.mean(samples**2, axis=1)
            active = energy > max(float(energy.max())*1e-4, 1e-12)
            rms = float(np.sqrt(np.mean(energy[active])))
            gain = 10**(target_rms/20) / max(rms, 1e-10)
            count = min(len(mix),len(samples))
            mix[:count] += samples[:count]*gain
            report['parts'][name] = {'program': program, 'midi_channel': channel+1,
                                      'note_count': len(events), 'reverb_send': reverb,
                                      'target_active_rms_dbfs': target_rms,
                                      'render_gain_db': round(20*math.log10(gain),2)}
        # Preserve the performance envelope; use global level and short outer
        # fades only. Individual instrument sends already establish the space.
        mix *= min(1.0, .88 / max(np.max(np.abs(mix)),1e-10))
        fade = round(.035*RATE)
        mix[:fade] *= np.linspace(0,1,fade)[:,None]
        fade = round(1.5*RATE)
        mix[-fade:] *= np.linspace(1,0,fade)[:,None]
        source = temporary / 'mix.wav'
        write_wav(source,mix)
        measured = loudness(args.ffmpeg,source)
        normalization = ('loudnorm=I=-18:TP=-2.3:LRA=11:linear=true:'
                         f"measured_I={measured['input_i']}:measured_TP={measured['input_tp']}:"
                         f"measured_LRA={measured['input_lra']}:measured_thresh={measured['input_thresh']}:"
                         f"offset={measured['target_offset']}")
        final = output / (name_prefix + '.wav')
        run([args.ffmpeg,'-v','error','-nostdin','-y','-i',source,'-af',normalization,
             '-ar',str(RATE),'-c:a','pcm_s16le',final])
        run([args.ffmpeg,'-v','error','-nostdin','-y','-i',final,'-c:a','libmp3lame','-b:a','256k',
             '-metadata','title=AbyssalDescent - Piano and Strings ' + ('Groove Study' if is_groove else 'Texture Study'),
             output/(name_prefix + '.mp3')])
        report['final_loudness'] = loudness(args.ffmpeg,final)
        with wave.open(str(final),'rb') as stream:
            data = np.frombuffer(stream.readframes(stream.getnframes()),dtype='<i2')
        report['clipped_samples'] = int(np.count_nonzero(np.abs(data.astype(np.int32)) >= 32767))
        assert report['clipped_samples'] == 0, 'Clipped preview samples'
        assert float(report['final_loudness']['input_tp']) < -1.9, 'Preview peak exceeds headroom'
    (output / 'render-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    print(final)


if __name__ == '__main__':
    main()
