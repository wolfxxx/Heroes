"""Sprite post-processing: dark outline + mild sharpening so 3D renders read like painted sprites.
python tools/art/postfx.py <files or dirs...>   (idempotent: originals kept in tools/art/raw/clean/)"""
import os, sys, shutil
import numpy as np
from PIL import Image, ImageFilter

CLEAN = "tools/art/raw/clean"

def outline(img, width=2, color=(28, 18, 10), strength=0.85):
    a = np.asarray(img).astype(np.float32)
    alpha = a[..., 3] / 255.0
    m = Image.fromarray((alpha * 255).astype(np.uint8))
    for _ in range(width):
        m = m.filter(ImageFilter.MaxFilter(3))
    grown = np.asarray(m).astype(np.float32) / 255.0
    ring = np.clip(grown - alpha, 0, 1) * strength
    out = np.zeros_like(a)
    out[..., :3] = color
    out[..., 3] = ring * 255
    # composite original over the outline
    fa = alpha[..., None]
    rgb = a[..., :3] * fa + out[..., :3] * (1 - fa)
    na = alpha + ring * (1 - alpha)
    res = np.dstack([rgb, na * 255])
    return Image.fromarray(np.clip(res, 0, 255).astype(np.uint8), "RGBA")

SAT = 1.0

def process(path, width):
    """Keeps the clean render in CLEAN; a file whose mtime matches the recorded processed mtime is
    re-processed from its clean copy (so running twice never double-outlines)."""
    import json
    rel = os.path.relpath(path).replace("\\", "/")
    backup = os.path.join(CLEAN, rel)
    log_path = os.path.join(CLEAN, "processed.json")
    log = json.load(open(log_path)) if os.path.exists(log_path) else {}
    if log.get(rel) != os.path.getmtime(path) or not os.path.exists(backup):
        os.makedirs(os.path.dirname(backup), exist_ok=True)
        shutil.copy2(path, backup)  # fresh render
    img = Image.open(backup).convert("RGBA")
    if SAT != 1.0:
        from PIL import ImageEnhance
        a = img.getchannel("A")
        rgb = ImageEnhance.Contrast(ImageEnhance.Color(img.convert("RGB")).enhance(SAT)).enhance(1.0 + (SAT - 1.0) * 0.4)
        img = rgb.convert("RGBA"); img.putalpha(a)
    img = img.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    outline(img, width).save(path)
    log[rel] = os.path.getmtime(path)
    os.makedirs(CLEAN, exist_ok=True)
    json.dump(log, open(log_path, "w"), indent=0)

if __name__ == "__main__":
    width = 2
    args = sys.argv[1:]
    while args and args[0].startswith("--"):
        k, v = args[0][2:].split("=")
        if k == "width":
            width = int(v)
        elif k == "sat":
            SAT = float(v)
        args = args[1:]
    for a in args:
        files = [os.path.join(a, f) for f in os.listdir(a) if f.endswith(".png")] if os.path.isdir(a) else [a]
        for f in files:
            process(f, width)
            print("fx", f)
