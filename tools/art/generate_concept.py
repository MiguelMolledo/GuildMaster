#!/usr/bin/env python3
"""
Guild Renew — Concept Art Generator
Genera imágenes de concept art usando fal.ai (FLUX)

Uso:
  python3 generate_concept.py "prompt aquí" [opciones]

Opciones:
  --model     dev (default, iteración) | pro (calidad final)
  --count     Número de imágenes (default: 1, max: 4)
  --size      landscape_4_3 (default) | square | portrait_4_3
  --tag       Nombre de carpeta/etiqueta para organizar (ej: moodboard, artesano, edificios)

Ejemplos:
  python3 generate_concept.py "medieval town square, isometric 2D game art" --tag moodboard
  python3 generate_concept.py "blacksmith character, pixel art" --model pro --count 4 --tag artesano
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
    "dev":  "fal-ai/flux/dev",
    "pro":  "fal-ai/flux-pro",
    "nano": "fal-ai/nano-banana",
    "nano2": "fal-ai/nano-banana-2",
    "nanopro": "fal-ai/nano-banana-pro",
    "gpt": "openai/gpt-image-2",
}

SIZE_MAP = {
    "landscape_4_3": "landscape_4_3",
    "square":        "square_hd",
    "portrait_4_3":  "portrait_4_3",
}

BASE_OUTPUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "concept")


def slugify(text: str, max_len: int = 40) -> str:
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "_", text)
    return text[:max_len].strip("_")


def generate(prompt: str, model: str, count: int, size: str, tag: str) -> None:
    api_key = os.environ.get("FAL_KEY")
    if not api_key:
        print("ERROR: variable de entorno FAL_KEY no encontrada.")
        print("  Ejecuta: export FAL_KEY=tu_api_key")
        sys.exit(1)

    model_id = MODELS[model]
    image_size = SIZE_MAP[size]

    out_dir = os.path.join(BASE_OUTPUT, tag) if tag else BASE_OUTPUT
    os.makedirs(out_dir, exist_ok=True)

    print(f"Modelo : {model_id}")
    print(f"Prompt : {prompt}")
    print(f"Imágenes: {count}  |  Tamaño: {image_size}")
    print(f"Destino: {out_dir}\n")

    if model == "gpt":
        result = fal_client.run(
            model_id,
            arguments={
                "prompt": prompt,
                "image_size": image_size,
                "quality": "high",
            },
        )
        # Normalize response: GPT Image may return output.url or images[]
        if "output" in result and "images" not in result:
            result["images"] = [{"url": result["output"]["url"]}]
        elif "images" not in result and "image" in result:
            result["images"] = [result["image"]]
        count = len(result.get("images", []))
    else:
        result = fal_client.run(
            model_id,
            arguments={
                "prompt": prompt,
                "num_images": count,
                "image_size": image_size,
                "enable_safety_checker": False,
            },
        )

    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    slug = slugify(prompt)

    for i, image in enumerate(result["images"]):
        url = image["url"]
        suffix = f"_{i+1}" if count > 1 else ""
        filename = f"{timestamp}_{slug}{suffix}.png"
        filepath = os.path.join(out_dir, filename)

        urllib.request.urlretrieve(url, filepath)
        print(f"  [{i+1}/{count}] Guardado: {filepath}")

    # Log de prompts para referencia
    log_path = os.path.join(out_dir, "prompts.log")
    with open(log_path, "a") as f:
        f.write(f"{timestamp} | model={model} | size={image_size} | count={count}\n")
        f.write(f"  {prompt}\n\n")

    print(f"\nLog actualizado: {log_path}")


def main():
    parser = argparse.ArgumentParser(description="Guild Renew — Concept Art Generator")
    parser.add_argument("prompt", help="Prompt de imagen")
    parser.add_argument("--model", choices=["dev", "pro", "nano", "nano2", "nanopro", "gpt"], default="dev")
    parser.add_argument("--count", type=int, default=1, choices=range(1, 5))
    parser.add_argument("--size", choices=["landscape_4_3", "square", "portrait_4_3"], default="landscape_4_3")
    parser.add_argument("--tag", default="", help="Subcarpeta/etiqueta (ej: moodboard, artesano)")
    args = parser.parse_args()

    generate(args.prompt, args.model, args.count, args.size, args.tag)


if __name__ == "__main__":
    main()
