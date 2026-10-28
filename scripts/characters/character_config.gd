class_name CharacterConfig
extends Resource
## Everything that makes one character different from another: its rig art, display
## scale, draw order and attack combo. Movement and animation tuning stays in code.

@export_group("Rig")
@export_file("*.json") var pivots_path := ""
@export_dir var part_dir := ""
@export var base_scale := 3.0
## Shifts the far thigh sideways so the two legs don't overlap exactly.
@export var far_leg_x_offset := -2.0
## Stretches both thighs lengthwise (1.0 = art size). The knees, shins and leg math
## follow, so animations stay correct; pixels get stretched until the art is redrawn.
@export_range(0.5, 2.0, 0.05) var thigh_length_scale := 1.0
## Part name -> z_index. Parts not listed use the z_index from pivots.json.
@export var draw_order: Dictionary = {}

@export_group("Combo")
@export var attacks: Array[AttackData] = []
## Fraction of the current hit after which another press queues the next hit.
@export_range(0.0, 1.0) var attack_queue_from := 0.4
## Blend time into each attack (s).
@export var attack_blend := 0.05
## Blend time back to idle after the combo ends (s).
@export var recover_blend := 0.12
