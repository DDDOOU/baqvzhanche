"""Generate original, compact card-effect sound cues for the Godot project."""

from __future__ import annotations

import math
import random
import wave
from pathlib import Path


RATE = 44_100
OUT = Path(__file__).resolve().parents[1] / "assets/audio/card_effects"
RNG = random.Random(1987)


def envelope(t: float, duration: float, attack: float = 0.01, release: float = 0.12) -> float:
    return min(1.0, t / max(attack, 1e-5), (duration - t) / max(release, 1e-5))


def write_wav(name: str, duration: float, sample_fn) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    samples = []
    for index in range(int(RATE * duration)):
        t = index / RATE
        value = max(-1.0, min(1.0, float(sample_fn(t, duration))))
        samples.append(int(value * 32767.0))
    with wave.open(str(OUT / name), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(b"".join(sample.to_bytes(2, "little", signed=True) for sample in samples))


def smoke(t: float, duration: float) -> float:
    # Slow filtered noise: a pressure release rather than harsh broadband static.
    phase = 2.0 * math.pi * (320.0 * t + 180.0 * t * t)
    noise = RNG.uniform(-1.0, 1.0)
    breath = noise * 0.18 + math.sin(phase) * 0.035
    return breath * envelope(t, duration, 0.08, 0.35)


def electronic(t: float, duration: float) -> float:
    gate = 1.0 if (t < 0.12 or 0.21 < t < 0.34 or 0.43 < t < 0.58) else 0.0
    frequency = 690.0 + 420.0 * t
    carrier = math.sin(2.0 * math.pi * frequency * t)
    sub = math.sin(2.0 * math.pi * 92.0 * t) * 0.20
    return (carrier * 0.28 * gate + sub) * envelope(t, duration, 0.005, 0.12)


def deploy(t: float, duration: float) -> float:
    thump = math.sin(2.0 * math.pi * (76.0 - 24.0 * t) * t) * math.exp(-10.0 * t)
    second_t = max(0.0, t - 0.34)
    second = math.sin(2.0 * math.pi * 92.0 * second_t) * math.exp(-18.0 * second_t) if t >= 0.34 else 0.0
    confirm = math.sin(2.0 * math.pi * 740.0 * t) * (1.0 if 0.48 < t < 0.62 else 0.0)
    return (thump * 0.55 + second * 0.35 + confirm * 0.16) * envelope(t, duration, 0.005, 0.12)


def mines(t: float, duration: float) -> float:
    value = 0.0
    for start, freq in ((0.03, 1450.0), (0.19, 1180.0), (0.36, 1560.0)):
        local = t - start
        if 0.0 <= local < 0.12:
            value += math.sin(2.0 * math.pi * freq * local) * math.exp(-32.0 * local) * 0.36
            value += RNG.uniform(-1.0, 1.0) * math.exp(-42.0 * local) * 0.10
    return value * envelope(t, duration, 0.002, 0.08)


def fortify(t: float, duration: float) -> float:
    value = 0.0
    for start in (0.0, 0.18, 0.39):
        local = t - start
        if 0.0 <= local < 0.22:
            value += math.sin(2.0 * math.pi * (105.0 - 45.0 * local) * local) * math.exp(-19.0 * local) * 0.42
            value += RNG.uniform(-1.0, 1.0) * math.exp(-28.0 * local) * 0.08
    return value * envelope(t, duration, 0.003, 0.12)


def main() -> None:
    write_wav("card_smoke.wav", 1.20, smoke)
    write_wav("card_electronic.wav", 0.68, electronic)
    write_wav("card_deploy.wav", 0.78, deploy)
    write_wav("card_mines.wav", 0.62, mines)
    write_wav("card_fortify.wav", 0.72, fortify)
    print(f"Built 5 card SFX in {OUT}")


if __name__ == "__main__":
    main()
