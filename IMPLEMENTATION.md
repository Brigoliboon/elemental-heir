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
- [x] M4.5 - Shared health, death and combat feedback
  - `Health` component configured from `CharacterData` / `EnemyData`.
  - Player i-frames, death state, HUD health bar, death overlay and timed respawn.
  - Mob damage flash, knockback, world health bar and death fade.
  - Tests: `tests/test_health.gd`, `tests/test_death_respawn.gd`.

## Blocking (added after M4)

- `CharacterData.block_damage_reduction` (default `0.5`) scales incoming damage while the guard is up.
- `Character.block(on: bool)` raises/lowers the guard, plays the `block` animation, and emits `blocking_changed`.
- While blocking: movement and attacks are ignored; `take_damage()` reduces damage by `block_damage_reduction`.
- `warrior_side_animations.gd` builds a static `block` clip (guard pose) added to the AnimationLibrary.
- UI: `Block` button in `area_base.tscn` and `warrior_rig_test.tscn`, wired to `Character.block()` on press/release; `K` key also toggles block in the rig test.

## Enemy chase and attack (current)

- `mob.gd` chases the player while the player is inside `aggro_radius` (default `325`, matching the Attack Radius area) and stops at `attack_range` (default `80`).
- Chase uses `CharacterBody2D.move_and_slide()` in `MOTION_MODE_FLOATING`, so the mob respects World collisions.
- `attack_timer`/`attack_cooldown` gate swings. The mob faces the player with `flip_h` and mirrors its hitbox with `facing_sign`.
- Damage is no longer applied from `animation_finished`. The mob owns an `AttackHitbox` (`Hitbox`, Enemy_Attackss layer 16, Player mask 2) that is live only between `attack_hit_start` and `attack_hit_end` of the attack clip.
- Uses `get_tree().get_first_node_in_group("player")` as the aggro fallback.
- `config == null` is guarded, but the real fix is that scenes must never null the data reference.

## Depth indexing (current)

- `scripts/world/depth_sort.gd` (`DepthSort`) is the single y -> z-index rule for the game:
  `z_index = clamp(round(world_y), -4096, 4096)`.
- Moving up the screen (smaller y) always produces a lower index; moving down (larger y) produces a higher index.
- `area.gd:_apply_depth()` applies the rule to the player using the **feet line** (`_feet_y`), not the Character origin.
- `mob.gd:_apply_depth()` applies it using `global_position.y + depth_foot_offset`.
- `DepthOverlay` (`scripts/world/depth_overlay.gd`) derives the index from a sprite's bottom edge, so props such as the forest fountain let the player pass behind (when above the base) or in front (when below it).
- Do not hand-author gameplay z-indices in scenes; they are overwritten every frame. Only backgrounds keep a fixed negative z-index.

## Combat hitboxes (current)

- `scripts/combat/hitbox.gd` (`Hitbox`) is the shared damage area:
  - `activate()` clears the per-swing hit set and turns monitoring on;
  - `deactivate()` turns it off;
  - each body in `target_group` is damaged at most once per activation;
  - targets must expose `take_damage(amount, knockback)`.
- Player sword:
  - `Character` builds `SwordHitbox` under the `sword` bone at runtime (`scripts/characters/character.gd`).
  - The box follows the animated blade, including the mirrored facing transform.
  - `AttackData.hit_start` / `hit_end` define the live fraction of each clip; `AttackData.damage` (0 = use `CharacterData.attack_damage`) sets per-hit damage.
  - `Character.SWORD_KNOCKBACK` is pushed into enemies through `Hitbox.knockback_force`.
- Enemy attack:
  - `mob.tscn` contains `AttackHitbox`; `mob.gd` sets its damage from `EnemyData.attack_damage`.
- Physics layers now follow Godot bit values (see the corrected table below). `collision_layer` is a mask, not a layer number.

## Shared health, death and feedback (current)

- `scripts/combat/health.gd` (`Health`) is the single health pool for every damageable entity:
  - `configure(max_health)` resets to full and is called from the entity's data resource;
  - `take_damage(amount)` clamps at zero, ignores dead/invulnerable targets and emits `damaged`, `health_changed` and `died`;
  - `heal`, `kill`, `reset`, `set_max_health(keep_ratio)` and `clear_invulnerability()` cover respawn, debug tools and future potions;
  - `invulnerability_seconds` is opt-in i-frames. Damage is refused while the timer runs.
- `warrior.tscn` and `mob.tscn` each own a `Health` child. `Character` and `Mob` delegate to it and keep their public API (`current_health`, `max_health`, `take_damage`, `is_alive`, `health_changed`, `died`) so existing HUD/tests do not need to know about the component. Both also expose `damaged` and `is_dead()`.
- A runtime `Health` is created as a fallback if a hand-built scene forgets the child, so the entity never silently loses health.
- Damage feedback:
  - `Character` and `Mob` flash red on `Health.damaged`;
  - the player's block reduction stays in `Character.take_damage` before forwarding to `Health`;
  - `Hitbox.knockback_force` pushes mobs away from the hit; `mob.gd` decays that impulse (`knockback_decay`) and feeds it through `move_and_slide()`;
  - `mob.tscn` owns a `WorldHealthBar` (`scripts/ui/world_health_bar.gd`) above the sprite. It binds to the sibling `Health` node, draws in world space, hides while full and fades with the corpse.
- Player death/respawn:
  - `Character` cancels the combo, deactivates the sword hitbox, locks movement/attack/block and fades the rig when `Health` reaches zero;
  - `Area` binds the player's health, updates the HUD bar/label and shows the death overlay;
  - after `respawn_delay` (2 s by default) the area calls `Character.revive()` and reuses `_place_player()` so the player returns to the area spawn point with full health and cleared i-frames.
- Mob death: collision, aggro and attacks turn off immediately; the corpse fades over `death_fade_seconds` and frees itself.
- HUD: `area_base.tscn` has `HUD/UI/PlayerHealth/{HealthLabel, HealthBar}` and a centered `DeathLabel`. The debug label moved down to make room.
- `AttackCombo.cancel()` stops a chain without playing the normal recovery clip; death and respawn use it.
- Tests: `tests/test_health.gd` and `tests/test_death_respawn.gd` cover damage/heal/death/i-frames/reset, player death/revive, mob fade, HUD binding and timed area respawn.

## Physics layers

| Layer | Name | Bit value |
| --- | --- | --- |
| 1 | World | 1 |
| 2 | Player | 2 |
| 3 | Enemies | 4 |
| 4 | Player_Attacks | 8 |
| 5 | Enemy_Attackss | 16 |

- Player body: layer 2, mask 1.
- Mob body: layer 4, mask 1.
- Player sword hitbox: layer 8, mask 4.
- Mob attack hitbox: layer 16, mask 2.
- Mob aggro area: layer 0, mask 2.

## Fixed: character invisible / `base_scale` on Nil

- Cause: `forest_village_square.tscn` and `forest_fight.tscn` still overrode `Player.config` with the deleted `warrior_t1_side.tres`, so `config` was `null`. `Character._ready()` returned early (no rig, invisible), and the next move attempt read `config.base_scale`.
- `forest_fight.tscn` also explicitly set `Mob.config = null`.
- Fix: removed the stale overrides, the duplicate `Skeleton2D2`/`AnimationPlayer2` nodes and the manual player `z_index`, so the inherited player entity keeps `warrior.tres`.
- Regression test: `tests/test_scene_integrity.gd` instantiates both forest scenes and asserts the data is non-null and the rig builds.

## Next milestones

### M5 - Character roster (Warrior, Mage, Assassin)

- One `.tres` per class (`warrior.tres`, `mage.tres`, `assassin.tres`) with distinct `part_dir`, `pivots_path`, `base_scale`, draw order, stat block and attack list.
- One entity scene per class, all reusing `Character` + `CharacterRig`:
  - `entities/characters/warrior.tscn`
  - `entities/characters/mage.tscn`
  - `entities/characters/assassin.tscn`
- `CharacterData.character_role` selects class restrictions and the animation builder. Keep `WarriorSideAnimations` behind a small `CharacterAnimations` interface if the mage/assassin rigs need different clips.
- Add `tests/test_character_roster.gd` that loads all three data resources and scenes, then builds each rig headlessly.

### M6 - Shared character components

Split the runtime `Character` into small components so classes stay data-driven:

- `Inventory` (equipment, consumables, stacking rules).
- `SkillLoadout` (unlocked skills + equipped slots).
- `Stats` (base stats + equipment/skill modifiers).
- `PotionBelt` (limited quick slots).
- Keep `Character` as the orchestrator that forwards input and exposes `take_damage()`, `attack()` and `move_2d()`.

### M7 - Skills

- `SkillData` resource: id, display name, class restriction, unlock level/cost, cooldown, resource cost, animation clip id, hit window, damage/effect type, icon.
- `SkillLoadout` stores unlocked ids and a fixed number of equipped slots (for example 3 active + 1 ultimate).
- Unlock and equip APIs: `unlock_skill(id)`, `equip_skill(id, slot)`, `unequip_skill(slot)`.
- Runtime casts reuse `Hitbox`; ranged/projectile skills add a projectile scene instead of a melee hitbox.
- Save format stores ids + slot indices, never node paths.

### M8 - Inventory and potions

- `ItemData` resource: id, type, stack size, rarity, class restrictions, icon, stats/effects.
- `InventoryData` resource on the character or a `CharacterInventory` node: fixed bag slots, add/remove/swap, stack splitting.
- `PotionBelt` with a small fixed number of quick slots (for example 3). Potions are `ItemData` with a heal/buff effect and a cooldown.
- UI: grid inventory, drag/drop or tap-to-move, potion belt HUD with counts.

### M9 - Equipment

- Slots: `head`, `chest`, `pants`, `foot`, `necklace`, `primary`, `secondary`.
- `EquipmentData` extends `ItemData` with slot, class masks, stat modifiers and optional granted skill.
- `EquipmentSet` validates `CharacterRole` before equipping; primary/secondary are also restricted by class (sword/buckler for Warrior, staff/orb for Mage, dagger/off-hand for Assassin).
- Stats recompute from base + equipment + skills and emit `stats_changed` so health/damage UI updates immediately.

### M10 - Persistence and authoring

- Save/load character id, class, level/exp, unlocked skills, equipped skill slots, inventory stacks, equipment slots and potion belt counts.
- Provide editor-facing `.tres` templates for every class/item/skill so balance changes do not require code edits.
- Add a data validation pass (ids unique, slot/class restrictions valid, referenced scenes/textures exist).

### M11 - Content and validation

- Add enemies beyond the goblin using the same `EnemyData` + `mob.tscn` pattern; only data and sprite frames vary.
- Add attack/death/hurt feedback, drop tables and loot pickup.
- Keep headless tests for: data resources load, all class rigs build, scenes have non-null data, hitboxes use the correct layers, depth order is monotonic.

## Non-goals for the current pass

- Full skill/inventory UI and save files (planned in M7-M10).
- Ranged projectiles; the current implementation covers melee hitbox timing.
- Loot drops and class-specific death animations (all classes currently share the fade-out).
