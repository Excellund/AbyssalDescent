#!/usr/bin/env python3
"""Render an original scenario-transition audition with aligned sampled stems.

Offline listening prototype only. Requires NumPy, FFmpeg, FluidSynth and a
user-supplied GeneralUser GS bank. No game assets or player data are modified.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

import numpy as np

from action_scenario_score import (BPM, BARS, SETTINGS, RESTRAINED_SETTINGS,
                                   score, restrained_score)
from create_sampled_texture_study import TICKS, RATE, variable_length, write_wav

ROOT = Path(__file__).resolve().parents[2]
TEMPO_US = round(60_000_000 / BPM)
BEAT = TEMPO_US / 1_000_000
TOTAL_BEATS = BARS * 4
TAIL = 2.6
FRAMES = round((TOTAL_BEATS * BEAT + TAIL) * RATE)
NAME = 'action-scenario-study'

# Same musical timeline throughout. Quiet sections retain the musical identity;
# the rhythm section and denser orchestration carry rising threat.
SCENES = [
    {'name': 'exploration', 'beat': 0, 'gains': {
        'guitar_ostinato': 1.0, 'bass': .48, 'strings': .22,
        'violin_lead': .40, 'overdrive': 0.0, 'drums': .17,
        'toms': .25, 'harmonics': .85}},
    {'name': 'combat', 'beat': 32, 'gains': {
        'guitar_ostinato': .85, 'bass': .95, 'strings': .78,
        'violin_lead': 1.0, 'overdrive': .36, 'drums': .85,
        'toms': .55, 'harmonics': .30}},
    {'name': 'climax', 'beat': 64, 'gains': {
        'guitar_ostinato': .70, 'bass': 1.0, 'strings': 1.0,
        'violin_lead': 1.05, 'overdrive': 1.0, 'drums': 1.0,
        'toms': 1.0, 'harmonics': .15}},
    {'name': 'reward', 'beat': 96, 'gains': {
        'guitar_ostinato': .60, 'bass': .28, 'strings': .30,
        'violin_lead': .46, 'overdrive': 0.0, 'drums': .07,
        'toms': 0.0, 'harmonics': 1.0}},
]

# Instrument-specific cleanup; no shared echo or bass-heavy oscillator layer.
FILTERS = {
    'guitar_ostinato': 'highpass=f=140,lowpass=f=6800',
    'bass': 'highpass=f=42,lowpass=f=2400',
    'strings': 'highpass=f=190,lowpass=f=8800',
    'violin_lead': 'highpass=f=270,lowpass=f=7800',
    'overdrive': 'highpass=f=170,lowpass=f=5300',
    'drums': 'highpass=f=36,lowpass=f=12500',
    'toms': 'highpass=f=58,lowpass=f=7500',
    'harmonics': 'highpass=f=380,lowpass=f=8600',
}

RESTRAINED_FILTERS = {
    **FILTERS,
    'guitar_ostinato': 'highpass=f=150,lowpass=f=4800',
    'bass': 'highpass=f=42,lowpass=f=1700',
    'strings': 'highpass=f=190,lowpass=f=6500',
    'violin_lead': 'highpass=f=160,equalizer=f=3000:t=q:w=0.8:g=-3.5,lowpass=f=5500',
    'overdrive': 'highpass=f=170,lowpass=f=4600',
    'harmonics': 'highpass=f=380,lowpass=f=6400',
}


def run(command, data=None):
    result = subprocess.run([str(v) for v in command], input=data,
                            capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
    return result


def midi_file(events, channel, program, pan, reverb):
    messages = [(0, 0, b'\xff\x51\x03' + TEMPO_US.to_bytes(3, 'big')),
                (0, 1, bytes([0xB0 | channel, 0, 0])),
                (0, 2, bytes([0xC0 | channel, program]))]
    for control, value in [(7, 100), (11, 100), (10, pan), (91, reverb), (93, 0)]:
        messages.append((0, 3, bytes([0xB0 | channel, control, value])))
    for beat, note, duration, velocity in events:
        onset = max(1, round(beat * TICKS))
        end = onset + max(1, round(duration * TICKS))
        messages.append((onset, 5, bytes([0x90 | channel, note, velocity])))
        messages.append((end, 4, bytes([0x80 | channel, note, 0])))
    last_tick = max(TOTAL_BEATS * TICKS, max(t for t, _, _ in messages))
    messages.append((last_tick, 9, b'\xff\x2f\x00'))
    body, previous = bytearray(), 0
    for tick, _, message in sorted(messages, key=lambda e: (e[0], e[1])):
        body.extend(variable_length(tick - previous))
        body.extend(message)
        previous = tick
    return (b'MThd' + struct.pack('>IHHH', 6, 0, 1, TICKS)
            + b'MTrk' + struct.pack('>I', len(body)) + body)


def validate_score(parts, settings=SETTINGS, filters=FILTERS):
    assert set(parts) == set(settings) == set(filters)
    notes = 0
    for name, events in parts.items():
        assert events, f'Empty part: {name}'
        last_end = {}
        for onset, pitch, duration, velocity in sorted(events):
            assert 0 <= onset < TOTAL_BEATS and 0 < duration
            assert onset + duration <= TOTAL_BEATS, (name, onset, duration)
            assert 0 <= pitch <= 127 and 1 <= velocity <= 127
            assert abs(onset * 4 - round(onset * 4)) < 1e-8, (name, onset)
            assert onset >= last_end.get(pitch, -1) - 1e-8, (name, pitch, onset)
            last_end[pitch] = onset + duration
            notes += 1
        assert set(SCENES[0]['gains']) == set(parts)
    return {'note_events': notes, 'instruments': len(parts),
            'score_bounds': 'passed', 'sixteenth_grid': 'passed',
            'same_pitch_note_overlap': 'none'}


def frame(beat):
    return round(beat * BEAT * RATE)


def envelope(role):
    env = np.full(FRAMES, SCENES[0]['gains'][role], dtype=np.float64)
    previous = SCENES[0]['gains'][role]
    for scene in SCENES[1:]:
        # Threat layers build through the preceding bar and arrive together.
        # The reward lets the arrival ring before settling over the next bar.
        start_beat = scene['beat'] - 4 if scene['name'] != 'reward' else scene['beat']
        start, end = frame(start_beat), frame(start_beat + 4)
        amount = np.linspace(0, 1, end - start, endpoint=False)
        amount = amount * amount * (3 - 2 * amount)
        target = scene['gains'][role]
        env[start:end] = previous + (target - previous) * amount
        env[end:] = target
        previous = target
    return env


def measure(ffmpeg, path):
    result = run([ffmpeg, '-hide_banner', '-nostdin', '-i', path, '-af',
                  'loudnorm=I=-18:TP=-2.3:LRA=11:print_format=json',
                  '-f', 'null', '-'])
    values = json.loads(re.findall(rb'\{[^{}]+\}', result.stderr)[-1])
    return {key: float(values[key]) for key in ['input_i', 'input_tp', 'input_lra']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fluidsynth', type=Path, required=True)
    parser.add_argument('--soundfont', type=Path, required=True)
    parser.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
    parser.add_argument('--revision', choices=['original', 'restrained'], default='original')
    args = parser.parse_args()
    for path in [args.fluidsynth, args.soundfont]:
        if not path.is_file():
            parser.error(f'Missing file: {path}')
    if not args.ffmpeg:
        parser.error('FFmpeg is required')
    revised = args.revision == 'restrained'
    parts = restrained_score() if revised else score()
    settings = RESTRAINED_SETTINGS if revised else SETTINGS
    filters = RESTRAINED_FILTERS if revised else FILTERS
    name = 'action-scenario-refined' if revised else NAME
    title = 'AbyssalDescent - Action Scenario ' + ('Refined' if revised else 'Study')
    checks = validate_score(parts, settings, filters)
    output = ROOT / 'tools/audio/examples' / name
    output.mkdir(parents=True, exist_ok=True)
    (output.parent / '.gdignore').write_text('')
    stems_path = output / 'stems'
    stems_path.mkdir(exist_ok=True)
    stems, report = {}, {'title': title, 'revision': args.revision,
        'bpm': BPM, 'tempo_microseconds': TEMPO_US, 'meter': [4, 4],
        'bars': BARS, 'harmonic_cycle_bars': 8, 'sample_rate': RATE,
        'frames': FRAMES, 'duration_seconds': round(FRAMES / RATE, 6),
        'tail_seconds': TAIL, 'loop_ready': False, 'runtime_integrated': False,
        'soundfont_sha256': hashlib.sha256(args.soundfont.read_bytes()).hexdigest(),
        'checks': checks, 'parts': {}, 'scenes': [], 'transitions': []}
    for scene in SCENES:
        report['scenes'].append({**scene, 'time_seconds': round(scene['beat'] * BEAT, 6),
                                 'frame': frame(scene['beat'])})
        if scene['beat']:
            start = scene['beat'] - 4 if scene['name'] != 'reward' else scene['beat']
            report['transitions'].append({'to': scene['name'], 'start_beat': start,
                'end_beat': start + 4, 'curve': 'smoothstep_amplitude'})
    with tempfile.TemporaryDirectory(prefix='abyssal-action-stems-') as temp_dir:
        temporary = Path(temp_dir)
        for role, events in parts.items():
            channel, program, pan, reverb, target_rms = settings[role]
            midi = output / f'{role}.mid'
            midi.write_bytes(midi_file(events, channel, program, pan, reverb))
            rendered = temporary / f'{role}.wav'
            result = run([args.fluidsynth, '-ni', '-C', '0', '-R', '1', '-g', '.5',
                '-r', RATE, '-T', 'wav', '-O', 'float', '-o', 'synth.reverb.room-size=0.34',
                '-o', 'synth.reverb.damp=0.72', '-o', 'synth.reverb.level=0.25',
                '-o', 'synth.reverb.width=0.85', '-F', rendered, args.soundfont, midi])
            log = result.stdout + result.stderr
            (output / f'{role}-render.log').write_bytes(log)
            assert not re.search(rb'warning|error|failed', log, re.I), log[-1500:]
            raw = run([args.ffmpeg, '-v', 'error', '-nostdin', '-i', rendered,
                '-af', filters[role], '-ar', RATE, '-ac', '2', '-f', 'f32le', '-']).stdout
            samples = np.frombuffer(raw, dtype='<f4').reshape(-1, 2).astype(np.float64)
            energy = np.mean(samples ** 2, axis=1)
            active = energy > max(float(energy.max()) * 1e-4, 1e-12)
            assert active.any(), f'Silent stem: {role}'
            rms = float(np.sqrt(np.mean(energy[active])))
            gain = 10 ** (target_rms / 20) / rms
            aligned = np.zeros((FRAMES, 2), dtype=np.float64)
            count = min(FRAMES, len(samples))
            aligned[:count] = samples[:count] * gain
            stems[role] = aligned
            report['parts'][role] = {'program_zero_based': program, 'channel': channel + 1,
                'pan': pan, 'reverb_send': reverb, 'note_count': len(events),
                'target_active_rms_dbfs': target_rms, 'balance_gain_db': 20 * math.log10(gain),
                'filter': filters[role], 'aligned_frames': FRAMES}
            print(f'Rendered {role}: {len(events)} notes', flush=True)
        mix = np.zeros((FRAMES, 2), dtype=np.float64)
        outer = np.ones(FRAMES, dtype=np.float64)
        fade_in, fade_out = round(.008 * RATE), round(1.5 * RATE)
        outer[:fade_in] = np.linspace(0, 1, fade_in)
        outer[-fade_out:] = np.linspace(1, 0, fade_out)
        for role, samples in stems.items():
            mix += samples * envelope(role)[:, None]
        mix *= outer[:, None]
        # A single static gain for the complete bundle retains scenario dynamics.
        # Measure with temporary headroom, then undo that scale in the gain math.
        probe_gain = min(1.0, .80 / max(float(np.abs(mix).max()), 1e-10))
        probe = temporary / 'probe.wav'
        write_wav(probe, mix * probe_gain)
        measured = measure(args.ffmpeg, probe)
        gain_db = min(-18 - measured['input_i'], -2.3 - measured['input_tp'])
        master_gain = probe_gain * 10 ** (gain_db / 20)
        report['common_master_gain_db'] = 20 * math.log10(master_gain)
        final = output / f'{name}.wav'
        mastered = mix * master_gain
        write_wav(final, mastered)
        run([args.ffmpeg, '-v', 'error', '-nostdin', '-y', '-i', final,
             '-c:a', 'libmp3lame', '-b:a', '256k', '-metadata',
             'title=' + title, output / f'{name}.mp3'])
        # Aligned lossless stems include the fixed tail window and common gain.
        # Reconstruct the audition by applying the documented scene envelopes
        # plus the audition's outer fade. These full-length files are not loops.
        for role, samples in stems.items():
            stem_samples = samples * master_gain
            assert np.max(np.abs(stem_samples)) < 1, f'Stem clips: {role}'
            run([args.ffmpeg, '-v', 'error', '-nostdin', '-y', '-f', 'f32le',
                 '-ar', RATE, '-ac', '2', '-i', 'pipe:0', '-c:a', 'flac',
                 '-sample_fmt', 's32', '-bits_per_raw_sample', '24',
                 stems_path / f'{role}.flac'], stem_samples.astype('<f4').tobytes())
        report['final_loudness'] = measure(args.ffmpeg, final)
        report['checks']['clipped_samples'] = int(np.count_nonzero(np.abs(mastered) >= 1))
        report['checks']['peak_sample_step'] = float(np.max(np.abs(np.diff(mastered, axis=0))))
        # Descriptive measurements only; individual boundary samples do not
        # establish whether a transition is perceptually seamless.
        report['checks']['transition_sample_steps'] = {}
        for transition in report['transitions']:
            for edge in ['start_beat', 'end_beat']:
                idx = frame(transition[edge])
                report['checks']['transition_sample_steps'][str(transition[edge])] = float(
                    np.max(np.abs(mastered[idx] - mastered[idx - 1])))
        report['scene_rms_dbfs'] = {}
        for index, scene in enumerate(SCENES):
            end_beat = SCENES[index + 1]['beat'] if index + 1 < len(SCENES) else TOTAL_BEATS
            excerpt = mastered[frame(scene['beat']):frame(end_beat)]
            report['scene_rms_dbfs'][scene['name']] = 20 * math.log10(float(np.sqrt(np.mean(excerpt ** 2))))
        assert report['checks']['clipped_samples'] == 0
        assert report['final_loudness']['input_tp'] <= -2.1
        assert np.isfinite(mastered).all()
    (output / 'render-report.json').write_text(json.dumps(report, indent=2) + '\n')
    (output / 'score.json').write_text(json.dumps(parts, separators=(',', ':')) + '\n')
    print(json.dumps({'path': str(final), 'loudness': report['final_loudness'],
                      'checks': report['checks'], 'scene_rms': report['scene_rms_dbfs']}, indent=2))


if __name__ == '__main__':
    main()
