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

# Puerta: pasos bajando una escalera (cada escalón más grave y un poco más rápido).
# Usa su propio rng para no alterar el ruido de los demás sonidos.
door_rng = np.random.default_rng(11)
steps = []
for i, (f, gap) in enumerate([(220, 0.13), (185, 0.12), (155, 0.11), (130, 0.0)]):
    d = 0.07
    n = int(RATE * d)
    grit = np.repeat(door_rng.uniform(-1, 1, n // 2 + 1), 2)[:n]
    thud = (lowpass(grit, 0.2) * env(d, attack=0.001, curve=5)
            + triangle(sweep(f, f * 0.55, d), d) * env(d, attack=0.001, curve=3) * 0.9)
    steps.append(thud * (1.0 - i * 0.08))
    steps.append(np.zeros(int(RATE * gap)))
save("door", concat(*steps), 0.45)

# Muerte en el agua: chapuzón + explosión
d = 0.5
splash = lowpass(noise(d), sweep(0.9, 0.05, d)) * env(d, attack=0.002, curve=2.5)
boom = lowpass(noise(d, 4), 0.2) * env(d, attack=0.001, curve=3)
save("die", splash * 0.8 + boom + square(sweep(300, 40, d), d) * env(d, curve=4) * 0.3, 0.55)

# Inicio del juego (intro): acorde arpegiado
nd = 0.1
save("start", concat(*[triangle(f, nd) * env(nd, curve=1) for f in (523, 659, 784)],
                     triangle(1047, 0.5) * env(0.5, curve=2)), 0.4)

# Terminal: rng propio para no alterar el ruido de los demás sonidos
term_rng = np.random.default_rng(23)

# Encendido del monitor: zumbido grave que sube + pitido agudo del tubo
d = 0.4
hum = square(sweep(50, 120, d), d, 0.5) * env(d, attack=0.01, curve=2)
whine = triangle(3520.0, d) * np.linspace(0, 1, len(t(d))) * env(d, attack=0.0, curve=0.6)
save("term_on", hum * 0.6 + whine * 0.2, 0.35)

# Apagado del monitor: "piuu" descendente
d = 0.2
save("term_off", square(sweep(600, 60, d), d, 0.25) * env(d, curve=1.5), 0.3)

# Tecla: click seco y muy corto
d = 0.018
click = term_rng.uniform(-1, 1, len(t(d)))
save("term_key", (click - lowpass(click, 0.3)) * env(d, attack=0.0005, curve=4), 0.3)

# Glifo descifrado: dos pitidos ascendentes
nd = 0.09
save("term_ok", concat(square(880, nd, 0.5) * env(nd, curve=0.8),
                       square(1320, 0.2, 0.5) * env(0.2, curve=2)), 0.25)

# Intento fallido: zumbido grave
d = 0.22
save("term_err", square(110, d, 0.5) * env(d, attack=0.002, curve=1.2)
     + square(116, d, 0.5) * env(d, attack=0.002, curve=1.2), 0.25)

# Mordida (habilidad eat): dos crujidos rápidos, el segundo más grave.
# Usa su propio rng para no alterar el ruido de los demás sonidos.
chomp_rng = np.random.default_rng(31)
bites = []
for f, gap in [(260, 0.035), (170, 0.0)]:
    d = 0.06
    n = int(RATE * d)
    grit = np.repeat(chomp_rng.uniform(-1, 1, n // 3 + 1), 3)[:n]
    bites.append(lowpass(grit, 0.5) * env(d, attack=0.001, curve=4)
                 + square(sweep(f, f * 0.5, d), d, 0.25) * env(d, attack=0.001, curve=3) * 0.6)
    bites.append(np.zeros(int(RATE * gap)))
save("chomp", concat(*bites), 0.45)

# Varita zahorí: "ping" cristalino corto (el código lo repite más rápido y más
# agudo cuanto más cerca está la puerta correcta). Sin ruido: no toca el rng.
d = 0.12
save("dowse", (triangle(1568, d) + triangle(2352, d) * 0.35) * env(d, attack=0.002, curve=3), 0.3)

# Voz sintética de la intro (fonemas inventados, estilo "animalese" grave y
# solemne): una sílaba por letra. 5 vocales x 3 ataques -> voice_<ataque><vocal>.wav
# Fuente glotal (diente de sierra con vibrato y caída de tono) pasada por dos
# formantes resonantes, como una vocal humana muy simplificada.
from scipy.signal import iirpeak, lfilter, sawtooth

voice_rng = np.random.default_rng(53)
FORMANTS = {"a": (730, 1090), "e": (530, 1840), "i": (300, 2200),
            "o": (570, 840), "u": (320, 800)}
VOICE_F0 = 98.0   # Hz, tono base (grave)
VOICE_DUR = 0.13  # segundos por sílaba


def formant_vowel(f1, f2, dur, f0=VOICE_F0):
    x = t(dur)
    freq = f0 * (1.0 - 0.06 * x / dur) * (1.0 + 0.012 * np.sin(2 * np.pi * 5.5 * x))
    src = sawtooth(2 * np.pi * np.cumsum(freq) / RATE)
    src += voice_rng.uniform(-1, 1, len(x)) * 0.05  # algo de aire
    out = np.zeros_like(src)
    for f, q, g in ((f1, 6, 1.0), (f2, 9, 0.6), (2600, 10, 0.15)):
        b, a = iirpeak(f, q, RATE)
        out += lfilter(b, a, src) * g
    return out


for v, (f1, f2) in FORMANTS.items():
    d = VOICE_DUR
    vowel = formant_vowel(f1, f2, d)
    e = env(d, attack=0.012, curve=1.4)
    # sola: vocal pura
    save(f"voice_{v}", vowel * e, 0.5)
    # "m": arranca nasal (formante grave, sin brillo) y se abre a la vocal
    nasal = formant_vowel(250, 900, d)
    mix = np.clip(t(d) / 0.035, 0, 1)
    save(f"voice_m{v}", (nasal * (1 - mix) * 0.7 + vowel * mix) * e, 0.5)
    # "k": golpecito de ruido filtrado antes de la vocal
    bd = 0.018
    burst = lowpass(voice_rng.uniform(-1, 1, int(RATE * bd)), 0.6) * env(bd, attack=0.0005, curve=2)
    save(f"voice_k{v}", concat(burst * 0.5, (vowel * e)[: int(RATE * (d - bd))]), 0.5)
