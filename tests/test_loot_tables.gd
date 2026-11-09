extends RefCounted
## Validates loot tables: per-entry drop chances, stack sizes, rarity bonuses,
## seeded reproducibility, the debug log, and spawning drops on death.

const BOARLET_DATA := "res://resources/entities/boarlet.tres"
const BOARLET_SCENE := "res://entities/enemies/boarlet.tscn"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_check_entry_validation())
	failures.append_array(_check_drop_chance())
	failures.append_array(_check_stack_range())
	failures.append_array(_check_rarity_passes())
	failures.append_array(_check_legendary_and_anomaly())
	failures.append_array(_check_reproducible())
	failures.append_array(_check_debug_log())
	failures.append_array(await _check_death_spawns_drops(tree))
	return failures


func _check_entry_validation() -> Array[String]:
	var failures: Array[String] = []
	var item := _item(&"hide")
	var entry := _entry(item, 1.0)
	if entry.validation_error() != "":
		failures.append("a normal loot entry must be valid")

	var missing := LootEntry.new()
	if missing.validation_error().is_empty():
		failures.append("a loot entry without an item must be invalid")

	var inverted := _entry(item, 1.0, 5, 2)
	if inverted.validation_error().is_empty():
		failures.append("a loot entry with max below min must be invalid")
	return failures


func _check_drop_chance() -> Array[String]:
	var failures: Array[String] = []
	var always := _entry(_item(&"always"), 1.0)
	var never := _entry(_item(&"never"), 0.0)

	var roller := LootRoller.new(1)
	roller.verbose = false
	var drops := roller.roll([always], EnemyData.Rarity.NORMAL)
	if drops.size() != 1 or (drops[0]["item"] as ItemData).id != &"always":
		failures.append("a 100% entry must drop")

	drops = roller.roll([never], EnemyData.Rarity.NORMAL)
	if not drops.is_empty():
		failures.append("a 0% entry must never drop")

	# Design-facing contract: 40% must read as roughly 40%, not as a weight that
	# gets normalised against the rest of the table. Fixed seeds keep this stable.
	var forty := _entry(_item(&"forty"), 0.4)
	var hits := 0
	var trials := 400
	for seed_value in trials:
		var sample := LootRoller.new(seed_value)
		sample.verbose = false
		if not sample.roll([forty], EnemyData.Rarity.NORMAL).is_empty():
			hits += 1
	var rate := float(hits) / float(trials)
	if rate < 0.33 or rate > 0.47:
		failures.append("a 40%% drop chance must land near 40%%, got %.0f%%" % [rate * 100.0])
	return failures


func _check_stack_range() -> Array[String]:
	var failures: Array[String] = []
	var entry := _entry(_item(&"stack"), 1.0, 2, 4)
	for seed_value in 12:
		var roller := LootRoller.new(seed_value)
		roller.verbose = false
		var drops := roller.roll([entry], EnemyData.Rarity.NORMAL)
		if drops.size() != 1:
			failures.append("the 100% stack entry must drop every time")
			continue
		var count := int(drops[0]["count"])
		if count < 2 or count > 4:
			failures.append("stack size %d must stay inside 2..4" % count)
	return failures


func _check_rarity_passes() -> Array[String]:
	var failures: Array[String] = []
	if LootRoller.passes_for_rarity(EnemyData.Rarity.NORMAL) != 1:
		failures.append("normal enemies must roll the table once")
	if LootRoller.passes_for_rarity(EnemyData.Rarity.EPIC) != 2:
		failures.append("epic enemies must get one extra table pass")
	if LootRoller.passes_for_rarity(EnemyData.Rarity.LEGENDARY) != 2:
		failures.append("legendary enemies must keep two table passes")

	var roller := LootRoller.new(3)
	roller.verbose = false
	var entry := _entry(_item(&"hide"), 1.0, 1, 1)
	var normal := roller.roll([entry], EnemyData.Rarity.NORMAL)
	var epic := roller.roll([entry], EnemyData.Rarity.EPIC)
	if int(normal[0]["count"]) != 1:
		failures.append("normal enemies must not double a guaranteed drop")
	if int(epic[0]["count"]) != 2:
		failures.append("epic enemies must get a second copy from the extra pass")
	return failures


func _check_legendary_and_anomaly() -> Array[String]:
	var failures: Array[String] = []
	var common := _entry(_item(&"common", ItemData.Rarity.COMMON), 0.0)
	var rare := _entry(_item(&"rare", ItemData.Rarity.RARE), 0.0)
	var unique := _entry(_item(&"unique_item", ItemData.Rarity.LEGENDARY), 0.0, 1, 1, 1.0, true)
	var filler := _entry(_item(&"filler", ItemData.Rarity.COMMON), 0.0)

	var roller := LootRoller.new(11)
	roller.verbose = false
	var drops := roller.roll([common, rare], EnemyData.Rarity.LEGENDARY)
	if not _has_item(drops, &"rare"):
		failures.append("legendary enemies must guarantee a rare-or-better drop")

	drops = roller.roll([filler, unique], EnemyData.Rarity.ANOMALY)
	if not _has_item(drops, &"unique_item"):
		failures.append("anomaly enemies must guarantee the unique entry")

	drops = roller.roll([common], EnemyData.Rarity.LEGENDARY)
	if not _has_item(drops, &"common"):
		failures.append("legendary guarantee must fall back when no rare entry exists")
	return failures


func _check_reproducible() -> Array[String]:
	var failures: Array[String] = []
	var table := [
		_entry(_item(&"a"), 0.5, 1, 3),
		_entry(_item(&"b"), 0.25, 1, 2),
		_entry(_item(&"c"), 0.75, 1, 1),
	]
	var first := LootRoller.new(4242)
	first.verbose = false
	var second := LootRoller.new(4242)
	second.verbose = false
	if not _same_drops(
		first.roll(table, EnemyData.Rarity.NORMAL),
		second.roll(table, EnemyData.Rarity.NORMAL)
	):
		failures.append("the same seed must produce the same drops")
	return failures


func _check_debug_log() -> Array[String]:
	var failures: Array[String] = []
	var roller := LootRoller.new(7)
	roller.verbose = false
	roller.source_name = "Boarlet"
	roller.roll([_entry(_item(&"hide"), 1.0)], EnemyData.Rarity.NORMAL)
	if roller.log_lines.is_empty():
		failures.append("loot rolls must keep a debug log")
	else:
		var joined := "\n".join(roller.log_lines)
		if not joined.contains("Boarlet"):
			failures.append("the loot log must name the enemy")
		if not joined.contains("result:"):
			failures.append("the loot log must include the roll result")
	return failures


func _check_death_spawns_drops(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var data := (load(BOARLET_DATA) as MonsterData).duplicate() as MonsterData
	if data == null:
		failures.append("%s did not load" % BOARLET_DATA)
		return failures
	data.loot_table = [_entry(_item(&"test_hide"), 1.0, 1, 1)]
	data.gold_min = 5
	data.gold_max = 5

	var container := Node2D.new()
	tree.root.add_child(container)
	var monster := _spawn_monster(container, data, 99)
	if monster == null:
		failures.append("the boarlet scene did not instantiate")
		container.queue_free()
		await tree.process_frame
		return failures

	var first_roll := monster.roll_loot()
	var second_roll := monster.roll_loot()
	if not _same_drops(first_roll, second_roll):
		failures.append("a monster must reproduce its loot for a fixed loot seed")

	monster.take_damage(999999)
	await tree.process_frame
	await tree.process_frame

	var items_found := 0
	var gold_found := 0
	for child in container.get_children():
		var pickup := child as LootPickup
		if pickup == null:
			continue
		if pickup.gold > 0:
			gold_found += pickup.gold
			continue
		if pickup.item != null and pickup.item.id == &"test_hide":
			items_found += pickup.count
	if items_found != 1:
		failures.append("killing a monster with a loot table must spawn its drop (got %d)" % items_found)
	if gold_found != 5:
		failures.append("killing a monster with a gold range must spawn that gold (got %d)" % gold_found)

	container.queue_free()
	await tree.process_frame
	return failures


func _spawn_monster(parent: Node, data: MonsterData, seed_value: int) -> Monster:
	var packed := load(BOARLET_SCENE) as PackedScene
	if packed == null:
		return null
	var monster := packed.instantiate() as Monster
	if monster == null:
		return null
	monster.config = data
	monster.loot_seed = seed_value
	monster.log_loot = false
	parent.add_child(monster)
	monster.global_position = Vector2(800, 500)
	return monster


func _item(id: StringName, rarity := ItemData.Rarity.COMMON) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.display_name = str(id)
	item.rarity = rarity
	return item


func _entry(
	item: ItemData,
	chance: float,
	min_count := 1,
	max_count := 1,
	weight := 1.0,
	unique := false,
) -> LootEntry:
	var entry := LootEntry.new()
	entry.item = item
	entry.drop_chance = chance
	entry.min_count = min_count
	entry.max_count = max_count
	entry.weight = weight
	entry.unique = unique
	return entry


func _has_item(drops: Array[Dictionary], id: StringName) -> bool:
	for drop in drops:
		var item := drop["item"] as ItemData
		if item != null and item.id == id:
			return true
	return false


func _same_drops(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var item_a := a[i]["item"] as ItemData
		var item_b := b[i]["item"] as ItemData
		if item_a != item_b or int(a[i]["count"]) != int(b[i]["count"]):
			return false
	return true
