# Artifacts and combination artifacts — proposal (awaiting the user's approval)

Status: **approved and built** (2026-10-20). The user's answers: the list as proposed; combinations merge as in
HoMM3; relics also on random maps; our own names. Built as described below, with these details:
- Medium and large maps get one set's three parts (large: two sets), spread far apart and guarded; relics appear on
  medium maps 60% of the time and always on large maps, never on small ones.
- A set split on the hero screen stays apart until the player joins it again (right-click a part) or takes a part
  off and puts it back on.
- On the map, each artifact is the item itself cut out of its painting (`assets/map/art_<id>.png`), over a glow of
  its tier's colour.
- The existing Ring of Vitality's +1 health had never been applied in battle; it is now.

## Today

- 11 artifacts in `GameData.ARTIFACTS`, all plain bonuses: attack, defense, spell power, knowledge, movement,
  morale, luck, +1 creature health. No tiers, no sets, no special effects.
- Slots (the classic paper-doll): head, cape, neck, weapon, shield, torso, 2 rings, feet, 5 misc; extras go to the
  backpack and do nothing. Bonuses are summed by `GameState.hero_stat()`.
- The map places about 7 random artifacts on a medium map, all with the same generic pedestal sprite, guarded or not
  at random. The winner of a battle takes the loser's artifacts.

## Goals

1. Let a hero **specialise** through what they find: a fighter, a battle mage of one school, a scout, a
   treasurer, a necromancer.
2. Make finding artifacts **exciting and readable**, as in HoMM3: four tiers, better ones harder to reach, each
   artifact shown on the map by its own picture.
3. Add **combination artifacts** the HoMM3 way (below), including the user's dragon sword and shield idea.

All names are our own (no names taken from the classic game); the effects follow its spirit.

## Tiers (as HoMM3's treasure / minor / major / relic)

| Tier | Strength | Where it is found |
|---|---|---|
| Treasure | small (+1 stat, small utility) | often; unguarded or weak guards; sometimes in chests |
| Minor | +2 to +3, modest utility | guarded by a middling stack |
| Major | +4 to +5, or a strong special effect | strong guards, away from the starting towns |
| Relic | game-changing | rare (0–2 per map), very strong guards near the middle of the map; never on small maps |

A random map of medium size would hold about 4 treasure, 3 minor, 2 major and 0–1 relic artifacts, plus the set
pieces placed far apart from each other.

## The list (38 artifacts: the 11 existing ones kept, 27 new)

**Might — attack, defense, the army's toughness**

| Artifact | Slot | Tier | Effect |
|---|---|---|---|
| Soldier's Shortsword | weapon | treasure | +1 Attack |
| Sword of Valor (existing) | weapon | minor | +3 Attack |
| Ogre-Hewn Cleaver | weapon | major | +5 Attack |
| Oaken Buckler | shield | treasure | +1 Defense |
| Shield of Dawn (existing) | shield | minor | +3 Defense |
| Ironwood Tower Shield | shield | major | +5 Defense |
| Quilted Gambeson | torso | treasure | +1 Defense |
| Breastplate of Ironbark (existing) | torso | minor | +2 Defense |
| Ring of Vitality (existing) | ring | major | +1 health for every creature |
| Ring of Swiftness | ring | major | +1 speed for every creature |
| Crown of Command (existing) | head | major | +2 to all four stats |

**Magic — spell power, knowledge, mana, one school stronger**

| Artifact | Slot | Tier | Effect |
|---|---|---|---|
| Apprentice's Circlet | head | treasure | +1 Knowledge |
| Helm of Wisdom (existing) | head | minor | +2 Knowledge |
| Amulet of Insight (existing) | neck | minor | +1 Spell Power, +1 Knowledge |
| Pendant of Clarity | neck | minor | +3 mana each day |
| Orb of Power (existing) | misc | minor | +3 Spell Power |
| Orb of Tempests | misc | major | Air spells +50% damage |
| Orb of Embers | misc | major | Fire spells +50% damage |
| Orb of Tides | misc | major | Water spells +50% damage |
| Orb of Bedrock | misc | major | Earth spells +50% damage |

**Logistics and scouting**

| Artifact | Slot | Tier | Effect |
|---|---|---|---|
| Traveller's Boots | feet | treasure | +200 movement |
| Boots of Speed (existing) | feet | major | +600 movement |
| Wayfarer's Cloak | cape | treasure | +1 scouting radius |
| Seer's Spyglass | misc | minor | +2 scouting radius |

**Morale, luck and economy**

| Artifact | Slot | Tier | Effect |
|---|---|---|---|
| Cape of Courage (existing) | cape | minor | +1 Morale |
| Clover of Fortune (existing) | misc | minor | +1 Luck |
| Signet of Coin | ring | minor | +250 gold each day |
| Bottomless Purse | misc | major | +750 gold each day |
| Banner of the Muster | misc | relic | +3 weekly growth of first-level creatures in all your towns |

**Set pieces** (strong on their own; they merge when all are worn, see below)

| Artifact | Slot | Tier | Effect |
|---|---|---|---|
| Dragonbone Blade | weapon | major | +4 Attack |
| Dragonscale Shield | shield | major | +4 Defense |
| Dragonskull Helm | head | major | +2 Attack, +2 Defense |
| Bone Crown | head | minor | +2 Knowledge |
| Gravecloak | cape | major | +10% Necromancy |
| Phylactery of Ages | misc | major | +2 Spell Power |
| Sun Pendant | neck | minor | +1 Morale |
| Seraph's Feather | misc | minor | +1 Luck |
| Sunsteel Cuirass | torso | major | +3 Defense, +1 Morale |

## Combination artifacts — the HoMM3 way

When a hero **wears every part** of a set, the parts **merge into one combination artifact** with a much stronger
effect. It sits in the first part's slot, and the other parts' slots show as taken by it. On the hero screen a
right-click can **split it back** into its parts (for example to hand them to another hero). This is how HoMM3's
combination artifacts work.

| Combination | Parts | Effect when merged |
|---|---|---|
| **Dragonheart Arms** (might) | Dragonbone Blade + Dragonscale Shield + Dragonskull Helm | +8 Attack, +8 Defense; the army takes no damage from Fire spells |
| **Mantle of the Lich King** (necromancy) | Bone Crown + Gravecloak + Phylactery of Ages | +3 Spell Power, +3 Knowledge, +25% Necromancy; Necromancy raises Zombies instead of Skeletons |
| **Seraph's Covenant** (holy) | Sun Pendant + Seraph's Feather + Sunsteel Cuirass | +3 Morale, +2 Luck, +3 Defense; the army is immune to Curse and Weakness |

**Alternative, not HoMM3:** a "set bonus" that applies while the parts stay separate (the usual RPG approach). I
recommend the merge, as in the classic; say if you prefer the set bonus.

## What else changes

- **The map:** each artifact lying on the map shows its own picture on a small glowing pedestal (as HoMM3 shows
  each artifact), with guards matched to its tier. The hover panel names it and its tier.
- **New rules hooks:** creature speed, scouting radius, mana per day, gold per day, spell-school damage, Necromancy
  percentage, creature growth, spell immunities, and merging / splitting combinations.
- **The hero screen:** tier shown by the socket's border colour (bronze, silver, gold, red); a merged combination
  shown across its slots; right-click to split.
- **The computer opponent** values artifacts by tier and goes for set parts its hero already half owns.
- **Art:** about 27 new painted icons (four sheets of eight with the existing `button_icons_paint.py` workflow),
  plus pictures for the three combinations.
- **Tests:** a battle and map test that equips each artifact and checks its effect, and one that merges and splits
  each combination.

## Suggested build order

1. Data and rules: tiers, the new effect hooks, merging and splitting (tested without new art).
2. Map placement by tier with matching guards; the artifact's own picture on the map.
3. Hero screen: tier borders, combinations, split.
4. Painted icons for all new artifacts and the three combinations.
5. AI valuation, then a judge round.

## Questions for the user

1. Is the list right, or should some directions get more (or fewer) artifacts?
2. Combinations merging, as in HoMM3 (recommended), or a set bonus while separate?
3. Relics on random maps: allowed (rare, heavily guarded) or only in scenarios?
4. Our own names (as listed) — fine?
