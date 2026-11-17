#!/usr/bin/env python3
"""Synthesize the van radio's original road-trip tunes (CC0): plucked-string chords, bass and
brushed drums through a small-speaker band-pass with a little static. Each tune loops seamlessly.

Usage: python3 tools/gen_radio.py game/assets/audio   (needs ffmpeg)
"""
import os
import subprocess
import sys
import wave

import numpy as np

SR = 32000
OUT = sys.argv[1] if len(sys.argv) > 1 else "game/assets/audio"
NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def hz(name, octave):
    return 440.0 * 2 ** ((NOTE[name] + 12 * (octave - 4) - 9) / 12)


def pluck(f, dur, rng, bright=0.5):
    """Karplus-Strong plucked string."""
    n = int(SR * dur)
    p = max(int(SR / f), 2)
    buf = rng.uniform(-1, 1, p) * bright + rng.uniform(-1, 1, p) * (1 - bright) * 0.3
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = 0.996 * 0.5 * (buf[i % p] + buf[(i + 1) % p])
    return out


def chord_tones(root, quality):
    r = NOTE[root]
    iv = {"maj": [0, 4, 7, 12], "min": [0, 3, 7, 12], "7": [0, 4, 7, 10], "sus": [0, 5, 7, 12]}[quality]
    names = list(NOTE.keys())
    return [(names[(r + i) % 12], 3 + (r + i) // 12) for i in iv]


def tune(name, prog, bpm, seed, swing=0.0):
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bars = len(prog)
    total = int(SR * beat * 4 * bars)
    mix = np.zeros(total + SR * 3)

    def add(sig, t, gain):
        i = int(t * SR)
        mix[i:i + len(sig)] += sig[: len(mix) - i] * gain

    for b, (root, q) in enumerate(prog):
        t0 = b * 4 * beat
        tones = chord_tones(root, q)
        # finger-picked pattern
        pattern = [0, 2, 1, 3, 0, 2, 1, 2]
        for k, idx in enumerate(pattern):
            t = t0 + k * beat * 0.5 + (swing * beat * 0.5 if k % 2 else 0)
            nm, octv = tones[idx]
            add(pluck(hz(nm, octv + 1), 1.6, rng, 0.6), t, 0.28)
        # bass on 1 and 3
        for k in (0, 2):
            nm, octv = tones[0] if k == 0 else tones[2]
            add(pluck(hz(nm, 2), 1.2, rng, 0.9), t0 + k * beat, 0.55)
        # brushed snare on 2 and 4, soft kick on 1 and 3
        for k in range(4):
            tt = t0 + k * beat
            nn = int(0.18 * SR)
            if k % 2 == 1:
                noise = rng.normal(size=nn) * np.exp(-np.arange(nn) / (0.05 * SR))
                add(noise, tt, 0.12)
            else:
                ts = np.arange(int(0.25 * SR)) / SR
                kick = np.sin(2 * np.pi * (55 + 60 * np.exp(-ts * 30)) * ts) * np.exp(-ts * 12)
                add(kick, tt, 0.35)
        # a simple melody: chord tones an octave up, every other bar
        if b % 2 == 1:
            for k in range(3):
                nm, octv = tones[(k * 2 + b) % 4]
                add(pluck(hz(nm, octv + 2), 0.9, rng, 0.8), t0 + k * beat * 1.33, 0.18)
    # wrap the tail so the loop is seamless
    tail = mix[total:]
    mix = mix[:total].copy()
    mix[: len(tail)] += tail
    # small speaker: band-pass 180 Hz .. 4.5 kHz, mild saturation, static hiss
    f = np.fft.rfft(mix)
    fr = np.fft.rfftfreq(len(mix), 1 / SR)
    f *= 1 / (1 + (180 / np.maximum(fr, 1)) ** 4) / (1 + (fr / 4500) ** 4)
    mix = np.fft.irfft(f, len(mix))
    mix = np.tanh(mix / (np.abs(mix).max() + 1e-9) * 1.6)
    mix += rng.normal(size=len(mix)) * 0.012
    mix = mix / np.abs(mix).max() * 0.85
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((mix * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", "4",
                    os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(path)
    print("radio", name)


tune("radio_0", [("G", "maj"), ("D", "maj"), ("E", "min"), ("C", "maj")] * 3, 92, 1, 0.12)
tune("radio_1", [("A", "min"), ("F", "maj"), ("C", "maj"), ("G", "maj"), ("A", "min"), ("F", "maj"), ("E", "7"), ("E", "7")] * 2, 76, 2, 0.0)
tune("radio_2", [("D", "maj"), ("D", "sus"), ("G", "maj"), ("A", "7")] * 3, 104, 3, 0.2)
