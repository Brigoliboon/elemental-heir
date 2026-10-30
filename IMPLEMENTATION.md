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

- `mob.gd` chases the player in 2.5D ground space (using feet-to-feet distance and depth anchors via `DepthSort.get_feet_y()`) while within `aggro_radius` (default `325`).
- The mob maintains attack spacing (`attack_space = 110`, `attack_range = 135`, `min_attack_space = 85`), avoiding crowding or overlapping into the player's sprite body.
- When too close (`dist_x < min_attack_space`), the mob backs up slightly to maintain attack spacing.
- The mob stops chasing and attacks only when **both** conditions are met:
  1. Horizontal range: `dist_x <= attack_range and dist_x >= min_attack_space`.
  2. Depth alignment: `abs(delta_y_feet) <= attack_depth_tolerance` (default `30`).
- If the player is above or below the mob on a different depth plane, the mob will navigate in Y to align with the player's depth lane rather than attacking the air above or below.
- Chase uses `CharacterBody2D.move_and_slide()` in `MOTION_MODE_FLOATING`, so the mob respects World collisions.
- Facing: Source sprite art is drawn facing left. When the player is to the left (`facing_sign = -1`), `flip_h = false`. When the player is to the right (`facing_sign = 1`), `flip_h = true`. The attack hitbox mirrors across the facing direction.
- `attack_timer`/`attack_cooldown` gate swings.
- Damage is no longer applied from `animation_finished`. The mob owns an `AttackHitbox` (`Hitbox`, Enemy_Attackss layer 16, Player mask 2) that is live only between `attack_hit_start` and `attack_hit_end` of the attack clip.
- Uses `get_tree().get_first_node_in_group("player")` as the aggro fallback.
- `config == null` is guarded, but the real fix is that scenes must never null the data reference.

## Depth indexing and spatial anchors (current)

- `scripts/world/depth_sort.gd` (`DepthSort`) is the single y -> z-index rule for the game:
  `z_index = clamp(round(world_y), -4096, 4096)`.
- `DepthSort.get_feet_y(node)` resolves the world-space feet coordinate:
  - `Character`: `global_position.y + FEET_OFFSET_LOCAL * render_scale`.
  - `Mob`: `global_position.y + depth_foot_offset * scale.y`.
- `DepthSort.is_in_depth(a, b, tolerance)` verifies whether two entities share roughly the same depth lane.
- Moving up the screen (smaller y) always produces a lower index; moving down (larger y) produces a higher index.
- `area.gd:_apply_depth()` applies the rule to the player using the **feet line** (`_feet_y`), not the Character origin.
- `mob.gd:_apply_depth()` applies it using `get_feet_y()`.
- `DepthOverlay` (`scripts/world/depth_overlay.gd`) derives the index from a sprite's bottom edge, so props such as the forest fountain let the player pass behind (when above the base) or in front (when below it).
- Do not hand-author gameplay z-indices in scenes; they are overwritten every frame. Only backgrounds keep a fixed negative z-index.

## Combat hitboxes (current)

- `scripts/combat/hitbox.gd` (`Hitbox`) is the shared damage area:
  - `activate()` clears the per-swing hit set and turns monitoring on;
  - `deactivate()` turns it off;
  - each body in `target_group` is damaged at most once per activation;
  - `depth_tolerance` (default `40.0` px): hits are rejected if `attacker` and target feet Y differ by more than `depth_tolerance`. Attacks only connect if both entities stand on the same depth lane;
  - targets must expose `take_damage(amount, knockback)`.
- Player sword:
  - `Character` builds `SwordHitbox` under the `sword` bone at runtime (`scripts/characters/character.gd`) with `attacker = self`.
  - The box follows the animated blade, including the mirrored facing transform.
  - `AttackData.hit_start` / `hit_end` define the live fraction of each clip; `AttackData.damage` (0 = use `CharacterData.attack_damage`) sets per-hit damage.
  - `Character.SWORD_KNOCKBACK` is pushed into enemies through `Hitbox.knockback_force`.
- Enemy attack:
  - `mob.tscn` contains `AttackHitbox`; `mob.gd` sets its damage from `EnemyData.attack_damage` and assigns `attacker = self`.
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

## Phase 2 - Stats and Leveling (DESIGN_ROADMAP §2)

> `docs/DESIGN_ROADMAP.md` is the source of truth for phases from here on. It
> supersedes M5-M11 below.

- [x] P2.1 - Stats component
  - Add `scripts/combat/stats.gd` (`Stats`) with the `(base + flat) * (1 + pct)`
    pipeline, modifier sources, and `stats_changed`.
  - Extend `CharacterData` and `EnemyData` with the seven core stats and
    per-level growth (`hp_per_level`, `attack_per_level`, `defence_per_level`).
  - Test: `tests/test_stats.gd`.
  - `Stats.get_stat()` is used instead of `Stats.get()` because `Object.get()`
    already exists in GDScript.
- [x] P2.2 - Damage formula
  - Add `scripts/combat/damage.gd` (`Damage`) with
    `raw = attack * skill_multiplier`, `mitigation = raw * defence / (defence + K)`,
    `final = max(1, raw - mitigation)`, `K = 100`.
  - `Hitbox` resolves the outgoing attack from the attacker's `Stats`;
    `Character.take_damage()` and `Mob.take_damage()` mitigate it through the
    target's `DEFENCE`, so the formula is applied exactly once.
  - `Character` and `Mob` source attack/health from `Stats`.
  - `Hitbox.damage` remains the fallback attack value; per-swing overrides are
    stored separately so a combo hit cannot leak into the next swing.
  - Test: `tests/test_damage.gd`.
- [x] P2.3 - XP and leveling
  - Add `resources/progression/progression_data.gd` (`ProgressionData`) and
    `default_progression.tres` for the `base_xp * level ^ exponent` curve, cap 15.
  - `Character` tracks level/experience, grants XP via `add_experience()`,
    reconfigures `Stats`/`Health` on level-up, and emits `level_changed`.
  - `EnemyData.xp_reward` is awarded to the player when a mob dies.
  - Test: `tests/test_leveling.gd`.
- [x] P2.4 - Role rename
  - Rename `CharacterData.CharacterRole.ARCHER` to `ASSASSIN` (DESIGN_ROADMAP §8).
  - Covered by `tests/test_character_data.gd`.

## UI - Stats panel and XP bar (current)

- [x] U1 - Player XP bar
  - `Character` emits `experience_changed` whenever XP is gained.
  - `area_base.tscn` HUD gains `PlayerHealth/XPLabel` and `XPBar`; the area keeps
    them in sync with `experience` / `experience_to_next_level()`.
- [x] U2 - Player stats button
  - HUD gains a `StatsButton` that toggles a reusable `StatsPanel`.
  - The panel lists level, HP, XP, attack, defence, move speed, crit and cooldown.
- [x] U3 - Monster stats on click
  - Clicking/tapping a mob in the world shows its `EnemyData` stats in the same
    panel (name, level, HP, XP reward, combat stats).
  - Test: `tests/test_stats_panel.gd`.

## Fix - Player progress persistence (current)

- [x] P1 - Progress store
  - Add a `PlayerProgress` autoload that keeps level/experience in memory and
    saves them to `user://player_progress.cfg`.
  - Test: `tests/test_player_progress.gd`.
- [x] P2 - Restore and record in areas
  - `Character.apply_progress()` applies saved level/experience and recomputes
    stats/health.
  - `Area` restores the store on load and records XP/level changes so switching
    scenes (and restarting the app) keeps progress.
- [x] P3 - Test isolation
  - The headless runner disables persistence and clears in-memory progress so
    tests are deterministic and never overwrite a real save.

## Phase 3 - Item System (DESIGN_ROADMAP §3)

- [ ] I3.1 - Item and equipment data
  - Add `ItemData`, `EquipmentData` and `StatModifier` resources with item
    type/group, rarity, icon, stacking, class restriction, equip slot and stat
    modifiers.
  - Test: `tests/test_item_data.gd`.
- [ ] I3.2 - Inventory
  - Add a fixed-capacity `Inventory` component with stacking, add/remove,
    slot swap, stack split and type sorting.
  - Test: `tests/test_inventory.gd`.
- [ ] I3.3 - Equipment manager
  - Add an `EquipmentManager` that validates slots/class rules, applies and
    removes `Stats` modifiers, and returns unequipped items to the inventory.
  - Test: `tests/test_equipment.gd`.
- [ ] I3.4 - Default warrior gear
  - Create `default_sword.tres` and `default_buckler.tres` from the warrior
    sprites, with names, descriptions, icons and stat modifiers.
  - Equip both on the warrior entity and keep `Health`/sword damage in sync
    with equipment stat changes.

## UI - HUD virtual joystick

- [x] J1 - Replace the D-pad with the joystick art
  - Use `assets/ui/hud/joystick_frame.png` and `joystick_btn.png` in
    `HUD/UI/MoveControls`.
  - Support touch/mouse drag, deadzone, analog direction and reset on release
    or death; keep keyboard movement working.
  - Test: `tests/test_virtual_joystick.gd`.

## UI - HUD health/XP bars

- [x] J2 - Replace the top-left bars with the bar art
  - Use `bar-container.png` with `health-bar.png` and `exp-bar.png` for the
    player health and XP bars; keep labels overlaid and values live.
  - Test: `tests/test_hud_bars.gd`.

## UI - HUD attack button

- [x] J3 - Use the attack button art
  - Replace the text `AttackButton` with a `TextureButton` using
    `assets/ui/hud/attack-btn.png`, while keeping the existing attack signal.
  - Test: `tests/test_hud_buttons.gd`.

## UI - HUD player profile

- [x] J4 - Show the real player level and open inventory from the profile
  - `HUD/UI/PlayerHealth/LevelLabel` displays `player.level` and updates on
    level changes.
  - Clicking `HUD/UI/PlayerHealth/Profile` toggles the inventory panel.
  - Test: `tests/test_hud_profile.gd`.

## UI - HUD attack press feedback

- [x] J5 - Dim the attack button while pressed
  - Reduce the `AttackButton` opacity on press and restore it on release
    without changing its art.
  - Test: `tests/test_hud_attack_state.gd`.

## UI - World map

- [x] J6 - Replace the top-right HUD buttons with the world map
  - Remove `StatsButton` and `InventoryButton`; add a `TextureButton` using
    `assets/ui/hud/map-btn.png` that opens the world map scene.
  - Add `scenes/map/world_map.tscn`, filled by
    `assets/backgrounds/world-map.jpg`, with back navigation and zoom in/out.
  - Test: `tests/test_world_map.gd`.

## Fix - Title screen responsive layout

- [x] T1 - Anchor title controls to the viewport
  - Add a full-rect `CanvasLayer/UI` Control and move the sound, credits,
    offline, online, settings and no-connection controls under it.
  - Anchor the top icons to the top-right and the navigation buttons to the
    bottom-right, so their margins stay fixed when the viewport grows instead
    of being pinned to 1920x1080 offsets.
  - Make the background video fill the root Control.
  - Test: `tests/test_title_layout.gd`.
- [x] T2 - Enlarge title touch targets for mobile
  - Top-right icons are 128x120 design px; navigation buttons are 360x104.
  - Images keep their aspect instead of stretching into the new touch rects.

## Fix - Background props and obstacle alignment

- [x] B1 - Lock props and collisions to the background
  - Add `BackgroundProps` under the area root. Fountain overlay, village
    lamps and static obstacle bodies live under it.
  - `Area._layout_background()` maps `BackgroundProps` to the same position and
    scale ratio as the background, so overlay art and collision footprints no
    longer drift when the viewport or DPI changes.
  - `Area` relayouts and re-collects blockers on viewport resize.
  - Test: `tests/test_background_props.gd`.

## Fix - HUD scale and centred area title

- [x] H1 - Scale the HUD layer for mobile
  - `Area._layout_hud()` scales `HUD/UI` by `hud_scale_for(view, mobile)` and
    shrinks its layout rect by the same factor, so the profile, bars, labels and
    touch targets grow while children anchored to the screen edges still land on
    the real edges.
  - `hud_scale_mobile = 1.4` / `hud_scale_desktop = 1.0` are exported so the
    amount can be tuned per area without touching code.
  - `HUD/UI` is now an explicit-size root laid out by the area, instead of a
    full-rect anchored control whose size the layout engine would override.
- [x] H2 - Centre the area title
  - `AreaLabel` is anchored to the horizontal centre with centre alignment, so
    it no longer sits at 1920-px offsets on wider or narrower screens.
  - Test: `tests/test_hud_layout.gd`.

## Fix - Character frozen after switching attack and block

- [x] C1 - Stop the combo latching when the guard interrupts a swing
  - Raising the guard mid-attack replaced the attack animation with `block`, so
    the combo never received `animation_finished`. `is_attacking()` stayed true
    forever and `Character.move_2d()` ignored all input, freezing the character.
  - `Character.block(true)` now cancels the active swing before raising the
    guard.
  - `AttackCombo` also clears itself whenever its attack animation is no longer
    the one playing, so any other interruption heals instead of latching.
  - `Area` reconciles the guard against the block button's real held state each
    frame, so a dropped `button_up` on touch input cannot keep the guard stuck.
  - Test: `tests/test_attack_block_lock.gd`.

## Next milestones

> Superseded by `docs/DESIGN_ROADMAP.md` (see the Phase 2 section above). Kept
> for historical context only.

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
