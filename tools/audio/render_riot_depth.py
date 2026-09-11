"""Original industrial action audition with a shared adaptive music timeline.

Band-limited, oversampled distorted voices; tightly shaped recorded percussion;
no horn, melodic string ensemble, guitar harmonics or bell instruments.
"""
from collections import Counter
import json
import math
from pathlib import Path
import shutil

import numpy as np

from riot_depth_score import BPM, BARS, score
from render_ember_path import Sampler, run, decode, encode, add_periodic
from create_action_scenario_study import measure
from create_sampled_texture_study import write_wav

HERE = Path(__file__).resolve().parent
OUT = HERE / 'examples/riot-depth'
RATE, OVERSAMPLE = 48000, 2
BEAT = 60 / BPM
FRAMES = round(BARS * 4 * BEAT * RATE)
SECONDS = FRAMES / RATE
BALANCE = {'base': -34.0, 'bass': -26.0, 'hook': -27.0, 'drums': -25.0, 'debris': -35.0}
FILTERS = {
    'base': 'highpass=f=100,lowpass=f=2000',
    'bass': 'highpass=f=55,equalizer=f=650:t=q:w=0.7:g=3,lowpass=f=3800',
    'hook': 'highpass=f=165,equalizer=f=2300:t=q:w=0.8:g=-3.5,lowpass=f=3600',
    'drums': 'highpass=f=35,lowpass=f=9500',
    'debris': 'highpass=f=400,lowpass=f=4500',
}
MODES = {
    'combat': {'bass': 1.0, 'hook': 1.0, 'drums': 1.0, 'debris': .75},
    'doors': {'bass': .27, 'hook': .13, 'drums': .12, 'debris': .28},
    'reward': {'bass': .38, 'hook': .52, 'drums': .19, 'debris': .10},
}
JOURNEY_BARS = [(0,'combat'),(12,'reward'),(16,'doors'),(20,'combat'),(36,'reward'),(42,'doors')]

# A finite Fourier table avoids the unbounded high-frequency content of raw
# saw discontinuities. Nonlinear stages run at 96 kHz before FIR decimation.
GRID = np.arange(8192) / 8192
SAW = sum(np.sin(2 * np.pi * k * GRID) / k for k in range(1, 45)) * (2 / np.pi)
SAW = np.r_[SAW, SAW[0]]
FIR_X = np.arange(63) - 31
FIR = .45 * np.sinc(.45 * FIR_X) * np.hamming(63)
FIR /= FIR.sum()


def osc(phase):
    return np.interp((phase % 1) * 8192, np.arange(8193), SAW)


def downsample(data):
    return np.convolve(data, FIR, mode='same')[::OVERSAMPLE].astype(np.float32)


def synth(role, pitch, duration, velocity, seed):
    sr = RATE * OVERSAMPLE
    release = .13 if role == 'bass' else (.22 if role == 'hook' else .4)
    gate = duration * BEAT
    t = np.arange(round((gate + release) * sr), dtype=np.float64) / sr
    f = 440 * 2 ** ((pitch - 69) / 12)
    rng = np.random.default_rng(seed)
    phase0 = rng.uniform(0, 1)
    # Small onset pitch tension, not a repeating wah/filter wobble.
    phase = f * (t + .0018 * (1 - np.exp(-t / .065))) + phase0
    if role == 'bass':
        body = .68 * osc(phase) + .27 * (osc(phase + .31) - osc(phase))
        edge = .22 * osc(phase * 1.0025 + .23)
        driven = np.tanh((body + edge) * (2.1 + velocity / 100))
        # Give distortion its own midrange space. Reduce its large fundamental
        # before adding a deliberate, smaller clean low component.
        sine, cosine = np.sin(2 * np.pi * phase), np.cos(2 * np.pi * phase)
        fundamental = 2 * (np.mean(driven * sine) * sine + np.mean(driven * cosine) * cosine)
        mono = (driven - fundamental) * .92 + sine * .15
        left, right = mono, mono
    elif role == 'hook':
        body = .65 * (osc(phase) - osc(phase + .38)) + .30 * osc(phase * .998)
        drift = .12 * np.sin(2 * np.pi * phase * 2 + .4 * np.sin(2 * np.pi * phase))
        left = np.tanh(1.65 * (body + drift))
        right = np.tanh(1.65 * (body + drift + .05 * osc(phase * 1.002 + .1)))
    else:
        left = .55 * osc(phase * .999) + .35 * osc(phase * 1.003 + .32)
        right = .55 * osc(phase * 1.001) + .35 * osc(phase * .997 + .43)
        left, right = np.tanh(left * 1.4), np.tanh(right * 1.4)
    attack = .018 if role == 'bass' else (.035 if role == 'hook' else .24)
    envelope = np.minimum(t / attack, 1)
    envelope *= .86 + .14 * np.exp(-t / .14)
    envelope *= np.clip((gate + release - t) / release, 0, 1) ** 1.8
    if role == 'base':
        envelope *= .8 + .2 * np.sin(np.pi * np.minimum(t / max(gate, .01), 1))
    amplitude = (velocity / 100) ** 1.4
    return np.column_stack([downsample(left * envelope * amplitude),
                            downsample(right * envelope * amplitude)])


def colored_noise(length, seed, low, high):
    rng = np.random.default_rng(seed)
    signal = rng.normal(0, 1, length)
    bins = np.fft.rfftfreq(length, 1 / RATE)
    mask = (1 - np.exp(-(bins / low) ** 4)) * np.exp(-(bins / high) ** 6)
    shaped = np.fft.irfft(np.fft.rfft(signal) * mask, n=length)
    return shaped / max(np.std(shaped), 1e-7)


def percussion(sampler, pitch, velocity, seed, debris=False):
    if debris:
        duration = {37:.12,39:.20,46:.32}.get(pitch,.17)
        n = round(duration * RATE)
        t = np.arange(n) / RATE
        noise = colored_noise(n, seed, 500, 3300)
        if pitch == 46:
            env = np.sin(np.pi * t / duration) ** 2
        else:
            env = np.minimum(t / .004, 1) * np.exp(-t / (.025 if pitch == 37 else .055))
        dry = np.tanh(noise * .9) * env * .24
        stereo = np.column_stack([dry, np.roll(dry, 53) * .8])
        stereo[-240:] *= np.linspace(1, 0, 240)[:,None]
        return stereo * (velocity / 100) ** 1.4
    if pitch == 42:
        n = round(.095 * RATE); t = np.arange(n) / RATE
        dry = colored_noise(n, seed, 3500, 8000) * np.exp(-t / .025) * .065
        dry *= np.minimum(t / .003, 1)
        return np.column_stack([dry, dry*.86]).astype(np.float32) * (velocity / 100) ** 1.4
    group = {36:'bass_drum',38:'snare',49:'cymbal'}[pitch]
    natural = sampler.note(group, pitch, .5, velocity)
    natural = natural / max(float(np.max(np.abs(natural))), 1e-6)
    if pitch == 36:
        n = round(.34 * RATE); t = np.arange(n) / RATE
        phase = 2 * np.pi * (53 * t + 88 * .021 * (1 - np.exp(-t/.021)))
        body = np.sin(phase) * np.exp(-t/.09) * .58
        attack = colored_noise(n,seed,1400,4200)*np.exp(-t/.006)*.10
        dry = np.zeros((n,2),np.float32)
        count=min(n,len(natural));dry[:count]=natural[:count]*.23*np.exp(-t[:count,None]/.10)
        dry += (body+attack)[:,None]
    elif pitch == 38:
        n=round(.19*RATE);t=np.arange(n)/RATE
        dry=np.zeros((n,2),np.float32);count=min(n,len(natural))
        dry[:count]=natural[:count]*.45*np.exp(-t[:count,None]/.055)
        snap=colored_noise(n,seed,900,6500)*np.exp(-t/.038)*.22
        chest=np.sin(2*np.pi*183*t)*np.exp(-t/.025)*.18
        dry+=(snap+chest)[:,None]
        dry=np.tanh(dry*1.7)/1.3
    else:
        n=min(len(natural),round(.65*RATE));t=np.arange(n)/RATE
        dry=natural[:n]*np.exp(-t[:,None]/.22)*.24
    dry[:120] *= np.linspace(0,1,120)[:,None]
    dry[-480:] *= np.linspace(1,0,480)[:,None]
    return dry.astype(np.float32)*(velocity/100)**1.4


def process(ffmpeg, samples, filter_string):
    raw=run([ffmpeg,'-v','error','-f','f32le','-ar',RATE,'-ac','2','-i','pipe:0',
             '-af',filter_string,'-f','f32le','-'],np.concatenate([samples,samples]).astype('<f4').tobytes())
    return np.frombuffer(raw,'<f4').reshape(-1,2)[FRAMES:].copy()


def weights():
    values={m:np.zeros(FRAMES,np.float32) for m in MODES};values['combat'][:]=1
    previous='combat'
    for bar,mode in JOURNEY_BARS[1:]:
        start=round(bar*4*BEAT*RATE);end=start+round(2*BEAT*RATE)
        t=np.linspace(0,1,end-start,endpoint=False,dtype=np.float32);t=t*t*(3-2*t)
        values[previous][start:end]=1-t;values[previous][end:]=0
        values[mode][start:end]=t;values[mode][end:]=1;previous=mode
    assert np.max(np.abs(sum(values.values())-1))<1e-6
    return values


def main():
    ffmpeg=shutil.which('ffmpeg');assert ffmpeg
    parts=score();assert set(parts)==set(BALANCE)
    for role,events in parts.items():
        ends={}
        for beat,pitch,duration,velocity in sorted(events):
            assert 0<=beat<BARS*4 and duration>0 and beat+duration<=BARS*4
            assert 1<=velocity<=127
            assert beat>=ends.get(pitch,-1)-1e-8,(role,beat,pitch)
            ends[pitch]=beat+duration
    manifest=json.loads((HERE/'vsco_source_manifest.json').read_text(encoding='utf-8'))
    sampler=Sampler(ffmpeg,HERE/'.sample-cache/vsco',manifest)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT.parent/'.gdignore').write_text('')
    stems={};kick_times=[e[0] for e in parts['drums'] if e[1]==36]
    duck=np.ones(FRAMES,np.float32)
    for beat in kick_times:
        start=round(beat*BEAT*RATE);length=round(.115*RATE)
        idx=(np.arange(length)+start)%FRAMES
        duck[idx]=np.minimum(duck[idx],.56+.44*(np.arange(length)/length)**.7)
    for role,events in parts.items():
        buffer=np.zeros((FRAMES,2),np.float32)
        for index,(beat,pitch,duration,velocity) in enumerate(events):
            if role in ('drums','debris'):
                sound=percussion(sampler,pitch,velocity,1900+index,role=='debris')
            else:
                sound=synth(role,pitch,duration,velocity,7700+index)
            add_periodic(buffer,sound,round(beat*BEAT*RATE))
        buffer=process(ffmpeg,buffer,FILTERS[role])
        energy=np.mean(buffer**2,axis=1);active=energy>max(float(energy.max())*1e-4,1e-12)
        assert active.any()
        buffer*=10**(BALANCE[role]/20)/float(np.sqrt(np.mean(energy[active])))
        if role=='drums':
            buffer=process(ffmpeg,buffer,'acompressor=threshold=0.16:ratio=3:attack=2:release=65:knee=2.5')
        if role=='bass':buffer*=duck[:,None]
        stems[role]=buffer
        print(f'Rendered {role}: {len(events)} events',flush=True)
    layers={'base':stems['base'].copy()}
    for mode,balance in MODES.items():layers[mode]=sum(stems[r]*v for r,v in balance.items())
    combat=layers['base']+layers['combat'];probe=OUT/'_probe.wav'
    probe_gain=min(1,.7/max(float(np.abs(combat).max()),1e-8));write_wav(probe,combat*probe_gain)
    measured=measure(ffmpeg,probe)
    gain=probe_gain*10**((-18-measured['input_i'])/20)
    peak=max(float(np.abs(layers['base']+layers[m]).max()) for m in MODES)
    gain=min(gain,10**(-2.7/20)/peak)
    for data in layers.values():data*=gain
    journey=layers['base'].copy()
    for mode,env in weights().items():journey+=layers[mode]*env[:,None]
    fade=round(.012*RATE);journey[:fade]*=np.linspace(0,1,fade)[:,None]
    fade=round(1.1*RATE);journey[-fade:]*=np.linspace(1,0,fade)[:,None]
    write_wav(OUT/'riot-depth-journey.wav',journey)
    encode(ffmpeg,OUT/'riot-depth-journey.mp3',journey,'mp3')
    report={'title':'Riot Depth','bpm':BPM,'bars':BARS,'frames':FRAMES,'seconds':SECONDS,
            'sample_rate':RATE,'runtime_integrated':False,'common_gain_db':20*math.log10(gain),
            'design':'oversampled distorted mid-bass; short low hook; gated recorded/synthetic drums; noise accents',
            'scenario_mix':MODES,'instrument_target_active_rms_dbfs':BALANCE,'filters':FILTERS,
            'note_counts':{r:len(e) for r,e in parts.items()},'loudness':{},'loop_steps':{},
            'source_recordings':sampler.inspect,'synthesis_rate':RATE*OVERSAMPLE,
            'hook_written_silence_percent':100*(1-sum(e[2] for e in parts['hook'])/(BARS*4))}
    for name,data in layers.items():
        assert np.isfinite(data).all() and np.max(np.abs(data))<1
        encode(ffmpeg,OUT/f'{name}.ogg',data,'ogg');encode(ffmpeg,OUT/f'{name}.flac',data,'flac')
        decoded=decode(ffmpeg,OUT/f'{name}.ogg');assert decoded.shape==(FRAMES,2)
        assert np.max(np.abs(decoded))<1
        report['loop_steps'][name]=float(np.max(np.abs(decoded[0]-decoded[-1])))
    for mode in MODES:
        full=layers['base']+layers[mode]
        encode(ffmpeg,OUT/f'{mode}-full.flac',full,'flac')
        report['loudness'][mode]=measure(ffmpeg,OUT/f'{mode}-full.flac')
        assert report['loudness'][mode]['input_tp']<-1.8
    report['loudness']['journey']=measure(ffmpeg,OUT/'riot-depth-journey.wav')
    report['clipped_samples']=int(np.count_nonzero(np.abs(journey)>=1));assert report['clipped_samples']==0
    for role,data in stems.items():encode(ffmpeg,OUT/f'instrument-{role}.flac',data*gain,'flac')
    (OUT/'render-report.json').write_text(json.dumps(report,indent=2)+'\n')
    (OUT/'score.json').write_text(json.dumps(parts,indent=2)+'\n')
    (OUT/'manifest.json').write_text(json.dumps({'title':'Riot Depth','bpm':BPM,'duration':SECONDS,
        'frames':FRAMES,'sampleRate':RATE,'layers':{n:n+'.ogg' for n in layers},
        'journey':[{'seconds':bar*4*BEAT,'scenario':mode} for bar,mode in JOURNEY_BARS]},indent=2)+'\n')
    shutil.copyfile(HERE/'.sample-cache/vsco/LICENSE.txt',OUT/'VSCO-CC0-LICENSE.txt')
    probe.unlink()
    print(json.dumps({'path':str(OUT),'loudness':report['loudness'],
                      'hook_silence':report['hook_written_silence_percent']},indent=2))


if __name__=='__main__':main()
