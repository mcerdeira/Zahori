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

# Teleport: disparo del proyectil ("piu" descendente de pulso fino)
d = 0.16
save("shoot", square(sweep(1400, 500, d), d, 0.125) * env(d, curve=2), 0.3)

# Teleport: el proyectil se deshace al chocar (chispa corta de ruido agudo)
d = 0.12
spark = noise(d)
save("pop", (spark - lowpass(spark, 0.4)) * env(d, attack=0.001, curve=3)
     + triangle(sweep(900, 1800, d), d) * env(d, curve=4) * 0.5, 0.3)

# Teleport: intercambio de lugar (barrido de ida y vuelta con vibrato)
d = 0.35
x = t(d)
f = 500 + 900 * np.sin(np.pi * x / d) + 40 * np.sin(2 * np.pi * 30 * x)
save("teleport", (square(f, d, 0.25) * 0.6 + triangle(f * 1.5, d) * 0.4) * env(d, attack=0.01, curve=1.5), 0.35)

# Evaporación del agua (hydro): siseo leve de ruido agudo que entra suave,
# se sostiene y se apaga (dura lo mismo que el efecto visual, ~1.8 s)
d = 1.8
hiss = noise(d)
hiss = hiss - lowpass(hiss, 0.35)  # pasaaltos: queda el "sss"
x = t(d)
shape = np.minimum(x / 0.25, 1.0) * np.clip((d - x) / 0.9, 0.0, 1.0) ** 1.5
wobble = 0.8 + 0.2 * np.sin(2 * np.pi * 7 * x)  # leve burbujeo
save("hiss", hiss * shape * wobble, 0.18)

# Enredadera enemiga. Usa su propio rng para no alterar el ruido de los demás sonidos.
vine_rng = np.random.default_rng(47)


def vine_noise(dur, step=1):
    n = int(RATE * dur)
    return np.repeat(vine_rng.uniform(-1, 1, n // step + 1), step)[:n]


# Despertar de la enredadera: rugido grave disonante con trémolo, un chillido que cae
# con vibrato nervioso y un raspado de ruido. Suena una vez cuando arranca a perseguir.
d = 1.8
x = t(d)
growl_env = np.minimum(x / 0.15, 1.0) * np.clip((d - x) / 1.0, 0.0, 1.0) ** 1.3
tremolo = 0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 11 * x))
growl = (square(sweep(62, 41, d), d, 0.5) + square(sweep(66, 43.5, d), d, 0.25)) * tremolo * growl_env
screech_f = sweep(1900, 330, d) * (1 + 0.035 * np.sin(2 * np.pi * 23 * x))
screech = (square(screech_f, d, 0.125) + square(screech_f * 1.06, d, 0.125)) \
    * np.minimum(x / 0.05, 1.0) * np.clip((d - x) / d, 0.0, 1.0) ** 2.2
rasp = lowpass(vine_noise(d, 3), 0.35) * growl_env * (0.5 + 0.5 * np.sin(2 * np.pi * 7 * x) ** 2)
save("vine_scream", growl * 0.55 + screech * 0.3 + rasp * 0.5, 0.6)

# Crecimiento: crujido corto de ramas (suena cada tantas celdas que avanza)
d = 0.07
crack = vine_noise(d, 2)
save("vine_creep", (crack - lowpass(crack, 0.5)) * env(d, attack=0.001, curve=5) * 0.7
     + square(sweep(120, 70, d), d, 0.25) * env(d, attack=0.001, curve=4) * 0.5, 0.3)

# Se come un bloque verde: masticado grave y áspero, tres mordidas que se arrastran
bites = []
for f in (150, 120, 95):
    d = 0.1
    grit = vine_noise(d, 4)
    bites.append(lowpass(grit, 0.45) * env(d, attack=0.002, curve=2.5)
                 + square(sweep(f, f * 0.6, d), d, 0.5) * env(d, attack=0.002, curve=3) * 0.7)
    bites.append(np.zeros(int(RATE * 0.03)))
save("vine_eat", concat(*bites), 0.5)

# Objeto obtenido (p. ej. la vara zahorí de la hermana): oscuro, no festivo. Dos golpes
# graves que bajan medio tono (la -> sol#) y un acorde disminuido (re, fa, sol#: el
# tritono) sobre un re grave, con trémolo lento y un leve desafinado que lo hace inquietante.
# Sin ruido: no toca el rng.
def dark_hit(f, d):
    return (triangle(f / 2, d) * 0.7 + square(f, d, 0.125) * 0.35) * env(d, attack=0.004, curve=2.5)


hits = concat(dark_hit(220.0, 0.22), dark_hit(207.65, 0.26))
d = 1.2
x = t(d)
trem = 0.7 + 0.3 * np.sin(2 * np.pi * 4.5 * x)
chord = (square(146.83, d, 0.125) * 0.3 + square(174.61 * 1.004, d, 0.125) * 0.25
         + square(207.65 * 0.997, d, 0.25) * 0.2 + triangle(73.42, d) * 0.75) \
    * trem * env(d, attack=0.03, curve=1.8)
save("item_get", concat(hits, chord), 0.5)

# Tableta de piedra: un fragmento encaja en su lugar. Golpe seco de piedra contra piedra
# (ruido grave filtrado) con un rebote más chico. Usa su propio rng.
tablet_rng = np.random.default_rng(23)


def stone_hit(d, f):
    n = int(RATE * d)
    grit = np.repeat(tablet_rng.uniform(-1, 1, n // 3 + 1), 3)[:n]
    return (lowpass(grit, 0.35) * 1.4 + triangle(sweep(f, f * 0.5, d), d) * 0.8) * env(d, attack=0.001, curve=4)


save("stone_clack", concat(stone_hit(0.16, 110), np.zeros(int(RATE * 0.04)), stone_hit(0.08, 90) * 0.4), 0.55)

# Tableta completa: la inscripción se revela. Zumbido grave que crece con un acorde
# menor agudo que titila arriba (la, do, mi), sin percusión: misterio, no fanfarria.
d = 2.4
x = t(d)
swell = np.minimum(x / 1.2, 1.0) * np.minimum((d - x) / 0.9, 1.0)
drone = triangle(55.0, d) * 0.8 + square(110.0 * 1.003, d, 0.125) * 0.2
shimmer = np.zeros_like(x)
for i, f in enumerate((880.0, 1046.5, 1318.5, 1046.5, 880.0, 1318.5)):
    start = int(RATE * (0.5 + i * 0.25))
    seg = triangle(f, 0.5) * env(0.5, attack=0.01, curve=2.0) * 0.18
    shimmer[start:start + len(seg)] += seg[:len(shimmer) - start]
save("tablet_reveal", drone * swell + shimmer, 0.5)

# Puerta sellada (level182): la puerta del laberinto se cierra para siempre detrás del
# player. Golpe grave de losa de piedra (ruido filtrado + barrido hacia abajo) y un
# retumbe largo que se apaga. Al apretar UP delante se usa el mismo, más agudo y bajito.
seal_rng = np.random.default_rng(31)
d = 0.9
n = int(RATE * d)
grit = np.repeat(seal_rng.uniform(-1, 1, n // 4 + 1), 4)[:n]
slam = (lowpass(grit, 0.25) * 1.6 + triangle(sweep(90, 35, d), d) * 0.9
        + square(sweep(70, 40, d), d, 0.25) * 0.25) * env(d, attack=0.002, curve=3.5)
rumble = lowpass(np.repeat(seal_rng.uniform(-1, 1, n // 8 + 1), 8)[:n], 0.15) * env(d, attack=0.05, curve=1.6) * 0.8
save("door_seal", slam + rumble, 0.6)
