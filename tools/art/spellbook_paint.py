"""Battle spellbook art: an open leather book with school bookmark tabs, and painted spell miniatures.
python tools/art/spellbook_paint.py prep      ->  imagegen/batch14/in/{book,icons}.png (layout guides) + style ref
python tools/art/spellbook_paint.py paint     ->  imagegen/batch14/out/*.png (Vertex image model)
python tools/art/spellbook_paint.py ingest    ->  assets/ui/spellbook.png, assets/icons/spell_<id>.png

The book is painted over a flat-colour layout guide (cover, two pages, five tabs) so the page and tab rectangles
are known: BOOK_LAYOUT below is what battle.gd uses (in the 1536x1024 book texture). The icons are a 4x4 sheet of
square miniatures; ingest crops each square and scales it to 128 px."""
import os, sys, json
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from pose_paint import key_out

BATCH = "imagegen/batch14"
BW, BH = 1536, 1024
# Layout guide (book texture pixels). Tabs, top to bottom: all, air, fire, water, earth.
COVER = (40, 40, 1420, 984)
PAGES = [(92, 82, 722, 942), (738, 82, 1368, 942)]
TABS = [(1412, 130 + i * 160, 1500, 260 + i * 160) for i in range(5)]
TAB_COL = [(150, 90, 170), (120, 180, 230), (200, 60, 40), (40, 90, 190), (120, 110, 50)]
TAB_SYM = ["a golden eight-pointed star (all schools)", "a swirl of wind (air)", "a flame (fire)",
           "a water drop (water)", "a mountain peak (earth)"]

ICONS = [
    ("magic_arrow", "a glowing violet-white arrow of pure magic streaking across a dark blue night sky"),
    ("bless", "a radiant golden halo of light shining down on an upraised sword"),
    ("curse", "a dark skull wreathed in smouldering red and black smoke"),
    ("shield", "a knight's kite-shaped shield made of translucent glowing blue light, its face plain and smooth, held up against flying sparks"),
    ("haste", "a winged boot rushing forward trailed by streaks of wind"),
    ("slow", "a heavy stone hourglass wrapped in iron chains, sand barely trickling"),
    ("cure", "two cupped hands holding a soft green healing light with a few leaves"),
    ("weakness", "a cracked sword drooping in a sickly grey-green mist"),
    ("lightning_bolt", "a forked bolt of lightning striking down from dark storm clouds"),
    ("ice_bolt", "a jagged spear of blue ice flying through the air leaving a frosty trail"),
    ("stone_skin", "a clenched fist turned to cracked grey stone"),
    ("fireball", "a blazing orange fireball bursting in an explosion of flame"),
    ("frost_ring", "a ring of sharp ice crystals bursting outward over snowy ground"),
    ("death_ripple", "a ghostly green-black shockwave rippling out from a grinning skull"),
    ("resurrection", "a fallen warrior's spirit rising in a column of golden light"),
    ("meteor_shower", "flaming meteors raining down from a red sky onto dark hills"),
]
ISZ, IGAP = 448, 32  # icon squares in the 2048 guide: 4 x (448 + 2*32)

BOOK_PROMPT = (
    "Paint over this layout guide a large open antique spellbook seen from straight above, exactly filling the "
    "brown shape: a dark brown tooled-leather cover with gold corner fittings and stitched edges; two aged cream "
    "parchment pages exactly where the light rectangles are, left and right of a shaded spine, the inner edges "
    "curving gently into the spine and the lower outer page corners slightly curled. The pages are completely "
    "blank: only a thin faded ink border, no writing, no letters, no pictures. Five leather bookmark tabs stick out "
    "of the right edge exactly where the coloured tabs are, each in its colour and embossed with a simple gold "
    "symbol, top to bottom: " + "; ".join(TAB_SYM) + ". "
    "Hand-painted fantasy strategy game interface art, warm light from the upper left, rich detail. Everything "
    "outside the book and tabs stays pure flat magenta (#FF00FF). No text anywhere.")
ICON_PROMPT = (
    "This is a layout guide of 16 grey squares in a 4 x 4 grid. Paint one square spell miniature for a fantasy "
    "strategy game's spellbook in each grey square, filling the square exactly edge to edge, in reading order (left "
    "to right, top row first):\n{items}\n"
    "Each miniature is a small, bold, hand-painted illustration with a dark vignette, a strong glowing focal "
    "element in the centre that reads clearly at small size, rich saturated colour, painted in the same style as "
    "the second image. Keep the black gaps between squares pure black. No frames, no borders, no text, no "
    "letters, no numbers.")

ICON_ONE = ("Paint over this grey square a square spell miniature for a fantasy strategy game's spellbook, filling it edge "
            "to edge: {what}. A small, bold, hand-painted illustration with a dark vignette, a strong glowing focal "
            "element in the centre that reads clearly at small size, rich saturated colour, painted in the same style "
            "as the second image. No symbols, no frame, no border, no text.")


def _square(cell):
    """Bounds of the painted square inside a sheet cell (the model rarely hits the guide exactly)."""
    a = np.asarray(cell.convert("L"), np.float32)
    rows, cols = np.nonzero(a.max(1) > 40)[0], np.nonzero(a.max(0) > 40)[0]
    return cols[0], rows[0], cols[-1] + 1, rows[-1] + 1


def prep():
    os.makedirs(f"{BATCH}/in", exist_ok=True)
    im = Image.new("RGB", (BW, BH), (255, 0, 255))
    d = ImageDraw.Draw(im)
    for (x0, y0, x1, y1), c in zip(TABS, TAB_COL):
        d.rounded_rectangle((x0 - 40, y0, x1, y1), 18, fill=c)
    d.rounded_rectangle(COVER, 28, fill=(80, 45, 25))
    for p in PAGES:
        d.rectangle(p, fill=(235, 220, 185))
    d.rectangle((PAGES[0][2], 70, PAGES[1][0], 954), fill=(120, 95, 60))
    im.save(f"{BATCH}/in/book.png")
    ic = Image.new("RGB", (2048, 2048), (0, 0, 0))
    d = ImageDraw.Draw(ic)
    for i in range(16):
        x, y = (i % 4) * 512 + IGAP, (i // 4) * 512 + IGAP
        d.rectangle((x, y, x + ISZ - 1, y + ISZ - 1), fill=(110, 110, 110))
    ic.save(f"{BATCH}/in/icons.png")
    Image.open("assets/creatures/portraits/angel.png").convert("RGB").save(f"{BATCH}/in/style.png")
    print("guides written")


def paint(names):
    import vertex_paint as vp
    from google import genai
    client = genai.Client(vertexai=True, project=vp.PROJECT, location=vp.LOCATION)
    os.makedirs(f"{BATCH}/out", exist_ok=True)
    style = Image.open(f"{BATCH}/in/style.png")
    for n in names:
        if n in dict(ICONS):  # repaint a single miniature: out/icon_<id>.png overrides its cell of the sheet
            Image.new("RGB", (1024, 1024), (110, 110, 110)).save(f"{BATCH}/in/icon.png")
            img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/icon.png", ICON_ONE.format(what=dict(ICONS)[n]),
                           "1:1", "1K", style)
            n = "icon_" + n
        elif n == "book":
            img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/book.png", BOOK_PROMPT, "3:2", "2K")
        else:
            items = "\n".join("%d. %s" % (i + 1, w) for i, (_, w) in enumerate(ICONS))
            img = vp.paint(client, "gemini-nano-banana-2.1", f"{BATCH}/in/icons.png", ICON_PROMPT.format(items=items),
                           "1:1", "2K", style)
        if img:
            img.save(f"{BATCH}/out/{n}.png")
            print("done", n, img.size)
        else:
            print("FAILED", n)


def ingest(names):
    if "book" in names and os.path.exists(f"{BATCH}/out/book.png"):
        b = key_out(Image.open(f"{BATCH}/out/book.png").convert("RGB").resize((BW, BH), Image.LANCZOS))
        b.save("assets/ui/spellbook.png")
        print("  ui/spellbook.png")
    if "icons" in names and os.path.exists(f"{BATCH}/out/icons.png"):
        sheet = Image.open(f"{BATCH}/out/icons.png").convert("RGB").resize((2048, 2048), Image.LANCZOS)
        inset = 8
        for i, (sid, _) in enumerate(ICONS):
            one = f"{BATCH}/out/icon_{sid}.png"
            if os.path.exists(one):
                im = Image.open(one).convert("RGB")
                im = im.crop((inset, inset, im.width - inset, im.height - inset))
            else:
                cx, cy = (i % 4) * 512, (i // 4) * 512
                x0, y0, x1, y1 = _square(sheet.crop((cx, cy, cx + 512, cy + 512)))
                im = sheet.crop((cx + x0 + inset, cy + y0 + inset, cx + x1 - inset, cy + y1 - inset))
            im.resize((128, 128), Image.LANCZOS).convert("RGBA").save(f"assets/icons/spell_{sid}.png")
        print("  %d spell icons" % len(ICONS))


if __name__ == "__main__":
    cmd, names = sys.argv[1], sys.argv[2:] or ["book", "icons"]
    {"prep": lambda: prep(), "paint": lambda: paint(names), "ingest": lambda: ingest(names)}[cmd]()
