class_name LootPickup
extends Area2D
## A dropped item on the ground. Collecting it is a simple walk-over: when the
## player's body enters the area, the item goes into the bag and the node frees
## itself. A full bag leaves the pickup where it is.

var item: ItemData
var count := 1

var _collected := false

## Longest side of a dropped item's icon, in world pixels, regardless of source art size.
const WORLD_ICON_PIXELS := 28.0

@onready var _icon: Sprite2D = $Visual/Icon


func _ready() -> void:
	add_to_group("loot_pickup")
	body_entered.connect(_on_body_entered)
	_refresh_visuals()


func setup_item(new_item: ItemData, new_count: int = 1) -> void:
	item = new_item
	count = maxi(1, new_count)
	if is_node_ready():
		_refresh_visuals()


## Attempts to collect this pickup for `character`. Returns true when the
## pickup was consumed. Kept public so tests and debug tools can collect
## without relying on physics overlap timing.
func collect_by(character: Character) -> bool:
	if _collected or character == null or item == null:
		return false
	var inventory := character.inventory
	if inventory == null:
		return false
	if not inventory.can_add(item, count):
		return false
	inventory.add_item(item, count)
	_finish()
	return true


func is_collected() -> bool:
	return _collected


func _on_body_entered(body: Node2D) -> void:
	if body is Character:
		collect_by(body as Character)


func _refresh_visuals() -> void:
	if _icon == null:
		return
	_icon.visible = item != null and item.icon != null
	if _icon.visible:
		_icon.texture = item.icon
		var icon_size := item.icon.get_size()
		var longest := maxf(1.0, maxf(icon_size.x, icon_size.y))
		_icon.scale = Vector2.ONE * (WORLD_ICON_PIXELS / longest)


func _finish() -> void:
	if _collected:
		return
	_collected = true
	set_deferred("monitoring", false)
	queue_free()
