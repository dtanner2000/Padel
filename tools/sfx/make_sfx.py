"""Synthesises the game's sound effects into assets/sfx/*.wav (22.05 kHz mono).
Everything is generated from noise and sine partials, so there are no licences
to track and the set is tiny. Re-run after tweaking:  python3 tools/sfx/make_sfx.py
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt
import os

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "sfx")
rng = np.random.default_rng(7)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, attack, decay):
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    return a * np.exp(-x / decay)


def band(x, lo, hi, order=2):
    sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, x)


def lowpass(x, f, order=2):
    return sosfilt(butter(order, f, btype="low", fs=SR, output="sos"), x)


def highpass(x, f, order=2):
    return sosfilt(butter(order, f, btype="high", fs=SR, output="sos"), x)


def partials(sec, freqs, decays, amps):
    x = t(sec)
    out = np.zeros_like(x)
    for f, d, a in zip(freqs, decays, amps):
        out += a * np.sin(2 * np.pi * f * x + rng.uniform(0, 6)) * np.exp(-x / d)
    return out


def save(name, x, peak=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = min(len(x), int(SR * 0.004))
    x[-fade:] *= np.linspace(1, 0, fade)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))
    print(f"{name}.wav  {len(x) / SR:.2f}s")


# paddle: the hollow "pock" of a foam-core padel paddle
n = int(SR * 0.12)
click = highpass(rng.normal(size=n), 2500) * env(n, 0.0003, 0.002)
body = partials(0.12, [820, 1380, 2150, 520], [0.018, 0.012, 0.008, 0.03], [1.0, 0.6, 0.3, 0.5])
save("paddle", click * 0.8 + body)

# smash: harder crack with more low body
n = int(SR * 0.2)
crack = highpass(rng.normal(size=n), 1800) * env(n, 0.0002, 0.004)
body = partials(0.2, [610, 1050, 1720, 330], [0.03, 0.02, 0.012, 0.05], [1.0, 0.7, 0.35, 0.8])
save("smash", crack * 1.2 + body, 0.95)

# floor: soft thud on sanded turf
n = int(SR * 0.1)
thud = lowpass(rng.normal(size=n), 900) * env(n, 0.0005, 0.012)
save("floor", thud + partials(0.1, [170, 260], [0.02, 0.012], [0.6, 0.3]), 0.7)

# glass: a dull boom from a big pane, plus a short ring
n = int(SR * 0.35)
hit = lowpass(rng.normal(size=n), 2200) * env(n, 0.0005, 0.01)
pane = partials(0.35, [95, 140, 410, 690, 1230], [0.12, 0.08, 0.05, 0.03, 0.02], [1.0, 0.7, 0.35, 0.25, 0.12])
save("glass", hit * 0.6 + pane, 0.85)

# mesh: metal fence rattle, a jangly burst of inharmonic partials
n = int(SR * 0.45)
x = t(0.45)
jangle = np.zeros(n)
for f in rng.uniform(1800, 5200, 14):
    jangle += np.sin(2 * np.pi * f * x + rng.uniform(0, 6)) * np.exp(-x / rng.uniform(0.04, 0.16))
rattle = band(rng.normal(size=n), 1500, 6000) * env(n, 0.001, 0.08) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 38 * x)))
save("mesh", jangle * 0.25 + rattle + partials(0.45, [210], [0.06], [0.6]), 0.8)

# net: soft rustle
n = int(SR * 0.18)
save("net", band(rng.normal(size=n), 600, 3500) * env(n, 0.01, 0.05), 0.55)

# squeak: trainers on turf
x = t(0.09)
f = np.linspace(2300, 3300, len(x)) + 120 * np.sin(2 * np.pi * 55 * x)
ph = 2 * np.pi * np.cumsum(f) / SR
sq = (np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.2 * np.sin(3 * ph)) * np.sin(np.pi * x / x[-1]) ** 1.5
save("squeak", sq, 0.35)

# click: UI tap
save("click", partials(0.05, [1900, 3100], [0.006, 0.004], [1.0, 0.4]) + highpass(rng.normal(size=int(SR * 0.05)), 3000) * env(int(SR * 0.05), 0.0002, 0.002) * 0.4, 0.5)

# ding: challenge goal (bright bell)
save("ding", partials(0.9, [1320, 2640, 3960, 1980], [0.35, 0.2, 0.1, 0.25], [1.0, 0.4, 0.2, 0.3]), 0.7)

# buzz: challenge miss
x = t(0.35)
saw = 2 * ((110 * x) % 1.0) - 1 + 0.5 * (2 * ((165 * x) % 1.0) - 1)
save("buzz", lowpass(saw, 1200) * np.exp(-x / 0.15) * np.clip(x / 0.01, 0, 1), 0.45)


# applause: many hand claps, swelling then dying away
def applause(sec, claps_per_sec, peak_at):
    n = int(SR * sec)
    out = np.zeros(n)
    x = np.arange(n) / SR
    shape = np.clip(x / peak_at, 0, 1) ** 0.7 * np.exp(-np.clip(x - peak_at, 0, None) / (sec * 0.35))
    count = int(claps_per_sec * sec)
    for _ in range(count):
        at = rng.uniform(0, sec - 0.05)
        if rng.uniform() > shape[int(at * SR)]:
            continue
        ln = int(SR * rng.uniform(0.012, 0.03))
        c = band(rng.normal(size=ln), rng.uniform(800, 1400), rng.uniform(2500, 4500)) * env(ln, 0.0005, rng.uniform(0.004, 0.009))
        i = int(at * SR)
        out[i:i + ln] += c * rng.uniform(0.3, 1.0)
    bed = lowpass(rng.normal(size=n), 1800) * shape * 0.04   # murmur under the claps
    return out + bed

# Applause is now real recordings (assets/sfx/applause*.ogg, Mixkit free licence),
# trimmed from mixkit-small-crowd-clapping-3035 and mixkit-cheering-crowd-loud-whistle-610.
# The synthesised versions below are kept for reference only.
# save("applause", applause(2.6, 260, 0.35), 0.6)
# save("applause_big", applause(4.0, 520, 0.5), 0.75)
