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
