extends RefCounted
## Validates the item/equipment resources and the default warrior gear.


const SWORD_PATH := "res://resources/items/weapons/default_sword.tres"
const BUCKLER_PATH := "res://resources/items/weapons/default_buckler.tres"


func run(_tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var sword := load(SWORD_PATH) as EquipmentData
	var buckler := load(BUCKLER_PATH) as EquipmentData
	if sword == null:
		failures.append("default_sword.tres did not load as EquipmentData")
	if buckler == null:
		failures.append("default_buckler.tres did not load as EquipmentData")
	if sword == null or buckler == null:
		return failures

	_expect_identity(failures, sword, &"default_sword", "Iron Sword")
	_expect_identity(failures, buckler, &"default_buckler", "Wooden Buckler")

	if sword.item_group != &"sword" or sword.equip_slot != &"primary":
		failures.append("the default sword must be a primary sword")
	if sword.weapon_anim_set != &"sword":
		failures.append("the default sword must use the sword animation set")
	if buckler.item_group != &"shield" or buckler.equip_slot != &"secondary":
		failures.append("the default buckler must be a secondary shield")

	if sword.icon == null or buckler.icon == null:
		failures.append("default equipment must keep its sprite icon")
	if sword.description.is_empty() or buckler.description.is_empty():
		failures.append("default equipment must have a description")
	if sword.max_stack != 1 or buckler.max_stack != 1:
		failures.append("equipment must not stack")

	if not sword.can_be_used_by(CharacterData.CharacterRole.WARRIOR):
		failures.append("the default sword must be usable by a warrior")
	if sword.can_be_used_by(CharacterData.CharacterRole.MAGE):
		failures.append("the default sword must reject a mage")

	var sword_attack := _modifier(sword, Stats.ATTACK)
	if sword_attack == null or not is_equal_approx(sword_attack.flat, 6.0):
		failures.append("the default sword must grant +6 attack")
	var sword_crit := _modifier(sword, Stats.CRIT_RATE)
	if sword_crit == null or not is_equal_approx(sword_crit.flat, 0.02):
		failures.append("the default sword must grant +2% crit rate")

	var buckler_defence := _modifier(buckler, Stats.DEFENCE)
	if buckler_defence == null or not is_equal_approx(buckler_defence.flat, 4.0):
		failures.append("the default buckler must grant +4 defence")
	var buckler_health := _modifier(buckler, Stats.MAX_HEALTH)
	if buckler_health == null or not is_equal_approx(buckler_health.flat, 10.0):
		failures.append("the default buckler must grant +10 max health")

	return failures


func _expect_identity(
	failures: Array[String],
	item: EquipmentData,
	id: StringName,
	display_name: String,
) -> void:
	if item.id != id:
		failures.append("%s must keep id %s" % [display_name, id])
	if item.display_name != display_name:
		failures.append("%s must keep its display name" % id)
	if item.item_type != ItemData.ItemType.WEAPON:
		failures.append("%s must be a weapon item" % id)
	if item.rarity != ItemData.Rarity.COMMON:
		failures.append("%s must start common rarity" % id)
	if item.class_restriction != [CharacterData.CharacterRole.WARRIOR]:
		failures.append("%s must be restricted to the warrior class" % id)


func _modifier(item: EquipmentData, stat: StringName) -> StatModifier:
	for modifier in item.stat_modifiers:
		if modifier != null and modifier.stat == stat:
			return modifier
	return null
