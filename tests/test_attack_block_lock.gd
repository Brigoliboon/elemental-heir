extends RefCounted
## Regression: raising the guard mid-swing used to abort the attack animation, so
## the combo never received `animation_finished`. `is_attacking()` then stayed
## true forever and `Character.move_2d()` ignored every input, freezing the
## character after switching between attack and block on the touch HUD.

const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const STEP := 1.0 / 60.0


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the attack/block lock test" % AREA_SCENE)
		return failures

	var area := packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame

	var player := area.player
	if player == null:
		failures.append("the area needs a player for the attack/block lock test")
		area.queue_free()
		await tree.process_frame
		return failures

	# Attack, then raise the guard while the swing is still playing.
	player.attack()
	await tree.process_frame
	if not player.is_attacking():
		failures.append("the attack must start")

	player.block(true)
	await tree.process_frame
	if not player.is_blocking():
		failures.append("the guard must come up when tapped during a swing")
	if player.is_attacking():
		failures.append("raising the guard must end the interrupted swing")

	player.block(false)
	await tree.process_frame
	if player.is_blocking():
		failures.append("releasing the guard must clear it")

	failures.append_array(await _expect_can_move(tree, player, "after switching from attack to block"))

	# The guard must still hold the character in place while it is up.
	player.block(true)
	await tree.process_frame
	var held := player.position
	for i in 10:
		player.move_2d(Vector2.RIGHT, STEP)
		await tree.process_frame
	if player.position.x > held.x + 0.5:
		failures.append("the guard must keep the character in place while held")
	player.block(false)
	await tree.process_frame

	# Guarding must not break attacking afterwards, and a finished combo must
	# hand movement back.
	player.attack()
	await tree.process_frame
	if not player.is_attacking():
		failures.append("the player must still be able to attack after blocking")
	if not await _wait_until_idle(tree, player):
		failures.append("the attack must finish instead of latching")
	failures.append_array(await _expect_can_move(tree, player, "after a completed attack"))

	# Any animation that replaces a swing from outside the combo must not latch it.
	player.attack()
	await tree.process_frame
	player.anim_player.play("idle")
	await tree.process_frame
	if player.is_attacking():
		failures.append("an interrupted swing must not leave the combo latched")
	failures.append_array(await _expect_can_move(tree, player, "after an external animation interrupt"))

	area.queue_free()
	await tree.process_frame
	return failures


## Fails unless the character actually walks right over the next few frames.
func _expect_can_move(tree: SceneTree, player: Character, context: String) -> Array[String]:
	var failures: Array[String] = []
	var before := player.position
	for i in 20:
		player.move_2d(Vector2.RIGHT, STEP)
		await tree.process_frame
	if player.position.x <= before.x + 0.5:
		failures.append("the character must move %s (animation=%s, blocking=%s, attacking=%s)" % [
			context,
			player.anim_player.current_animation,
			player.is_blocking(),
			player.is_attacking(),
		])
	return failures


## Waits for the current swing to finish, returning false if it never does.
func _wait_until_idle(tree: SceneTree, player: Character, max_frames := 240) -> bool:
	for _i in max_frames:
		if not player.is_attacking():
			return true
		await tree.process_frame
	return false
