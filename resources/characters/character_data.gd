extends Resource
class_name CharacterData

enum CharacterRole {
	WARRIOR,
	MAGE,
	ARCHER,
	ENEMY
}

@export_group("Identity")
@export var character_name: String = "Character"
@export var character_role: CharacterRole = CharacterRole.WARRIOR

@export_group("Base Stats")
@export var max_health: int = 100
@export var move_speed: float = 230.0
@export var attack_damage: int = 15
@export var defence: int = 10

@export_group("Progression")
@export var starting_level: int = 1
@export var starting_exp: int = 0

@export_group("Rig")
@export_file("*.json") var pivots_path := ""
@export_dir var part_dir := ""
@export var base_scale := 3.0
@export var far_leg_x_offset := -2.0
@export_range(0.5, 2.0, 0.05) var thigh_length_scale := 1.0
@export var draw_order: Dictionary = {}

@export_group("Combo")
@export var attacks: Array[AttackData] = []
@export_range(0.0, 1.0) var attack_queue_from := 0.4
@export var attack_blend := 0.05
@export var recover_blend := 0.12

@export_group("Block")
@export var block_damage_reduction: float = 0.5
