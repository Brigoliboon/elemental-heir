extends RefCounted
## Guards the floating damage numbers: both sides must show the damage that actually
## landed, the text must sit above the creature instead of on its body, it must rise
## and fade, and it must clean itself up.

const WARRIOR_SCENE := "res://entities/characters/warrior.tscn"
const MOB_SCENE := "res://entities/enemies/mob.tscn"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	await _check_player(tree, failures)
	await _check_mob(tree, failures)
	return failures


func _check_player(tree: SceneTree, failures: Array[String]) -> void:
	var packed := load(WARRIOR_SCENE) as PackedScene
	if packed == null:
		failures.append("warrior scene did not load for the damage number test")
		return
	var player := packed.instantiate()
	tree.root.add_child(player)
	await tree.physics_frame

	var before := _numbers(tree.root)
	var health_before: int = player.current_health
	player.take_damage(12)
	var dealt: int = health_before - player.current_health

	var numbers := _numbers(tree.root)
	if numbers.size() != before.size() + 1:
		failures.append("a player hit should spawn exactly one damage number (got %d)" % (numbers.size() - before.size()))
		_cleanup(player)
		await tree.physics_frame
		return

	var number: DamageNumber = numbers[-1]
	if number.label.text != str(dealt):
		failures.append("player damage number shows %s but %d damage landed" % [number.label.text, dealt])

	var anchor: Vector2 = player.damage_number_anchor()
	if number.global_position.distance_to(anchor) > 1.0:
		failures.append("player number must start at the character's head anchor")
	if number.global_position.y >= player.get_feet_y():
		failures.append("player number must sit above the feet, not on the ground")
	if number.z_index <= DepthSort.z_for_y(player.get_feet_y()):
		failures.append("player number must draw in front of the character")

	# It should rise over its lifetime, then free itself.
	var start_y := number.global_position.y
	for _frame in 15:
		await tree.physics_frame
	if is_instance_valid(number) and number.global_position.y >= start_y - 5.0:
		failures.append("damage number did not rise")

	for _frame in 60:
		await tree.physics_frame
	if is_instance_valid(number):
		failures.append("damage number must free itself after its lifetime")
		number.free()

	_cleanup(player)
	await tree.physics_frame


func _check_mob(tree: SceneTree, failures: Array[String]) -> void:
	var packed := load(MOB_SCENE) as PackedScene
	if packed == null:
		failures.append("mob scene did not load for the damage number test")
		return
	var mob := packed.instantiate()
	tree.root.add_child(mob)
	await tree.physics_frame

	var before := _numbers(tree.root)
	var health_before: int = mob.current_health
	mob.take_damage(9)
	var dealt: int = health_before - mob.current_health

	var numbers := _numbers(tree.root)
	if numbers.size() != before.size() + 1:
		failures.append("a mob hit should spawn exactly one damage number (got %d)" % (numbers.size() - before.size()))
		_cleanup(mob)
		await tree.physics_frame
		return

	var number: DamageNumber = numbers[-1]
	if number.label.text != str(dealt):
		failures.append("mob damage number shows %s but %d damage landed" % [number.label.text, dealt])
	if number.global_position.y >= mob.global_position.y:
		failures.append("mob number must start above the body, not at its center")

	number.free()
	_cleanup(mob)
	await tree.physics_frame


func _numbers(parent: Node) -> Array[DamageNumber]:
	var found: Array[DamageNumber] = []
	for child in parent.get_children():
		if child is DamageNumber:
			found.append(child)
	return found


func _cleanup(node: Node) -> void:
	if is_instance_valid(node):
		node.free()
