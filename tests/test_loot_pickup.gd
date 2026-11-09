extends RefCounted
## Validates walk-over loot pickups: collection, full bags, despawn and the
## automatic pickup when the player's body overlaps the area.

const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const PICKUP_SCENE := "res://scenes/world/loot_pickup.tscn"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load" % AREA_SCENE)
		return failures
	var area := packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame
	if area.player == null:
		failures.append("the test area needs a player")
		area.queue_free()
		await tree.process_frame
		return failures

	failures.append_array(await _check_collection(tree, area))
	failures.append_array(await _check_full_inventory(tree, area))
	failures.append_array(await _check_despawn(tree, area))
	failures.append_array(await _check_walk_over(tree, area))

	area.queue_free()
	await tree.process_frame
	return failures


func _check_collection(tree: SceneTree, area: Area) -> Array[String]:
	var failures: Array[String] = []
	var player := area.player
	var item := _item(&"test_pickup_item")
	var pickup := _spawn(area, player.global_position + Vector2(40, 70))
	pickup.setup_item(item, 3)

	if not pickup.collect_by(player):
		failures.append("an item pickup must collect into an empty bag")
	if player.inventory.count_of(item) != 3:
		failures.append("a pickup of 3 must add 3 items")
	if pickup.collect_by(player):
		failures.append("a collected pickup must not be collectable twice")
	if player.inventory.count_of(item) != 3:
		failures.append("collecting twice must not duplicate items")
	await tree.process_frame
	return failures


func _check_full_inventory(tree: SceneTree, area: Area) -> Array[String]:
	var failures: Array[String] = []
	var player := area.player
	var original := player.inventory
	var full := Inventory.new()
	full.capacity = 2
	for i in 2:
		var filler := _item(StringName("filler_%d" % i))
		full.add_item(filler, 1)
	player.inventory = full

	var item := _item(&"blocked_item")
	var pickup := _spawn(area, player.global_position + Vector2(40, 70))
	pickup.setup_item(item, 1)
	var blocked_messages: Array[String] = []
	pickup.collect_blocked.connect(func(message: String) -> void: blocked_messages.append(message))

	if pickup.collect_by(player):
		failures.append("a pickup must not collect into a full bag")
	if blocked_messages.is_empty() or blocked_messages[0] != "Inventory full":
		failures.append("a blocked pickup must explain that the inventory is full")
	if full.count_of(item) != 0:
		failures.append("a blocked pickup must not add anything")
	if not is_instance_valid(pickup) or pickup.is_collected():
		failures.append("a blocked pickup must stay on the ground")

	var toast := area.get_node_or_null("HUD/UI/Toast") as Label
	if toast == null or toast.text != "Inventory full":
		failures.append("the HUD toast must show 'Inventory full'")

	player.inventory = original
	pickup.queue_free()
	await tree.process_frame
	return failures


func _check_despawn(tree: SceneTree, area: Area) -> Array[String]:
	var failures: Array[String] = []
	var pickup := _spawn(area, area.player.global_position + Vector2(-60, 70))
	pickup.setup_item(_item(&"despawn_item"), 1)
	pickup.despawn_seconds = 0.05
	await tree.create_timer(0.25).timeout
	if is_instance_valid(pickup):
		failures.append("uncollected pickups must despawn")
		pickup.queue_free()
	return failures


func _check_walk_over(tree: SceneTree, area: Area) -> Array[String]:
	var failures: Array[String] = []
	var player := area.player
	var item := _item(&"walk_over_item")
	var pickup := _spawn(area, player.global_position + Vector2(0, 70))
	pickup.setup_item(item, 1)
	var before := player.inventory.count_of(item)

	await tree.physics_frame
	await tree.physics_frame
	await tree.physics_frame
	if player.inventory.count_of(item) != before + 1:
		failures.append("walking over a pickup must collect it automatically")
	await tree.process_frame
	return failures


func _spawn(area: Area, position: Vector2) -> LootPickup:
	var pickup := (load(PICKUP_SCENE) as PackedScene).instantiate() as LootPickup
	area.add_child(pickup)
	pickup.global_position = position
	return pickup


func _item(id: StringName) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.display_name = str(id)
	item.max_stack = 99
	return item
