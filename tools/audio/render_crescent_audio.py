"""Prepare recorded Crescent swishes and repeatable musical-context auditions.

Requires NumPy and FFmpeg. Source: artisticdude's CC0 Swishes Sound Pack.
Pass an extracted swishes directory; this script never downloads or plays audio.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import wave

import numpy as np

RATE = 48000
ROOT = Path(__file__).resolve().parents[2]
SOURCE_PAGE = 'https://opengameart.org/content/swishes-sound-pack'
GAIN_DB = -21.5
RETURN_TRIM_DB = -8.0
SOURCE_HASHES = {
    9: '123883f006ce55feecbff11eea5f87c4493df4399989983037144570a23723c1',
    10: '4f7381a76f280d3f36f962ac3f44f16f77eec44797f30715d063c81ea3859024',
    11: '9e81d548d8215fbb36f7a41b5771d4b52c2fd02fbb9b5ff9a4c65118fd88ee4d',
    12: '0513a86d428d9ed8601e93b8554580a5932c6c1a82d39d81a8f48883f1807a67',
    13: '698230ba3fe05a68c18d68cd6b3a07fb98e6c1198bb1a4238592ee9912c02c77',
}


def decode(path, filters='', channels=1, seconds=None):
    args = [shutil.which('ffmpeg'), '-v', 'error', '-i', str(path)]
    if seconds is not None:
        args += ['-t', str(seconds)]
    if filters:
        args += ['-af', filters]
    args += ['-f', 'f32le', '-ar', str(RATE), '-ac', str(channels), '-']
    samples = np.frombuffer(subprocess.check_output(args), dtype='<f4').astype(np.float64)
    return samples.reshape(-1, channels) if channels > 1 else samples


def save(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    assert np.isfinite(samples).all() and abs(samples).max() < .99
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1 if samples.ndim == 1 else samples.shape[1])
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(np.rint(samples * 32767.0).astype('<i2').tobytes())


def prepare(source, number, tempo=1.0, lowpass=3600, highpass=95):
    path = source / ('swish-%d.wav' % number)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == SOURCE_HASHES[number]
    # Keep the recorded gesture. EQ removes microphone rumble and hiss;
    # constant tempo changes preserve pitch, with no oscillator or modulation.
    filters = 'highpass=f=%s,lowpass=f=%s,atempo=%s' % (highpass, lowpass, tempo)
    samples = decode(path, filters)
    samples -= np.mean(samples)
    fade_in = min(int(.004 * RATE), len(samples) // 4)
    fade_out = min(int(.018 * RATE), len(samples) // 4)
    samples[:fade_in] *= np.sin(np.linspace(0, np.pi / 2, fade_in)) ** 2
    samples[-fade_out:] *= np.cos(np.linspace(0, np.pi / 2, fade_out)) ** 2
    samples *= .65 / max(.001, abs(samples).max())
    samples[0] = samples[-1] = 0.0
    return samples


def add(buffer, samples, when, gain_db, pan=0.0):
    start = round(when * RATE)
    count = min(len(samples), len(buffer) - start)
    if count <= 0:
        return
    # Modest pan belongs only to these audition examples, not runtime audio.
    channel = np.array([1.0 - max(0.0, pan), 1.0 + min(0.0, pan)])
    buffer[start:start + count] += samples[:count, None] * channel * 10 ** (gain_db / 20)


def audition(outbound, returning, music, output):
    seconds = 12.0
    mix = np.zeros((round(seconds * RATE), 2))
    # Three dry throws, then normal cadence and alternating level-two throws
    # over the unchanged game score at its default -20 setting and -2 trim.
    bed = music[:round(7 * RATE)] * 10 ** (-22 / 20)
    fade = round(.06 * RATE)
    bed[:fade] *= np.linspace(0, 1, fade)[:, None]
    bed[-fade:] *= np.linspace(1, 0, fade)[:, None]
    mix[round(5 * RATE):round(5 * RATE) + len(bed)] += bed
    throws = [.3, 1.6, 2.9, 5.35, 6.15, 6.95, 7.75, 8.15, 8.55, 8.95, 9.35, 9.75, 10.15, 10.55, 10.95]
    for i, time in enumerate(throws):
        add(mix, outbound[i % len(outbound)], time, GAIN_DB)
        add(mix, returning[i % len(returning)], time + .36, GAIN_DB + RETURN_TRIM_DB)
    save(output, mix)
    return {'peak_dbfs': float(20 * np.log10(abs(mix).max())), 'seconds': seconds,
            'mix_gain_db': GAIN_DB, 'return_trim_db': RETURN_TRIM_DB}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'sounds/crescent')
    parser.add_argument('--auditions', type=Path, required=True)
    args = parser.parse_args()
    light = [prepare(args.source, n, tempo=t) for n, t in [(10, .83), (11, .8), (12, .65)]]
    returns = [prepare(args.source, n, tempo=t, lowpass=2900) for n, t in [(13, .86), (12, .95)]]
    heavy = [prepare(args.source, 9, tempo=1.0, lowpass=2900, highpass=160)]
    # A wall cue stays a short air flick. No synthetic metallic ping is added.
    bounce = prepare(args.source, 13, tempo=1.1, lowpass=4000)
    report = {'source': SOURCE_PAGE, 'author': 'artisticdude', 'license': 'CC0',
              'source_sha256': SOURCE_HASHES, 'gain_db': GAIN_DB,
              'return_trim_db': RETURN_TRIM_DB, 'files': {}, 'auditions': {}}
    for group, samples in [('outbound', light), ('return', returns), ('bounce', [bounce])]:
        for index, sample in enumerate(samples):
            path = args.output / ('crescent_%s_%d.wav' % (group, index + 1))
            save(path, sample)
            report['files'][path.name] = {'seconds': len(sample) / RATE,
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'peak_dbfs': float(20 * np.log10(abs(sample).max())),
                'rms_dbfs': float(20 * np.log10(np.sqrt(np.mean(sample * sample))))}
    music = decode(ROOT / 'music/riot-depth/base.ogg', channels=2, seconds=7)
    music += decode(ROOT / 'music/riot-depth/drive.ogg', channels=2, seconds=7)
    report['auditions']['light'] = audition(light, returns, music, args.auditions / 'crescent_light.wav')
    report['auditions']['weightier'] = audition(heavy, returns, music, args.auditions / 'crescent_weightier.wav')
    (args.output / 'render-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
