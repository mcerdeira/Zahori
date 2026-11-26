"""Genera el latido del corazón vegetal: sounds/heart_lub.wav y sounds/heart_dub.wav.

Va aparte de gen_sfx.py para poder ajustarlo sin regenerar los demás efectos.
Un golpe grave (~45-75 Hz) con armónicos y un "toc" amortiguado en el ataque, para que se oiga
también en parlantes chicos o auriculares, que no reproducen el sub-grave.

Uso: python3 tools/gen_heartbeat_sfx.py
"""
import wave
from pathlib import Path

import numpy as np

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "sounds"


def lowpass(x, a):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y


def thump(dur, f0, f1, drive, seed):
    """Golpe grave: seno que cae de tono, saturado para sumar armónicos, más un toc de ruido filtrado."""
    rng = np.random.default_rng(seed)
    n = int(RATE * dur)
    x = np.arange(n) / RATE
    phase = 2 * np.pi * np.cumsum(np.geomspace(f0, f1, n)) / RATE
    decay = (1.0 - x / dur) ** 2.2
    attack = np.minimum(x / 0.006, 1.0)
    body = np.tanh((np.sin(phase) + 0.6 * np.sin(2 * phase) + 0.3 * np.sin(3 * phase)) * drive) * decay * attack
    body = lowpass(lowpass(body, 0.12), 0.12)  # deja pasar hasta ~500 Hz
    knock = rng.uniform(-1, 1, n) * np.exp(-x / 0.018)
    knock = lowpass(lowpass(knock, 0.09), 0.09)  # toc sordo (~300 Hz)
    knock /= np.max(np.abs(knock))
    return body + 0.9 * knock


def save(name, x, peak):
    x = x / np.max(np.abs(x)) * peak
    fade = min(len(x), int(RATE * 0.01))
    x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


save("heart_lub", thump(0.46, 90, 55, 3.0, 1), 0.86)
save("heart_dub", thump(0.34, 100, 62, 2.8, 2), 0.62)
