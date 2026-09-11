"""Render an original adaptive suite from the pinned CC0 VSCO recordings.

Creates a looping common bed plus three compatible scenario layers, full mixes,
and a guided audition. All natural note releases wrap onto the same loop clock.
No General MIDI patches, oscillator instruments or plucked ostinatos are used.
"""
import argparse
from collections import Counter, defaultdict
from dataclasses import asdict
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess

import numpy as np

from ember_path_score import BPM, BARS, HARMONY, score
from create_action_scenario_study import measure
from create_sampled_texture_study import write_wav

HERE = Path(__file__).resolve().parent
RATE = 48000
BEAT = 60 / BPM
SECONDS = BARS * 4 * BEAT
FRAMES = round(SECONDS * RATE)
OUT = HERE / 'examples/ember-path'
MAP = {'foundation': 'cello_sustain', 'motion': 'cello_spiccato',
       'theme': 'horn_sustain', 'answer': 'viola_sustain'}
DRUMS = {36: 'bass_drum', 38: 'snare', 49: 'cymbal'}
BALANCE = {'foundation': -31.5, 'motion': -31.5, 'theme': -29.0,
           'answer': -31.0, 'drums': -28.5}
FILTERS = {
    'foundation': 'highpass=f=80,lowpass=f=6500',
    'motion': 'highpass=f=110,lowpass=f=6800',
    'theme': 'highpass=f=110,equalizer=f=2900:t=q:w=0.8:g=-2,lowpass=f=6200',
    'answer': 'highpass=f=200,equalizer=f=3100:t=q:w=0.8:g=-2.5,lowpass=f=6500',
    'drums': 'highpass=f=38,lowpass=f=10000',
}
PAN = {'foundation': -.12, 'motion': -.24, 'theme': .12, 'answer': .28, 'drums': 0}
MODES = {
    'combat': {'motion': 1.0, 'theme': 1.0, 'answer': .58, 'drums': 1.0},
    'doors': {'motion': .23, 'theme': .25, 'answer': .55, 'drums': 0.0},
    'reward': {'motion': .04, 'theme': .48, 'answer': 1.0, 'drums': 0.0},
}
JOURNEY = [(0, 'combat'), (32, 'reward'), (48, 'doors'),
           (64, 'combat'), (96, 'reward'), (112, 'doors')]


def run(command, data=None):
    result = subprocess.run([str(x) for x in command], input=data, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout


def decode(ffmpeg, path):
    data = run([ffmpeg, '-v', 'error', '-i', path, '-ar', RATE, '-ac', '2', '-f', 'f32le', '-'])
    return np.frombuffer(data, '<f4').reshape(-1, 2).copy()


def encode(ffmpeg, path, samples, codec):
    args = [ffmpeg, '-v', 'error', '-y', '-f', 'f32le', '-ar', RATE,
            '-ac', '2', '-i', 'pipe:0']
    if codec == 'flac':
        args += ['-c:a', 'flac', '-sample_fmt', 's32', '-bits_per_raw_sample', '24']
    elif codec == 'ogg':
        args += ['-c:a', 'libvorbis', '-q:a', '6']
    elif codec == 'mp3':
        args += ['-c:a', 'libmp3lame', '-b:a', '256k']
    else:
        raise ValueError(codec)
    run(args + [path], samples.astype('<f4').tobytes())


class Sampler:
    def __init__(self, ffmpeg, cache, manifest):
        self.ffmpeg, self.cache = ffmpeg, cache
        self.groups = defaultdict(list)
        self.rr = Counter()
        self.raw, self.pitched = {}, {}
        self.used = Counter()
        self.inspect = {}
        self.shifts = Counter()
        for item in manifest['samples']:
            self.groups[item['role']].append(item)

    def load(self, item):
        key = item['path']
        if key not in self.raw:
            path = self.cache / key
            assert path.stat().st_size == item['size_bytes'], key
            data = decode(self.ffmpeg, path)
            peak = float(np.max(np.abs(data)))
            assert peak > 0 and np.isfinite(data).all(), key
            # Remove only leading near-silence, retaining the natural attack.
            onset = np.flatnonzero(np.max(np.abs(data), axis=1) > peak * .012)
            trim = max(0, min(int(onset[0]) - round(.012 * RATE), round(.3 * RATE)))
            data = data[trim:]
            energy = np.mean(data ** 2, axis=1)
            active = energy > peak ** 2 * .0004
            rms = float(np.sqrt(np.mean(energy[active])))
            # Balance recorded zones before applying the written velocities.
            # The recording's evolving dynamics and articulation remain intact.
            self.raw[key] = data * (.10 / max(rms, 1e-7))
            self.inspect[key] = {'decoded_seconds': len(data) / RATE,
                'trimmed_leading_ms': trim * 1000 / RATE,
                'source_active_rms_dbfs': 20 * math.log10(rms),
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        return self.raw[key]

    def choose(self, group, pitch, velocity):
        options = self.groups[group]
        if options[0]['root_midi'] is not None:
            distance = min(abs(s['root_midi'] - pitch) for s in options)
            options = [s for s in options if abs(s['root_midi'] - pitch) == distance]
        # Keep horn on its medium/quiet recordings. Strings have soft and firm
        # bowing; medium written velocities favor the less cutting soft layer.
        layers = sorted(set(s['velocity_layer'] for s in options))
        desired = layers[-1] if velocity >= (74 if group == 'horn_sustain' else 83) else layers[0]
        options = sorted((s for s in options if s['velocity_layer'] == desired),
                         key=lambda s: (s['round_robin'], s['path']))
        rr_key = (group, pitch, desired)
        item = options[self.rr[rr_key] % len(options)]
        self.rr[rr_key] += 1
        self.used[item['path']] += 1
        return item

    def note(self, group, pitch, duration, velocity):
        item = self.choose(group, pitch, velocity)
        shift = pitch - item['root_midi'] if item['root_midi'] is not None else 0
        self.shifts[(group, shift)] += 1
        key = (item['path'], shift)
        if key not in self.pitched:
            data = self.load(item)
            ratio = 2 ** (shift / 12)
            positions = np.arange(0, len(data) - 1, ratio)
            # Small zone transpositions; native samples supply the sound itself.
            self.pitched[key] = np.column_stack([
                np.interp(positions, np.arange(len(data)), data[:, ch]) for ch in range(2)
            ]).astype(np.float32)
        data = self.pitched[key]
        sustaining = group.endswith('sustain')
        release = .32 if group == 'horn_sustain' else .42
        if sustaining:
            gate = round(duration * BEAT * RATE)
            count = gate + round(release * RATE)
            # These short phrases must fit the recorded sustain. No invented
            # microsample loops or stretching an attack into a pad.
            assert count <= len(data), (group, pitch, duration, len(data) / RATE)
            result = data[:count].copy()
            result[gate:] *= np.linspace(1, 0, count - gate, dtype=np.float32)[:, None] ** 1.6
        else:
            limit = 2.7 if group == 'cymbal' else (1.4 if group == 'cello_spiccato' else 1.8)
            count = min(len(data), round(limit * RATE))
            result = data[:count].copy()
            fade = min(round(.15 * RATE), count)
            result[-fade:] *= np.linspace(1, 0, fade, dtype=np.float32)[:, None]
        attack = min(round(.008 * RATE), len(result))
        result[:attack] *= np.linspace(0, 1, attack, dtype=np.float32)[:, None]
        result *= (velocity / 100) ** 1.5
        return result


def add_periodic(target, samples, start):
    first = min(len(samples), len(target) - start)
    target[start:start + first] += samples[:first]
    if first < len(samples):
        target[:len(samples) - first] += samples[first:]


def validate(parts):
    assert set(parts) == {*MAP, 'drums'}
    for role, events in parts.items():
        ends = {}
        for beat, pitch, duration, velocity in sorted(events):
            assert 0 <= beat < BARS * 4 and 0 < duration <= 3.5
            assert beat + duration <= BARS * 4
            assert 1 <= velocity <= 127
            assert beat >= ends.get(pitch, -1) - 1e-8, (role, beat, pitch)
            ends[pitch] = beat + duration
        if role == 'motion':
            assert max(Counter(int(e[0] // 4) for e in events).values()) <= 4
    assert all(50 <= event[1] <= 62 for event in parts['theme'])
    sounding = sum(e[2] for e in parts['theme'])
    return {'note_events': sum(map(len, parts.values())), 'horn_written_silence_percent':
            round(100 * (1 - sounding / (BARS * 4)), 2), 'bounds_and_overlap': 'passed'}


def journey_weights():
    weights = {mode: np.zeros(FRAMES, dtype=np.float32) for mode in MODES}
    weights[JOURNEY[0][1]][:] = 1
    previous = JOURNEY[0][1]
    for seconds, mode in JOURNEY[1:]:
        start, end = round(seconds * RATE), round((seconds + 1) * RATE)
        x = np.linspace(0, 1, end - start, endpoint=False, dtype=np.float32)
        curve = x * x * (3 - 2 * x)
        weights[previous][start:end] = 1 - curve
        weights[previous][end:] = 0
        weights[mode][start:end] = curve
        weights[mode][end:] = 1
        previous = mode
    assert np.max(np.abs(sum(weights.values()) - 1)) < 1e-6
    return weights


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=HERE / '.sample-cache/vsco')
    parser.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
    args = parser.parse_args()
    manifest = json.loads((HERE / 'vsco_source_manifest.json').read_text(encoding='utf-8'))
    parts = score()
    checks = validate(parts)
    sampler = Sampler(args.ffmpeg, args.cache, manifest)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT.parent / '.gdignore').write_text('')
    stems = {}
    for role, events in parts.items():
        buffer = np.zeros((FRAMES, 2), np.float32)
        for beat, pitch, duration, velocity in events:
            group = DRUMS[pitch] if role == 'drums' else MAP[role]
            sound = sampler.note(group, pitch, duration, velocity)
            add_periodic(buffer, sound, round(beat * BEAT * RATE))
        # Filter two identical periods, keeping the second to make filter state
        # continuous across the exported loop rather than starting it at zero.
        raw = run([args.ffmpeg, '-v', 'error', '-f', 'f32le', '-ar', RATE, '-ac', '2',
                   '-i', 'pipe:0', '-af', FILTERS[role], '-f', 'f32le', '-'],
                  np.concatenate((buffer, buffer)).astype('<f4').tobytes())
        buffer = np.frombuffer(raw, '<f4').reshape(-1, 2)[FRAMES:].copy()
        assert len(buffer) == FRAMES
        energy = np.mean(buffer ** 2, axis=1)
        active = energy > max(float(energy.max()) * 1e-4, 1e-12)
        rms = float(np.sqrt(np.mean(energy[active])))
        buffer *= 10 ** (BALANCE[role] / 20) / rms
        buffer[:, 0] *= math.sqrt(1 - PAN[role])
        buffer[:, 1] *= math.sqrt(1 + PAN[role])
        if role == 'drums':
            # Tame isolated close-miked drum spikes so one hit does not set the
            # loudness of the entire score. Keep the musical dynamics elsewhere.
            raw = run([args.ffmpeg, '-v', 'error', '-f', 'f32le', '-ar', RATE,
                       '-ac', '2', '-i', 'pipe:0', '-af',
                       'acompressor=threshold=0.14:ratio=3:attack=4:release=150:knee=2.8',
                       '-f', 'f32le', '-'], np.concatenate((buffer, buffer)).astype('<f4').tobytes())
            buffer = np.frombuffer(raw, '<f4').reshape(-1, 2)[FRAMES:].copy()
        stems[role] = buffer
        print(f'Rendered {role}: {len(events)} performed notes', flush=True)

    layers = {'base': stems['foundation'].copy()}
    for mode, mix in MODES.items():
        layers[mode] = sum(stems[role] * gain for role, gain in mix.items())
    weights = journey_weights()
    audition = layers['base'].copy()
    for mode in MODES:
        audition += layers[mode] * weights[mode][:, None]
    # Set common static gain from combat, with peak headroom for every state.
    combat = layers['base'] + layers['combat']
    probe_gain = min(1, .7 / max(float(np.abs(combat).max()), 1e-10))
    probe = OUT / '_level_probe.wav'
    write_wav(probe, combat * probe_gain)
    measured = measure(args.ffmpeg, probe)
    gain = probe_gain * 10 ** ((-18 - measured['input_i']) / 20)
    peak = max(float(np.abs(layers['base'] + layers[mode]).max()) for mode in MODES)
    gain = min(gain, 10 ** (-2.8 / 20) / peak)
    for samples in layers.values():
        samples *= gain
    for samples in stems.values():
        samples *= gain
    audition *= gain
    fade_in, fade_out = round(.025 * RATE), round(2 * RATE)
    audition[:fade_in] *= np.linspace(0, 1, fade_in, dtype=np.float32)[:, None]
    audition[-fade_out:] *= np.linspace(1, 0, fade_out, dtype=np.float32)[:, None]
    write_wav(OUT / 'ember-path-journey.wav', audition)
    encode(args.ffmpeg, OUT / 'ember-path-journey.mp3', audition, 'mp3')
    report = {'title': 'Ember Path', 'bpm': BPM, 'bars': BARS, 'seconds': SECONDS,
        'sample_rate': RATE, 'loop_frames': FRAMES, 'runtime_integrated': False,
        'common_gain_db': 20 * math.log10(gain), 'checks': checks,
        'source': manifest['source'], 'source_commit': manifest['revision'],
        'scenario_mix': MODES, 'stem_target_rms_dbfs': BALANCE,
        'drum_dynamics': 'threshold=0.14 ratio=3 attack=4ms release=150ms knee=2.8',
        'journey': [{'seconds': t, 'scenario': mode} for t, mode in JOURNEY],
        'transitions': {'quantize_beats': 1, 'fade_beats': 2, 'curve': 'smoothstep_amplitude'},
        'source_recordings': sampler.inspect,
        'transpositions': [{'role': role, 'semitones': shift, 'notes': n}
                           for (role, shift), n in sorted(sampler.shifts.items())],
        'loudness': {}, 'loop_boundary_steps': {}}
    for name, samples in layers.items():
        assert np.max(np.abs(samples)) < 1
        encode(args.ffmpeg, OUT / f'{name}.flac', samples, 'flac')
        encode(args.ffmpeg, OUT / f'{name}.ogg', samples, 'ogg')
        report['loop_boundary_steps'][name] = float(np.max(np.abs(samples[0] - samples[-1])))
        decoded = decode(args.ffmpeg, OUT / f'{name}.ogg')
        assert decoded.shape == (FRAMES, 2), (name, decoded.shape)
        assert np.isfinite(decoded).all() and np.max(np.abs(decoded)) < 1
    for mode in MODES:
        full = layers['base'] + layers[mode]
        encode(args.ffmpeg, OUT / f'{mode}-full.flac', full, 'flac')
        report['loudness'][mode] = measure(args.ffmpeg, OUT / f'{mode}-full.flac')
        assert report['loudness'][mode]['input_tp'] < -1.8
    report['loudness']['journey'] = measure(args.ffmpeg, OUT / 'ember-path-journey.wav')
    report['checks']['clipped_samples'] = int(np.count_nonzero(np.abs(audition) >= 1))
    assert report['checks']['clipped_samples'] == 0
    report['checks']['encoded_layers_aligned'] = True
    for role, samples in stems.items():
        encode(args.ffmpeg, OUT / f'instrument-{role}.flac', samples, 'flac')
    (OUT / 'render-report.json').write_text(json.dumps(report, indent=2) + '\n')
    (OUT / 'score.json').write_text(json.dumps({'harmony': [asdict(c) for c in HARMONY],
                                             'parts': parts}, indent=2) + '\n')
    (OUT / 'manifest.json').write_text(json.dumps({
        'title': 'Ember Path', 'bpm': BPM, 'duration': SECONDS, 'frames': FRAMES,
        'sampleRate': RATE, 'layers': {name: name + '.ogg' for name in layers},
        'journey': report['journey']}, indent=2) + '\n')
    shutil.copyfile(args.cache / 'LICENSE.txt', OUT / 'VSCO-CC0-LICENSE.txt')
    shutil.copyfile(args.cache / 'receipt.json', OUT / 'source-receipt.json')
    probe.unlink()
    print(json.dumps({'output': str(OUT), 'loudness': report['loudness'], 'checks': report['checks']}, indent=2))


if __name__ == '__main__':
    main()
