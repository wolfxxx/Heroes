extends RefCounted
class_name TownLayout
## Where each building sprite sits on the 1920x810 town backdrop: [bottom-centre position, display width, draw layer].
## Sprites come from res://assets/town/<faction>_<building>.png (see ASSETS.md).

const VIEW_H := 810.0

const POS := {
	"fort": [Vector2(960, 420), 820.0, 0],
	"dwelling_7": [Vector2(1700, 380), 300.0, 1],
	"mage_guild": [Vector2(1520, 560), 210.0, 2],
	"hall": [Vector2(960, 590), 380.0, 3],
	"dwelling_6": [Vector2(560, 520), 280.0, 2],
	"dwelling_5": [Vector2(1260, 520), 230.0, 2],
	"tavern": [Vector2(330, 660), 270.0, 4],
	"blacksmith": [Vector2(1300, 720), 230.0, 4],
	"marketplace": [Vector2(660, 730), 270.0, 5],
	"dwelling_1": [Vector2(140, 790), 250.0, 6],
	"dwelling_2": [Vector2(430, 800), 240.0, 6],
	"dwelling_3": [Vector2(1540, 800), 250.0, 6],
	"dwelling_4": [Vector2(1800, 770), 250.0, 6],
	# faction specials (their own slots; rendered towns place them by town/layout_<faction>.json)
	"stables": [Vector2(700, 800), 230.0, 7],
	"brotherhood": [Vector2(1220, 800), 220.0, 7],
	"necromancy_amplifier": [Vector2(700, 800), 220.0, 7],
	"skeleton_transformer": [Vector2(1220, 800), 220.0, 7],
}

## Which layout slot + sprite id a built building uses (upgrades share the base slot).
static func slot_of(id: String) -> String:
	if id in ["village_hall", "town_hall", "city_hall", "capitol"]:
		return "hall"
	if id in ["fort", "citadel", "castle"]:
		return "fort"
	if id.begins_with("mage_guild"):
		return "mage_guild"
	if id.begins_with("dwelling_") and id.ends_with("u"):
		return id.trim_suffix("u")  # (the upgraded dwelling stands where the base one stood)
	return id

static func sprite_id(id: String) -> String:
	if id.begins_with("mage_guild"):
		return "mage_guild_1" if id == "mage_guild_1" else "mage_guild_2"
	return id
