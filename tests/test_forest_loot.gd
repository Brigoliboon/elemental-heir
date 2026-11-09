extends RefCounted
## Validates the Verdant Forest drop tables and the first loot items.

const BOARLET_DATA := "res://resources/entities/boarlet.tres"
const GOBLIN_DATA := "res://resources/entities/goblin.tres"
const ROOTBOUND_DATA := "res://resources/entities/rootbound.tres"
const GUARDIAN_DATA := "res://resources/entities/guardian.tres"
const POTION_PATH := "res://resources/items/consumables/small_health_potion.tres"
const HEARTWOOD_PATH := "res://resources/items/materials/heartwood.tres"
const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const PICKUP_SCENE := "res://scenes/world/loot_pickup.tscn"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_check_items())
	failures.append_array(_check_tables())
	failures.append_array(_check_boss_guarantee())
	failures.append_array(await _check_potion_pickup_and_use(tree))
	return failures


func _check_items() -> Array[String]:
	var failures: Array[String] = []
	var potion := load(POTION_PATH) as ConsumableData
	if potion == null:
		failures.append("%s did not load as ConsumableData" % POTION_PATH)
	else:
		if potion.heal_amount <= 0:
			failures.append("the small health potion must heal")
		if potion.max_stack <= 1:
			failures.append("the small health potion must stack")
		if potion.item_type != ItemData.ItemType.CONSUMABLE:
			failures.append("the small health potion must be a consumable")
		if potion.icon == null:
			failures.append("the small health potion needs an icon for the bag and pickups")

	var heartwood := load(HEARTWOOD_PATH) as ItemData
	if heartwood == null:
		failures.append("%s did not load as ItemData" % HEARTWOOD_PATH)
	elif int(heartwood.rarity) < ItemData.Rarity.RARE:
		failures.append("heartwood must be rare or better so rarity bonuses can pick it")
	return failures


func _check_tables() -> Array[String]:
	var failures: Array[String] = []
	var boarlet := load(BOARLET_DATA) as MonsterData
	var goblin := load(GOBLIN_DATA) as MonsterData
	var rootbound := load(ROOTBOUND_DATA) as MonsterData
	var guardian := load(GUARDIAN_DATA) as MonsterData
	if boarlet == null or goblin == null or rootbound == null or guardian == null:
		failures.append("the forest enemy data resources must all load")
		return failures

	if not _has_entry(boarlet, &"boar_hide"):
		failures.append("boarlets must drop boar hide")
	if not _has_entry(boarlet, &"small_health_potion"):
		failures.append("boarlets must be able to drop a small health potion")
	if not _has_entry(rootbound, &"root_fiber"):
		failures.append("rootbound enemies must drop root fiber")
	if not _has_entry(rootbound, &"small_health_potion"):
		failures.append("rootbound enemies must be able to drop a small health potion")
	if not _has_entry(goblin, &"small_health_potion"):
		failures.append("goblins must be able to drop a small health potion")
	if not _has_entry(guardian, &"heartwood"):
		failures.append("the Hollowhart Guardian must drop heartwood")

	if boarlet.gold_max <= 0:
		failures.append("boarlets must drop gold")
	if goblin.gold_max <= 0:
		failures.append("goblins must drop gold")
	if guardian.gold_min < 50:
		failures.append("the boss must drop a boss-sized gold pile")

	if not guardian.is_boss:
		failures.append("the Hollowhart Guardian must be flagged as a boss")
	if _has_entry(guardian, &"knight_armour"):
		failures.append("knight armour is on hold and must not be in the boss table yet")
	return failures


func _check_boss_guarantee() -> Array[String]:
	var failures: Array[String] = []
	var guardian := load(GUARDIAN_DATA) as MonsterData
	if guardian == null:
		return failures
	for seed_value in 25:
		var roller := LootRoller.new(seed_value)
		roller.verbose = false
		var drops := roller.roll(guardian.loot_table, EnemyData.Rarity.NORMAL)
		if not _drop_has(drops, &"heartwood"):
			failures.append("the boss must always drop heartwood (seed %d)" % seed_value)
			break
	return failures


func _check_potion_pickup_and_use(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load" % AREA_SCENE)
		return failures
	var area := packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame
	var player := area.player
	var potion := load(POTION_PATH) as ConsumableData
	if player == null or potion == null:
		failures.append("the potion test needs a player and a potion")
		area.queue_free()
		await tree.process_frame
		return failures

	var pickup := (load(PICKUP_SCENE) as PackedScene).instantiate() as LootPickup
	area.add_child(pickup)
	pickup.global_position = player.global_position + Vector2(80, 70)
	pickup.setup_item(potion, 1)
	if not pickup.collect_by(player):
		failures.append("a potion pickup must collect into the bag")
	if player.inventory.count_of(potion) != 1:
		failures.append("the collected potion must be in the bag")

	player.health.reset()
	if player.use_item(potion):
		failures.append("a potion must not be spent at full health")
	if player.inventory.count_of(potion) != 1:
		failures.append("a rejected potion must stay in the bag")

	player.set_health(10)
	var before := player.current_health
	if not player.use_item(potion):
		failures.append("a potion must be usable when hurt")
	if player.current_health <= before:
		failures.append("using a potion must heal the player")
	if player.inventory.count_of(potion) != 0:
		failures.append("using a potion must consume one from the bag")

	area.queue_free()
	await tree.process_frame
	return failures


func _has_entry(data: MonsterData, id: StringName) -> bool:
	for entry in data.loot_table:
		if entry != null and entry.item != null and entry.item.id == id:
			return true
	return false


func _drop_has(drops: Array[Dictionary], id: StringName) -> bool:
	for drop in drops:
		var item := drop["item"] as ItemData
		if item != null and item.id == id:
			return true
	return false
