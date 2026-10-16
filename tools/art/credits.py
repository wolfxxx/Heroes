"""Write CREDITS.md from the Sketchfab license.txt files of the models the game actually uses.
python tools/art/credits.py   (sources live in tools/art/imported_specs.json -> "sketchfab")"""
import json, os, re

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SPECS = os.path.join(ROOT, "tools", "art", "imported_specs.json")
CACHE = os.path.join(ROOT, "tools", "art", "raw", "sketchfab")

# which Sketchfab model each rendered asset comes from (also used by `imported.py` re-imports)
SOURCES = {
    "skeleton": "808c0148d6514562a9cfae7bbde0869b", "griffin": "389459fd5d4e4793b217df27678f4815",
    "pikeman": "b7cc646a8d8d4e768d978eb4fa52804f", "swordsman": "58fc98f3223f4036b5570ae296e1be5d",
    "archer": "47c311cb422a47d4a825b6832297607b", "cavalier": "faca2ad557f64809b598c3a646a8804f",
    "dread_knight": "faca2ad557f64809b598c3a646a8804f", "lich": "164430e3ff18462eac550f26e70e0c05",
    "zombie": "0541416bd635486f95cb3d44f8f676c1", "vampire": "4f574802e7384952a9546f20ea5f30df",
    "ghost": "b8af50271d484548881fe61a06376142", "bone_dragon": "db50c4d1bcda463ca3acc185c0969acc",
    "angel": "939d2410f96c4382bf4d803abc48bab5", "monk": "36e72d20f4354cdc8de26c4aa8ef00bb",
    "lord_morthis": "37fd804499614441a7996427a98ccc11", "kragor_the_pale": "de1c1847fa45442e8e94b2e6a68d47e1",
    "vesna_nightshade": "6c506ca03faf4c4aa4cba1e18f3bbce7", "ilsa_grimveil": "e423e38bbd534db48af7b5463fc18efb",
    "sir_aldric": "dbfeea7957a641329aed853150ce5576", "lord_gareth": "f5a4479d211e49d49937b55fd9478e85",
    "brother_tomas": "36e72d20f4354cdc8de26c4aa8ef00bb", "lady_seraphine": "1e13605a47ff4e84846a21bf71431cac",
}

def field(txt, name):
    m = re.search(r"\*\s*" + name + r":\s*(.+)", txt)
    return m.group(1).strip() if m else "?"

def main():
    spec = json.load(open(SPECS))
    for k, uid in SOURCES.items():
        if k in spec:
            spec[k]["sketchfab"] = uid
    json.dump(spec, open(SPECS, "w"), indent=1, sort_keys=True)
    users = {}
    for k, uid in SOURCES.items():
        users.setdefault(uid, []).append(k)
    lines = ["# Credits", "", "3D models used to render the creature, hero and portrait sprites (via Sketchfab).",
             "Each is used under the license listed; models were re-posed, re-lit, recoloured and rendered to 2D sprites.", ""]
    nc = []
    for uid, used in users.items():
        lic = os.path.join(CACHE, uid, "license.txt")
        if not os.path.exists(lic):
            continue
        txt = open(lic, encoding="utf-8", errors="replace").read()
        license_ = field(txt, "license type")
        lines.append(f"- **{field(txt, 'title')}** by {field(txt, 'author')} — {field(txt, 'source')} — "
                     f"{license_} — used for: {', '.join(sorted(used))}")
        if "NC" in license_.upper() or "NONCOMMERCIAL" in license_.upper():
            nc.append(field(txt, "title"))
    if nc:
        lines += ["", "**Non-commercial only:** " + ", ".join(nc) + ". Replace these before any commercial release."]
    lines += ["", "Music, sound effects and voice lines were generated with ElevenLabs.", ""]
    open(os.path.join(ROOT, "CREDITS.md"), "w", encoding="utf-8").write("\n".join(lines))
    print(f"wrote CREDITS.md ({len(users)} models)")

if __name__ == "__main__":
    main()
