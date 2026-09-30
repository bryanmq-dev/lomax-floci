#!/usr/bin/env python3
"""Genera fotos de producto de prueba (JPEG) con Pillow.
Uso: gen-placeholder-images.py --out /tmp/lomax-fotos --count 20 [--size 1200x800]
Por defecto usa un tamano distinto por imagen (para no depender de un solo caso).
El caso 1200x800 (--size) se usa puntualmente en Etapa 3 para el chequeo de
dimensiones que pide el enunciado (debe producir una miniatura de 300x200).
"""
import argparse
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

COLORES = [
    (66, 133, 244), (219, 68, 55), (244, 180, 0), (15, 157, 88),
    (171, 71, 188), (255, 112, 67), (0, 172, 193), (124, 179, 66),
]


def generar(path: Path, ancho: int, alto: int, etiqueta: str) -> None:
    color = random.choice(COLORES)
    img = Image.new("RGB", (ancho, alto), color=color)
    draw = ImageDraw.Draw(img)
    texto = f"{etiqueta}\n{ancho}x{alto}"
    try:
        font = ImageFont.load_default(size=max(18, ancho // 20))
    except TypeError:
        font = ImageFont.load_default()
    draw.multiline_text((ancho * 0.08, alto * 0.4), texto, fill=(255, 255, 255), font=font)
    img.save(path, "JPEG", quality=85)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--count", type=int, default=1)
    ap.add_argument("--size", default=None, help="ANCHOxALTO fijo, ej. 1200x800")
    ap.add_argument("--prefix", default="producto_")
    args = ap.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.size:
        ancho, alto = (int(x) for x in args.size.lower().split("x"))
        tamanos = [(ancho, alto)] * args.count
    else:
        opciones = [(800, 600), (1000, 1000), (1200, 800), (640, 480), (900, 1200)]
        tamanos = [random.choice(opciones) for _ in range(args.count)]

    for i, (ancho, alto) in enumerate(tamanos, start=1):
        path = out_dir / f"{args.prefix}{i}.jpg"
        generar(path, ancho, alto, f"Lomax #{i}")
        print(f"{path} ({ancho}x{alto})")


if __name__ == "__main__":
    main()
