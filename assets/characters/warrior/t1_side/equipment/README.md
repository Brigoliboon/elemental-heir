# Warrior equipment art

Each slot folder holds replacement parts for the rig in `../rig/`.
Every file is 1x pixel art, right-facing, transparent, in bone-local space
(upright, not posed), and reuses the pivots from `../rig/pivots.json`.

Name files `<item_id>_<part>.png`:

- `chestplate/iron_chestplate_torso.png`
- `chestplate/iron_chestplate_upper_arm_l.png`
- `helmet/iron_helm_head.png`
- `leggings/leather_leggings_pelvis.png`
- `boots/leather_boots_foot_l.png`
- `sword/iron_sword_sword.png`
- `shield/wooden_buckler_buckler.png`

Only include the parts an item actually replaces. Missing parts fall back to
the base rig.

Slot ownership:

- chestplate: torso + both upper arms + both forearms (+ hands for gauntlets)
- helmet: head
- leggings: pelvis + both thighs
- boots: both shins + both feet
- sword: sword
- shield: buckler
