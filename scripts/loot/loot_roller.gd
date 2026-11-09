class_name LootRoller
extends RefCounted
## Rolls a monster loot table into a list of drops.
##
## Rolls are deterministic for a given seed. Every roll is written to
## [member log_lines] so QA can see exactly why a drop appeared (or did not).
## The debug log is printed in debug builds; release builds stay quiet.
##
## Rarity bonuses (see DESIGN_ROADMAP §5):
## - Normal: one pass over the table.
## - Epic: one extra pass, so every entry gets a second chance.
## - Legendary: two passes plus a guaranteed RARE-or-better entry.
## - Anomaly: two passes plus a guaranteed [member LootEntry.unique] entry.

const RARE_ITEM_RARITY := ItemData.Rarity.RARE

var rng: RandomNumberGenerator
var log_lines: Array[String] = []
## Set false to keep [member log_lines] without printing them.
var verbose := true
var source_name := ""


func _init(seed_value: int = -1) -> void:
	rng = RandomNumberGenerator.new()
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value


## Rolls `table` and returns drops as `{ "item": ItemData, "count": int }`.
## Duplicate items are merged so one enemy death never spawns two pickups of
## the same material.
func roll(table: Array, rarity: int = EnemyData.Rarity.NORMAL) -> Array[Dictionary]:
	log_lines.clear()
	var totals: Dictionary = {}
	var order: Array[ItemData] = []
	var passes := passes_for_rarity(rarity)

	for pass_index in passes:
		for raw in table:
			var entry := raw as LootEntry
			if entry == null or entry.item == null:
				continue
			if entry.validation_error() != "":
				_log("%s: skipping invalid entry" % _label(entry))
				continue
			var hit := rng.randf() < clampf(entry.drop_chance, 0.0, 1.0)
			if not hit:
				_log("pass %d: %s %.0f%% -> miss" % [
					pass_index + 1,
					_label(entry),
					entry.drop_chance * 100.0,
				])
				continue
			var count := entry.roll_count(rng)
			_append(totals, order, entry.item, count)
			_log("pass %d: %s %.0f%% -> %s x%d" % [
				pass_index + 1,
				_label(entry),
				entry.drop_chance * 100.0,
				entry.item.id,
				count,
			])

	if rarity == EnemyData.Rarity.LEGENDARY:
		_guaranteed_pick(table, totals, order, "legendary rare-or-better", _is_rare_or_better)
	elif rarity == EnemyData.Rarity.ANOMALY:
		_guaranteed_pick(table, totals, order, "anomaly unique", _is_unique)

	var drops: Array[Dictionary] = []
	for item in order:
		drops.append({"item": item, "count": int(totals[item])})
	if drops.is_empty():
		_log("result: nothing")
	else:
		_log("result: %s" % _describe(drops))
	return drops


## Rolls a gold amount in `[min_amount, max_amount]`. 0 when the range is empty.
func roll_gold(min_amount: int, max_amount: int) -> int:
	var low := maxi(0, min_amount)
	var high := maxi(low, max_amount)
	if high <= 0:
		return 0
	var amount := rng.randi_range(low, high)
	_log("gold: %d (%d-%d)" % [amount, low, high])
	return amount


static func passes_for_rarity(rarity: int) -> int:
	if rarity >= EnemyData.Rarity.EPIC:
		return 2
	return 1


func _guaranteed_pick(
	table: Array,
	totals: Dictionary,
	order: Array[ItemData],
	label: String,
	predicate: Callable,
) -> void:
	var eligible: Array[LootEntry] = []
	for raw in table:
		var entry := raw as LootEntry
		if entry == null or entry.item == null:
			continue
		if predicate.call(entry):
			eligible.append(entry)
	if eligible.is_empty():
		# No rare/unique entry configured: fall back to the normal table so the
		# bonus is never silently lost.
		for raw in table:
			var entry := raw as LootEntry
			if entry != null and entry.item != null:
				eligible.append(entry)
	if eligible.is_empty():
		_log("%s: no eligible entries" % label)
		return
	var picked := _weighted_pick(eligible)
	if picked == null:
		return
	var count := picked.roll_count(rng)
	_append(totals, order, picked.item, count)
	_log("%s: %s -> %s x%d" % [label, _label(picked), picked.item.id, count])


func _weighted_pick(entries: Array[LootEntry]) -> LootEntry:
	var total := 0.0
	for entry in entries:
		total += maxf(0.0, entry.weight)
	if total <= 0.0:
		return entries[0]
	var pick := rng.randf() * total
	for entry in entries:
		pick -= maxf(0.0, entry.weight)
		if pick <= 0.0:
			return entry
	return entries[-1]


func _append(totals: Dictionary, order: Array[ItemData], item: ItemData, count: int) -> void:
	if count <= 0:
		return
	if not totals.has(item):
		totals[item] = 0
		order.append(item)
	totals[item] = int(totals[item]) + count


func _is_rare_or_better(entry: LootEntry) -> bool:
	return entry.item != null and int(entry.item.rarity) >= RARE_ITEM_RARITY


func _is_unique(entry: LootEntry) -> bool:
	return entry.unique


func _label(entry: LootEntry) -> String:
	if entry == null or entry.item == null:
		return "<invalid>"
	return "%s(w=%.1f)" % [entry.item.id, entry.weight]


func _describe(drops: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for drop in drops:
		var item := drop["item"] as ItemData
		parts.append("%s x%d" % [item.id if item != null else "?", int(drop["count"])])
	return ", ".join(parts)


func _log(line: String) -> void:
	var full := "[loot] %s%s" % [
		"%s " % source_name if not source_name.is_empty() else "",
		line,
	]
	log_lines.append(full)
	if verbose and OS.is_debug_build():
		print(full)
