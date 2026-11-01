#!/usr/bin/env python3
"""
Guild Renew — Audio Generator
Genera música, efectos de sonido y ambiente usando fal.ai

Uso:
  python3 generate_audio.py "prompt" [opciones]

Tipos (--type):
  music    Música completa (MiniMax Music 2.6) — hasta ~4 min
  sfx      Efectos de sonido (Stable Audio) — hasta 47s
  ambient  Alias de sfx con duración más larga por defecto (30s)

Opciones:
  --type        music | sfx | ambient (default: sfx)
  --duration    Duración en segundos (default: 10 para sfx/ambient, ignorado en music)
  --instrumental  Solo instrumental, sin voces (solo music, default: True)
  --lyrics      Letra de la canción (solo music)
  --tag         Subcarpeta para organizar (ej: tavern, combat, ambient)
  --count       Número de variaciones (default: 1, max: 4)

Ejemplos:
  # Música de taberna
  python3 generate_audio.py "medieval tavern music, lute and fiddle, warm and cozy" --type music --tag tavern

  # Efecto de sonido
  python3 generate_audio.py "blacksmith hammer hitting anvil, metallic clang" --type sfx --tag crafting

  # Ambiente en loop
  python3 generate_audio.py "peaceful medieval village, birds chirping, distant chatter" --type ambient --duration 30 --tag ambient
"""

import argparse
import os
import sys
import datetime
import re
import urllib.request

from dotenv import load_dotenv

# Carga .env desde la raíz del proyecto
load_dotenv(os.path.join(os.path.dirname(__file__), "..", "..", ".env"))

import fal_client


MODELS = {
    "music": "fal-ai/minimax-music/v2.6",
    "sfx": "fal-ai/stable-audio",
    "ambient": "fal-ai/stable-audio",
}

DEFAULT_DURATION = {
    "music": None,  # MiniMax decide la duración
    "sfx": 10,
    "ambient": 30,
}

BASE_OUTPUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")


def slugify(text: str, max_len: int = 40) -> str:
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "_", text)
    return text[:max_len].strip("_")


def generate_music(prompt: str, instrumental: bool, lyrics: str | None) -> dict:
    """Genera música con MiniMax Music 2.6."""
    args = {
        "prompt": prompt,
        "is_instrumental": instrumental,
    }
    if lyrics:
        args["lyrics"] = lyrics
        args["is_instrumental"] = False
    elif not instrumental:
        args["lyrics_optimizer"] = True

    print("Enviando a MiniMax Music 2.6 (puede tardar ~60s)...")
    result = fal_client.subscribe(
        MODELS["music"],
        arguments=args,
        with_logs=True,
    )
    return result


def generate_sfx(prompt: str, duration: int) -> dict:
    """Genera efectos de sonido con Stable Audio."""
    args = {
        "prompt": prompt,
        "seconds_total": duration,
    }

    print(f"Enviando a Stable Audio (duración: {duration}s)...")
    result = fal_client.subscribe(
        MODELS["sfx"],
        arguments=args,
        with_logs=True,
    )
    return result


def save_audio(result: dict, audio_type: str, prompt: str, tag: str, index: int, total: int) -> str:
    """Descarga y guarda el archivo de audio."""
    # MiniMax devuelve result["audio"], Stable Audio devuelve result["audio_file"]
    audio_data = result.get("audio") or result.get("audio_file") or result.get("output")

    if isinstance(audio_data, dict):
        url = audio_data["url"]
        content_type = audio_data.get("content_type", "audio/mpeg")
    elif isinstance(audio_data, list) and len(audio_data) > 0:
        url = audio_data[0]["url"]
        content_type = audio_data[0].get("content_type", "audio/mpeg")
    else:
        print(f"  Estructura de respuesta inesperada: {list(result.keys())}")
        print(f"  Resultado completo: {result}")
        sys.exit(1)

    # Determinar extensión — fal-ai/stable-audio devuelve WAV aunque el content_type diga mp3
    if "wav" in content_type or "wave" in content_type:
        ext = ".wav"
    elif url.lower().endswith(".wav"):
        ext = ".wav"
    else:
        # Inspeccionar los primeros bytes para detectar RIFF/WAV real
        import urllib.request as _ur
        with _ur.urlopen(url) as _resp:
            header = _resp.read(4)
        ext = ".wav" if header == b"RIFF" else ".mp3"

    out_dir = os.path.join(BASE_OUTPUT, tag) if tag else os.path.join(BASE_OUTPUT, audio_type)
    os.makedirs(out_dir, exist_ok=True)

    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    slug = slugify(prompt)
    suffix = f"_{index+1}" if total > 1 else ""
    filename = f"{timestamp}_{slug}{suffix}{ext}"
    filepath = os.path.join(out_dir, filename)

    urllib.request.urlretrieve(url, filepath)
    print(f"  [{index+1}/{total}] Guardado: {filepath}")

    return filepath


def generate(prompt: str, audio_type: str, duration: int | None, instrumental: bool,
             lyrics: str | None, tag: str, count: int) -> None:
    api_key = os.environ.get("FAL_KEY")
    if not api_key:
        print("ERROR: variable de entorno FAL_KEY no encontrada.")
        print("  Asegúrate de tener FAL_KEY en .env o ejecuta: export FAL_KEY=tu_api_key")
        sys.exit(1)

    model_id = MODELS[audio_type]
    actual_duration = duration or DEFAULT_DURATION[audio_type]

    print(f"Tipo    : {audio_type}")
    print(f"Modelo  : {model_id}")
    print(f"Prompt  : {prompt}")
    if actual_duration:
        print(f"Duración: {actual_duration}s")
    if audio_type == "music":
        print(f"Instrumental: {instrumental}")
        if lyrics:
            print(f"Lyrics  : {lyrics[:80]}...")
    print(f"Variaciones: {count}")
    print()

    out_dir = os.path.join(BASE_OUTPUT, tag) if tag else os.path.join(BASE_OUTPUT, audio_type)

    for i in range(count):
        if audio_type == "music":
            result = generate_music(prompt, instrumental, lyrics)
        else:
            result = generate_sfx(prompt, actual_duration)

        save_audio(result, audio_type, prompt, tag, i, count)

    # Log de prompts
    os.makedirs(out_dir, exist_ok=True)
    log_path = os.path.join(out_dir, "prompts.log")
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    with open(log_path, "a") as f:
        f.write(f"{timestamp} | type={audio_type} | model={model_id} | count={count}")
        if actual_duration:
            f.write(f" | duration={actual_duration}s")
        f.write(f"\n  {prompt}\n\n")

    print(f"\nLog actualizado: {log_path}")


def main():
    parser = argparse.ArgumentParser(description="Guild Renew — Audio Generator")
    parser.add_argument("prompt", help="Descripción del audio a generar")
    parser.add_argument("--type", choices=["music", "sfx", "ambient"], default="sfx",
                        help="Tipo de audio (default: sfx)")
    parser.add_argument("--duration", type=int, default=None,
                        help="Duración en segundos (default: 10 sfx, 30 ambient)")
    parser.add_argument("--instrumental", action="store_true", default=True,
                        help="Solo instrumental, sin voces (solo music, default: True)")
    parser.add_argument("--vocals", action="store_true", default=False,
                        help="Incluir voces (solo music)")
    parser.add_argument("--lyrics", type=str, default=None,
                        help="Letra de la canción (solo music)")
    parser.add_argument("--tag", default="", help="Subcarpeta (ej: tavern, combat, ambient)")
    parser.add_argument("--count", type=int, default=1, choices=range(1, 5),
                        help="Número de variaciones (default: 1, max: 4)")
    args = parser.parse_args()

    instrumental = not args.vocals

    generate(args.prompt, args.type, args.duration, instrumental, args.lyrics, args.tag, args.count)


if __name__ == "__main__":
    main()
