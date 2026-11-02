#!/usr/bin/env python3
"""Pasa un audio crudo de audio-generations/ a assets/audio/ listo para Godot (.ogg vorbis) y lo comprueba.

Uso:
  python3 tools/audio/master.py sfx  <crudo> assets/audio/sfx/sfx_hammer_01.ogg [--peak -1] [--max 2.5] [--mono]
  python3 tools/audio/master.py loop <crudo> assets/audio/music/music_city_day.ogg [--lufs -18] [--fade 2.0]
                                     [--start 0] [--end 0 | --length <s>]
  python3 tools/audio/master.py check <fichero> [--loop]

sfx: normaliza el pico a --peak dBFS, recorta el silencio de delante y de detrás, corta a --max segundos con un
fundido corto y codifica a ogg (oggenc). loop: normaliza la sonoridad (loudnorm en dos pasadas, lineal) y cierra el
bucle: los últimos --fade segundos se funden sobre los primeros, así el final enlaza con el principio sin clic.
check: duración, pico, RMS y, con --loop, el salto en la costura (último → primer sample) frente al salto típico.
Necesita ffmpeg y oggenc (brew: ffmpeg, vorbis-tools). Solo stdlib.
"""

import argparse
import array
import json
import math
import os
import re
import subprocess
import sys
import tempfile

RATE = 44100


def _run(cmd: list, capture: bool = True) -> subprocess.CompletedProcess:
    r = subprocess.run(cmd, capture_output=capture, text=False)
    if r.returncode != 0:
        sys.exit("falla: %s\n%s" % (" ".join(cmd), r.stderr.decode("utf-8", "replace")[-1500:]))
    return r


def decode(path: str, channels: int) -> array.array:
    """PCM float32 intercalado a 44,1 kHz."""
    r = _run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", str(channels), "-ar", str(RATE), "-"])
    a = array.array("f")
    a.frombytes(r.stdout)
    return a


def channels_of(path: str) -> int:
    r = _run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels", "-of",
              "default=nw=1:nk=1", path])
    return int(r.stdout.decode().strip() or "2")


def write_ogg(samples: array.array, channels: int, out: str, quality: int) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "x.f32")
        wav = os.path.join(tmp, "x.wav")
        with open(raw, "wb") as f:
            samples.tofile(f)
        _run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", str(channels), "-ar", str(RATE), "-i", raw,
              "-c:a", "pcm_s16le", wav])
        _run(["oggenc", "-Q", "-q", str(quality), "-o", out, wav])


def peak_db(s: array.array) -> float:
    m = max((abs(x) for x in s), default=0.0)
    return 20 * math.log10(m) if m > 0 else -120.0


def rms_db(s: array.array) -> float:
    if not s:
        return -120.0
    v = math.sqrt(sum(x * x for x in s) / len(s))
    return 20 * math.log10(v) if v > 0 else -120.0


def trim_silence(s: array.array, ch: int, thresh_db: float) -> array.array:
    t = 10 ** (thresh_db / 20)
    frames = len(s) // ch
    first, last = 0, frames - 1
    while first < frames and max(abs(s[first * ch + c]) for c in range(ch)) < t:
        first += 1
    while last > first and max(abs(s[last * ch + c]) for c in range(ch)) < t:
        last -= 1
    first = max(0, first - int(0.005 * RATE))             # 5 ms de margen delante
    last = min(frames - 1, last + int(0.03 * RATE))       # 30 ms detrás (la cola)
    return s[first * ch:(last + 1) * ch]


def fade_out(s: array.array, ch: int, seconds: float) -> None:
    n = min(len(s) // ch, int(seconds * RATE))
    frames = len(s) // ch
    for i in range(n):
        g = (n - i) / n
        f = frames - n + i
        for c in range(ch):
            s[f * ch + c] *= g


def fade_in(s: array.array, ch: int, seconds: float) -> None:
    n = min(len(s) // ch, int(seconds * RATE))
    for i in range(n):
        g = i / n
        for c in range(ch):
            s[i * ch + c] *= g


def cmd_sfx(a: argparse.Namespace) -> None:
    ch = 1 if a.mono else min(2, channels_of(a.src))
    s = decode(a.src, ch)
    gain = 10 ** ((a.peak - peak_db(s)) / 20)          # normaliza antes: el umbral del recorte es tras normalizar
    s = array.array("f", (x * gain for x in s))
    s = trim_silence(s, ch, a.silence)
    if a.max and len(s) // ch > int(a.max * RATE):
        s = s[:int(a.max * RATE) * ch]
        fade_out(s, ch, 0.08)
    else:
        fade_out(s, ch, 0.01)
    fade_in(s, ch, 0.002)
    write_ogg(s, ch, a.dst, a.quality)
    report(a.dst, False)


def loudnorm(src: str, ch: int, lufs: float) -> array.array:
    """Dos pasadas de loudnorm lineal (sin compresión dinámica)."""
    flt = "loudnorm=I=%s:TP=-1.5:LRA=11" % lufs
    r = subprocess.run(["ffmpeg", "-hide_banner", "-i", src, "-af", flt + ":print_format=json", "-f", "null", "-"],
                       capture_output=True, text=True)
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", r.stderr, re.S)
    if not m:
        sys.exit("loudnorm: sin medida")
    j = json.loads(m.group(0))
    flt2 = flt + (":measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true"
                  % (j["input_i"], j["input_tp"], j["input_lra"], j["input_thresh"], j["target_offset"]))
    rr = _run(["ffmpeg", "-v", "error", "-i", src, "-af", flt2, "-f", "f32le", "-ac", str(ch), "-ar", str(RATE), "-"])
    out = array.array("f")
    out.frombytes(rr.stdout)
    return out


def splice(s: array.array, ch: int, c0: int, c1: int, x: int) -> array.array:
    """s sin los frames [c0, c1): los x frames antes de c0 se funden con los x que empiezan en c1."""
    out = s[:(c0 - x) * ch]
    for i in range(x):
        t = i / x
        gi, go = math.sin(t * math.pi / 2), math.cos(t * math.pi / 2)
        for c in range(ch):
            out.append(s[(c0 - x + i) * ch + c] * go + s[(c1 + i) * ch + c] * gi)
    out.extend(s[(c1 + x) * ch:])
    return out


def cmd_loop(a: argparse.Namespace) -> None:
    ch = 1 if a.mono else min(2, channels_of(a.src))
    s = loudnorm(a.src, ch, a.lufs)
    frames = len(s) // ch
    start = int(a.start * RATE)
    end = frames - int(a.end * RATE) if a.end else frames
    if a.length:                                   # cuerpo del bucle exacto (p. ej. N compases) + el fundido
        end = min(frames, start + int((a.length + a.fade) * RATE))
    s = s[start * ch:end * ch]
    for cut in a.cut:                              # quita un tramo (un hueco, un golpe raro) con un fundido corto
        c0, c1 = (int(float(t) * RATE) for t in cut.split("-"))
        s = splice(s, ch, c0, c1, int(0.25 * RATE))
    frames = len(s) // ch
    x = int(a.fade * RATE)
    if x * 2 >= frames:
        sys.exit("el fundido es demasiado largo para %.1f s" % (frames / RATE))
    # cuerpo = s[0 : frames-x]; sus primeros x frames = cola (s[frames-x:]) que se apaga + cabeza que entra.
    # El final del cuerpo (s[frames-x-1]) seguía en el original con s[frames-x], que es justo el primer frame del
    # cuerpo: la costura es continua. Fundido de igual potencia.
    body = s[:(frames - x) * ch]
    for i in range(x):
        t = i / x
        gi, go = math.sin(t * math.pi / 2), math.cos(t * math.pi / 2)
        for c in range(ch):
            body[i * ch + c] = s[i * ch + c] * gi + s[(frames - x + i) * ch + c] * go
    pk = peak_db(body)
    if pk > -1.0:
        g = 10 ** ((-1.0 - pk) / 20)
        body = array.array("f", (v * g for v in body))
    write_ogg(body, ch, a.dst, a.quality)
    report(a.dst, True)


def report(path: str, loop: bool) -> dict:
    ch = min(2, channels_of(path))
    s = decode(path, ch)
    frames = len(s) // ch
    info = {"file": path, "seconds": round(frames / RATE, 2), "channels": ch, "peak_db": round(peak_db(s), 1),
            "rms_db": round(rms_db(s), 1)}
    if loop and frames > RATE:
        # Salto en la costura frente al salto típico entre samples vecinos (percentil 99 de un tramo).
        seam = max(abs(s[c] - s[(frames - 1) * ch + c]) for c in range(ch))
        steps = sorted(abs(s[(i + 1) * ch] - s[i * ch]) for i in range(0, min(frames - 1, RATE * 10)))
        p99 = steps[int(len(steps) * 0.99)] if steps else 0.0
        head = rms_db(s[:int(0.05 * RATE) * ch])
        tail = rms_db(s[-int(0.05 * RATE) * ch:])
        info |= {"seam_jump": round(seam, 4), "typical_p99": round(p99, 4),
                 "seam_ok": seam <= max(p99 * 1.5, 0.01), "rms_head_db": round(head, 1), "rms_tail_db": round(tail, 1)}
    print(json.dumps(info, ensure_ascii=False))
    return info


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = p.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("sfx")
    s.add_argument("src")
    s.add_argument("dst")
    s.add_argument("--peak", type=float, default=-1.0)
    s.add_argument("--max", type=float, default=0.0)
    s.add_argument("--silence", type=float, default=-55.0, help="umbral del recorte en dBFS (tras normalizar)")
    s.add_argument("--mono", action="store_true")
    s.add_argument("--quality", type=int, default=5)
    s.set_defaults(fn=cmd_sfx)
    lp = sp.add_parser("loop")
    lp.add_argument("src")
    lp.add_argument("dst")
    lp.add_argument("--lufs", type=float, default=-18.0)
    lp.add_argument("--fade", type=float, default=2.0)
    lp.add_argument("--start", type=float, default=0.0)
    lp.add_argument("--end", type=float, default=0.0, help="segundos a quitar del final antes de cerrar el bucle")
    lp.add_argument("--length", type=float, default=0.0,
                    help="largo del bucle en segundos desde --start (p. ej. N compases); usa también --fade s después")
    lp.add_argument("--cut", action="append", default=[], help="tramo a quitar (segundos tras --start): 16.6-18.1")
    lp.add_argument("--mono", action="store_true")
    lp.add_argument("--quality", type=int, default=5)
    lp.set_defaults(fn=cmd_loop)
    c = sp.add_parser("check")
    c.add_argument("src")
    c.add_argument("--loop", action="store_true")
    c.set_defaults(fn=lambda a: report(a.src, a.loop))
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
