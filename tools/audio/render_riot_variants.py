"""Develop Riot Depth by chamber/boss identity, without selection-volume dips.

Preserves the approved base and Drive bytes. Other additions are mastered to
the same integrated level and rendered offline on the same harmonic clock.
"""
import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import shutil

import numpy as np

from riot_depth_variants import variants
from render_riot_depth import (
    BPM, BARS, RATE, BEAT, FRAMES, SECONDS, BALANCE, FILTERS,
    Sampler, synth, percussion, process, add_periodic, decode, encode, measure,
)
from create_sampled_texture_study import write_wav

HERE = Path(__file__).resolve().parent
DEFAULT_OUTPUT = HERE / 'examples/riot-variants'


def render_variant(name, parts, reference, cache, output):
    ffmpeg = shutil.which('ffmpeg')
    reference, cache, output = Path(reference), Path(cache), Path(output)
    manifest = json.loads((HERE / 'vsco_source_manifest.json').read_text())
    sampler = Sampler(ffmpeg, cache, manifest)
    base = decode(ffmpeg, reference / 'base.ogg')
    assert base.shape == (FRAMES, 2)
    duck = np.ones(FRAMES, np.float32)
    for beat, pitch, *_ in parts['drums']:
        if pitch == 36:
            start, length = round(beat * BEAT * RATE), round(.115 * RATE)
            idx = (np.arange(length) + start) % FRAMES
            duck[idx] = np.minimum(duck[idx], .56 + .44 * (np.arange(length) / length) ** .7)
    addition = np.zeros_like(base)
    for role in ['bass', 'hook', 'drums', 'debris']:
        buffer = np.zeros_like(base)
        ends = {}
        for index, (beat, pitch, duration, velocity) in enumerate(sorted(parts[role])):
            assert 0 <= beat < BARS * 4 and duration > 0 and beat + duration <= BARS * 4
            assert 1 <= velocity <= 127 and beat >= ends.get(pitch, -1) - 1e-7, (name, role, beat, pitch)
            ends[pitch] = beat + duration
            if role in ['drums', 'debris']:
                sound = percussion(sampler, pitch, velocity, 1900 + index, role == 'debris')
            else:
                sound = synth(role, pitch, duration, velocity, 7700 + index)
            add_periodic(buffer, sound, round(beat * BEAT * RATE))
        buffer = process(ffmpeg, buffer, FILTERS[role])
        energy = np.mean(buffer ** 2, axis=1)
        active = energy > max(float(energy.max()) * 1e-4, 1e-12)
        assert active.any(), (name, role)
        buffer *= 10 ** (BALANCE[role] / 20) / float(np.sqrt(np.mean(energy[active])))
        if role == 'drums':
            buffer = process(ffmpeg, buffer, 'acompressor=threshold=0.16:ratio=3:attack=2:release=65:knee=2.5')
        elif role == 'bass':
            buffer *= duck[:, None]
        addition += buffer * (.75 if role == 'debris' else 1.0)
        print(f'{name}: rendered {role}', flush=True)
    probe = output / f'_{name}-probe.wav'
    static_gain = 1.0
    peak_control = False
    for _ in range(3):
        full = base + addition
        # Floating-point probe avoids clipping before the static mastering pass.
        encode(ffmpeg, output / f'_{name}-probe.flac', full * min(1.0, .75 / float(np.abs(full).max())), 'flac')
        pre_gain = min(1.0, .75 / float(np.abs(full).max()))
        measured = measure(ffmpeg, output / f'_{name}-probe.flac')
        gain = 10 ** ((-18.01 - (measured['input_i'] - 20 * np.log10(pre_gain))) / 20)
        addition *= gain
        static_gain *= gain
        full = base + addition
        if float(np.abs(full).max()) > .78:
            # Offline peak control only. The game never normalizes or ducks in
            # response to reward/door UI; every run arrangement has a fixed gain.
            full = process(ffmpeg, full, 'alimiter=limit=0.78:attack=5:release=65:level=false:latency=true')
            addition = full - base
            peak_control = True
        write_wav(probe, base + addition)
        final = measure(ffmpeg, probe)
        if abs(final['input_i'] + 18.01) <= .15:
            break
    encode(ffmpeg, output / f'{name}.ogg', addition, 'ogg')
    encode(ffmpeg, output / f'{name}-full.flac', base + addition, 'flac')
    decoded = decode(ffmpeg, output / f'{name}.ogg')
    assert decoded.shape == base.shape and np.isfinite(decoded).all()
    write_wav(probe, base + decoded)
    final = measure(ffmpeg, probe)
    assert abs(final['input_i'] + 18.01) < .5, (name, final)
    assert final['input_tp'] < -1.0 and float(np.abs(base + decoded).max()) < 1, (name, final)
    report = {'loudness': final, 'static_gain_db': float(20 * np.log10(static_gain)),
              'offline_peak_control': peak_control, 'notes': {r: len(v) for r, v in parts.items()},
              'source_recordings': sampler.inspect}
    probe.unlink()
    (output / f'_{name}-probe.flac').unlink()
    return name, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-dir', type=Path, default=HERE.parents[1] / 'music/riot-depth')
    parser.add_argument('--cache', type=Path, default=HERE / '.sample-cache/vsco')
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    ffmpeg = shutil.which('ffmpeg')
    assert ffmpeg
    scores = variants()
    names = ['drive', 'pursuit', 'pressure', 'boss']
    assert set(scores) == set(names)
    for parts in scores.values():
        assert parts['base'] == scores['drive']['base'], 'Every arrangement must share the harmonic bed'
    drive_source = args.reference_dir / 'drive.ogg'
    if not drive_source.exists():
        drive_source = args.reference_dir / 'combat.ogg'
    shutil.copyfile(args.reference_dir / 'base.ogg', output / 'base.ogg')
    shutil.copyfile(drive_source, output / 'drive.ogg')
    reports = {}
    with ProcessPoolExecutor(max_workers=2) as workers:
        jobs = [workers.submit(render_variant, name, scores[name], str(args.reference_dir),
                               str(args.cache), str(output)) for name in names[1:]]
        for job in as_completed(jobs):
            name, report = job.result()
            reports[name] = report
            print(name, json.dumps(report['loudness']), flush=True)
    base = decode(ffmpeg, output / 'base.ogg')
    additions = {name: decode(ffmpeg, output / f'{name}.ogg') for name in names}
    assert all(data.shape == (FRAMES, 2) for data in additions.values())
    encode(ffmpeg, output / 'drive-full.flac', base + additions['drive'], 'flac')
    reports['drive'] = {'loudness': measure(ffmpeg, output / 'drive-full.flac'), 'approved_bytes_preserved': True}
    levels = [report['loudness']['input_i'] for report in reports.values()]
    assert max(levels) - min(levels) < .75, levels
    journey = base.copy()
    journey += additions['drive']
    previous = 'drive'
    cues = [(0, 'drive'), (12, 'pursuit'), (24, 'pressure'), (36, 'boss')]
    for bar, name in cues[1:]:
        start, length = round(bar * 4 * BEAT * RATE), round(4 * BEAT * RATE)
        t = np.linspace(0, 1, length, endpoint=False, dtype=np.float32)
        t = (t * t * (3 - 2 * t))[:, None]
        journey[start:start + length] += (additions[name][start:start + length] - additions[previous][start:start + length]) * t
        journey[start + length:] += additions[name][start + length:] - additions[previous][start + length:]
        previous = name
    assert np.max(np.abs(journey)) < 1
    journey[:576] *= np.linspace(0, 1, 576)[:, None]
    journey[-48000:] *= np.linspace(1, 0, 48000)[:, None]
    encode(ffmpeg, output / 'riot-depth-variants.mp3', journey, 'mp3')
    write_wav(output / 'riot-depth-variants.wav', journey)
    report = {'bpm': BPM, 'bars': BARS, 'frames': FRAMES, 'sample_rate': RATE, 'seconds': SECONDS,
              'selection_behavior': 'Reward and doors keep the current arrangement, target and master level.',
              'arrangements': reports, 'integrated_level_spread_lu': round(max(levels) - min(levels), 3),
              'guided_journey': [{'seconds': bar * 4 * BEAT, 'arrangement': name} for bar, name in cues],
              'hashes': {name: hashlib.sha256((output / f'{name}.ogg').read_bytes()).hexdigest() for name in ['base', *names]}}
    (output / 'variance-report.json').write_text(json.dumps(report, indent=2) + '\n')
    (output / 'variant-scores.json').write_text(json.dumps(scores, indent=2) + '\n')
    print(json.dumps({'output': str(output), 'levels': {n:r['loudness'] for n,r in reports.items()}}))


if __name__ == '__main__':
    main()
