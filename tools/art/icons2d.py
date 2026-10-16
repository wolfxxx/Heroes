"""2D icon work: framed backgrounds for skill/artifact renders and painted spell icons.
python tools/art/icons2d.py"""
import os, math, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersampling

def framed(size, top, bottom, border=(214, 170, 80)):
    W = size * S
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    grad = Image.new("RGBA", (W, W))
    gd = ImageDraw.Draw(grad)
    for y in range(W):
        t = y / W
        c = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)) + (255,)
        gd.line([(0, y), (W, y)], fill=c)
    # radial highlight
    hl = Image.new("L", (W, W), 0)
    ImageDraw.Draw(hl).ellipse([W * 0.1, W * 0.02, W * 0.9, W * 0.7], fill=70)
    hl = hl.filter(ImageFilter.GaussianBlur(W * 0.12))
    grad = Image.composite(Image.new("RGBA", (W, W), (255, 240, 200, 255)), grad, hl)
    mask = Image.new("L", (W, W), 0)
    r = W * 0.12
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, W - 1], r, fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S * 1.5, S * 1.5, W - S * 1.5, W - S * 1.5], r, outline=border + (255,), width=int(S * 2.5))
    d.rounded_rectangle([S * 5, S * 5, W - S * 5, W - S * 5], r * 0.8, outline=(40, 25, 10, 200), width=S)
    return img

def put_on_bg(path, top, bottom):
    clean = os.path.join("tools/art/raw/clean_icons", os.path.basename(path))
    os.makedirs(os.path.dirname(clean), exist_ok=True)
    marker = clean + ".mtime"
    written = open(marker).read() if os.path.exists(marker) else ""
    if written != str(os.path.getmtime(path)) or not os.path.exists(clean):
        Image.open(path).save(clean)
    fg = Image.open(clean).convert("RGBA")
    size = fg.width
    bg = framed(size, top, bottom).resize((size, size), Image.LANCZOS)
    inner = fg.resize((int(size * 0.84), int(size * 0.84)), Image.LANCZOS)
    shadow = Image.new("RGBA", inner.size, (0, 0, 0, 0))
    shadow.putalpha(inner.getchannel("A").point(lambda a: a * 0.6))
    shadow = shadow.filter(ImageFilter.GaussianBlur(3))
    o = (size - inner.width) // 2
    bg.alpha_composite(shadow, (o + 3, o + 4))
    bg.alpha_composite(inner, (o, o))
    bg.save(path)
    open(marker, "w").write(str(os.path.getmtime(path)))

# ---------------------------------------------------------------------------------------------
# Spells
# ---------------------------------------------------------------------------------------------
SCHOOL = {"fire": ((120, 25, 10), (240, 120, 30), (255, 220, 120)), "air": ((40, 70, 140), (150, 200, 240), (255, 255, 255)),
          "water": ((10, 50, 110), (60, 160, 220), (210, 245, 255)), "earth": ((60, 40, 20), (150, 120, 60), (240, 220, 160))}
SPELL_SCHOOL = {"magic_arrow": "air", "bless": "water", "curse": "fire", "shield": "earth", "haste": "air", "slow": "earth", "cure": "water",
                "weakness": "water", "lightning_bolt": "air", "ice_bolt": "water", "stone_skin": "earth", "fireball": "fire", "frost_ring": "water",
                "death_ripple": "earth", "resurrection": "earth", "meteor_shower": "earth"}

def star(cx, cy, r1, r2, n, rot=0):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = rot + i * math.pi / n
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts

def draw_symbol(name, d, W, glow_col, core):
    c = W / 2
    u = W / 100
    G = tuple(glow_col) + (255,)
    K = tuple(core) + (255,)
    if name == "magic_arrow":
        d.polygon([(20 * u, 72 * u), (64 * u, 34 * u), (58 * u, 28 * u), (84 * u, 16 * u), (72 * u, 42 * u), (66 * u, 36 * u), (26 * u, 78 * u)], fill=K)
    elif name == "bless":
        d.polygon(star(c, c, 38 * u, 12 * u, 8), fill=K)
        d.ellipse([c - 14 * u, c - 14 * u, c + 14 * u, c + 14 * u], fill=G)
    elif name == "curse":
        for k in range(3):
            d.arc([c - (30 - k * 9) * u, c - (30 - k * 9) * u, c + (30 - k * 9) * u, c + (30 - k * 9) * u], k * 70, k * 70 + 250, fill=(60, 10, 70, 255), width=int(6 * u))
        d.ellipse([c - 8 * u, c - 8 * u, c + 8 * u, c + 8 * u], fill=(20, 0, 30, 255))
    elif name in ("shield", "stone_skin"):
        col = K if name == "shield" else (150, 140, 120, 255)
        d.polygon([(c - 26 * u, 22 * u), (c + 26 * u, 22 * u), (c + 26 * u, 52 * u), (c, 82 * u), (c - 26 * u, 52 * u)], fill=col, outline=(60, 40, 20, 255))
        if name == "stone_skin":
            for (x0, y0, x1, y1) in ((-20, 35, 5, 45), (0, 50, 20, 58), (-15, 60, 5, 66)):
                d.line([(c + x0 * u, y0 * u), (c + x1 * u, y1 * u)], fill=(80, 70, 60, 255), width=int(2 * u))
    elif name == "haste":
        for k in range(4):
            d.line([(18 * u, (30 + k * 12) * u), ((60 - k * 6) * u, (30 + k * 12) * u)], fill=K, width=int(5 * u))
        d.polygon([(60 * u, 22 * u), (86 * u, 50 * u), (60 * u, 78 * u)], fill=K)
    elif name == "slow":
        pts = [(c + math.cos(t * 0.35) * t * 1.2 * u, c + math.sin(t * 0.35) * t * 1.2 * u) for t in range(0, 34)]
        d.line(pts, fill=K, width=int(6 * u), joint="curve")
    elif name in ("cure", "resurrection"):
        d.rectangle([c - 8 * u, 18 * u, c + 8 * u, 82 * u], fill=K)
        d.rectangle([22 * u, c - 8 * u if name == "cure" else 36 * u - 8 * u, 78 * u, c + 8 * u if name == "cure" else 36 * u + 8 * u], fill=K)
        if name == "resurrection":
            d.ellipse([c - 16 * u, 10 * u, c + 16 * u, 34 * u], outline=K, width=int(5 * u))
    elif name == "weakness":
        d.polygon([(30 * u, 75 * u), (52 * u, 45 * u), (56 * u, 49 * u), (36 * u, 79 * u)], fill=K)
        d.polygon([(58 * u, 41 * u), (76 * u, 18 * u), (80 * u, 22 * u), (62 * u, 45 * u)], fill=K)
        d.line([(22 * u, 60 * u), (44 * u, 82 * u)], fill=(120, 80, 30, 255), width=int(5 * u))
    elif name == "lightning_bolt":
        d.polygon([(58 * u, 10 * u), (28 * u, 54 * u), (48 * u, 54 * u), (38 * u, 90 * u), (74 * u, 40 * u), (54 * u, 40 * u), (66 * u, 10 * u)], fill=K)
    elif name == "ice_bolt":
        d.polygon([(c, 10 * u), (c + 14 * u, c), (c, 90 * u), (c - 14 * u, c)], fill=K)
        d.polygon([(c - 30 * u, c - 6 * u), (c + 30 * u, c - 6 * u), (c, c + 4 * u)], fill=G)
    elif name == "fireball":
        d.polygon(star(c, c, 40 * u, 22 * u, 9, 0.2), fill=G)
        d.ellipse([c - 22 * u, c - 22 * u, c + 22 * u, c + 22 * u], fill=K)
    elif name == "frost_ring":
        d.ellipse([c - 36 * u, c - 36 * u, c + 36 * u, c + 36 * u], outline=K, width=int(9 * u))
        for k in range(8):
            a = k * math.pi / 4
            d.polygon(star(c + math.cos(a) * 36 * u, c + math.sin(a) * 36 * u, 9 * u, 3 * u, 4), fill=K)
    elif name == "death_ripple":
        for k in range(4):
            r = (12 + k * 10) * u
            d.ellipse([c - r, c - r, c + r, c + r], outline=(40, 70, 30, 255) if k % 2 else (150, 220, 120, 255), width=int(4 * u))
    elif name == "meteor_shower":
        for (x, y, r) in ((30, 30, 9), (62, 22, 7), (50, 58, 13), (76, 66, 8)):
            d.line([(x * u, y * u), ((x - 20) * u, (y - 20) * u)], fill=G, width=int(r * 0.9 * u))
            d.ellipse([(x - r) * u, (y - r) * u, (x + r) * u, (y + r) * u], fill=K)

def spell_icon(name, size=96):
    W = size * S
    dark, mid, light = SCHOOL[SPELL_SCHOOL[name]]
    if name in ("curse", "death_ripple"):
        dark, mid, light = (25, 10, 35), (90, 50, 110), (200, 255, 180)
    bg = framed(size, mid, dark)
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_symbol(name, ImageDraw.Draw(glow), W, light, light)
    halo = glow.filter(ImageFilter.GaussianBlur(W * 0.05))
    halo2 = Image.new("RGBA", (W, W), tuple(light) + (0,))
    halo2.putalpha(halo.getchannel("A"))
    bg.alpha_composite(halo2)
    bg.alpha_composite(halo2)
    sym = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_symbol(name, ImageDraw.Draw(sym), W, light, (255, 255, 255) if name not in ("curse", "death_ripple") else light)
    bg.alpha_composite(sym)
    return bg.resize((size, size), Image.LANCZOS)

def sword_poly(d, u, cx, cy, ang, length, blade=(235, 238, 245, 255), hilt=(200, 150, 50, 255), grip=(90, 50, 25, 255)):
    ca, sa = math.cos(ang), math.sin(ang)
    def P(x, y):  # x along the blade, y across
        return ((cx + x * ca - y * sa) * u, (cy + x * sa + y * ca) * u)
    L = length
    d.polygon([P(-L * 0.18, -4), P(L * 0.62, -4), P(L * 0.72, 0), P(L * 0.62, 4), P(-L * 0.18, 4)], fill=blade, outline=(70, 70, 80, 255))
    d.line([P(-L * 0.12, 0), P(L * 0.6, 0)], fill=(180, 185, 200, 255), width=max(1, int(1.2 * u)))
    d.polygon([P(-L * 0.2, -14), P(-L * 0.16, -14), P(-L * 0.16, 14), P(-L * 0.2, 14)], fill=hilt)
    d.polygon([P(-L * 0.4, -3.5), P(-L * 0.2, -3.5), P(-L * 0.2, 3.5), P(-L * 0.4, 3.5)], fill=grip)
    x, y = P(-L * 0.43, 0)
    d.ellipse([x - 5 * u, y - 5 * u, x + 5 * u, y + 5 * u], fill=hilt)

def painted_icon(kind, size, top, bottom, gold=False):
    W = size * S
    u = W / 100
    bg = framed(size, top, bottom)
    sym = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(sym)
    blade = (250, 215, 120, 255) if gold else (235, 238, 245, 255)
    if kind == "sword":
        sword_poly(d, u, 50 - 8, 50 + 8, -math.pi / 4, 95, blade)
    elif kind == "crossed":
        sword_poly(d, u, 40, 60, -math.pi / 4, 88)
        sword_poly(d, u, 60, 60, -3 * math.pi / 4, 88)
    elif kind == "banner":
        d.line([(30 * u, 14 * u), (30 * u, 88 * u)], fill=(110, 70, 30, 255), width=int(4 * u))
        d.ellipse([26 * u, 9 * u, 34 * u, 17 * u], fill=(230, 185, 70, 255))
        d.polygon([(32 * u, 18 * u), (78 * u, 22 * u), (72 * u, 40 * u), (80 * u, 58 * u), (32 * u, 54 * u)], fill=(25, 60, 170, 255), outline=(230, 185, 70, 255))
        d.polygon([(46 * u, 30 * u), (60 * u, 30 * u), (60 * u, 36 * u), (46 * u, 36 * u)], fill=(230, 185, 70, 255))
        d.polygon([(51 * u, 24 * u), (55 * u, 24 * u), (55 * u, 46 * u), (51 * u, 46 * u)], fill=(230, 185, 70, 255))
    elif kind == "book":
        d.polygon([(20 * u, 30 * u), (50 * u, 38 * u), (50 * u, 82 * u), (20 * u, 74 * u)], fill=(235, 225, 195, 255), outline=(90, 60, 30, 255))
        d.polygon([(80 * u, 30 * u), (50 * u, 38 * u), (50 * u, 82 * u), (80 * u, 74 * u)], fill=(245, 235, 205, 255), outline=(90, 60, 30, 255))
        for k in range(5):
            y = 44 + k * 7
            d.line([(25 * u, (y - 2) * u), (45 * u, (y + 3) * u)], fill=(120, 100, 80, 255), width=int(1.5 * u))
            d.line([(55 * u, (y + 3) * u), (75 * u, (y - 2) * u)], fill=(120, 100, 80, 255), width=int(1.5 * u))
        d.polygon([(16 * u, 74 * u), (50 * u, 84 * u), (84 * u, 74 * u), (84 * u, 78 * u), (50 * u, 89 * u), (16 * u, 78 * u)], fill=(120, 30, 25, 255))
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    shadow.putalpha(sym.getchannel("A").point(lambda a: a * 0.55))
    shadow = shadow.filter(ImageFilter.GaussianBlur(W * 0.015))
    bg.alpha_composite(shadow, (int(2 * u), int(3 * u)))
    if gold:
        halo = Image.new("RGBA", (W, W), (255, 200, 90, 0))
        halo.putalpha(sym.getchannel("A").filter(ImageFilter.GaussianBlur(W * 0.04)))
        bg.alpha_composite(halo)
    bg.alpha_composite(sym)
    return bg.resize((size, size), Image.LANCZOS)

if __name__ == "__main__":
    painted_icon("sword", 128, (90, 80, 70), (35, 28, 22)).save("assets/icons/stat_attack.png")
    painted_icon("book", 128, (90, 80, 70), (35, 28, 22)).save("assets/icons/stat_knowledge.png")
    painted_icon("crossed", 128, (60, 80, 120), (20, 25, 45)).save("assets/icons/skill_offense.png")
    painted_icon("banner", 128, (60, 80, 120), (20, 25, 45)).save("assets/icons/skill_leadership.png")
    painted_icon("sword", 128, (110, 40, 40), (35, 10, 20), gold=True).save("assets/icons/artifact_sword_of_valor.png")
    os.makedirs("assets/icons", exist_ok=True)
    for f in sorted(x for x in os.listdir("assets/icons") if x.endswith(".png")):
        p = f"assets/icons/{f}"
        if f in ("skill_offense.png", "skill_leadership.png", "artifact_sword_of_valor.png"):
            continue
        if f.startswith("skill_"):
            put_on_bg(p, (60, 80, 120), (20, 25, 45))
        elif f in ("stat_defense.png", "stat_power.png"):
            put_on_bg(p, (90, 80, 70), (35, 28, 22))
        elif f.startswith("artifact_"):
            put_on_bg(p, (110, 40, 40), (35, 10, 20))
    for s in SPELL_SCHOOL:
        spell_icon(s).save(f"assets/icons/spell_{s}.png")
    print("icons done")
