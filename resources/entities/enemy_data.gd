extends Resource
class_name EnemyData

## Rarity is assigned by the area spawn table at runtime. It scales the stat block
## and is only presentation on the data resource itself.
enum Rarity { NORMAL, EPIC, LEGENDARY, ANOMALY }

const RARITY_MULTIPLIERS := [1.0, 1.5, 2.5, 4.0]
const RARITY_TINTS := [
	Color.WHITE,
	Color(0.82, 0.55, 1.0),
	Color(1.0, 0.85, 0.35),
	Color(1.0, 0.35, 0.35),
]

@export_group("Identity")
@export var enemy_name: String = "Goblin"
@export var level: int = 1
@export var rarity: Rarity = Rarity.NORMAL

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
## Bosses get a dedicated health bar and are expected to carry the best drops.
@export var is_boss: bool = false

@export_group("Loot")
## Rows rolled by [LootRoller] when this enemy dies. Empty means no item drops.
@export var loot_table: Array[LootEntry] = []
## Inclusive gold range rolled alongside the loot table. 0/0 drops no gold.
@export var gold_min: int = 0
@export var gold_max: int = 0

@export_group("Audio")
## Optional voice: attack, hurt, idle and death sounds. Leave unset for a silent
## enemy; the SFX component skips missing streams.
@export var sfx: SfxSet


static func rarity_multiplier(value: int) -> float:
	if value < 0 or value >= RARITY_MULTIPLIERS.size():
		return 1.0
	return float(RARITY_MULTIPLIERS[value])


static func rarity_tint(value: int) -> Color:
	if value < 0 or value >= RARITY_TINTS.size():
		return Color.WHITE
	return RARITY_TINTS[value]


static func rarity_name(value: int) -> String:
	if value < 0 or value >= Rarity.size():
		return "Normal"
	return Rarity.keys()[value].capitalize()
