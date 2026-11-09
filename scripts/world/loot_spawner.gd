class_name LootSpawner
extends RefCounted
## Turns rolled loot into world pickups. Kept separate from [Monster] so the AI
## does not need to know how drops are presented, and so tests can spawn drops
## without killing a monster.
##
## Pickups scatter a little around the death spot, stay inside the walkable band
## and sort by depth like every other world entity.

const PICKUP_SCENE := preload("res://scenes/world/loot_pickup.tscn")
const SCATTER_RADIUS := 34.0
## Vertical scatter is flattened so drops do not jump between depth lanes.
const SCATTER_DEPTH_RATIO := 0.45


## Spawns one pickup per drop. `drops` is the `{ "item", "count" }` list
## returned by [LootRoller]. Returns the nodes it created.
static func spawn_drops(
	parent: Node,
	origin: Vector2,
	drops: Array[Dictionary],
	rng: RandomNumberGenerator,
) -> Array[LootPickup]:
	var spawned: Array[LootPickup] = []
	if parent == null:
		return spawned
	for drop in drops:
		var item := drop.get("item") as ItemData
		if item == null:
			continue
		var pickup := _spawn(parent, origin, rng)
		if pickup == null:
			continue
		pickup.setup_item(item, int(drop.get("count", 1)))
		spawned.append(pickup)
	return spawned


static func _spawn(parent: Node, origin: Vector2, rng: RandomNumberGenerator) -> LootPickup:
	var pickup := PICKUP_SCENE.instantiate() as LootPickup
	if pickup == null:
		return null
	var angle := rng.randf_range(0.0, TAU)
	var distance := rng.randf_range(6.0, SCATTER_RADIUS)
	var offset := Vector2(
		cos(angle) * distance,
		sin(angle) * distance * SCATTER_DEPTH_RATIO
	)
	var point := origin + offset
	parent.add_child(pickup)
	pickup.global_position = point
	pickup.z_index = DepthSort.z_for_y(point.y) + 1
	return pickup
