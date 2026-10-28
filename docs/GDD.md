# Elemental Heir - Game Design Document

## Vision

Elemental Heir is a top-down 2D action RPG built for Android in Godot 4.7 with
the GL Compatibility renderer. The tone is dark-knight fantasy: ancient stone,
ember-lit skies, and elemental magic. The hero inherits the power of five
elements and fights to reclaim a broken kingdom.

## Classes and progression

- Playable classes: **Warrior**, **Assassin**, and **Mage**.
- Each class is available as a male or female character at level 1.
- Both gender variants share the same evolved forms.
- Each class has **three evolution tiers**. Evolution changes stats, visuals,
  and abilities while preserving the chosen class identity.
- Level cap: **15**.

## World

Five regions, each tied to an element:

1. **Verdant Forest** - Wind
2. **Scorched Desert** - Fire
3. **Sunken Coast** - Water
4. **Stone Caverns** - Earth
5. **Shadow Citadel** - Shadow

Regions are explored from a top-down perspective and culminate in region
bosses. Enemy levels and loot scale with progression.

## Systems

- **Loot**: enemies, chests, and bosses drop equipment and materials.
- **Gold store**: spend gold on gear, consumables, and cosmetic upgrades.
- **Evolution**: gather evolution materials to advance through the three tiers.
- **Multiplayer**: 1v1 PvP over IP, with a turn-based fallback when real-time
  play is not viable.

## Art and animation direction

- Dark-knight fantasy art style with high-contrast metal, cloth, and elemental
  VFX.
- Characters use cutout-rig animation built on **Skeleton2D**.
- Source character scale: **128 px**.
- Required animation set per character: **idle, walk, attack, dodge, hurt,
  death**.
- UI uses the Cinzel typeface with light, warm text on dark stone panels.

## Milestone 1 scope

- Title screen with static key art, looping background music, connectivity-gated
  Online button, audio toggle persistence, Settings/Credits placeholders.
- Warrior tier 1 side-view cutout rig test with idle and walk animations.
