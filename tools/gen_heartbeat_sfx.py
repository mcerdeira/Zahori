"""Genera el latido del corazón vegetal: sounds/heart_lub.wav y sounds/heart_dub.wav.

Va aparte de gen_sfx.py para poder ajustarlo sin regenerar los demás efectos.
Es un sub-grave casi puro (30-50 Hz): se siente más de lo que se oye, así que en parlantes
muy chicos pierde presencia.

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


def thump(dur, f0, f1, drive):
    """Golpe sub-grave: seno que cae de tono, apenas saturado y con un pasabajos fuerte."""
    n = int(RATE * dur)
    x = np.arange(n) / RATE
    phase = 2 * np.pi * np.cumsum(np.geomspace(f0, f1, n)) / RATE
    decay = (1.0 - x / dur) ** 2.2
    attack = np.minimum(x / 0.010, 1.0)
    body = np.tanh(np.sin(phase) * drive) * decay * attack
    for _ in range(3):  # cada pasada recorta lo que queda por encima de ~150 Hz
        body = lowpass(body, 0.045)
    return body


def save(name, x, peak):
    x = x / np.max(np.abs(x)) * peak
    fade = min(len(x), int(RATE * 0.01))
    x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


save("heart_lub", thump(0.46, 50, 30, 1.5), 0.86)
save("heart_dub", thump(0.34, 58, 36, 1.3), 0.62)
