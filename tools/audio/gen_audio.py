"""Generate game audio with ElevenLabs (key from the ELEVENLABS_API_KEY environment variable).

    python tools/audio/gen_audio.py sfx            # all missing sound effects
    python tools/audio/gen_audio.py music          # all missing music tracks
    python tools/audio/gen_audio.py voice          # narrator lines
    python tools/audio/gen_audio.py sfx sword_hit  # one item (regenerates it)

Writes assets/audio/{sfx,music,voice}/<name>.mp3. Existing files are skipped unless named explicitly.
"""
import os, sys, time, json
import requests

API = "https://api.elevenlabs.io/v1"
OUT = "assets/audio"

SFX = {
    "click": ("short soft wooden UI click, medieval game menu button", 0.5),
    "page": ("single page of an old thick parchment book turning over, a quick soft paper flip", 0.7),
    "build": ("construction sounds, hammering on wood and stone, short fantasy game building completed fanfare", 2.5),
    "recruit": ("armored soldiers marching footsteps and a short brass fanfare, recruiting troops in a fantasy strategy game", 2.0),
    "gold_pickup": ("pile of gold coins being scooped up, jingling coins", 1.2),
    "resource_pickup": ("picking up a heavy bundle of wood and stone, satisfying thud with a soft magical chime", 1.2),
    "chest_open": ("old wooden treasure chest creaking open with a sparkling magical shimmer", 1.8),
    "footstep_horse": ("single horse hoof step on grass, short", 0.5),
    "new_day": ("a single rooster crow far away, morning ambience", 1.6),
    "new_week": ("short triumphant medieval fanfare with trumpets and drums, new week begins", 3.0),
    "level_up": ("magical ascending chime with choir, hero level up fantasy game", 2.0),
    "spell_cast": ("magical spell casting whoosh with sparkling shimmer", 1.2),
    "magic_arrow": ("magic missile zapping through the air, energy bolt", 1.0),
    "lightning": ("loud lightning bolt strike with crackling thunder", 1.8),
    "fireball": ("fireball explosion whoosh and boom with crackling flames", 2.0),
    "bless": ("holy blessing, angelic choir chord with bright chimes", 1.6),
    "curse": ("dark curse spell, eerie low whisper and ominous drone", 1.6),
    "heal": ("gentle healing magic, warm sparkling chimes rising", 1.5),
    "meteor": ("meteors crashing down, multiple heavy fiery impacts and rumbling", 2.5),
    "arrow_shot": ("bow string release and arrow whoosh", 0.7),
    "arrow_hit": ("arrow hitting armor and flesh, thunk", 0.5),
    "sword_hit": ("sword slash hitting steel armor, metallic clang", 0.7),
    "blunt_hit": ("heavy blunt weapon impact, club smashing into body, thud", 0.7),
    "claw_hit": ("monster claw slash, ripping and tearing, beast attack", 0.7),
    "magic_hit": ("magic energy impact burst", 0.7),
    "death_human": ("soldier death groan and armor falling to the ground", 1.2),
    "death_undead": ("skeleton collapsing into a pile of rattling bones, ghostly hiss", 1.4),
    "death_beast": ("large beast dying roar fading out", 1.4),
    "wings": ("large wings flapping, creature taking flight", 1.2),
    "battle_start": ("war horns and drums, battle begins, army war cry", 2.5),
    "victory_cheer": ("army victory cheer, soldiers shouting hurrah", 2.5),
    "defeat": ("somber low horn, defeat, mournful", 2.5),
    "move_step": ("armored soldier footsteps on grass, short", 0.5),
    "retaliate": ("quick sword counter attack swipe", 0.6),
    "miss": ("weapon whoosh missing the target", 0.5),
    "flag_capture": ("flag flapping in wind and a short trumpet call", 1.5),
    "mine_capture": ("pickaxe hitting rock and coins clinking, mine captured", 1.6),
    "error": ("dull wooden knock, negative UI buzz, medieval game", 0.5),
}

MUSIC = {
    "menu": "Epic orchestral fantasy main theme for a medieval strategy game, noble brass melody, strings, choir, harp, majestic and adventurous, no vocals",
    "adventure_grass": "Peaceful pastoral orchestral exploration music for a fantasy strategy game, flutes, strings, harp and light percussion, sunny meadow adventure mood, no vocals",
    "adventure_dirt": "Mysterious adventurous orchestral exploration music for a fantasy strategy game, oboe and low strings, curious wandering mood through wild lands, no vocals",
    "town_haven": "Noble medieval castle town theme, harpsichord, lute, recorder and strings, warm and proud, Renaissance fantasy, no vocals",
    "town_necropolis": "Dark gothic necropolis town theme, pipe organ, low choir hums, bells and eerie strings, ominous undead fantasy kingdom, no vocals",
    "battle": "Intense epic orchestral battle music for a turn-based fantasy strategy game, driving war drums, aggressive brass and strings, heroic and urgent, no vocals",
    "victory": "Short triumphant orchestral victory fanfare, brass and timpani, heroic resolution, fantasy game",
    "defeat": "Short somber orchestral defeat theme, slow mournful strings and low horn, fantasy game",
}
MUSIC_LEN = {"victory": 8000, "defeat": 8000}

VOICE = {
    "intro": "The crown is shattered, and the realm lies divided. Gather your armies, hero, and reclaim what was lost.",
    "victory": "Victory! The lands bow before you.",
    "defeat": "Your armies are broken. The shattered crown slips from your grasp.",
    "new_week": "A new week dawns. Your dwellings swell with fresh recruits.",
}

def key():
    k = os.environ.get("ELEVENLABS_API_KEY", "")
    if not k:
        sys.exit("ELEVENLABS_API_KEY is not set")
    return k

def post(path, payload, params=None):
    for attempt in range(4):
        r = requests.post(f"{API}{path}", headers={"xi-api-key": key(), "Content-Type": "application/json"},
                          json=payload, params=params, timeout=300)
        if r.status_code == 200:
            return r.content
        if r.status_code == 429:
            time.sleep(5 * (attempt + 1))
            continue
        raise RuntimeError(f"{path} -> HTTP {r.status_code}: {r.text[:300]}")
    raise RuntimeError(f"{path} rate limited")

def save(kind, name, data):
    os.makedirs(f"{OUT}/{kind}", exist_ok=True)
    open(f"{OUT}/{kind}/{name}.mp3", "wb").write(data)
    print("wrote", kind, name, len(data) // 1024, "KB", flush=True)

def gen_sfx(name):
    text, dur = SFX[name]
    save("sfx", name, post("/sound-generation", {"text": text, "duration_seconds": max(0.5, dur), "prompt_influence": 0.45}))

def gen_music(name):
    payload = {"prompt": MUSIC[name], "music_length_ms": MUSIC_LEN.get(name, 90000)}
    save("music", name, post("/music", payload))

def gen_voice(name):
    voice = os.environ.get("ELEVENLABS_VOICE_ID", "JBFqnCBsd6RMkjVDRZzb")  # "George": warm British narrator
    payload = {"text": VOICE[name], "model_id": "eleven_multilingual_v2",
               "voice_settings": {"stability": 0.55, "similarity_boost": 0.75, "style": 0.35}}
    save("voice", name, post(f"/text-to-speech/{voice}", payload, {"output_format": "mp3_44100_128"}))

if __name__ == "__main__":
    kind = sys.argv[1]
    table, fn = {"sfx": (SFX, gen_sfx), "music": (MUSIC, gen_music), "voice": (VOICE, gen_voice)}[kind]
    names = sys.argv[2:] or [n for n in table if not os.path.exists(f"{OUT}/{kind}/{n}.mp3")]
    failed = []
    for n in names:
        try:
            fn(n)
        except Exception as e:
            print("FAILED", n, e, flush=True)
            failed.append(n)
    print("done;", len(names) - len(failed), "ok,", len(failed), "failed")
