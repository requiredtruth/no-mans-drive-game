#!/usr/bin/env python3
"""Synthesize the game's original sound effects and ambience loops (CC0).

Usage: python3 tools/gen_audio.py game/assets/audio   (needs ffmpeg for .ogg)
"""
import os
import subprocess
import sys
import wave

import numpy as np

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else "game/assets/audio"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def periodic_noise(n, lo, hi, seed):
    r = np.random.default_rng(seed)
    f = np.fft.rfft(r.normal(size=n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    f *= (freqs >= lo) & (freqs <= hi)
    x = np.fft.irfft(f, n)
    return x / np.abs(x).max()


def env(n, a, d):
    t = np.arange(n) / SR
    e = np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-np.maximum(t - a, 0) / d)
    return e


def lowpass(x, cutoff):
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    f *= 1 / (1 + (freqs / cutoff) ** 4)
    return np.fft.irfft(f, len(x))


def write(name, x, ogg=True):
    x = np.asarray(x, dtype=np.float64)
    x = x / max(np.abs(x).max(), 1e-6) * 0.9
    pcm = (x * 32767).astype(np.int16)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    if ogg:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", "5",
                        os.path.join(OUT, name + ".ogg")], check=True)
        os.remove(path)
    print("audio", name)


# Loops ---------------------------------------------------------------------
def engine_loop():
    n = SR * 2
    t = np.arange(n) / SR
    base = 30.0  # Hz, integer cycles per loop
    x = np.zeros(n)
    for h, a in [(1, 1.0), (2, 0.6), (3, 0.35), (4, 0.25), (6, 0.12), (8, 0.06)]:
        x += a * np.sin(2 * np.pi * base * h * t + h)
    pulses = (np.sin(2 * np.pi * base * t) > 0.6).astype(float)
    x += 0.5 * lowpass(pulses * periodic_noise(n, 50, 2000, 1), 900)
    x += 0.2 * periodic_noise(n, 40, 400, 2)
    write("engine_loop", x)


def wind_loop():
    n = SR * 8
    t = np.arange(n) / SR
    gust = 0.6 + 0.4 * np.sin(2 * np.pi * t / 8) * np.sin(2 * np.pi * 3 * t / 8)
    write("wind_loop", periodic_noise(n, 80, 900, 3) * gust)


def rain_loop():
    n = SR * 4
    x = periodic_noise(n, 400, 9000, 4) * 0.5
    drops = np.zeros(n)
    for p in rng.integers(0, n - 2000, 900):
        k = rng.uniform(0.2, 1)
        drops[p:p + 400] += k * np.exp(-np.arange(400) / 60) * rng.normal(size=400)
    write("rain_loop", x + drops * 0.4)


def fire_loop():
    n = SR * 4
    x = lowpass(periodic_noise(n, 30, 3000, 5), 600) * 0.6
    for p in rng.integers(0, n - 3000, 160):
        L = int(rng.uniform(150, 1500))
        x[p:p + L] += rng.uniform(0.3, 1.2) * np.exp(-np.arange(L) / (L / 6)) * rng.normal(size=L)
    write("fire_loop", x)


def crickets_loop():
    n = SR * 6
    t = np.arange(n) / SR
    x = np.zeros(n)
    for c in range(5):
        f = rng.uniform(3800, 5200)
        rate = rng.choice([1, 2, 3]) / 1.0 * 1.5  # chirps per second, periodic over 6s
        gate = (np.sin(2 * np.pi * rate * t + c) > 0.7).astype(float)
        trill = (np.sin(2 * np.pi * 40 * t) > 0).astype(float)
        x += np.sin(2 * np.pi * f * t) * gate * trill * rng.uniform(0.3, 1)
    write("crickets_loop", x + 0.05 * periodic_noise(n, 200, 2000, 6))


def birds_loop():
    n = SR * 10
    x = 0.08 * periodic_noise(n, 300, 3000, 8)
    for _ in range(26):
        p = int(rng.uniform(0, n - SR))
        L = int(SR * rng.uniform(0.06, 0.25))
        t = np.arange(L) / SR
        f0 = rng.uniform(2000, 4500)
        sweep = f0 + rng.uniform(-1500, 1500) * t / t[-1]
        ph = 2 * np.pi * np.cumsum(sweep) / SR
        x[p:p + L] += np.sin(ph) * np.sin(np.pi * t / t[-1]) * rng.uniform(0.2, 0.7)
    write("birds_loop", x)


def ocean_loop():  # river/lake lapping
    n = SR * 6
    t = np.arange(n) / SR
    write("water_loop", periodic_noise(n, 100, 2500, 9) * (0.6 + 0.4 * np.sin(2 * np.pi * t / 3)))


# One shots -----------------------------------------------------------------
def footstep(name, lo, hi, d):
    n = int(SR * 0.18)
    write(name, lowpass(rng.normal(size=n), hi) * env(n, 0.003, d))


def gunshot():
    n = int(SR * 1.2)
    x = rng.normal(size=n) * env(n, 0.001, 0.06)
    x += lowpass(rng.normal(size=n), 400) * env(n, 0.002, 0.35) * 2
    write("gunshot", x)


def bow():
    n = int(SR * 0.35)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * 110 * t * (1 + t)) * env(n, 0.002, 0.08)
    x += 0.4 * rng.normal(size=n) * env(n, 0.001, 0.03)
    write("bow", x)


def chop():
    n = int(SR * 0.3)
    t = np.arange(n) / SR
    x = lowpass(rng.normal(size=n), 2500) * env(n, 0.001, 0.04)
    x += np.sin(2 * np.pi * 180 * t) * env(n, 0.001, 0.07)
    write("chop", x)


def hit():
    n = int(SR * 0.2)
    t = np.arange(n) / SR
    write("hit", np.sin(2 * np.pi * 90 * t) * env(n, 0.001, 0.05) + 0.3 * rng.normal(size=n) * env(n, 0.001, 0.02))


def pickup():
    n = int(SR * 0.15)
    t = np.arange(n) / SR
    write("pickup", np.sin(2 * np.pi * (700 + 900 * t / t[-1]) * t) * env(n, 0.003, 0.05))


def click():
    n = int(SR * 0.05)
    t = np.arange(n) / SR
    write("click", np.sin(2 * np.pi * 1200 * t) * env(n, 0.001, 0.01))


def howl():
    n = int(SR * 2.6)
    t = np.arange(n) / SR
    f = 380 + 220 * np.sin(np.pi * t / t[-1]) + 10 * np.sin(2 * np.pi * 5 * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = (np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)) * np.sin(np.pi * t / t[-1]) ** 0.6
    write("howl", x)


def growl():
    n = int(SR * 0.9)
    t = np.arange(n) / SR
    x = lowpass(rng.normal(size=n), 300) * (0.6 + 0.4 * np.sin(2 * np.pi * 28 * t)) * env(n, 0.05, 0.4)
    write("growl", x)


def splash():
    n = int(SR * 0.7)
    write("splash", lowpass(rng.normal(size=n), 3000) * env(n, 0.005, 0.18))


def eat():
    n = int(SR * 0.5)
    x = np.zeros(n)
    for k in range(4):
        p = int(k * SR * 0.11)
        L = int(SR * 0.06)
        x[p:p + L] += lowpass(rng.normal(size=L), 1500) * env(L, 0.002, 0.02)
    write("eat", x)


def hammer():
    n = int(SR * 0.5)
    t = np.arange(n) / SR
    x = (np.sin(2 * np.pi * 220 * t) + 0.5 * np.sin(2 * np.pi * 517 * t)) * env(n, 0.001, 0.08)
    x += rng.normal(size=n) * env(n, 0.001, 0.015)
    write("hammer", x)


def door():
    n = int(SR * 0.6)
    t = np.arange(n) / SR
    creak = np.sin(2 * np.pi * np.cumsum(300 + 200 * np.sin(2 * np.pi * 3 * t)) / SR)
    x = 0.4 * creak * env(n, 0.05, 0.3)
    x[-int(SR * 0.12):] += lowpass(rng.normal(size=int(SR * 0.12)), 500) * env(int(SR * 0.12), 0.001, 0.03)
    write("door", x)


def engine_start():
    n = int(SR * 1.4)
    t = np.arange(n) / SR
    crank = (np.sin(2 * np.pi * 9 * t) > 0.3).astype(float) * lowpass(rng.normal(size=n), 800)
    crank *= (t < 0.8)
    f = np.where(t > 0.8, 30 + 25 * np.exp(-(t - 0.8) * 4), 0)
    rumble = np.sin(2 * np.pi * np.cumsum(f) / SR) * (t > 0.8)
    write("engine_start", crank * 0.7 + rumble)


def reel():
    n = int(SR * 0.5)
    t = np.arange(n) / SR
    write("reel", (np.sin(2 * np.pi * 40 * t) > 0.5) * rng.normal(size=n) * 0.6)


for fn in [engine_loop, wind_loop, rain_loop, fire_loop, crickets_loop, birds_loop, ocean_loop,
           gunshot, bow, chop, hit, pickup, click, howl, growl, splash, eat, hammer, door,
           engine_start, reel]:
    fn()
footstep("step_ground", 80, 900, 0.03)
footstep("step_wood", 100, 2500, 0.025)
footstep("step_snow", 200, 3500, 0.05)


# --- v1.2 ambience variety: many one-shot calls, scheduled randomly in-game ----
def _sweep(f0, f1, dur, shape="lin", vib=0.0, vib_rate=0.0, harm=(1.0,)):
    n = int(SR * dur)
    t = np.arange(n) / SR
    k = t / max(dur, 1e-6)
    if shape == "exp":
        f = f0 * (f1 / f0) ** k
    elif shape == "arch":
        f = f0 + (f1 - f0) * np.sin(np.pi * k)
    else:
        f = f0 + (f1 - f0) * k
    f = f * (1 + vib * np.sin(2 * np.pi * vib_rate * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = sum(a * np.sin((i + 1) * ph) for i, a in enumerate(harm))
    return x * np.sin(np.pi * np.clip(k, 0, 1)) ** 0.5


def _seq(parts, gap_range=(0.03, 0.08), r=None):
    out = []
    for p in parts:
        out.append(p)
        out.append(np.zeros(int(SR * r.uniform(*gap_range))))
    return np.concatenate(out + [np.zeros(int(SR * 0.15))])


def birds_variety():
    r = np.random.default_rng(1001)
    for v in range(4):  # sparrow-like chip series
        base = r.uniform(3800, 5200)
        notes = [_sweep(base * r.uniform(0.95, 1.05), base * r.uniform(0.7, 0.85), r.uniform(0.03, 0.06)) for _ in range(r.integers(4, 9))]
        write("bird_chip_%d" % v, _seq(notes, (0.04, 0.09), r))
    for v in range(4):  # robin-like warble phrases
        notes = []
        for _ in range(r.integers(4, 7)):
            f0 = r.uniform(2000, 3400)
            notes.append(_sweep(f0, f0 * r.uniform(0.8, 1.3), r.uniform(0.08, 0.18), "arch", 0.02, 40))
        write("bird_warble_%d" % v, _seq(notes, (0.02, 0.12), r))
    for v in range(3):  # wren-like fast trill
        f = r.uniform(4000, 6000)
        n = int(SR * r.uniform(0.8, 1.4))
        t = np.arange(n) / SR
        am = (np.sin(2 * np.pi * r.uniform(18, 28) * t) > 0).astype(float)
        x = np.sin(2 * np.pi * np.cumsum(f * (1 - 0.25 * t / t[-1]) + 300 * np.sin(2 * np.pi * 22 * t)) / SR) * am
        write("bird_trill_%d" % v, x * np.sin(np.pi * t / t[-1]))
    for v in range(3):  # two-note whistle "fee-bee"
        f = r.uniform(3000, 3800)
        notes = [_sweep(f, f, 0.32), _sweep(f * 0.84, f * 0.82, 0.38)]
        if v == 2:
            notes.append(_sweep(f * 0.84, f * 0.82, 0.3))
        write("bird_whistle_%d" % v, _seq(notes, (0.05, 0.1), r))
    for v in range(2):  # descending song (meadowlark-ish)
        notes = [_sweep(r.uniform(3000, 4200), r.uniform(1800, 2600), r.uniform(0.15, 0.3), "exp", 0.01, 30) for _ in range(4)]
        write("bird_song_%d" % v, _seq(notes, (0.01, 0.05), r))
    for v in range(3):  # crow caw
        notes = []
        for _ in range(r.integers(2, 5)):
            d = r.uniform(0.25, 0.4)
            n = int(SR * d)
            nz = lowpass(r.normal(size=n), 2200)
            tone = _sweep(r.uniform(500, 650), r.uniform(380, 450), d, harm=(1, 0.8, 0.6, 0.4, 0.3))
            notes.append((nz * 0.6 + tone) * env(n, 0.02, d * 0.6))
        write("crow_%d" % v, _seq(notes, (0.12, 0.25), r))
    for v in range(2):  # woodpecker drumming
        n = int(SR * 1.2)
        x = np.zeros(n)
        rate = r.uniform(14, 20)
        for k in range(int(rate * 0.9)):
            p = int(k / rate * SR)
            L = 600
            x[p:p + L] += lowpass(r.normal(size=L), 1800) * np.exp(-np.arange(L) / 90) * (1 - k / (rate * 0.9) * 0.5)
        write("woodpecker_%d" % v, x)
    for v in range(2):  # dove coo
        notes = [_sweep(520, 600, 0.35, "arch", harm=(1, 0.3)), _sweep(560, 480, 0.6, "arch", harm=(1, 0.3)), _sweep(500, 470, 0.4, harm=(1, 0.3))]
        write("dove_%d" % v, _seq(notes, (0.1, 0.25), r))
    for v in range(3):  # owl hoots (night)
        notes = [_sweep(r.uniform(330, 400), r.uniform(300, 360), r.uniform(0.25, 0.6), "arch", harm=(1, 0.15)) for _ in range(r.integers(2, 5))]
        write("owl_%d" % v, _seq(notes, (0.15, 0.45), r))
    for v in range(2):  # hawk screech
        write("hawk_%d" % v, _sweep(3200, 1900, 1.1, "exp", 0.04, 50, harm=(1, 0.5, 0.3)) + 0.2 * lowpass(r.normal(size=int(SR * 1.1)), 4000) * env(int(SR * 1.1), 0.05, 0.6))
    for v in range(3):  # frogs
        notes = []
        for _ in range(r.integers(3, 8)):
            d = r.uniform(0.08, 0.18)
            n = int(SR * d)
            t = np.arange(n) / SR
            pulse = (np.sin(2 * np.pi * r.uniform(60, 110) * t) > 0.3).astype(float)
            notes.append(lowpass(r.normal(size=n), 900) * pulse * env(n, 0.005, d * 0.5) + 0.4 * np.sin(2 * np.pi * r.uniform(180, 300) * t) * env(n, 0.005, d * 0.5))
        write("frog_%d" % v, _seq(notes, (0.08, 0.3), r))
    for v in range(2):  # coyote yips (desert night)
        notes = [_sweep(r.uniform(700, 900), r.uniform(1100, 1500), r.uniform(0.1, 0.25), "arch", 0.03, 25, harm=(1, 0.4)) for _ in range(r.integers(4, 8))]
        write("coyote_%d" % v, _seq(notes, (0.03, 0.12), r))
    for v in range(4):  # wind gusts
        n = int(SR * r.uniform(2.5, 4.5))
        t = np.arange(n) / SR
        g = np.sin(np.pi * t / t[-1]) ** 2
        write("gust_%d" % v, lowpass(r.normal(size=n), r.uniform(500, 1100)) * g)
    for v in range(3):  # leaves rustle
        n = int(SR * r.uniform(1.0, 2.0))
        x = r.normal(size=n) * (0.3 + 0.7 * (np.abs(lowpass(r.normal(size=n), 6)) > 0.3))
        f = np.fft.rfft(x)
        fr = np.fft.rfftfreq(n, 1 / SR)
        f *= (fr > 1500) & (fr < 9000)
        x = np.fft.irfft(f, n)
        write("leaves_%d" % v, x * np.sin(np.pi * np.arange(n) / n))
    for v in range(2):  # distant thunder
        n = int(SR * 4.0)
        write("thunder_%d" % v, lowpass(r.normal(size=n), 160) * env(n, 0.3, 1.2) + lowpass(r.normal(size=n), 400) * env(n, 0.05, 0.3) * 0.5)
    # gentler beds
    n = SR * 8
    t = np.arange(n) / SR
    write("insects_day_loop", periodic_noise(n, 5000, 8000, 77) * (0.6 + 0.4 * np.sin(2 * np.pi * t / 4)) * 0.4)
    write("forest_bed_loop", periodic_noise(n, 150, 1200, 78) * 0.5)


birds_variety()
