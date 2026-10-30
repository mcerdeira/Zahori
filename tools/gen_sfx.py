"""Genera los efectos de sonido del juego (estilo 8-bit) en sounds/*.wav.

Uso: python3 tools/gen_sfx.py
"""
import wave
from pathlib import Path

import numpy as np

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "sounds"
rng = np.random.default_rng(7)


def t(dur):
    return np.arange(int(RATE * dur)) / RATE


def square(freq, dur, duty=0.5):
    """Onda cuadrada; freq puede ser un array (barrido)."""
    f = np.broadcast_to(freq, t(dur).shape)
    phase = np.cumsum(f) / RATE
    return np.where(phase % 1.0 < duty, 1.0, -1.0)


def triangle(freq, dur):
    f = np.broadcast_to(freq, t(dur).shape)
    phase = np.cumsum(f) / RATE
    return 4.0 * np.abs(phase % 1.0 - 0.5) - 1.0


def noise(dur, step=1):
    """Ruido blanco; step > 1 lo hace más grave (sample & hold)."""
    n = int(RATE * dur)
    vals = rng.uniform(-1, 1, n // step + 1)
    return np.repeat(vals, step)[:n]


def lowpass(x, a):
    """Filtro pasabajos de un polo (a cerca de 0 = más grave; puede ser un array)."""
    a = np.broadcast_to(a, x.shape)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a[i] * (v - acc)
        y[i] = acc
    return y


def env(dur, attack=0.005, curve=2.0):
    """Envolvente: ataque lineal corto y caída exponencial."""
    x = t(dur)
    e = (1.0 - x / dur) ** curve
    a = int(RATE * attack)
    if a:
        e[:a] *= np.linspace(0, 1, a)
    return e


def sweep(f0, f1, dur):
    return np.geomspace(f0, f1, len(t(dur)))


def concat(*parts):
    return np.concatenate(parts)


def save(name, x, gain=0.5):
    x = x / max(np.max(np.abs(x)), 1e-9) * gain
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    OUT.mkdir(exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print(f"sounds/{name}.wav")


# Bloque generado: "tuc" corto y ascendente (el código sube el pitch por altura)
d = 0.09
save("block", square(sweep(330, 520, d), d, 0.25) * env(d, curve=3) * 0.8
     + lowpass(noise(d), 0.3) * env(d, curve=8) * 0.6, 0.45)

# Bloque desvaneciéndose: blip suave descendente
d = 0.12
save("vanish", triangle(sweep(700, 350, d), d) * env(d, curve=2), 0.35)

# Aterrizaje: golpe sordo
d = 0.08
save("land", lowpass(noise(d, 2), 0.15) * env(d, curve=4)
     + triangle(sweep(140, 60, d), d) * env(d, curve=3) * 0.7, 0.5)

# Paso: click muy corto
d = 0.03
save("step", lowpass(noise(d), 0.25) * env(d, attack=0.001, curve=5), 0.25)

# Puerta: arpegio ascendente
notes = [392, 523, 659, 784]
nd = 0.08
save("door", concat(*[square(f, nd, 0.5) * env(nd, curve=1.2) for f in notes[:-1]],
                    square(notes[-1], 0.25, 0.5) * env(0.25, curve=2)), 0.3)

# Muerte en el agua: chapuzón + explosión
d = 0.5
splash = lowpass(noise(d), sweep(0.9, 0.05, d)) * env(d, attack=0.002, curve=2.5)
boom = lowpass(noise(d, 4), 0.2) * env(d, attack=0.001, curve=3)
save("die", splash * 0.8 + boom + square(sweep(300, 40, d), d) * env(d, curve=4) * 0.3, 0.55)

# Inicio del juego (intro): acorde arpegiado
nd = 0.1
save("start", concat(*[triangle(f, nd) * env(nd, curve=1) for f in (523, 659, 784)],
                     triangle(1047, 0.5) * env(0.5, curve=2)), 0.4)
