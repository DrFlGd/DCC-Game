#!/usr/bin/env python3
"""Generate the placeholder sound effects, ambient loops and music for DCC Game.

Everything is synthesised from oscillators, filtered noise and envelopes, so
the output is original, needs no samples and is deterministic (each sound has
its own fixed random seed derived from its name). Files are 22050 Hz, 16-bit,
mono WAV, peak-normalised to about -6 dBFS; the mix level lives in
game/data/audio.json, not in the files.

Loops (ambient/*, music/*) are rendered "around a circle": every voice that
runs past the end wraps to the start and every oscillator completes a whole
number of cycles, so the loop seam is inaudible. They also carry a RIFF `smpl`
chunk with a forward loop over the whole file, which Godot's WAV importer
picks up with its default "Detect From WAV" loop mode.

Usage (from the repository root):
    python3 tools/gen_sfx.py [--out game/assets/audio] [--only name ...]
Python 3 standard library only. Placeholder quality, not final audio.
"""
import argparse
import math
import os
import random
import struct
import zlib

RATE = 22050
PEAK = 10 ** (-6.0 / 20.0)  # -6 dBFS
TAU = 2.0 * math.pi


# --- Building blocks ----------------------------------------------------------------

def frames(seconds):
    return max(1, int(round(seconds * RATE)))


def silence(seconds):
    return [0.0] * frames(seconds)


def rng_for(name):
    return random.Random(zlib.crc32(name.encode("utf-8")))


def note(name):
    """'A4' / 'C#5' / 'Eb3' -> Hz (equal temperament, A4 = 440)."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semis = names[name[0]]
    rest = name[1:]
    if rest[0] == "#":
        semis, rest = semis + 1, rest[1:]
    elif rest[0] == "b":
        semis, rest = semis - 1, rest[1:]
    return 440.0 * 2 ** ((semis + 12 * (int(rest) - 4)) / 12.0)


def wave_value(shape, phase, duty=0.5):
    p = phase % 1.0
    if shape == "sine":
        return math.sin(TAU * p)
    if shape == "square":
        return 1.0 if p < duty else -1.0
    if shape == "saw":
        return 2.0 * p - 1.0
    if shape == "triangle":
        return 4.0 * p - 1.0 if p < 0.5 else 3.0 - 4.0 * p
    raise ValueError(shape)


def tone(seconds, freq, shape="sine", duty=0.5, vibrato=(0.0, 0.0), phase=0.0):
    """Oscillator. `freq` is a number or a function of t in [0, 1] (sweeps).
    `vibrato` is (rate Hz, depth as a frequency ratio)."""
    n = frames(seconds)
    out = [0.0] * n
    f = freq if callable(freq) else (lambda _t, v=freq: v)
    vib_rate, vib_depth = vibrato
    for i in range(n):
        t = i / n
        hz = f(t)
        if vib_depth:
            hz *= 1.0 + vib_depth * math.sin(TAU * vib_rate * i / RATE)
        out[i] = wave_value(shape, phase, duty)
        phase += hz / RATE
    return out


def noise(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(frames(seconds))]


def sweep(start, end, curve=1.0):
    """Exponential-ish frequency sweep from `start` to `end` Hz."""
    return lambda t: start * (end / start) ** (t ** curve)


def lowpass(samples, cutoff, passes=1):
    """One-pole low-pass; `cutoff` is Hz or a function of t in [0, 1]."""
    out = list(samples)
    n = len(out)
    for _ in range(passes):
        y = 0.0
        for i in range(n):
            hz = cutoff(i / n) if callable(cutoff) else cutoff
            a = 1.0 - math.exp(-TAU * hz / RATE)
            y += a * (out[i] - y)
            out[i] = y
    return out


def highpass(samples, cutoff):
    low = lowpass(samples, cutoff)
    return [s - l for s, l in zip(samples, low)]


def bandpass(samples, low, high):
    return lowpass(highpass(samples, low), high)


def envelope(samples, attack=0.005, release=None, decay=None, hold=0.0):
    """Linear attack, optional hold, then either an exponential `decay`
    (time constant in seconds) or a linear `release` to zero at the end."""
    n = len(samples)
    a = frames(attack)
    h = frames(hold)
    out = [0.0] * n
    for i in range(n):
        if i < a:
            g = i / a
        elif i < a + h or (decay is None and release is None):
            g = 1.0
        elif decay is not None:
            g = math.exp(-(i - a - h) / (decay * RATE))
        else:
            r = frames(release)
            g = max(0.0, min(1.0, (n - i) / r))
        out[i] = samples[i] * g
    # A short fade-out on every sound so nothing clicks at the end.
    tail = min(n, frames(0.004))
    for k in range(tail):
        out[n - 1 - k] *= k / tail
    return out


def gain(samples, g):
    return [s * g for s in samples]


def mix(*layers):
    """Sum layers; each is a list or (list, offset_seconds, gain)."""
    parts = []
    length = 0
    for layer in layers:
        data, offset, g = (layer, 0.0, 1.0) if isinstance(layer, list) else layer
        start = frames(offset) if offset else 0
        parts.append((data, start, g))
        length = max(length, start + len(data))
    out = [0.0] * length
    for data, start, g in parts:
        for i, s in enumerate(data):
            out[start + i] += s * g
    return out


def concat(*parts):
    out = []
    for part in parts:
        out.extend(part)
    return out


def tremolo(samples, rate, depth):
    return [s * (1.0 - depth * 0.5 * (1.0 + math.sin(TAU * rate * i / RATE)))
            for i, s in enumerate(samples)]


def soft_clip(samples, drive=1.5):
    k = math.tanh(drive)
    return [math.tanh(drive * s) / k for s in samples]


def normalize(samples, peak=PEAK):
    top = max(1e-9, max(abs(s) for s in samples))
    return [s * peak / top for s in samples]


# --- Looping helpers -----------------------------------------------------------------

def add_wrapped(buffer, data, start, g=1.0):
    """Adds `data` into `buffer` at frame `start`, wrapping past the end."""
    n = len(buffer)
    for i, s in enumerate(data):
        buffer[(start + i) % n] += s * g


def loop_lowpass(samples, cutoff):
    """Circular one-pole low-pass: a warm-up lap makes the filter state at the
    loop end match the start."""
    doubled = lowpass(samples + samples, cutoff)
    return doubled[len(samples):]


def loop_freq(target, seconds):
    """Nearest frequency with a whole number of cycles in `seconds`."""
    return max(1, round(target * seconds)) / seconds


def loop_tone(seconds, target_hz, shape="sine", lfo=None):
    """A seamless drone voice; `lfo` = (rate, depth) amplitude wobble, with the
    rate also snapped to whole cycles."""
    hz = loop_freq(target_hz, seconds)
    out = tone(seconds, hz, shape)
    if lfo:
        rate = loop_freq(lfo[0], seconds)
        out = tremolo(out, rate, lfo[1])
    return out


# --- Sound effects ---------------------------------------------------------------------
# Each function returns a list of floats; normalisation happens on write.

def ui_move(r):
    return envelope(tone(0.045, 1046.5, "triangle"), 0.002, decay=0.012)


def ui_confirm(r):
    a = envelope(tone(0.05, note("E5"), "triangle"), 0.002, decay=0.02)
    b = envelope(tone(0.09, note("B5"), "triangle"), 0.002, decay=0.03)
    return mix(a, (b, 0.045, 1.0))


def ui_back(r):
    a = envelope(tone(0.05, note("B5"), "triangle"), 0.002, decay=0.02)
    b = envelope(tone(0.09, note("E5"), "triangle"), 0.002, decay=0.03)
    return mix(a, (b, 0.045, 1.0))


def melee_swing(r):
    whoosh = lowpass(highpass(noise(0.17, r), 500.0), lambda t: 4500.0 * (1 - t) + 600.0, 2)
    return envelope(whoosh, 0.03, release=0.12)


def melee_hit(r):
    thump = envelope(tone(0.14, sweep(170.0, 55.0, 0.6), "sine"), 0.001, decay=0.05)
    crack = envelope(lowpass(noise(0.06, r), 3000.0), 0.0005, decay=0.012)
    return soft_clip(mix(thump, (crack, 0.0, 0.8)), 1.4)


def ranged_fire(r):
    pew = tone(0.13, sweep(1300.0, 320.0, 0.5), "square", duty=0.3)
    return envelope(lowpass(pew, 3500.0), 0.002, decay=0.045)


def enemy_fire(r):
    gurgle = tone(0.16, sweep(420.0, 160.0), "triangle", vibrato=(38.0, 0.12))
    spit = envelope(bandpass(noise(0.08, r), 600.0, 2200.0), 0.002, decay=0.02)
    return mix(envelope(gurgle, 0.004, decay=0.06), (spit, 0.0, 0.7))


def ranged_hit(r):
    click = envelope(tone(0.03, 1800.0, "square", duty=0.2), 0.0005, decay=0.006)
    fizz = envelope(highpass(noise(0.07, r), 1500.0), 0.001, decay=0.018)
    return mix((click, 0.0, 0.5), fizz)


def player_hurt(r):
    grunt = tone(0.22, sweep(260.0, 110.0), "square", duty=0.4, vibrato=(28.0, 0.05))
    body = envelope(lowpass(grunt, 1400.0), 0.002, decay=0.08)
    hit = envelope(lowpass(noise(0.05, r), 2000.0), 0.0005, decay=0.012)
    return mix(body, (hit, 0.0, 0.7))


def player_dodge(r):
    air = bandpass(noise(0.2, r), 700.0, 1.0)
    air = lowpass(air, lambda t: 900.0 + 3500.0 * math.sin(math.pi * t), 2)
    return envelope(air, 0.05, release=0.14)


def player_death(r):
    fall = tone(1.3, sweep(330.0, 50.0, 0.8), "saw", vibrato=(6.0, 0.03))
    fall = lowpass(fall, lambda t: 2400.0 * (1 - t) + 200.0)
    rumble = lowpass(noise(1.3, r), 260.0, 2)
    return envelope(mix(fall, (rumble, 0.0, 1.4)), 0.01, decay=0.5)


def enemy_hurt(r):
    squeak = tone(0.075, sweep(720.0, 430.0), "triangle")
    return envelope(squeak, 0.002, decay=0.03)


def enemy_death(r):
    drop = envelope(tone(0.32, sweep(320.0, 60.0, 0.7), "triangle"), 0.002, decay=0.12)
    puff = envelope(lowpass(noise(0.22, r), 1600.0), 0.001, decay=0.05)
    return mix(drop, (puff, 0.0, 0.8))


def boss_death(r):
    rumble = lowpass(noise(2.0, r), lambda t: 500.0 * (1 - t) + 80.0, 2)
    groan = tone(2.0, sweep(90.0, 28.0, 0.7), "saw")
    groan = lowpass(groan, 600.0)
    bell = mix(*[(envelope(tone(1.6, f, "sine"), 0.002, decay=0.5), 0.05, g)
                 for f, g in ((311.0, 0.5), (523.0, 0.3), (847.0, 0.18))])
    return envelope(mix((rumble, 0.0, 2.2), groan, (bell, 0.0, 0.6)), 0.01, decay=0.7)


def pickup_item(r):
    out = []
    for k, name in enumerate(("C6", "E6", "G6")):
        out.append((envelope(tone(0.09, note(name), "triangle"), 0.002, decay=0.035),
                    0.05 * k, 1.0))
    return mix(*out)


def pickup_credits(r):
    a = envelope(tone(0.08, note("B5"), "square", duty=0.25), 0.001, decay=0.03)
    b = envelope(tone(0.22, note("E6"), "square", duty=0.25), 0.001, decay=0.07)
    return lowpass(mix((a, 0.0, 0.8), (b, 0.06, 1.0)), 5000.0)


def item_use(r):
    gulp = tone(0.22, lambda t: 260.0 + 340.0 * t + 70.0 * math.sin(TAU * 3.0 * t), "sine")
    return envelope(gulp, 0.01, decay=0.08)


def player_heal(r):
    out = []
    for k, name in enumerate(("A4", "C#5", "E5", "A5")):
        voice = tone(0.45, note(name), "sine", vibrato=(5.0, 0.004))
        out.append((envelope(voice, 0.03, decay=0.16), 0.04 * k, 0.8))
    return mix(*out)


def chest_open(r):
    creak = tone(0.26, lambda t: 150.0 + 60.0 * t, "saw", vibrato=(23.0, 0.18))
    creak = envelope(bandpass(creak, 300.0, 1600.0), 0.02, release=0.08)
    sparkle = mix(*[(envelope(tone(0.12, note(n), "triangle"), 0.002, decay=0.04), 0.22 + 0.05 * k,
                     0.6) for k, n in enumerate(("G5", "C6", "E6", "G6"))])
    return mix((creak, 0.0, 0.8), sparkle)


def loot_box(r):
    thud = envelope(tone(0.2, sweep(130.0, 55.0), "sine"), 0.001, decay=0.06)
    hiss = envelope(bandpass(noise(0.3, r), 1200.0, 6000.0), 0.01, decay=0.08)
    sparkle = mix(*[(envelope(tone(0.2, note(n), "triangle"), 0.002, decay=0.07), 0.12 + 0.06 * k,
                     0.55) for k, n in enumerate(("C5", "E5", "G5", "C6", "E6", "G6"))])
    return mix(thud, (hiss, 0.05, 0.4), sparkle)


def _clunk(r, base, length=0.16):
    body = envelope(tone(length, sweep(base, base * 0.6), "sine"), 0.001, decay=0.05)
    knock = envelope(lowpass(noise(0.04, r), 1800.0), 0.0005, decay=0.01)
    return mix(body, (knock, 0.0, 0.9))


def door_lock(r):
    return soft_clip(mix(_clunk(r, 110.0), (_clunk(r, 85.0, 0.22), 0.11, 1.1)), 1.3)


def door_unlock(r):
    click = envelope(tone(0.03, 1400.0, "square", duty=0.3), 0.0005, decay=0.008)
    lift = envelope(tone(0.22, sweep(220.0, 440.0), "triangle"), 0.01, decay=0.08)
    return mix((click, 0.0, 0.4), (_clunk(r, 160.0, 0.12), 0.02, 0.8), (lift, 0.07, 0.6))


def level_up(r):
    out = []
    for k, name in enumerate(("C5", "E5", "G5", "C6")):
        length = 0.5 if k == 3 else 0.12
        tri = tone(length, note(name), "triangle")
        sq = tone(length, note(name), "square", duty=0.25)
        voice = envelope(mix(tri, (lowpass(sq, 3000.0), 0.0, 0.35)), 0.003,
                         decay=0.2 if k == 3 else 0.05)
        out.append((voice, 0.085 * k, 1.0))
    return mix(*out)


def xp_tick(r):
    return envelope(tone(0.03, 1567.98, "sine"), 0.001, decay=0.008)


def _block(freq, length=0.05):
    return envelope(mix(tone(length, freq, "sine"), (tone(length, freq * 2.76, "sine"), 0.0, 0.3)),
                    0.0008, decay=0.012)


def ticks_gain(r):
    return mix(_block(1000.0), (_block(1500.0), 0.07, 1.0))


def ticks_loss(r):
    return mix(_block(900.0), (_block(620.0, 0.07), 0.08, 1.0))


def grace_warning(r):
    out = []
    for k in range(4):
        freq = 880.0 if k % 2 == 0 else 660.0
        beep = lowpass(tone(0.15, freq, "square", duty=0.5), 2500.0)
        out.append((envelope(beep, 0.004, release=0.03), 0.17 * k, 1.0))
    return mix(*out)


def hazard_telegraph(r):
    whine = tone(0.42, sweep(280.0, 760.0, 0.8), "sine")
    return envelope(tremolo(whine, 18.0, 0.6), 0.06, release=0.06)


def hazard_hit(r):
    crunch = envelope(lowpass(noise(0.25, r), lambda t: 3500.0 * (1 - t) + 300.0), 0.0005, decay=0.06)
    thud = envelope(tone(0.2, sweep(120.0, 45.0), "sine"), 0.001, decay=0.06)
    return soft_clip(mix(crunch, (thud, 0.0, 1.2)), 1.5)


def _chord(names, length, decay, shape="triangle", offset=0.0, g=1.0):
    voices = []
    for name in names:
        tri = tone(length, note(name), shape, vibrato=(5.5, 0.003))
        voices.append((envelope(tri, 0.01, decay=decay), offset, g))
    return voices


def floor_cleared(r):
    lead = []
    for k, name in enumerate(("G4", "C5", "E5")):
        lead.append((envelope(tone(0.12, note(name), "square", duty=0.25), 0.003, decay=0.05),
                     0.1 * k, 0.45))
    return lowpass(mix(*lead, *_chord(("C5", "E5", "G5", "C6"), 0.9, 0.35, offset=0.3)), 4000.0)


def run_victory(r):
    parts = []
    phrase = (("C5", 0.0), ("E5", 0.15), ("G5", 0.3), ("C6", 0.45), ("A5", 0.75), ("C6", 0.9))
    for name, at in phrase:
        sq = envelope(tone(0.18, note(name), "square", duty=0.25), 0.003, decay=0.07)
        parts.append((sq, at, 0.5))
    parts += _chord(("F4", "A4", "C5", "F5"), 0.5, 0.2, offset=0.75, g=0.6)
    parts += _chord(("C4", "G4", "C5", "E5", "G5"), 1.2, 0.45, offset=1.05)
    return lowpass(mix(*parts), 4200.0)


def run_defeat(r):
    parts = []
    for k, name in enumerate(("E4", "D4", "C4", "B3")):
        voice = tone(0.38, note(name), "triangle", vibrato=(5.0, 0.006))
        parts.append((envelope(voice, 0.01, decay=0.16), 0.3 * k, 1.0))
    parts += _chord(("A2", "E3", "A3", "C4"), 1.0, 0.4, offset=1.2, g=0.7)
    return lowpass(mix(*parts), 2500.0)


def announcer_blip(r):
    a = envelope(tone(0.035, 990.0, "square", duty=0.5), 0.001, release=0.01)
    b = envelope(tone(0.045, 1485.0, "square", duty=0.5), 0.001, release=0.015)
    return lowpass(mix(a, (b, 0.045, 0.8)), 3200.0)


def shop_buy(r):
    ding = envelope(mix(tone(0.4, 1318.5, "sine"), (tone(0.4, 2637.0, "sine"), 0.0, 0.25)),
                    0.001, decay=0.12)
    rattle = envelope(bandpass(noise(0.12, r), 2500.0, 7000.0), 0.002, decay=0.03)
    return mix((rattle, 0.0, 0.6), (pickup_credits(r), 0.04, 0.6), (ding, 0.12, 0.8))


def skill_use(r):
    rise = tone(0.36, sweep(400.0, 1250.0, 0.7), "sine", vibrato=(14.0, 0.02))
    shimmer = bandpass(noise(0.36, r), 3000.0, 8000.0)
    body = mix(envelope(rise, 0.02, decay=0.14), (envelope(shimmer, 0.05, decay=0.1), 0.0, 0.25))
    return body


SFX = {
    "ui_move": ui_move, "ui_confirm": ui_confirm, "ui_back": ui_back,
    "melee_swing": melee_swing, "melee_hit": melee_hit,
    "ranged_fire": ranged_fire, "enemy_fire": enemy_fire, "ranged_hit": ranged_hit,
    "player_hurt": player_hurt, "player_dodge": player_dodge, "player_death": player_death,
    "player_heal": player_heal,
    "enemy_hurt": enemy_hurt, "enemy_death": enemy_death, "boss_death": boss_death,
    "pickup_item": pickup_item, "pickup_credits": pickup_credits, "item_use": item_use,
    "chest_open": chest_open, "loot_box": loot_box,
    "door_lock": door_lock, "door_unlock": door_unlock,
    "level_up": level_up, "xp_tick": xp_tick,
    "ticks_gain": ticks_gain, "ticks_loss": ticks_loss, "grace_warning": grace_warning,
    "hazard_telegraph": hazard_telegraph, "hazard_hit": hazard_hit,
    "floor_cleared": floor_cleared, "run_victory": run_victory, "run_defeat": run_defeat,
    "announcer_blip": announcer_blip, "shop_buy": shop_buy, "skill_use": skill_use,
}


# --- Ambient loops ---------------------------------------------------------------------

def crypt_drone(r, seconds=8.0):
    n = frames(seconds)
    bed = [0.0] * n
    for hz, g, lfo in ((55.0, 0.5, (0.25, 0.4)), (82.5, 0.3, (0.375, 0.5)),
                       (110.0, 0.12, (0.125, 0.7)), (164.8, 0.06, (0.5, 0.8))):
        add_wrapped(bed, loop_tone(seconds, hz, "sine", lfo), 0, g)
    wind = loop_lowpass(loop_lowpass([r.uniform(-1, 1) for _ in range(n)], 380.0), 380.0)
    wind = tremolo(wind, loop_freq(0.25, seconds), 0.7)
    add_wrapped(bed, wind, 0, 1.6)
    for _ in range(3):  # distant water drips
        start = r.randrange(n)
        drip = envelope(tone(0.09, sweep(1400.0 + r.uniform(-200, 200), 900.0), "sine"),
                        0.001, decay=0.02)
        add_wrapped(bed, lowpass(drip, 2500.0), start, 0.12)
    return bed


def boss_drone(r, seconds=8.0):
    n = frames(seconds)
    bed = [0.0] * n
    for hz, g, shape, lfo in ((41.25, 0.55, "sine", (0.125, 0.3)), (58.3, 0.3, "sine", (0.25, 0.5)),
                              (82.5, 0.18, "triangle", (0.375, 0.6)), (116.6, 0.08, "saw", (0.5, 0.7))):
        add_wrapped(bed, loop_lowpass(loop_tone(seconds, hz, shape, lfo), 400.0), 0, g)
    beats = 10  # 75 BPM heartbeat, a whole number per loop
    for k in range(beats):
        start = int(k * n / beats)
        for offset, g in ((0, 1.0), (frames(0.22), 0.7)):
            thump = envelope(tone(0.18, sweep(70.0, 38.0), "sine"), 0.002, decay=0.05)
            add_wrapped(bed, thump, start + offset, 0.5 * g)
    grit = loop_lowpass([r.uniform(-1, 1) for _ in range(n)], 220.0)
    add_wrapped(bed, grit, 0, 1.2)
    return bed


AMBIENT = {"crypt_drone": crypt_drone, "boss_drone": boss_drone}


# --- Music loop -----------------------------------------------------------------------

def crypt_theme(r, bpm=120.0, bars=8):
    """16 s chiptune-ish arpeggio in A minor: Am F C G | Am F Dm E."""
    beat = 60.0 / bpm
    seconds = bars * 4 * beat
    n = frames(seconds)
    buffer = [0.0] * n
    chords = [("A3", "C4", "E4"), ("F3", "A3", "C4"), ("C4", "E4", "G4"), ("G3", "B3", "D4"),
              ("A3", "C4", "E4"), ("F3", "A3", "C4"), ("D3", "F3", "A3"), ("E3", "G#3", "B3")]
    pattern = (0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 2, 3, 2)  # 3 = root an octave up
    step = beat / 4.0
    for bar, chord in enumerate(chords):
        freqs = [note(name) for name in chord] + [note(chord[0]) * 2]
        for k, idx in enumerate(pattern):
            start = frames((bar * 16 + k) * step)
            voice = tone(step * 1.6, freqs[idx] * 2, "square", duty=0.25)
            add_wrapped(buffer, envelope(lowpass(voice, 2600.0), 0.002, decay=0.06), start, 0.32)
        root = note(chord[0]) / 2
        for q in range(4):  # bass on the quarter notes
            start = frames((bar * 4 + q) * beat)
            bass = envelope(tone(beat * 0.9, root, "triangle"), 0.004, decay=0.25)
            add_wrapped(buffer, bass, start, 0.55)
        for e in range(8):  # quiet hats on the off-beats
            if e % 2 == 1:
                start = frames((bar * 8 + e) * beat / 2)
                hat = envelope(highpass(noise(0.04, r), 5000.0), 0.0005, decay=0.008)
                add_wrapped(buffer, hat, start, 0.12)
    pad_notes = ("A4", "F4", "G4", "G4", "A4", "F4", "F4", "E4")
    for bar, name in enumerate(pad_notes):  # a soft lead pad, one note per bar
        start = frames(bar * 4 * beat)
        pad = tone(4 * beat, note(name), "sine", vibrato=(4.5, 0.004))
        add_wrapped(buffer, envelope(pad, 0.25, release=0.6), start, 0.18)
    return buffer


MUSIC = {"crypt_theme": crypt_theme}


# --- Output ---------------------------------------------------------------------------

def to_pcm(samples):
    clipped = (max(-1.0, min(1.0, s)) for s in samples)
    return struct.pack("<%dh" % len(samples), *(int(round(s * 32767)) for s in clipped))


def write_wav(path, samples, loop=False):
    pcm = to_pcm(samples)
    fmt = struct.pack("<HHIIHH", 1, 1, RATE, RATE * 2, 2, 16)
    chunks = [b"fmt " + struct.pack("<I", len(fmt)) + fmt,
              b"data" + struct.pack("<I", len(pcm)) + pcm]
    if loop:
        # smpl: 9 header words, then one forward loop (cue id, type 0, start, end,
        # fraction, play count 0 = infinite). Godot treats `end` as exclusive.
        smpl = struct.pack("<9I", 0, 0, int(1e9 / RATE), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(samples), 0, 0)
        chunks.append(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
    body = b"WAVE" + b"".join(chunks)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(b"RIFF" + struct.pack("<I", len(body)) + body)
    return 8 + len(body)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default=os.path.join(root, "game", "assets", "audio"))
    parser.add_argument("--only", nargs="*", help="generate only these names")
    args = parser.parse_args()
    groups = (("sfx", SFX, False), ("ambient", AMBIENT, True), ("music", MUSIC, True))
    total = 0
    for folder, table, loop in groups:
        for name, build in table.items():
            if args.only and name not in args.only:
                continue
            samples = build(rng_for(name))
            if loop:  # square voices leave a DC offset; a loop can drop it seam-free
                mean = sum(samples) / len(samples)
                samples = [s - mean for s in samples]
            samples = normalize(samples)
            path = os.path.join(args.out, folder, name + ".wav")
            size = write_wav(path, samples, loop)
            total += size
            print("wrote %s (%.2f s, %d KB%s)" % (os.path.relpath(path), len(samples) / RATE,
                                                  size // 1024, ", loop" if loop else ""))
    print("total %.2f MB" % (total / 1048576.0))


if __name__ == "__main__":
    main()
