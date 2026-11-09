extends ItemData
class_name ConsumableData
## A stackable item the player can use from the bag.
##
## A consumable is only spent when it actually changes something, so drinking a
## potion at full health does not waste it.

## Health restored on use. 0 means the item does not heal.
@export var heal_amount: int = 0
## Skill energy restored on use. 0 means the item does not restore energy.
@export var energy_amount: float = 0.0
## Verb shown by the inventory UI, e.g. "Drink".
@export var use_text: String = "Use"
