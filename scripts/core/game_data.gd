extends Node
## Static game data shared by every system. All asset file names are derived from the ids here
## (see scripts/core/assets.gd and ASSETS.md). Do NOT rename ids without updating assets.

const RESOURCES := ["gold", "wood", "ore", "mercury", "sulfur", "crystal", "gems"]
const RESOURCE_NAMES := {
	"gold": "Gold", "wood": "Wood", "ore": "Ore", "mercury": "Mercury",
	"sulfur": "Sulfur", "crystal": "Crystal", "gems": "Gems",
}

const PLAYER_COLORS := [Color(0.85, 0.15, 0.15), Color(0.2, 0.4, 0.95), Color(0.2, 0.75, 0.3), Color(0.85, 0.7, 0.15)]
const PLAYER_COLOR_NAMES := ["Red", "Blue", "Green", "Gold"]

# ---------------------------------------------------------------------------------------------
# Factions
# ---------------------------------------------------------------------------------------------
const FACTIONS := {
	"haven": {
		"name": "Haven",
		"desc": "Knights and holy warriors sworn to the Shattered Crown.",
		"creatures": ["pikeman", "archer", "griffin", "swordsman", "monk", "cavalier", "angel"],
		"upgrades": ["halberdier", "marksman", "royal_griffin", "crusader", "zealot", "champion", "archangel"],
		"terrain": "grass",
	},
	"necropolis": {
		"name": "Necropolis",
		"desc": "Necromancers commanding legions of the restless dead.",
		"creatures": ["skeleton", "zombie", "ghost", "vampire", "lich", "dread_knight", "bone_dragon"],
		"upgrades": ["skeleton_warrior", "plague_zombie", "wraith", "vampire_lord", "arch_lich", "doom_rider", "ghost_dragon"],
		"terrain": "dirt",
	},
}

# ---------------------------------------------------------------------------------------------
# Creatures.  speed = hexes per turn, init = initiative ordering (higher acts first).
# shots > 0 => ranged.  growth = weekly growth. cost = resource dictionary.
# abilities: flying, ranged, no_retaliation, double_strike, undead, no_melee_penalty,
#            jousting, life_drain, breath, unlimited_retaliation, regenerate, fear, two_hex
# ---------------------------------------------------------------------------------------------
const CREATURES := {
	# ---------------- HAVEN ----------------
	"pikeman": {"name": "Pikeman", "plural": "Pikemen", "faction": "haven", "tier": 1,
		"attack": 4, "defense": 5, "dmg": [1, 3], "hp": 10, "speed": 4, "growth": 14, "shots": 0,
		"cost": {"gold": 60}, "abilities": ["anti_cavalry"], "ai_value": 80},
	"archer": {"name": "Archer", "plural": "Archers", "faction": "haven", "tier": 2,
		"attack": 6, "defense": 3, "dmg": [2, 3], "hp": 10, "speed": 4, "growth": 9, "shots": 12,
		"cost": {"gold": 100}, "abilities": ["ranged"], "ai_value": 126},
	"griffin": {"name": "Griffin", "plural": "Griffins", "faction": "haven", "tier": 3,
		"attack": 8, "defense": 8, "dmg": [3, 6], "hp": 25, "speed": 6, "growth": 7, "shots": 0,
		"cost": {"gold": 200}, "abilities": ["flying", "two_retaliations", "two_hex"], "ai_value": 351},
	"swordsman": {"name": "Swordsman", "plural": "Swordsmen", "faction": "haven", "tier": 4,
		"attack": 10, "defense": 12, "dmg": [6, 9], "hp": 35, "speed": 5, "growth": 4, "shots": 0,
		"cost": {"gold": 300}, "abilities": [], "ai_value": 445},
	"monk": {"name": "Monk", "plural": "Monks", "faction": "haven", "tier": 5,
		"attack": 12, "defense": 7, "dmg": [10, 12], "hp": 30, "speed": 5, "growth": 3, "shots": 12,
		"cost": {"gold": 400}, "abilities": ["ranged"], "ai_value": 582},
	"cavalier": {"name": "Cavalier", "plural": "Cavaliers", "faction": "haven", "tier": 6,
		"attack": 15, "defense": 15, "dmg": [15, 25], "hp": 100, "speed": 7, "growth": 2, "shots": 0,
		"cost": {"gold": 1000}, "abilities": ["jousting", "two_hex"], "ai_value": 1946},
	"angel": {"name": "Angel", "plural": "Angels", "faction": "haven", "tier": 7,
		"attack": 20, "defense": 20, "dmg": [50, 50], "hp": 200, "speed": 12, "growth": 1, "shots": 0,
		"cost": {"gold": 3000, "gems": 1}, "abilities": ["flying", "hates_undead", "two_hex"], "ai_value": 5019},
	# ---------------- NECROPOLIS ----------------
	"skeleton": {"name": "Skeleton", "plural": "Skeletons", "faction": "necropolis", "tier": 1,
		"attack": 5, "defense": 4, "dmg": [1, 3], "hp": 6, "speed": 4, "growth": 12, "shots": 0,
		"cost": {"gold": 60}, "abilities": ["undead"], "ai_value": 60},
	"zombie": {"name": "Zombie", "plural": "Zombies", "faction": "necropolis", "tier": 2,
		"attack": 5, "defense": 5, "dmg": [2, 3], "hp": 20, "speed": 3, "growth": 8, "shots": 0,
		"cost": {"gold": 100}, "abilities": ["undead", "disease"], "ai_value": 128},
	"ghost": {"name": "Ghost", "plural": "Ghosts", "faction": "necropolis", "tier": 3,
		"attack": 7, "defense": 7, "dmg": [3, 5], "hp": 18, "speed": 7, "growth": 7, "shots": 0,
		"cost": {"gold": 200}, "abilities": ["undead", "flying", "regenerate"], "ai_value": 270},
	"vampire": {"name": "Vampire", "plural": "Vampires", "faction": "necropolis", "tier": 4,
		"attack": 10, "defense": 9, "dmg": [5, 8], "hp": 30, "speed": 6, "growth": 4, "shots": 0,
		"cost": {"gold": 360}, "abilities": ["undead", "flying", "no_retaliation", "life_drain"], "ai_value": 555},
	"lich": {"name": "Lich", "plural": "Liches", "faction": "necropolis", "tier": 5,
		"attack": 13, "defense": 10, "dmg": [11, 13], "hp": 30, "speed": 6, "growth": 3, "shots": 12,
		"cost": {"gold": 550}, "abilities": ["undead", "ranged", "death_cloud"], "ai_value": 848},
	"dread_knight": {"name": "Dread Knight", "plural": "Dread Knights", "faction": "necropolis", "tier": 6,
		"attack": 18, "defense": 18, "dmg": [15, 30], "hp": 120, "speed": 7, "growth": 2, "shots": 0,
		"cost": {"gold": 1200}, "abilities": ["undead", "death_blow", "two_hex"], "ai_value": 2382},
	"bone_dragon": {"name": "Bone Dragon", "plural": "Bone Dragons", "faction": "necropolis", "tier": 7,
		"attack": 17, "defense": 15, "dmg": [25, 50], "hp": 150, "speed": 9, "growth": 1, "shots": 0,
		"cost": {"gold": 1800}, "abilities": ["undead", "flying", "fear", "two_hex"], "ai_value": 3388},
	# ---------------- WAR MACHINES (tier 0: never recruited or met on the map; "machine" stacks don't move) ----------------
	"ballista": {"name": "Ballista", "plural": "Ballistas", "faction": "neutral", "tier": 0, "machine": true,
		"attack": 10, "defense": 10, "dmg": [10, 20], "hp": 250, "speed": 0, "growth": 0, "shots": 99,
		"cost": {"gold": 2500}, "abilities": ["ranged"], "ai_value": 600},
	"first_aid_tent": {"name": "First Aid Tent", "plural": "First Aid Tents", "faction": "neutral", "tier": 0, "machine": true,
		"attack": 0, "defense": 0, "dmg": [0, 0], "hp": 75, "speed": 0, "growth": 0, "shots": 0,
		"cost": {"gold": 750}, "abilities": ["heals"], "ai_value": 300},
	"ammo_cart": {"name": "Ammo Cart", "plural": "Ammo Carts", "faction": "neutral", "tier": 0, "machine": true,
		"attack": 0, "defense": 5, "dmg": [0, 0], "hp": 100, "speed": 0, "growth": 0, "shots": 0,
		"cost": {"gold": 1000}, "abilities": ["ammo"], "ai_value": 200},
	"catapult": {"name": "Catapult", "plural": "Catapults", "faction": "neutral", "tier": 0, "machine": true,
		"attack": 10, "defense": 10, "dmg": [0, 0], "hp": 1000, "speed": 30, "growth": 0, "shots": 0,
		"cost": {}, "abilities": ["siege"], "ai_value": 100},  # (speed: it fires first each round; it never moves)
	"arrow_tower": {"name": "Arrow Tower", "plural": "Arrow Towers", "faction": "neutral", "tier": 0, "machine": true,
		"attack": 10, "defense": 10, "dmg": [10, 15], "hp": 999, "speed": 0, "growth": 0, "shots": 99,
		"cost": {}, "abilities": ["ranged"], "ai_value": 0},
	# ---------------- UPGRADES (from an upgraded dwelling; "upgrade_of" names the base creature) ----------------
	"halberdier": {"name": "Halberdier", "plural": "Halberdiers", "faction": "haven", "tier": 1, "upgrade_of": "pikeman",
		"attack": 6, "defense": 5, "dmg": [2, 3], "hp": 10, "speed": 5, "growth": 14, "shots": 0,
		"cost": {"gold": 75}, "abilities": ["anti_cavalry"], "ai_value": 115},
	"marksman": {"name": "Marksman", "plural": "Marksmen", "faction": "haven", "tier": 2, "upgrade_of": "archer",
		"attack": 7, "defense": 4, "dmg": [2, 4], "hp": 10, "speed": 6, "growth": 9, "shots": 24,
		"cost": {"gold": 150}, "abilities": ["ranged"], "ai_value": 184},
	"royal_griffin": {"name": "Royal Griffin", "plural": "Royal Griffins", "faction": "haven", "tier": 3, "upgrade_of": "griffin",
		"attack": 9, "defense": 9, "dmg": [3, 6], "hp": 25, "speed": 9, "growth": 7, "shots": 0,
		"cost": {"gold": 240}, "abilities": ["flying", "two_retaliations", "two_hex"], "ai_value": 448},
	"crusader": {"name": "Crusader", "plural": "Crusaders", "faction": "haven", "tier": 4, "upgrade_of": "swordsman",
		"attack": 12, "defense": 12, "dmg": [7, 10], "hp": 35, "speed": 6, "growth": 4, "shots": 0,
		"cost": {"gold": 400}, "abilities": ["double_strike"], "ai_value": 588},
	"zealot": {"name": "Zealot", "plural": "Zealots", "faction": "haven", "tier": 5, "upgrade_of": "monk",
		"attack": 12, "defense": 10, "dmg": [10, 12], "hp": 30, "speed": 7, "growth": 3, "shots": 24,
		"cost": {"gold": 450}, "abilities": ["ranged"], "ai_value": 750},
	"champion": {"name": "Champion", "plural": "Champions", "faction": "haven", "tier": 6, "upgrade_of": "cavalier",
		"attack": 16, "defense": 16, "dmg": [20, 25], "hp": 100, "speed": 9, "growth": 2, "shots": 0,
		"cost": {"gold": 1200}, "abilities": ["jousting", "two_hex"], "ai_value": 2100},
	"archangel": {"name": "Archangel", "plural": "Archangels", "faction": "haven", "tier": 7, "upgrade_of": "angel",
		"attack": 30, "defense": 30, "dmg": [50, 50], "hp": 250, "speed": 18, "growth": 1, "shots": 0,
		"cost": {"gold": 5000, "gems": 3}, "abilities": ["flying", "hates_undead", "two_hex"], "ai_value": 8776},
	"skeleton_warrior": {"name": "Skeleton Warrior", "plural": "Skeleton Warriors", "faction": "necropolis", "tier": 1, "upgrade_of": "skeleton",
		"attack": 6, "defense": 6, "dmg": [1, 3], "hp": 6, "speed": 5, "growth": 12, "shots": 0,
		"cost": {"gold": 70}, "abilities": ["undead"], "ai_value": 85},
	"plague_zombie": {"name": "Plague Zombie", "plural": "Plague Zombies", "faction": "necropolis", "tier": 2, "upgrade_of": "zombie",
		"attack": 7, "defense": 6, "dmg": [2, 3], "hp": 25, "speed": 4, "growth": 8, "shots": 0,
		"cost": {"gold": 140}, "abilities": ["undead", "disease"], "ai_value": 180},
	"wraith": {"name": "Wraith", "plural": "Wraiths", "faction": "necropolis", "tier": 3, "upgrade_of": "ghost",
		"attack": 7, "defense": 7, "dmg": [3, 5], "hp": 18, "speed": 9, "growth": 7, "shots": 0,
		"cost": {"gold": 230}, "abilities": ["undead", "flying", "regenerate"], "ai_value": 315},
	"vampire_lord": {"name": "Vampire Lord", "plural": "Vampire Lords", "faction": "necropolis", "tier": 4, "upgrade_of": "vampire",
		"attack": 10, "defense": 10, "dmg": [5, 8], "hp": 40, "speed": 9, "growth": 4, "shots": 0,
		"cost": {"gold": 500}, "abilities": ["undead", "flying", "no_retaliation", "life_drain"], "ai_value": 783},
	"arch_lich": {"name": "Arch Lich", "plural": "Arch Liches", "faction": "necropolis", "tier": 5, "upgrade_of": "lich",
		"attack": 13, "defense": 10, "dmg": [11, 15], "hp": 40, "speed": 7, "growth": 3, "shots": 24,
		"cost": {"gold": 600}, "abilities": ["undead", "ranged", "death_cloud"], "ai_value": 1079},
	"doom_rider": {"name": "Doom Rider", "plural": "Doom Riders", "faction": "necropolis", "tier": 6, "upgrade_of": "dread_knight",
		"attack": 20, "defense": 20, "dmg": [20, 35], "hp": 130, "speed": 9, "growth": 2, "shots": 0,
		"cost": {"gold": 1500}, "abilities": ["undead", "death_blow", "two_hex"], "ai_value": 2950},
	"ghost_dragon": {"name": "Ghost Dragon", "plural": "Ghost Dragons", "faction": "necropolis", "tier": 7, "upgrade_of": "bone_dragon",
		"attack": 19, "defense": 17, "dmg": [25, 50], "hp": 200, "speed": 14, "growth": 1, "shots": 0,
		"cost": {"gold": 3000, "mercury": 1}, "abilities": ["undead", "flying", "fear", "two_hex"], "ai_value": 4696},
}

## War machines a hero can own (bought at a Blacksmith); the catapult comes with every hero laying siege.
const WAR_MACHINES := ["ballista", "first_aid_tent", "ammo_cart"]
const MACHINE_TEXT := {
	"ballista": "Shoots an enemy stack every round, guided by the hero's Attack.",
	"first_aid_tent": "Heals the top creature of a wounded friendly stack every round.",
	"ammo_cart": "Friendly shooters never run out of arrows.",
	"catapult": "Batters the walls and towers of a besieged town.",
}

const ABILITY_TEXT := {
	"ranged": "Ranged attack", "flying": "Flying", "undead": "Undead",
	"no_retaliation": "No enemy retaliation", "life_drain": "Drains life",
	"two_retaliations": "Retaliates twice", "jousting": "Jousting bonus",
	"anti_cavalry": "Immune to jousting", "hates_undead": "Hates undead (+50% dmg)",
	"disease": "Disease (-2 Atk/Def)", "regenerate": "Regenerates", "death_cloud": "Death cloud",
	"death_blow": "Chance for double damage", "fear": "Causes fear", "two_hex": "Large creature",
}

# ---------------------------------------------------------------------------------------------
# Heroes. class: might (knight/death_knight) or magic (cleric/necromancer).
# ---------------------------------------------------------------------------------------------
const HEROES := {
	"sir_aldric": {"name": "Sir Aldric", "faction": "haven", "class": "Knight",
		"attack": 2, "defense": 2, "power": 1, "knowledge": 1, "specialty": "Leadership", "skills": {"leadership": 1}},
	"lady_seraphine": {"name": "Lady Seraphine", "faction": "haven", "class": "Cleric",
		"attack": 1, "defense": 0, "power": 2, "knowledge": 2, "specialty": "Light magic", "skills": {"wisdom": 1}, "spells": ["bless", "cure"]},
	"lord_gareth": {"name": "Lord Gareth", "faction": "haven", "class": "Knight",
		"attack": 3, "defense": 1, "power": 1, "knowledge": 1, "specialty": "Archery", "skills": {"archery": 1}},
	"brother_tomas": {"name": "Brother Tomas", "faction": "haven", "class": "Cleric",
		"attack": 0, "defense": 1, "power": 2, "knowledge": 3, "specialty": "Knowledge", "skills": {"wisdom": 1}, "spells": ["magic_arrow", "shield"]},
	"lord_morthis": {"name": "Lord Morthis", "faction": "necropolis", "class": "Death Knight",
		"attack": 2, "defense": 2, "power": 1, "knowledge": 1, "specialty": "Necromancy", "skills": {"necromancy": 1}},
	"vesna_nightshade": {"name": "Vesna Nightshade", "faction": "necropolis", "class": "Necromancer",
		"attack": 1, "defense": 0, "power": 3, "knowledge": 2, "specialty": "Dark magic", "skills": {"necromancy": 1}, "spells": ["curse", "slow"]},
	"kragor_the_pale": {"name": "Kragor the Pale", "faction": "necropolis", "class": "Death Knight",
		"attack": 3, "defense": 2, "power": 0, "knowledge": 1, "specialty": "Offense", "skills": {"necromancy": 1, "offense": 1}},
	"ilsa_grimveil": {"name": "Ilsa Grimveil", "faction": "necropolis", "class": "Necromancer",
		"attack": 0, "defense": 1, "power": 2, "knowledge": 3, "specialty": "Sorcery", "skills": {"necromancy": 1}, "spells": ["magic_arrow", "weakness"]},
}

const SKILLS := {
	"leadership": {"name": "Leadership", "desc": "+1 morale per level."},
	"wisdom": {"name": "Wisdom", "desc": "Learn higher level spells."},
	"archery": {"name": "Archery", "desc": "+15% ranged damage per level."},
	"offense": {"name": "Offense", "desc": "+10% melee damage per level."},
	"armorer": {"name": "Armorer", "desc": "-7% damage taken per level."},
	"necromancy": {"name": "Necromancy", "desc": "Raise 10% of slain enemies as skeletons per level."},
	"logistics": {"name": "Logistics", "desc": "+10% movement per level."},
	"luck": {"name": "Luck", "desc": "+1 luck per level."},
	"sorcery": {"name": "Sorcery", "desc": "+10% spell damage per level."},
}

# ---------------------------------------------------------------------------------------------
# Spells (combat).  target: enemy, ally, any, all_enemies, area, ally_dead
# ---------------------------------------------------------------------------------------------
const SPELLS := {
	"magic_arrow": {"name": "Magic Arrow", "level": 1, "school": "air", "mana": 5, "target": "enemy", "damage": [10, 10], "desc": "Deals 10 + 10×Power damage."},
	"bless": {"name": "Bless", "level": 1, "school": "water", "mana": 5, "target": "ally", "desc": "Target deals maximum damage."},
	"curse": {"name": "Curse", "level": 1, "school": "fire", "mana": 6, "target": "enemy", "desc": "Target deals minimum damage."},
	"shield": {"name": "Shield", "level": 1, "school": "earth", "mana": 5, "target": "ally", "desc": "Reduces melee damage taken by 15%."},
	"haste": {"name": "Haste", "level": 1, "school": "air", "mana": 6, "target": "ally", "desc": "+3 speed."},
	"slow": {"name": "Slow", "level": 1, "school": "earth", "mana": 6, "target": "enemy", "desc": "-25% speed."},
	"cure": {"name": "Cure", "level": 1, "school": "water", "mana": 6, "target": "ally", "desc": "Heals 10 + 5×Power HP and removes negative effects."},
	"weakness": {"name": "Weakness", "level": 2, "school": "water", "mana": 8, "target": "enemy", "desc": "-3 attack."},
	"lightning_bolt": {"name": "Lightning Bolt", "level": 2, "school": "air", "mana": 10, "target": "enemy", "damage": [10, 25], "desc": "Deals 10 + 25×Power damage."},
	"ice_bolt": {"name": "Ice Bolt", "level": 2, "school": "water", "mana": 8, "target": "enemy", "damage": [10, 20], "desc": "Deals 10 + 20×Power damage."},
	"stone_skin": {"name": "Stone Skin", "level": 1, "school": "earth", "mana": 5, "target": "ally", "desc": "+3 defense."},
	"fireball": {"name": "Fireball", "level": 3, "school": "fire", "mana": 15, "target": "area", "damage": [15, 10], "desc": "Deals 15 + 10×Power damage in an area."},
	"frost_ring": {"name": "Frost Ring", "level": 3, "school": "water", "mana": 12, "target": "area", "damage": [15, 10], "desc": "Deals 15 + 10×Power damage in an area."},
	"death_ripple": {"name": "Death Ripple", "level": 2, "school": "earth", "mana": 10, "target": "all_living", "damage": [10, 5], "desc": "Deals 10 + 5×Power damage to every living creature."},
	"resurrection": {"name": "Resurrection", "level": 4, "school": "earth", "mana": 20, "target": "ally", "desc": "Revives 40 + 20×Power HP of fallen creatures."},
	"meteor_shower": {"name": "Meteor Shower", "level": 4, "school": "earth", "mana": 16, "target": "area", "damage": [25, 25], "desc": "Deals 25 + 25×Power damage in an area."},
}

# ---------------------------------------------------------------------------------------------
# Town buildings. dwelling_tier > 0 => creature dwelling. requires = list of building ids.
# ---------------------------------------------------------------------------------------------
const BUILDINGS := {
	"village_hall": {"name": "Village Hall", "cost": {}, "income": 500, "requires": [], "desc": "+500 gold per day."},
	"town_hall": {"name": "Town Hall", "cost": {"gold": 2500}, "income": 1000, "requires": ["village_hall", "tavern"], "replaces": "village_hall", "desc": "+1000 gold per day."},
	"city_hall": {"name": "City Hall", "cost": {"gold": 5000}, "income": 2000, "requires": ["town_hall", "marketplace", "mage_guild_1"], "replaces": "town_hall", "desc": "+2000 gold per day."},
	"capitol": {"name": "Capitol", "cost": {"gold": 10000, "wood": 10, "ore": 10}, "income": 4000, "requires": ["city_hall", "castle"], "replaces": "city_hall", "desc": "+4000 gold per day. Only one Capitol per kingdom."},
	"fort": {"name": "Fort", "cost": {"gold": 5000, "wood": 20, "ore": 20}, "requires": [], "desc": "A wall, a gate and a moat defend the town in sieges."},
	"citadel": {"name": "Citadel", "cost": {"gold": 2500, "ore": 5}, "requires": ["fort"], "replaces": "fort", "desc": "+50% creature growth. A keep with an arrow turret defends the town in sieges."},
	"castle": {"name": "Castle", "cost": {"gold": 5000, "wood": 10, "ore": 10}, "requires": ["citadel"], "replaces": "citadel", "desc": "+100% creature growth. Two more arrow towers defend the town in sieges."},
	"tavern": {"name": "Tavern", "cost": {"gold": 500, "wood": 5}, "requires": [], "desc": "Hire heroes. +1 morale on defense."},
	"marketplace": {"name": "Marketplace", "cost": {"gold": 500, "wood": 5}, "requires": [], "desc": "Trade resources."},
	"mage_guild_1": {"name": "Mage Guild", "cost": {"gold": 2000, "wood": 5, "ore": 5}, "requires": [], "desc": "Teaches level 1 spells."},
	"mage_guild_2": {"name": "Mage Guild Lv2", "cost": {"gold": 1000, "wood": 5, "ore": 5, "crystal": 4, "gems": 4}, "requires": ["mage_guild_1"], "replaces": "mage_guild_1", "desc": "Teaches level 2 spells."},
	"mage_guild_3": {"name": "Mage Guild Lv3", "cost": {"gold": 1000, "wood": 5, "ore": 5, "mercury": 4, "sulfur": 4, "crystal": 4, "gems": 4}, "requires": ["mage_guild_2"], "replaces": "mage_guild_2", "desc": "Teaches level 3 spells."},
	"mage_guild_4": {"name": "Mage Guild Lv4", "cost": {"gold": 1000, "wood": 5, "ore": 5, "mercury": 6, "sulfur": 6, "crystal": 6, "gems": 6}, "requires": ["mage_guild_3"], "replaces": "mage_guild_3", "desc": "Teaches level 4 spells."},
	"blacksmith": {"name": "Blacksmith", "cost": {"gold": 1000, "wood": 5}, "requires": [], "desc": "Sells war machines and hones a visiting hero's weapons: +1 Attack."},
	# faction special buildings ("faction": only that faction's towns can build them)
	"stables": {"name": "Stables", "faction": "haven", "cost": {"gold": 2000, "wood": 10}, "requires": [], "desc": "Heroes who start the day in this town get +400 movement points."},
	"brotherhood": {"name": "Brotherhood of the Sword", "faction": "haven", "cost": {"gold": 500, "wood": 5}, "requires": ["tavern"], "desc": "+2 morale for the defenders when the town is besieged."},
	"necromancy_amplifier": {"name": "Necromancy Amplifier", "faction": "necropolis", "cost": {"gold": 1000}, "requires": ["mage_guild_1"], "desc": "All your heroes raise 10% more Skeletons with Necromancy."},
	"skeleton_transformer": {"name": "Skeleton Transformer", "faction": "necropolis", "cost": {"gold": 1000}, "requires": ["dwelling_1"], "desc": "Turns a visiting hero's living creatures into Skeletons."},
	"dwelling_1": {"name": "Dwelling I", "cost": {"gold": 1000, "ore": 5}, "dwelling_tier": 1, "requires": ["fort"]},
	"dwelling_2": {"name": "Dwelling II", "cost": {"gold": 1000, "wood": 5, "ore": 5}, "dwelling_tier": 2, "requires": ["dwelling_1"]},
	"dwelling_3": {"name": "Dwelling III", "cost": {"gold": 1500, "wood": 5, "ore": 5}, "dwelling_tier": 3, "requires": ["dwelling_1"]},
	"dwelling_4": {"name": "Dwelling IV", "cost": {"gold": 2000, "wood": 10, "ore": 5, "mercury": 2}, "dwelling_tier": 4, "requires": ["dwelling_2", "tavern"]},
	"dwelling_5": {"name": "Dwelling V", "cost": {"gold": 3000, "wood": 5, "ore": 5, "crystal": 5, "gems": 5}, "dwelling_tier": 5, "requires": ["dwelling_3", "mage_guild_1"]},
	"dwelling_6": {"name": "Dwelling VI", "cost": {"gold": 5000, "wood": 10, "ore": 10, "sulfur": 5}, "dwelling_tier": 6, "requires": ["dwelling_4", "blacksmith"]},
	"dwelling_7": {"name": "Dwelling VII", "cost": {"gold": 20000, "ore": 10, "mercury": 10, "gems": 10}, "dwelling_tier": 7, "requires": ["dwelling_5", "dwelling_6", "citadel"]},
	# upgraded dwellings replace their base one and recruit (and upgrade stacks to) the faction's upgraded creature
	"dwelling_1u": {"name": "Upg. Dwelling I", "cost": {"gold": 1000, "ore": 5}, "dwelling_tier": 1, "requires": ["dwelling_1", "blacksmith"], "replaces": "dwelling_1"},
	"dwelling_2u": {"name": "Upg. Dwelling II", "cost": {"gold": 1000, "wood": 5, "ore": 5}, "dwelling_tier": 2, "requires": ["dwelling_2"], "replaces": "dwelling_2"},
	"dwelling_3u": {"name": "Upg. Dwelling III", "cost": {"gold": 1000, "wood": 5, "ore": 5}, "dwelling_tier": 3, "requires": ["dwelling_3"], "replaces": "dwelling_3"},
	"dwelling_4u": {"name": "Upg. Dwelling IV", "cost": {"gold": 1500, "wood": 5, "ore": 5, "crystal": 5}, "dwelling_tier": 4, "requires": ["dwelling_4"], "replaces": "dwelling_4"},
	"dwelling_5u": {"name": "Upg. Dwelling V", "cost": {"gold": 3000, "wood": 5, "ore": 5, "crystal": 2, "gems": 2}, "dwelling_tier": 5, "requires": ["dwelling_5", "mage_guild_2"], "replaces": "dwelling_5"},
	"dwelling_6u": {"name": "Upg. Dwelling VI", "cost": {"gold": 3000, "wood": 10, "ore": 10, "sulfur": 5}, "dwelling_tier": 6, "requires": ["dwelling_6"], "replaces": "dwelling_6"},
	"dwelling_7u": {"name": "Upg. Dwelling VII", "cost": {"gold": 20000, "ore": 10, "mercury": 10, "gems": 10}, "dwelling_tier": 7, "requires": ["dwelling_7", "mage_guild_3"], "replaces": "dwelling_7"},
}

## Requirements only one faction has (its specials in the chain, as the Stables before the Haven's cavalry).
const FACTION_REQUIRES := {"haven": {"dwelling_6": ["stables"]}}

## Everything a building needs in a town of this faction.
static func requires(faction: String, id: String) -> Array:
	return BUILDINGS[id]["requires"] + FACTION_REQUIRES.get(faction, {}).get(id, [])

## Each faction's special buildings (in the Town Hall's second row).
const SPECIALS := {"haven": ["stables", "brotherhood"], "necropolis": ["necromancy_amplifier", "skeleton_transformer"]}

const DWELLING_NAMES := {
	"haven": ["Guardhouse", "Archers' Tower", "Griffin Tower", "Barracks", "Monastery", "Training Grounds", "Portal of Glory"],
	"necropolis": ["Cursed Temple", "Graveyard", "Tomb of Souls", "Estate", "Mausoleum", "Hall of Darkness", "Dragon Vault"],
}

# ---------------------------------------------------------------------------------------------
# Artifacts
# ---------------------------------------------------------------------------------------------
const ARTIFACTS := {
	"sword_of_valor": {"name": "Sword of Valor", "slot": "weapon", "bonus": {"attack": 3}, "desc": "+3 Attack"},
	"shield_of_dawn": {"name": "Shield of Dawn", "slot": "shield", "bonus": {"defense": 3}, "desc": "+3 Defense"},
	"helm_of_wisdom": {"name": "Helm of Wisdom", "slot": "head", "bonus": {"knowledge": 2}, "desc": "+2 Knowledge"},
	"orb_of_power": {"name": "Orb of Power", "slot": "misc", "bonus": {"power": 3}, "desc": "+3 Spell Power"},
	"boots_of_speed": {"name": "Boots of Speed", "slot": "feet", "bonus": {"movement": 600}, "desc": "+600 movement points"},
	"ring_of_vitality": {"name": "Ring of Vitality", "slot": "ring", "bonus": {"hp": 1}, "desc": "+1 HP to all creatures"},
	"clover_of_fortune": {"name": "Clover of Fortune", "slot": "misc", "bonus": {"luck": 1}, "desc": "+1 Luck"},
	"crown_of_command": {"name": "Crown of Command", "slot": "head", "bonus": {"attack": 2, "defense": 2, "power": 2, "knowledge": 2}, "desc": "+2 to all skills"},
}

# ---------------------------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------------------------
## The New Game list: a fixed map (seed, size, rivals) with its victory and loss conditions; "random" lets the
## player pick the size and the rivals, a new land each time.
const SCENARIOS := [
	{"id": "shattered_crown", "name": "The Shattered Crown", "size": 48, "opponents": 1, "seed": 7301,
		"desc": "Two lords claim the broken crown of the old kingdom, and the realm will not suffer both. Raise your banners and drive your rival from the land.",
		"victory": {"type": "conquer"}, "loss": {"type": "standard"}},
	{"id": "border_skirmish", "name": "Border Skirmish", "size": 36, "opponents": 1, "seed": 4410,
		"desc": "A rival lord has raised a town just across the border. Seize it before its walls grow tall.",
		"victory": {"type": "capture"}, "loss": {"type": "standard"}},
	{"id": "old_kings_gold", "name": "Gold of the Old Kings", "size": 48, "opponents": 2, "seed": 9127,
		"desc": "The treasure of the old kings lies scattered across these hills. Whoever gathers enough of it can buy the loyalty of the whole realm.",
		"victory": {"type": "gold", "amount": 60000}, "loss": {"type": "standard"}},
	{"id": "last_champion", "name": "The Last Champion", "size": 48, "opponents": 2, "seed": 5583,
		"desc": "Your hero is the last of an ancient order of champions. Two rivals hunt you; should your hero fall, the order dies with them.",
		"victory": {"type": "conquer"}, "loss": {"type": "hero"}},
	{"id": "before_the_thaw", "name": "Before the Thaw", "size": 64, "opponents": 3, "seed": 2246,
		"desc": "Three warlords gather while the passes are frozen. Break them all before the snows melt and their hosts join together.",
		"victory": {"type": "conquer"}, "loss": {"type": "days", "days": 112}},
	{"id": "random", "name": "Random Map", "random": true,
		"desc": "A new land every time: choose its size and how many rivals you face.",
		"victory": {"type": "conquer"}, "loss": {"type": "standard"}},
]

static func scenario(id: String) -> Dictionary:
	for s in SCENARIOS:
		if s["id"] == id:
			return s
	return SCENARIOS[0]

static func victory_text(v: Dictionary) -> String:
	match v.get("type", "conquer"):
		"capture": return "Capture an enemy town"
		"gold": return "Amass %d gold" % int(v.get("amount", 0))
	return "Defeat all enemies"

static func loss_text(l: Dictionary) -> String:
	match l.get("type", "standard"):
		"hero": return "Lose your starting hero"
		"days": return "Time runs out (month %d ends)" % (int(l.get("days", 112)) / 28)
	return "Lose all your towns and heroes"

## Starting bonus for the player's first hero (as the classics: gold, an artifact or resources).
const START_BONUSES := {"gold": ["Gold", "+2500 gold"], "artifact": ["Artifact", "A random artifact"],
	"resource": ["Resources", "+10 wood and ore"]}
const BONUS_ARTIFACTS := ["sword_of_valor", "shield_of_dawn", "helm_of_wisdom", "orb_of_power", "boots_of_speed",
	"ring_of_vitality", "clover_of_fortune"]

# ---------------------------------------------------------------------------------------------
# Adventure map
# ---------------------------------------------------------------------------------------------
const TERRAINS := {
	"grass": {"name": "Grass", "move_cost": 100},
	"dirt": {"name": "Dirt", "move_cost": 100},
	"sand": {"name": "Sand", "move_cost": 150},
	"snow": {"name": "Snow", "move_cost": 150},
	"swamp": {"name": "Swamp", "move_cost": 175},
	"water": {"name": "Water", "move_cost": -1},
	"road": {"name": "Road", "move_cost": 50},
}

const MINES := {
	"gold_mine": {"name": "Gold Mine", "resource": "gold", "amount": 1000},
	"sawmill": {"name": "Sawmill", "resource": "wood", "amount": 2},
	"ore_mine": {"name": "Ore Pit", "resource": "ore", "amount": 2},
	"crystal_cavern": {"name": "Crystal Cavern", "resource": "crystal", "amount": 1},
	"gem_pond": {"name": "Gem Pond", "resource": "gems", "amount": 1},
	"alchemist_lab": {"name": "Alchemist's Lab", "resource": "mercury", "amount": 1},
	"sulfur_dune": {"name": "Sulfur Dune", "resource": "sulfur", "amount": 1},
}

const XP_LEVELS := [0, 1000, 2000, 3200, 4600, 6200, 8000, 10000, 12200, 14700, 17500, 20600, 24320, 28784, 34140, 40567]

static func creature(id: String) -> Dictionary:
	return CREATURES.get(id, {})

static func faction_creature(faction: String, tier: int) -> String:
	return FACTIONS[faction]["creatures"][tier - 1]

static func dwelling_name(faction: String, tier: int, upgraded := false) -> String:
	return ("Upg. " if upgraded else "") + DWELLING_NAMES[faction][tier - 1]

## The upgraded creature of a base one ("" when it has none: already upgraded, or not a faction creature).
static func upgrade_of_base(cid: String) -> String:
	var c: Dictionary = CREATURES.get(cid, {})
	if c.is_empty() or c.has("upgrade_of") or not FACTIONS.has(c.get("faction", "")):
		return ""
	return FACTIONS[c["faction"]].get("upgrades", [])[c["tier"] - 1]

## The base creature of an upgraded one (itself for a base creature): sounds and attack effects follow it.
static func base_of(cid: String) -> String:
	return CREATURES.get(cid, {}).get("upgrade_of", cid)

static func building_name(faction: String, id: String) -> String:
	var b: Dictionary = BUILDINGS[id]
	if b.has("dwelling_tier"):
		return dwelling_name(faction, b["dwelling_tier"], b.has("replaces"))
	return b["name"]
