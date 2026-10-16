"""Builds assets/terrain/*.png (512x512 seamless) from CC0 Poly Haven textures + procedural water.
Run from repo root:  python -I tools/art/terrain.py"""
import io, os, sys, requests
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

RAW = "tools/art/raw/terrain"
OUT = "assets/terrain"
os.makedirs(RAW, exist_ok=True); os.makedirs(OUT, exist_ok=True)

# terrain -> (polyhaven id, tint rgb, tint strength, saturation, brightness, contrast)
SPEC = {
    "grass": ("leafy_grass", (60, 125, 35), 0.5, 1.25, 1.05, 1.1),
    "dirt":  ("dirt_floor", (125, 95, 62), 0.35, 1.0, 1.0, 1.1),
    "sand":  ("sand_01", (235, 200, 130), 0.35, 1.2, 1.15, 1.0),
    "snow":  ("snow_02", (235, 242, 255), 0.25, 0.9, 1.1, 1.05),
    "swamp": ("brown_mud_leaves_01", (70, 90, 45), 0.45, 1.2, 0.95, 1.05),
    "road":  ("grass_path_2", (165, 135, 95), 0.3, 1.05, 1.15, 1.1),
}

def fetch(pid):
    path = f"{RAW}/{pid}.jpg"
    if not os.path.exists(path):
        files = requests.get(f"https://api.polyhaven.com/files/{pid}", timeout=30).json()
        url = files["Diffuse"]["1k"]["jpg"]["url"]
        data = requests.get(url, timeout=60).content
        open(path, "wb").write(data)
    return Image.open(path).convert("RGB")

def grade(img, tint, k, sat, bri, con):
    img = img.resize((512, 512), Image.LANCZOS)
    img = ImageEnhance.Contrast(img).enhance(con)
    a = np.asarray(img).astype(np.float32) / 255.0
    lum = a.mean(axis=2, keepdims=True)
    t = np.array(tint, np.float32) / 255.0
    tinted = lum * t * 2.0  # luminance-preserving colourise (overlay-ish)
    a = a * (1 - k) + np.clip(tinted, 0, 1) * k
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    img = ImageEnhance.Color(img).enhance(sat)
    img = ImageEnhance.Brightness(img).enhance(bri)
    return img

def seamless_noise(size, scale, rng, octaves=5):
    out = np.zeros((size, size), np.float32)
    amp = 1.0
    for o in range(octaves):
        n = int(scale * 2 ** o)
        grid = rng.random((n, n)).astype(np.float32)
        # tile-safe upsample: wrap then bicubic
        img = Image.fromarray((grid * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
        g = np.asarray(img).astype(np.float32) / 255.0
        # blend with rolled copy to hide seam
        g = 0.5 * g + 0.5 * np.roll(np.roll(g, size // 2, 0), size // 2, 1)
        out += g * amp
        amp *= 0.5
    out -= out.min(); out /= out.max()
    return out

def spectral_noise(size, rng, beta=2.0, lo=2):
    """Periodic (perfectly tileable) noise with a 1/f^beta spectrum."""
    fx = np.fft.fftfreq(size)[:, None] * size
    fy = np.fft.rfftfreq(size)[None, :] * size
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1
    amp = 1.0 / f ** (beta / 2)
    amp[f < lo] = 0
    spec = amp * np.exp(2j * np.pi * rng.random(amp.shape))
    n = np.fft.irfft2(spec, s=(size, size))
    n -= n.min(); n /= n.max()
    return n.astype(np.float32)

def water():
    rng = np.random.default_rng(7)
    n = spectral_noise(512, rng, 2.4, 2)
    n2 = spectral_noise(512, rng, 1.6, 6)
    deep = np.array([18, 58, 100], np.float32)
    mid = np.array([30, 95, 140], np.float32)
    hi = np.array([90, 160, 190], np.float32)
    v = n[..., None]
    col = deep * (1 - v) + mid * v
    streak = np.clip((n2 - 0.62) * 4, 0, 1)[..., None]
    col = col * (1 - streak * 0.5) + hi * streak * 0.5
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8))
    return img.filter(ImageFilter.GaussianBlur(0.6))

def make_tileable(img):
    """Blend the image with a half-offset copy using a cross-fade mask so edges wrap."""
    a = np.asarray(img).astype(np.float32)
    s = a.shape[0]
    b = np.roll(np.roll(a, s // 2, 0), s // 2, 1)
    x = np.abs(np.linspace(-1, 1, s))
    m = np.maximum(x[None, :], x[:, None])
    m = np.clip((m - 0.6) / 0.4, 0, 1)[..., None]
    return Image.fromarray((a * (1 - m) + b * m).astype(np.uint8))

if __name__ == "__main__":
    for t, (pid, tint, k, sat, bri, con) in SPEC.items():
        img = grade(fetch(pid), tint, k, sat, bri, con)
        if t == "snow":
            a = np.asarray(img).astype(np.float32) / 255.0
            a = np.maximum(a, 0.80)  # lift dark scratches
            drift = spectral_noise(512, np.random.default_rng(3), 2.6, 2)[..., None]
            a = a * (0.9 + 0.1 * drift) * np.array([0.97, 0.99, 1.03])
            img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
        img.save(f"{OUT}/{t}.png")
        print("wrote", t)
    water().save(f"{OUT}/water.png")
    print("wrote water")
