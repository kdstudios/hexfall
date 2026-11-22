#!/usr/bin/env python3
"""Generates HEXFALL's original audio assets (synthesised, no samples, no licensing issues).
Run:  python3 tools/generate_audio.py   (needs numpy)
"""
import wave, numpy as np, os
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)

def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.005, r=0.1):
    e = np.ones(n); na = max(1, int(a * SR)); nr = max(1, int(r * SR))
    e[:na] = np.linspace(0, 1, na); e[-nr:] *= np.linspace(1, 0, nr); return e
def expdecay(x, k): return np.exp(-x * k)
def lowpass(x, a): 
    y = np.zeros_like(x); s = 0.0
    for i, v in enumerate(x): s += a * (v - s); y[i] = s
    return y
def save(name, x, gain=0.8):
    x = np.asarray(x, dtype=np.float64); m = np.max(np.abs(x)) or 1.0
    pcm = (x / m * gain * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
def sweep(f0, f1, d):
    x = t(d); f = f0 + (f1 - f0) * (x / d); return np.sin(2 * np.pi * np.cumsum(f) / SR)

# --- effects ---
x = t(0.09); save('reveal.wav', sweep(880, 1400, 0.09) * expdecay(x, 28) * env(len(x), .002, .02))
x = t(0.7); save('scan.wav', sweep(300, 1900, 0.7) * (0.6 + 0.4 * np.sin(2*np.pi*18*x)) * env(len(x), .02, .25), 0.6)
x = t(0.14); save('flag.wav', (np.sin(2*np.pi*520*x) + .6*np.sin(2*np.pi*780*np.maximum(x-0.05,0))*(x>0.05)) * expdecay(x, 18) * env(len(x), .002, .03))
x = t(0.11); save('unflag.wav', sweep(700, 430, 0.11) * expdecay(x, 20) * env(len(x), .002, .03))
x = t(0.05); save('click.wav', np.sin(2*np.pi*1500*x) * expdecay(x, 70), 0.5)
x = t(1.1)
sh = sweep(180, 950, 1.1) * env(len(x), .05, .5) + 0.4*np.sin(2*np.pi*1800*x)*np.sin(2*np.pi*7*x)*expdecay(x, 2.5)
sh += 0.5 * lowpass(rng.normal(size=len(x)), 0.15) * expdecay(x, 9)
save('shield.wav', sh)
x = t(1.0)
ex = lowpass(rng.normal(size=len(x)), 0.12) * expdecay(x, 4.5) + 0.9*np.sin(2*np.pi*(55-20*x)*x) * expdecay(x, 5)
save('explosion.wav', ex * env(len(x), .001, .1))
# victory arpeggio
notes = [523.25, 659.25, 783.99, 1046.5]; out = np.zeros(int(SR*1.9))
for i, f in enumerate(notes):
    s = int(i * 0.16 * SR); d = t(1.2); tone = (np.sin(2*np.pi*f*d) + .4*np.sin(2*np.pi*2*f*d)) * expdecay(d, 2.2) * env(len(d), .005, .2)
    out[s:s+len(tone)] += tone[:len(out)-s]
save('victory.wav', out)
notes = [392.0, 329.63, 261.63, 196.0]; out = np.zeros(int(SR*1.9))
for i, f in enumerate(notes):
    s = int(i * 0.28 * SR); d = t(1.0); tone = (np.sin(2*np.pi*f*d) + .5*np.sin(2*np.pi*f*0.5*d)) * expdecay(d, 2.5) * env(len(d), .01, .2)
    out[s:s+len(tone)] += tone[:len(out)-s]
save('defeat.wav', out)

# --- ambience: seamless 12 s loop (all LFOs complete whole cycles) ---
D = 12.0; x = t(D)
amb = 0.6*np.sin(2*np.pi*55*x) + 0.4*np.sin(2*np.pi*82.5*x + 1.0*np.sin(2*np.pi*(1/D)*x))
amb *= 0.75 + 0.25*np.sin(2*np.pi*(2/D)*x)
wind = lowpass(rng.normal(size=len(x)), 0.02); wind = wind - np.linspace(wind[0], wind[-1], len(x))
amb += 3.0 * wind * (0.6 + 0.4*np.sin(2*np.pi*(3/D)*x))
save('ambient.wav', amb, 0.5)

# --- music: 24 s loop, Am - F - C - G pads with soft arpeggio ---
D = 24.0; x = t(D); mus = np.zeros(len(x))
chords = [[110.0, 164.81, 220.0, 261.63], [87.31, 130.81, 174.61, 261.63], [130.81, 196.0, 261.63, 329.63], [98.0, 146.83, 196.0, 293.66]]
for ci, ch in enumerate(chords):
    s = int(ci * 6 * SR); d = t(6.0); pad = np.zeros(len(d))
    for f in ch: pad += np.sin(2*np.pi*f*d) + 0.3*np.sin(2*np.pi*f*2*d)
    pad *= env(len(d), 1.5, 1.5) * 0.25
    mus[s:s+len(pad)] += pad
    for k in range(12):
        f = ch[k % 4] * 2; s2 = s + int(k * 0.5 * SR); dd = t(0.9)
        pl = np.sin(2*np.pi*f*dd) * expdecay(dd, 5) * env(len(dd), .004, .1) * 0.35
        mus[s2:s2+len(pl)] += pl[:len(mus)-s2]
save('music.wav', mus, 0.55)
print('audio written to', os.path.abspath(OUT))
