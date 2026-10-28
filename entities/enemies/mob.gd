extends CharacterBody2D
class_name BaseMob

@export var config: EnemyData
var current_health: int

func _ready() -> void:
	if config:
		current_health = config.max_health
		print("Successfully spawned a ", config.enemy_name, " with ", current_health, " HP!")
	else:
		push_error("Error: This mob scene is missing an EnemyData resource configuration!")
