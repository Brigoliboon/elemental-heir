extends Resource
class_name EnemyData

@export_group("Identity")
@export var enemy_name: String = "Goblin"
@export var level: int = 1

@export_group("Base Stats")
@export var max_health: int = 100
@export var move_speed: float = 200.0
@export var attack_damage: int = 15
@export var defence: int = 0
@export_range(0.0, 1.0) var crit_rate: float = 0.0
@export var crit_damage: float = 1.5
@export_range(0.0, 1.0) var cooldown_reduction: float = 0.0

@export_group("Rewards")
@export var xp_reward: int = 10
