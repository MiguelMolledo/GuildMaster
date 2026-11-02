#!/usr/bin/env python3
"""ElevenLabs directo (sin fal): efectos, música, voz y saldo, con registro de coste y tope de gasto.

Uso:
  python3 tools/audio/eleven.py balance
  python3 tools/audio/eleven.py budget --start-used 69266 --cap 20000   # fija el tope de un encargo
  python3 tools/audio/eleven.py sfx "blacksmith hammer on anvil" --id sfx_hammer --duration 1.5 [--count 3] [--loop]
  python3 tools/audio/eleven.py music "medieval town, lute..." --id music_city_day --seconds 90
  python3 tools/audio/eleven.py voices --search spanish                  # gratis: lista voces
  python3 tools/audio/eleven.py voice "¡Pan recién hecho!" --id voice_vendor --voice-id <id>
  python3 tools/audio/eleven.py log                                      # gasto registrado

Todo se descarga en bruto a audio-generations/<sección>/ (fuera de git, con .gdignore: Godot no lo importa).
De ahí, tools/audio/master.py lo recorta, normaliza y pasa a .ogg en assets/audio/.

Cada llamada de pago: estima el coste, se niega si el gasto del encargo (character_count actual - start_used del
presupuesto) más la estimación pasaría del tope, consulta el saldo antes y después y apunta todo en
audio-generations/log.jsonl (fecha, sección, id, prompt, parámetros, fichero, coste estimado y real, saldo).
La clave sale de .env (ELEVENLABS_API_KEY) y nunca se imprime ni se escribe.
"""

import argparse
import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "audio-generations")
LOG = os.path.join(OUT, "log.jsonl")
BUDGET = os.path.join(OUT, "budget.json")
API = "https://api.elevenlabs.io"

# Tarifas para estimar (créditos). Se corrigen con lo medido: ver docs/audio/plan.md.
RATE_SFX_PER_SEC = 15.0        # efectos con duración fija (medido: 11 por 1 s)
RATE_SFX_AUTO = 100.0          # efectos sin duración (la elige el modelo)
RATE_MUSIC_PER_MIN = 2000.0    # música
RATE_TTS_PER_CHAR = 1.0        # voz (multilingual v2)


def _key() -> str:
    path = os.path.join(ROOT, ".env")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            if line.startswith("ELEVENLABS_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    k = os.environ.get("ELEVENLABS_API_KEY", "")
    if not k:
        sys.exit("Falta ELEVENLABS_API_KEY en .env")
    return k


def _request(method: str, path: str, body: dict | None = None, query: dict | None = None) -> tuple[bytes, dict]:
    url = API + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"xi-api-key": _key(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return r.read(), dict(r.headers)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:800]
        sys.exit("ElevenLabs %s %s -> HTTP %d: %s" % (method, path, e.code, detail))


def subscription() -> dict:
    raw, _ = _request("GET", "/v1/user/subscription")
    d = json.loads(raw)
    return {"used": int(d["character_count"]), "limit": int(d["character_limit"]),
            "reset_unix": d.get("next_character_count_reset_unix"), "tier": d.get("tier")}


def _budget() -> dict | None:
    if os.path.exists(BUDGET):
        return json.load(open(BUDGET))
    return None


def _logged_since(start_used: int) -> int:
    """Coste registrado en log.jsonl desde que se fijó el presupuesto (el saldo de la API llega con retraso)."""
    if not os.path.exists(LOG):
        return 0
    total = 0
    for line in open(LOG, encoding="utf-8"):
        e = json.loads(line)
        if int(e["used_before"]) >= start_used:
            total += int(e["cost"])
    return total


def _guard(estimate: float) -> dict:
    """Saldo antes; corta si el encargo pasaría del tope (lo mayor entre saldo de la API y registro)."""
    sub = subscription()
    b = _budget()
    if b is not None:
        spent = max(sub["used"] - int(b["start_used"]), _logged_since(int(b["start_used"])))
        if spent + estimate > float(b["cap"]):
            sys.exit("Tope: gastado %d + estimado %.0f > %d créditos. No se genera." % (spent, estimate, b["cap"]))
        print("[eleven] encargo: gastado %d de %d (estimado ahora %.0f)" % (spent, b["cap"], estimate))
    if sub["used"] + estimate > sub["limit"]:
        sys.exit("Sin saldo: usados %d + %.0f > límite %d" % (sub["used"], estimate, sub["limit"]))
    return sub


def _after(before: dict) -> dict:
    time.sleep(5)
    return subscription()


def _header_cost(headers: dict) -> int:
    for k, v in headers.items():
        if k.lower() == "character-cost":
            try:
                return int(float(v))
            except ValueError:
                return -1
    return -1


def _save(section: str, name: str, ext: str, data: bytes) -> str:
    d = os.path.join(OUT, section)
    os.makedirs(d, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    path = os.path.join(d, "%s_%s.%s" % (name, stamp, ext))
    n = 1
    while os.path.exists(path):
        n += 1
        path = os.path.join(d, "%s_%s-%d.%s" % (name, stamp, n, ext))
    with open(path, "wb") as f:
        f.write(data)
    return path


def _log(entry: dict) -> None:
    os.makedirs(OUT, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def _record(section: str, sid: str, prompt: str, params: dict, files: list, estimate: float,
            before: dict, after: dict, hdr_costs: list) -> None:
    """Coste real = suma de la cabecera character-cost de cada llamada; si falta, la diferencia de saldo."""
    delta = after["used"] - before["used"]
    real = sum(hdr_costs) if hdr_costs and min(hdr_costs) >= 0 else delta
    _log({"date": datetime.datetime.now().isoformat(timespec="seconds"), "section": section, "id": sid,
          "prompt": prompt, "params": params, "files": [os.path.relpath(p, ROOT) for p in files],
          "estimate": round(estimate), "cost": real, "used_before": before["used"], "used_after": after["used"],
          "limit": after["limit"], "header_costs": hdr_costs, "balance_delta": delta})
    b = _budget()
    tail = ""
    if b is not None:
        spent = max(after["used"] - int(b["start_used"]), _logged_since(int(b["start_used"])))
        tail = " · encargo %d / %d" % (spent, int(b["cap"]))
    print("[eleven] %s %s: coste real %d (estimado %.0f) · saldo API %d -> %d de %d (puede ir con retraso)%s"
          % (section, sid, real, estimate, before["used"], after["used"], after["limit"], tail))
    for p in files:
        print("  " + os.path.relpath(p, ROOT))


def cmd_balance(a: argparse.Namespace) -> None:
    s = subscription()
    b = _budget()
    print("usados %d de %d (quedan %d) · plan %s · se renueva %s" % (
        s["used"], s["limit"], s["limit"] - s["used"], s["tier"],
        datetime.datetime.fromtimestamp(s["reset_unix"]).date() if s["reset_unix"] else "?"))
    if b is not None:
        start = int(b["start_used"])
        print("encargo: gastado %d de %d (saldo API %d, registro %d; desde usados=%d)" % (
            max(s["used"] - start, _logged_since(start)), int(b["cap"]), s["used"] - start, _logged_since(start), start))


def cmd_budget(a: argparse.Namespace) -> None:
    os.makedirs(OUT, exist_ok=True)
    start = a.start_used if a.start_used is not None else subscription()["used"]
    json.dump({"start_used": start, "cap": a.cap, "set": datetime.date.today().isoformat()}, open(BUDGET, "w"))
    print("tope del encargo: %d créditos desde usados=%d" % (a.cap, start))


def cmd_sfx(a: argparse.Namespace) -> None:
    per = RATE_SFX_PER_SEC * a.duration if a.duration else RATE_SFX_AUTO
    estimate = per * a.count
    if a.dry_run:
        print("estimado: %.0f créditos (%d × %.0f)" % (estimate, a.count, per))
        return
    before = _guard(estimate)
    body: dict = {"text": a.prompt, "prompt_influence": a.influence, "model_id": a.model}
    if a.duration:
        body["duration_seconds"] = a.duration
    if a.loop:
        body["loop"] = True
    files, costs = [], []
    for _ in range(a.count):
        raw, headers = _request("POST", "/v1/sound-generation", body, {"output_format": a.format})
        files.append(_save("sfx" if not a.section else a.section, a.id, "mp3", raw))
        costs.append(_header_cost(headers))
    _record(a.section or "sfx", a.id, a.prompt, {k: v for k, v in body.items() if k != "text"} | {"count": a.count},
            files, estimate, before, _after(before), costs)


def cmd_music(a: argparse.Namespace) -> None:
    estimate = RATE_MUSIC_PER_MIN * a.seconds / 60.0
    if a.dry_run:
        print("estimado: %.0f créditos (%d s)" % (estimate, a.seconds))
        return
    before = _guard(estimate)
    body = {"prompt": a.prompt, "music_length_ms": int(a.seconds * 1000), "model_id": "music_v1",
            "force_instrumental": True}
    raw, headers = _request("POST", "/v1/music", body, {"output_format": a.format})
    path = _save("music", a.id, "mp3", raw)
    _record("music", a.id, a.prompt, {k: v for k, v in body.items() if k != "prompt"}, [path], estimate, before,
            _after(before), [_header_cost(headers)])


def cmd_voices(a: argparse.Namespace) -> None:
    q = {"page_size": 50}
    if a.search:
        q["search"] = a.search
    raw, _ = _request("GET", "/v2/voices", None, q)
    for v in json.loads(raw).get("voices", []):
        lab = v.get("labels", {}) or {}
        print("%s  %-28s %s" % (v["voice_id"], v.get("name", "")[:28],
                                 " ".join("%s=%s" % (k, lab[k]) for k in sorted(lab))))


def cmd_voice(a: argparse.Namespace) -> None:
    estimate = RATE_TTS_PER_CHAR * len(a.text)
    if a.dry_run:
        print("estimado: %.0f créditos (%d caracteres)" % (estimate, len(a.text)))
        return
    before = _guard(estimate)
    body = {"text": a.text, "model_id": a.model, "language_code": "es",
            "voice_settings": {"stability": a.stability, "similarity_boost": 0.75, "style": a.style}}
    raw, headers = _request("POST", "/v1/text-to-speech/%s" % a.voice_id, body, {"output_format": a.format})
    path = _save("voice", a.id, "mp3", raw)
    _record("voice", a.id, a.text, {"voice_id": a.voice_id, "model": a.model, "stability": a.stability,
                                     "style": a.style}, [path], estimate, before, _after(before), [_header_cost(headers)])


def cmd_log(a: argparse.Namespace) -> None:
    if not os.path.exists(LOG):
        print("sin registro")
        return
    total = 0
    for line in open(LOG, encoding="utf-8"):
        e = json.loads(line)
        total += int(e["cost"])
        print("%s  %-6s %-22s coste %5d (est %5d)  usados %d->%d" % (e["date"], e["section"], e["id"], e["cost"],
                                                                     e["estimate"], e["used_before"], e["used_after"]))
    print("total registrado: %d créditos" % total)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = p.add_subparsers(dest="cmd", required=True)
    sp.add_parser("balance").set_defaults(fn=cmd_balance)
    b = sp.add_parser("budget")
    b.add_argument("--start-used", type=int, default=None)
    b.add_argument("--cap", type=int, required=True)
    b.set_defaults(fn=cmd_budget)
    s = sp.add_parser("sfx")
    s.add_argument("prompt")
    s.add_argument("--id", required=True)
    s.add_argument("--duration", type=float, default=None, help="0.5-30 s; sin ella la elige el modelo")
    s.add_argument("--count", type=int, default=1)
    s.add_argument("--loop", action="store_true", help="loop sin costura (modelo v2)")
    s.add_argument("--influence", type=float, default=0.5)
    s.add_argument("--model", default="eleven_text_to_sound_v2")
    s.add_argument("--section", default="", help="carpeta cruda (sfx por defecto; ambient para ambientes)")
    s.add_argument("--format", default="mp3_44100_128")
    s.add_argument("--dry-run", action="store_true")
    s.set_defaults(fn=cmd_sfx)
    m = sp.add_parser("music")
    m.add_argument("prompt")
    m.add_argument("--id", required=True)
    m.add_argument("--seconds", type=float, default=90)
    m.add_argument("--format", default="mp3_44100_128")
    m.add_argument("--dry-run", action="store_true")
    m.set_defaults(fn=cmd_music)
    vs = sp.add_parser("voices")
    vs.add_argument("--search", default="")
    vs.set_defaults(fn=cmd_voices)
    v = sp.add_parser("voice")
    v.add_argument("text")
    v.add_argument("--id", required=True)
    v.add_argument("--voice-id", required=True)
    v.add_argument("--model", default="eleven_multilingual_v2")
    v.add_argument("--stability", type=float, default=0.5)
    v.add_argument("--style", type=float, default=0.3)
    v.add_argument("--format", default="mp3_44100_128")
    v.add_argument("--dry-run", action="store_true")
    v.set_defaults(fn=cmd_voice)
    sp.add_parser("log").set_defaults(fn=cmd_log)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
