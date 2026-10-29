# Elemental Heir - Implementation Plan

## Scope

Migrate the character and enemy entity architecture so each entity is defined by:

1. A data blueprint resource (`CharacterData`, `EnemyData`).
2. A `.tres` configuration instance (`warrior.tres`, `goblin.tres`).
3. A saved entity scene (`warrior.tscn`, `mob.tscn`).

The UI, branding, theme (Cinzel dark stone) and existing rig art are unchanged.
Movement tuning for the cutout rig stays in `WarriorSideAnimations`; the new data
fields are consumed where the current runtime already exposes them.

## Architecture

### Character

- `CharacterData` is the single per-character resource. It replaces
  `CharacterConfig` and holds identity, stats/progression, rig settings, draw
  order and the attack combo.
- `Character` (runtime) extends `CharacterBody2D` so enemies can detect and
  damage it through physics areas. It owns runtime health and `take_damage()`.
- `entities/characters/warrior.tscn` is the player entity: script, data,
  collision, `player` group, `Skeleton2D` and `AnimationPlayer`.
- Areas and the rig test instance the entity scene instead of rebuilding the
  node tree inline.

### Enemy

- `EnemyData` remains a stats-only blueprint.
- `mob.gd` exports `EnemyData`, initializes health/damage from it and exposes
  `take_damage()`.
- `mob.tscn` references `goblin.tres`, uses the project physics layers
  (Enemies = 3, Player = 2, World = 1) and its attack area detects the Player
  layer.
- The attack clip is non-looping so `animation_finished` fires.

### Layers

| Layer | Name |
| --- | --- |
| 1 | World |
| 2 | Player |
| 3 | Enemies |
| 4 | Player_Attacks |
| 5 | Enemy_Attackss |

## Modules and checkpoints

- [x] M1 - Character data consolidation
  - Merge `CharacterConfig` fields into `CharacterData`.
  - Consolidate `warrior_t1_side.tres` into `warrior.tres`.
  - Update `Character`, `CharacterRig`, `AttackCombo` to use `CharacterData`.
  - Remove `character_config.gd`.
  - Test: `tests/test_character_data.gd`.
- [x] M2 - Player entity
  - `warrior.tscn` becomes the player entity (`CharacterBody2D` root, `player`
    group, collision, health, `take_damage`).
  - Replace inline player nodes in `area_base.tscn` and `warrior_rig_test.tscn`.
  - Test: `tests/test_player_entity.gd`.
- [x] M3 - Enemy data wiring
  - `mob.gd` exports `EnemyData`; `mob.tscn` references `goblin.tres`.
  - Fix attack loop, physics layers and attack-area detection.
  - Remove unused `hostile-mob.gd`.
  - Test: `tests/test_mob_entity.gd`.
- [x] M4 - Validation
  - Headless import succeeds.
  - Test scene passes.
  - Existing scenes load headless.

## Blocking (added after M4)

- `CharacterData.block_damage_reduction` (default `0.5`) scales incoming damage while the guard is up.
- `Character.block(on: bool)` raises/lowers the guard, plays the `block` animation, and emits `blocking_changed`.
- While blocking: movement and attacks are ignored; `take_damage()` reduces damage by `block_damage_reduction`.
- `warrior_side_animations.gd` builds a static `block` clip (guard pose) added to the AnimationLibrary.
- UI: `Block` button in `area_base.tscn` and `warrior_rig_test.tscn`, wired to `Character.block()` on press/release; `K` key also toggles block in the rig test.

## Enemy chase (added after M4)

- `mob.gd` chases the player when within `attack_radius` (Area2D) using `config.move_speed`.
- `attack_range` export (default `80`) sets the distance at which the mob stops moving to attack.
- Mob faces the player direction (`flip_h`) while chasing and plays the `walk` animation; reverts to `default` when idle.
- Uses `get_tree().get_first_group("player")` as a fallback if Area2D detection misses the player.
- While attacking, movement pauses and resumes after the attack animation finishes.
- Guards against `config == null` to avoid crashes when `EnemyData` is unassigned.

## Player depth z-index (added after M4)

- `area.gd:_apply_depth()` sets `player.z_index = int(lerpf(-10, 10, depth_ratio()))`, so the player renders behind objects when farther up (far edge, depth_ratio near 0) and in front when farther down (near edge, depth_ratio near 1). This gives proper sprite overlap in depth-based area scenes.

## Non-goals

- Chase AI, death animation, inventory or status systems.
- `move_speed` and `defence` are stored data; they are not wired into new gameplay formulas in this migration.
