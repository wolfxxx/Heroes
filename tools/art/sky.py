"""Paint a sky behind transparent battlefield / town renders.
python tools/art/sky.py <image.png> <style>   styles: day, dusk, snow, swamp, necro, desert"""
import sys, os
import numpy as np
from PIL import Image, ImageFilter

STYLES = {  # top, horizon, cloud colour, cloud amount
    "day":    ((0.22, 0.42, 0.78), (0.78, 0.86, 0.92), (1.0, 1.0, 1.0), 0.55),
    "desert": ((0.3, 0.5, 0.82), (0.95, 0.88, 0.72), (1.0, 0.97, 0.9), 0.3),
    "dusk":   ((0.25, 0.3, 0.55), (0.98, 0.7, 0.45), (1.0, 0.8, 0.65), 0.5),
    "snow":   ((0.45, 0.55, 0.7), (0.88, 0.9, 0.94), (0.95, 0.96, 1.0), 0.75),
    "swamp":  ((0.2, 0.25, 0.22), (0.55, 0.6, 0.5), (0.7, 0.75, 0.68), 0.7),
    "necro":  ((0.1, 0.06, 0.16), (0.45, 0.6, 0.45), (0.5, 0.45, 0.6), 0.65),
}

def spectral(h, w, rng, beta=2.2):
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.rfftfreq(w)[None, :] * w
    f = np.sqrt(fx ** 2 + (fy * 1.8) ** 2); f[0, 0] = 1
    amp = 1 / f ** (beta / 2); amp[f < 2] = 0
    n = np.fft.irfft2(amp * np.exp(2j * np.pi * rng.random(amp.shape)), s=(h, w))
    n -= n.min(); n /= n.max()
    return n

def sky(w, h, style, seed=1):
    top, hor, cc, amt = STYLES[style]
    rng = np.random.default_rng(seed)
    y = np.linspace(0, 1, h)[:, None, None]
    grad = np.array(top) * (1 - y ** 0.8) + np.array(hor) * (y ** 0.8)
    img = np.broadcast_to(grad, (h, w, 3)).copy()
    n = spectral(h, w, rng, 3.4)
    clouds = np.clip((n - (1 - amt * 0.75)) * 2.2, 0, 1) ** 1.3
    clouds *= np.clip(1.2 - y[..., 0] * 0.9, 0, 1)  # thinner near the horizon
    shade = spectral(h, w, rng, 2.6)
    ccol = np.array(cc) * (0.78 + 0.22 * shade[..., None])
    img = img * (1 - clouds[..., None] * 0.85) + ccol * clouds[..., None] * 0.85
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))

if __name__ == "__main__":
    path, style = sys.argv[1], sys.argv[2]
    clean = os.path.join("tools/art/raw/clean_sky", path.replace("/", "_"))
    os.makedirs(os.path.dirname(clean), exist_ok=True)
    fg = Image.open(path).convert("RGBA")
    if fg.getextrema()[3][0] == 255 and os.path.exists(clean):  # already composited: use the clean copy
        fg = Image.open(clean).convert("RGBA")
    else:
        fg.save(clean)
    bg = sky(fg.width, fg.height, style).convert("RGBA")
    bg.alpha_composite(fg)
    # gentle painterly vignette
    w, h = bg.size
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
    v = np.clip(1.08 - 0.22 * d ** 2, 0.75, 1.0)[..., None]
    out = np.asarray(bg.convert("RGB")).astype(np.float32) * v
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(path)
    print("sky", path)
