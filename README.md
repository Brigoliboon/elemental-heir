		# Elemental Heir

Elemental Heir is a top-down 2D action RPG for Android. The player chooses a
Warrior, Assassin, or Mage, explores five elemental regions, collects loot, and
evolves their hero through three tiers.

This repository currently contains Milestone 1: the title screen, the online
connectivity gate, placeholder settings/online/credits screens, and a cutout-rig
warrior animation test scene.

## Engine

- Godot 4.7
- GL Compatibility renderer (mobile-friendly)
- GDScript only
- Design resolution: 1920x1080, `canvas_items` stretch, `expand` aspect,
  sensor landscape on mobile

## Open and run

Open `project.godot` in Godot 4.7 and press Play. The title screen is the main
scene.

From a terminal:

```sh
~/.local/bin/godot --path .
```

Headless validation:

```sh
~/.local/bin/godot --headless --path . --import
~/.local/bin/godot --headless --path . --quit-after 120
~/.local/bin/godot --headless --path . --quit-after 120 res://scenes/tests/warrior_rig_test.tscn
```

## Folder layout

- `scenes/title/` - title screen scene and connectivity/audio script
- `scenes/tests/` - warrior Skeleton2D cutout-rig test
- `scenes/online/`, `scenes/settings/`, `scenes/credits/` - milestone placeholders
- `scripts/` - shared UI scripts and the persistent music autoload
- `themes/` - shared Cinzel dark UI theme
- `assets/` - source art, audio, font, and warrior rig parts
- `docs/` - game design document
- `CREDITS.md` - asset and code credits
