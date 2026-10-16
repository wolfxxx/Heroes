"""UI textures: 9-slice panel, buttons, portrait frame, parchment, title logo.
python tools/art/ui_art.py   (needs tools/art/raw/textures/* from the Blender pipeline for wood/stone)"""
import os, math, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

OUT = "assets/ui"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(5)

def spectral(h, w, beta=2.4, lo=2, seed=0):
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.rfftfreq(w)[None, :] * w
    f = np.sqrt(fx ** 2 + fy ** 2); f[0, 0] = 1
    amp = 1 / f ** (beta / 2); amp[f < lo] = 0
    n = np.fft.irfft2(amp * np.exp(2j * np.pi * r.random(amp.shape)), s=(h, w))
    n -= n.min(); n /= n.max()
    return n

def tex_or_noise(pid, size, tint, k=0.6, dark=1.0):
    p = f"tools/art/raw/textures/{pid}/diff.jpg"
    if os.path.exists(p):
        im = Image.open(p).convert("RGB").resize(size, Image.LANCZOS)
        a = np.asarray(im).astype(np.float32) / 255
    else:
        n = spectral(size[1], size[0], 2.0, 2, 1)[..., None]
        a = np.repeat(n, 3, 2) * 0.5 + 0.25
    lum = a.mean(2, keepdims=True)
    a = a * (1 - k) + lum * np.array(tint) * 2 * k
    return np.clip(a * dark, 0, 1)

def to_img(a, alpha=None):
    rgb = (np.clip(a, 0, 1) * 255).astype(np.uint8)
    im = Image.fromarray(rgb, "RGB").convert("RGBA")
    if alpha is not None:
        im.putalpha(Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8)))
    return im

def gold_frame(w, h, bw, radius=10, ornate=True):
    """Beveled gold border ring of width bw as RGBA."""
    S = 3
    W, H, B, R = w * S, h * S, bw * S, radius * S
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, W - 1, H - 1], R, fill=255)
    d.rounded_rectangle([B, B, W - 1 - B, H - 1 - B], max(1, R - B // 2), fill=0)
    # bevel: distance-like shading from blurred mask
    blur = mask.filter(ImageFilter.GaussianBlur(B * 0.35))
    sh = np.asarray(blur).astype(np.float32) / 255
    gy, gx = np.gradient(sh)
    light = np.clip(0.55 + (-gx - gy) * 18, 0.15, 1.3)
    base = np.array([0.82, 0.62, 0.25])
    hi = np.array([1.0, 0.92, 0.6])
    lo = np.array([0.35, 0.22, 0.06])
    col = np.where(light[..., None] > 0.6, base + (hi - base) * ((light[..., None] - 0.6) / 0.7), lo + (base - lo) * (light[..., None] / 0.6))
    n = spectral(H, W, 2.6, 4, 7)[..., None]
    col *= 0.85 + 0.3 * n
    im = to_img(col, np.asarray(mask).astype(np.float32) / 255)
    d2 = ImageDraw.Draw(im)
    # inner and outer dark lines
    d2.rounded_rectangle([S, S, W - 1 - S, H - 1 - S], R, outline=(40, 25, 8, 255), width=S * 2)
    d2.rounded_rectangle([B - S, B - S, W - B + S, H - B + S], max(1, R - B // 2), outline=(40, 25, 8, 255), width=S * 2)
    if ornate:
        for (cx, cy) in ((B / 2, B / 2), (W - B / 2, B / 2), (B / 2, H - B / 2), (W - B / 2, H - B / 2)):
            r = B * 0.62
            d2.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(150, 25, 20, 255), outline=(255, 230, 150, 255), width=S * 2)
            d2.ellipse([cx - r * 0.45, cy - r * 0.6, cx - r * 0.05, cy - r * 0.2], fill=(255, 150, 140, 200))
    return im.resize((w, h), Image.LANCZOS)

def panel():
    w = h = 256
    base = tex_or_noise("brown_planks_05", (w, h), (0.36, 0.25, 0.15), 0.6, 0.45)
    vign = spectral(h, w, 3.0, 1, 3)[..., None]
    base *= 0.8 + 0.25 * vign
    im = to_img(base)
    im.alpha_composite(gold_frame(w, h, 22, 14))
    im.save(f"{OUT}/panel.png")

def button(state):
    w, h = 192, 64
    tint = {"normal": (0.45, 0.28, 0.14), "hover": (0.62, 0.42, 0.18), "pressed": (0.3, 0.18, 0.08), "selected": (0.8, 0.56, 0.2)}[state]
    base = tex_or_noise("brown_planks_05", (w, h), tint, 0.75, 0.75 if state not in ("hover", "selected") else 1.0)
    y = np.linspace(0, 1, h)[:, None, None]
    shade = (1.25 - y * 0.55) if state != "pressed" else (0.75 + y * 0.35)
    im = to_img(base * shade)
    im.alpha_composite(gold_frame(w, h, 8 if state != "selected" else 11, 10, ornate=False))
    if state == "selected":
        glow = Image.new("L", (w, h), 0)
        ImageDraw.Draw(glow).rounded_rectangle([10, 10, w - 11, h - 11], 8, outline=255, width=4)
        glow = glow.filter(ImageFilter.GaussianBlur(4))
        g = Image.new("RGBA", (w, h), (255, 225, 140, 0)); g.putalpha(glow.point(lambda v: v * 0.8))
        im.alpha_composite(g)
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], 10, fill=255)
    im.putalpha(ImageChops.multiply(im.getchannel("A"), m))
    im.save(f"{OUT}/button_{state}.png" if state != "normal" else f"{OUT}/button.png")

def portrait_frame():
    s = 160
    im = gold_frame(s, s, 14, 8)
    im.save(f"{OUT}/frame_portrait.png")

def parchment():
    w = h = 512
    n = spectral(h, w, 2.2, 2, 11)[..., None]
    n2 = spectral(h, w, 1.4, 8, 12)[..., None]
    col = np.array([0.93, 0.85, 0.66]) * (0.82 + 0.2 * n) - 0.06 * n2
    yy, xx = np.mgrid[0:h, 0:w]
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)) / 40
    col *= np.clip(0.6 + edge[..., None] * 0.4, 0.6, 1.0)
    to_img(col).save(f"{OUT}/parchment.png")

def logo():
    font_path = "assets/fonts/title.ttf"
    S = 2
    W, H = 1500 * S, 400 * S
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    f_small = ImageFont.truetype(font_path, 62 * S)
    f_big = ImageFont.truetype(font_path, 122 * S)
    text_mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(text_mask)
    t1 = "HEROES OF THE"
    t2 = "SHATTERED CROWN"
    w1 = d.textlength(t1, font=f_small)
    w2 = d.textlength(t2, font=f_big)
    d.text(((W - w1) / 2, 105 * S), t1, font=f_small, fill=255)
    d.text(((W - w2) / 2, 190 * S), t2, font=f_big, fill=255)
    # crown emblem above the title
    cx, cy = W / 2, 70 * S
    crown = [(cx - 70 * S, cy + 10 * S), (cx - 80 * S, cy - 35 * S), (cx - 40 * S, cy - 5 * S), (cx, cy - 50 * S), (cx + 40 * S, cy - 5 * S),
             (cx + 80 * S, cy - 35 * S), (cx + 70 * S, cy + 10 * S)]
    d.polygon(crown, fill=255)
    d.line([(cx - 20 * S, cy - 40 * S), (cx + 25 * S, cy + 12 * S)], fill=0, width=5 * S)  # the shatter crack
    m = np.asarray(text_mask).astype(np.float32) / 255
    blur = np.asarray(text_mask.filter(ImageFilter.GaussianBlur(4 * S))).astype(np.float32) / 255
    gy, gx = np.gradient(blur)
    light = np.clip(0.6 + (-gx - gy) * 40, 0.2, 1.4)[..., None]
    y = np.linspace(0, 1, H)[:, None, None]
    gold = np.array([1.0, 0.86, 0.45]) * (1.15 - 0.45 * ((y * 3) % 1.0)) * light
    face = to_img(gold, m)
    outline = text_mask.filter(ImageFilter.MaxFilter(9))
    sh = Image.new("RGBA", (W, H), (25, 12, 4, 0)); sh.putalpha(outline)
    glow = Image.new("RGBA", (W, H), (255, 190, 80, 0)); glow.putalpha(outline.filter(ImageFilter.GaussianBlur(18 * S)).point(lambda a: a * 0.6))
    drop = Image.new("RGBA", (W, H), (0, 0, 0, 0)); drop.putalpha(outline.filter(ImageFilter.GaussianBlur(6 * S)).point(lambda a: a * 0.8))
    img.alpha_composite(glow)
    img.alpha_composite(drop, (0, 0))
    shifted = Image.new("RGBA", (W, H), (0, 0, 0, 0)); shifted.paste(drop, (6 * S, 8 * S))
    img.alpha_composite(shifted)
    img.alpha_composite(sh)
    img.alpha_composite(face)
    img.resize((W // S, H // S), Image.LANCZOS).save(f"{OUT}/logo.png")

if __name__ == "__main__":
    panel()
    for st in ("normal", "hover", "pressed", "selected"):
        button(st)
    portrait_frame()
    parchment()
    logo()
    print("ui done")
