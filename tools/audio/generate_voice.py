#!/usr/bin/env python3
"""
Guild Renew — Voice Generator
Genera audio de voz usando ElevenLabs TTS vía fal.ai

Uso:
  python3 generate_voice.py "texto aquí" [opciones]

Opciones:
  --voice       Nombre de voz ElevenLabs (default: Rachel)
  --lang        Código de idioma ISO 639-1 (default: es)
  --stability   Consistencia de voz 0.0-1.0 (default: 0.5)
  --tag         Subcarpeta/etiqueta para organizar (ej: artesano, patrona)

Ejemplos:
  python3 generate_voice.py "El acero no miente" --tag artesano
  python3 generate_voice.py "Bienvenido al gremio" --voice Brian --stability 0.7 --tag erudito
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


MODEL_ID = "fal-ai/elevenlabs/tts/eleven-v3"

BASE_OUTPUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "voices")


def slugify(text: str, max_len: int = 40) -> str:
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "_", text)
    return text[:max_len].strip("_")


def generate(text: str, voice: str, lang: str, stability: float, tag: str) -> None:
    api_key = os.environ.get("FAL_KEY")
    if not api_key:
        print("ERROR: variable de entorno FAL_KEY no encontrada.")
        print("  Ejecuta: export FAL_KEY=tu_api_key")
        sys.exit(1)

    out_dir = os.path.join(BASE_OUTPUT, tag) if tag else BASE_OUTPUT
    os.makedirs(out_dir, exist_ok=True)

    print(f"Modelo   : {MODEL_ID}")
    print(f"Voz      : {voice}")
    print(f"Idioma   : {lang}")
    print(f"Stabilidad: {stability}")
    print(f"Texto    : {text}")
    print(f"Destino  : {out_dir}\n")

    result = fal_client.run(
        MODEL_ID,
        arguments={
            "text": text,
            "voice": voice,
            "language_code": lang,
            "stability": stability,
            "apply_text_normalization": "auto",
        },
    )

    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    slug = slugify(text)

    audio_url = result["audio"]["url"]
    filename = f"{timestamp}_{slug}.mp3"
    filepath = os.path.join(out_dir, filename)

    urllib.request.urlretrieve(audio_url, filepath)
    print(f"  Guardado: {filepath}")

    # Log para referencia
    log_path = os.path.join(out_dir, "voices.log")
    with open(log_path, "a") as f:
        f.write(f"{timestamp} | voice={voice} | lang={lang} | stability={stability}\n")
        f.write(f"  {text}\n\n")

    print(f"Log actualizado: {log_path}")


def main():
    parser = argparse.ArgumentParser(description="Guild Renew — Voice Generator (ElevenLabs vía fal.ai)")
    parser.add_argument("text", help="Texto a convertir en voz")
    parser.add_argument("--voice", default="Rachel", help="Nombre de voz ElevenLabs (default: Rachel)")
    parser.add_argument("--lang", default="es", help="Código idioma ISO 639-1 (default: es)")
    parser.add_argument("--stability", type=float, default=0.5, help="Consistencia de voz 0.0-1.0 (default: 0.5)")
    parser.add_argument("--tag", default="", help="Subcarpeta/etiqueta (ej: artesano, erudito)")
    args = parser.parse_args()

    if not 0.0 <= args.stability <= 1.0:
        print("ERROR: --stability debe estar entre 0.0 y 1.0")
        sys.exit(1)

    generate(args.text, args.voice, args.lang, args.stability, args.tag)


if __name__ == "__main__":
    main()
