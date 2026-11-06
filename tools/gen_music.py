"""Genera el tema principal del juego (music/main_theme.ogg), pensado para sonar en loop.

Chiptune opresivo y deprimente, con los mismos "instrumentos" que una consola de
8 bits (y que los SFX de tools/gen_sfx.py):
  - pulse 1: melodía (onda cuadrada angosta, con vibrato y eco)
  - pulse 2: arpegios lentos de los acordes, graves y bajitos
  - triángulo: bajo (forma de onda escalonada de 4 bits)
  - ruido: latido "lub-dub" y tic-tac de reloj (ruido de LFSR, como el NES)
Los volúmenes van en 16 escalones, como los registros de volumen de 4 bits.

En La menor, lento, con un bajo que baja de a semitono (lamento), el acorde de
Si bemol (segundo grado frigio) chocando contra el La y un disminuido sin resolver.

El final se encadena con el principio (las colas se suman al comienzo), así el
loop no tiene corte.

Uso: python3 tools/gen_music.py   (necesita numpy y ffmpeg con libvorbis)
"""
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

RATE = 44100
BPM = 58
BEAT = 60.0 / BPM
BAR = BEAT * 4
OUT = Path(__file__).resolve().parent.parent / "music" / "main_theme.ogg"


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def t(dur):
    return np.arange(int(RATE * dur)) / RATE


def steps(env):
    """Cuantiza una envolvente a 16 niveles (volumen de 4 bits)."""
    return np.round(np.clip(env, 0, 1) * 15) / 15


def decay_env(dur, attack=0.005, decay=1.0, sustain=0.0, release=0.05):
    """Ataque corto, caída exponencial hacia sustain y corte al final."""
    tt = t(dur)
    e = sustain + (1 - sustain) * np.exp(-tt * decay)
    e *= np.clip(tt / max(attack, 1e-4), 0, 1)
    e *= np.clip((dur - tt) / release, 0, 1)
    return steps(e)


# --- Canales --------------------------------------------------------------------

def pulse(m, dur, duty, env, vibrato=0.0):
    tt = t(dur)
    f = hz(m)
    if vibrato:
        # El vibrato entra recién después de medio segundo, como en los juegos de NES
        f = f * (1 + vibrato * np.sin(2 * np.pi * 5.0 * tt) * np.clip((tt - 0.5) / 0.5, 0, 1))
        ph = np.cumsum(f) / RATE
    else:
        ph = f * tt
    # Se resta la continua: una cuadrada angosta está casi siempre abajo y, si no,
    # cada nota sería un "empujón" inaudible que se come el volumen y hace clicks
    return (np.where(ph % 1 < duty, 1.0, -1.0) - (2 * duty - 1)) * env


def triangle(m, dur, env):
    """Triángulo de 4 bits: 16 escalones por subida, como el canal del NES."""
    ph = hz(m) * t(dur) % 1
    tri = np.abs(ph * 2 - 1) * 2 - 1
    return np.round(tri * 7.5) / 7.5 * env


def lfsr(n, short):
    """Ruido del NES: registro de 15 bits; short=True da el ruido metálico (93 pasos)."""
    reg = 1
    tap = 6 if short else 1
    out = np.empty(n)
    for i in range(n):
        bit = (reg ^ (reg >> tap)) & 1
        reg = (reg >> 1) | (bit << 14)
        out[i] = 1.0 if reg & 1 else -1.0
    return out


NOISE_LONG = lfsr(32767, False)
NOISE_SHORT = lfsr(93, True)


def noise(dur, rate, short, env):
    """rate: veces por segundo que avanza el registro (más bajo = más grave)."""
    idx = (np.arange(int(RATE * dur)) * rate / RATE).astype(int)
    src = NOISE_SHORT if short else NOISE_LONG
    return src[idx % len(src)] * env


def heartbeat():
    """Latido grave: "lub" y un "dub" más débil."""
    d = 0.22
    lub = noise(d, 1800, False, decay_env(d, 0.002, 22)) * 0.9 \
        + triangle(33, d, decay_env(d, 0.002, 14)) * 1.2
    dub = noise(d, 1500, False, decay_env(d, 0.002, 26)) * 0.5 \
        + triangle(31, d, decay_env(d, 0.002, 16)) * 0.8
    gap = int(RATE * 0.28)
    out = np.zeros(gap + len(dub))
    out[:len(lub)] += lub
    out[gap:] += dub
    return out * 0.45


def tick():
    """Tic de reloj: ruido metálico cortísimo."""
    d = 0.03
    return noise(d, 9000, True, decay_env(d, 0.0005, 160)) * 0.07


# --- Partitura ------------------------------------------------------------------
# Acorde: (nota del bajo, notas del arpegio). A4 = 69.

CH = {
    "Am":     (45, [57, 60, 64, 69]),
    "Am/G#":  (44, [56, 60, 64, 69]),
    "Am/G":   (43, [55, 60, 64, 69]),
    "F#m7b5": (42, [54, 57, 60, 64]),
    "Bb/F":   (41, [53, 58, 62, 65]),
    "E":      (40, [52, 56, 59, 64]),
    "Edim":   (40, [52, 55, 58, 64]),
    "Bb":     (46, [53, 58, 62, 65]),
    "Gm":     (43, [55, 58, 62, 67]),
    "E7b9":   (40, [52, 56, 62, 65]),
}

INTRO = ["Am", "Am/G#", "Am/G", "F#m7b5"]
A = ["Am", "Am/G#", "Am/G", "F#m7b5", "Bb/F", "E", "Am", "Edim"]
B = ["Am", "Bb", "Am", "Bb", "Gm", "Bb", "Am", "E7b9"]
OUTRO = ["Am", "Am/G#", "Am/G", "E"]
SONG = INTRO + A + B + A + OUTRO  # 32 compases ≈ 2:12 a 58 BPM

# Melodía: (beat de inicio, duración en beats, nota). Pocas notas, que caen.
MEL_A = [
    [(0, 3, 76), (3, 1, 74)],
    [(0, 4, 72)],
    [(0, 2, 71), (2, 2, 69)],
    [(0, 3, 72), (3, 1, 69)],
    [(0, 2, 70), (2, 2, 74)],
    [(0, 3, 68), (3, 1, 71)],
    [(0, 4, 69)],
    [(0, 2, 70), (2, 2, 67)],
]
MEL_B = [
    [(0, 3, 76), (3, 1, 77)],
    [(0, 2, 77), (2, 2, 74)],
    [(0, 3, 76), (3, 1, 72)],
    [(0, 4, 70)],
    [(0, 2, 74), (2, 2, 70)],
    [(0, 2, 77), (2, 1, 74), (3, 1, 70)],
    [(0, 4, 69)],
    [(0, 2, 77), (2, 2, 68)],
]
# Segunda vuelta de A: igual, pero el final baja al Mi en vez de quedar en el disminuido
MEL_A2 = [list(b) for b in MEL_A]
MEL_A2[7] = [(0, 2, 70), (2, 2, 64)]
MELODY = [[]] * 4 + MEL_A + MEL_B + MEL_A2 + [[]] * 4

ARPS_FROM = 0              # los arpegios suenan desde el principio
TICKS = set(range(12, 20)) # el reloj suena en la sección B


def render():
    total = len(SONG) * BAR
    tail = 4.0
    mix = np.zeros(int(RATE * (total + tail)) + RATE)

    def put(x, start):
        i = int(RATE * start)
        mix[i:i + len(x)] += x

    hb = heartbeat()
    for b, name in enumerate(SONG):
        t0 = b * BAR
        root, arp = CH[name]

        # Bajo: una redonda de triángulo
        put(triangle(root, BAR, decay_env(BAR, 0.01, 0.35, 0.45, 0.08)) * 0.32, t0)

        # Arpegio en corcheas: sube y baja por el acorde
        if b >= ARPS_FROM:
            e = BEAT / 2
            for k, idx in enumerate([0, 1, 2, 3, 2, 1, 2, 1]):
                vel = 0.2 if k % 2 == 0 else 0.14
                put(pulse(arp[idx], e, 0.25, decay_env(e, 0.002, 5)) * vel, t0 + k * e)

        # Latido en el 1 y en el 3
        put(hb, t0)
        put(hb * 0.75, t0 + 2 * BEAT)

        if b in TICKS:
            for k in range(4):
                put(tick(), t0 + k * BEAT)

        # Melodía (pulse angosto) con eco a una corchea con puntillo
        for start, beats, m in MELODY[b]:
            dur = beats * BEAT
            env = decay_env(dur, 0.01, 0.6, 0.35, 0.12)
            x = pulse(m, dur, 0.125, env, vibrato=0.008) * 0.16
            put(x, t0 + start * BEAT)
            put(x * 0.35, t0 + (start + 0.75) * BEAT)
            put(x * 0.12, t0 + (start + 1.5) * BEAT)

    # Loop sin corte: lo que suena después del final se suma al principio
    n = int(RATE * total)
    rest = mix[n:]
    out = mix[:n].copy()
    out[:len(rest)] += rest
    out -= np.mean(out)
    out /= np.max(np.abs(out))
    return out * 0.8


def main():
    audio = render()
    OUT.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / "theme.wav"
        with wave.open(str(wav_path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes((audio * 32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path),
                        "-c:a", "libvorbis", "-q:a", "5", str(OUT)], check=True)
    print(f"{OUT.relative_to(OUT.parent.parent)}  ({len(audio) / RATE:.1f} s)")


if __name__ == "__main__":
    main()
