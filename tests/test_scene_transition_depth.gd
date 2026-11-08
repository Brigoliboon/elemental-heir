extends RefCounted
## Guards the depth gate on scene transitions: a doorway painted into the back
## wall must only fire at the far edge of the walkable band, while exits walked
## down into use the near edge. Also guards that interior exits put the player
## back at the doorway they used instead of the area's default spawn.

const VILLAGE_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const INN_SCENE := "res://scenes/areas/forest/forest_inn.tscn"
const GUILD_SCENE := "res://scenes/areas/forest/forest_guild.tscn"
const INN_DOOR := "InnEntrance/Inn"
const GUILD_DOOR := "GuildEntrance/Guild"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var village_packed := load(VILLAGE_SCENE) as PackedScene
	if village_packed == null:
		failures.append("%s did not load for the transition depth test" % VILLAGE_SCENE)
		return failures

	var village := village_packed.instantiate() as Area
	tree.root.add_child(village)
	await tree.process_frame
	await tree.process_frame

	var guild := village.get_node_or_null("GuildEntrance") as Area2D
	if guild == null:
		failures.append("the village needs its GuildEntrance")
	elif not guild.has_method("is_player_in_depth"):
		failures.append("scene transitions must expose their depth check")
	else:
		if not is_equal_approx(float(guild.get("depth_ratio")), 0.0):
			failures.append("the guild door is in the back wall and must use the far edge")
		if float(guild.get("depth_tolerance")) <= 0.0:
			failures.append("the guild door needs a depth tolerance")
		if not is_equal_approx(guild.depth_anchor_y(), village.ground_far_y):
			failures.append("the guild doorway depth must match the far edge")

		var player := village.player
		_set_feet(player, village.ground_near_y)
		if guild.is_player_in_depth(player):
			failures.append("the guild door must not fire from the front of the square")
		_set_feet(player, guild.depth_anchor_y())
		if not guild.is_player_in_depth(player):
			failures.append("the guild door must fire when the feet reach its depth")

	var inn_x := _door_x(village, INN_DOOR)
	var guild_x := _door_x(village, GUILD_DOOR)
	if is_nan(inn_x):
		failures.append("the village needs an InnEntrance collision shape")
	if is_nan(guild_x):
		failures.append("the village needs a GuildEntrance collision shape")

	village.queue_free()
	await tree.process_frame

	var inn_packed := load(INN_SCENE) as PackedScene
	if inn_packed == null:
		failures.append("%s did not load for the transition depth test" % INN_SCENE)
		return failures

	var inn := inn_packed.instantiate() as Area
	tree.root.add_child(inn)
	await tree.process_frame
	await tree.process_frame

	var exit := inn.get_node_or_null("BackgroundProps/SceneTransition") as Area2D
	if exit == null:
		failures.append("the inn needs its exit transition")
	elif exit.has_method("is_player_in_depth"):
		if not is_equal_approx(float(exit.get("depth_ratio")), 1.0):
			failures.append("the inn exit must use the near edge of the floor")
		if not is_equal_approx(exit.depth_anchor_y(), inn.ground_near_y):
			failures.append("the inn exit depth must match the near edge")
		_set_feet(inn.player, inn.ground_far_y)
		if exit.is_player_in_depth(inn.player):
			failures.append("the inn exit must not fire from the back of the room")
		_set_feet(inn.player, inn.ground_near_y)
		if not exit.is_player_in_depth(inn.player):
			failures.append("the inn exit must fire at the front of the room")
		_check_exit_spawn(exit, INN_DOOR, "the inn", failures)

	inn.queue_free()
	await tree.process_frame

	var guild_packed := load(GUILD_SCENE) as PackedScene
	if guild_packed == null:
		failures.append("%s did not load for the transition depth test" % GUILD_SCENE)
		return failures

	var guild_hall := guild_packed.instantiate() as Area
	tree.root.add_child(guild_hall)
	await tree.process_frame
	await tree.process_frame

	var hall_exit := guild_hall.get_node_or_null("BackgroundProps/SceneTransition") as Area2D
	if hall_exit == null:
		failures.append("the guild needs its exit transition")
	else:
		_check_exit_spawn(hall_exit, GUILD_DOOR, "the guild", failures)

	guild_hall.queue_free()
	await tree.process_frame

	# Walking out of the inn should spawn at the inn doorway, not at the
	# village's default spawn point (which sits by the guild door).
	if not is_nan(inn_x):
		Area.set_entry_spawn(INN_DOOR)
		var spawned := village_packed.instantiate() as Area
		tree.root.add_child(spawned)
		await tree.process_frame
		await tree.process_frame
		if absf(spawned.player.position.x - inn_x) > 0.01:
			failures.append("leaving a building must spawn at its own doorway")
		if absf(spawned.depth_ratio() - spawned.spawn_depth) > 0.02:
			failures.append("a doorway spawn must keep the area's default depth")
		spawned.queue_free()
		await tree.process_frame

	# The override is one-shot: after it is used, the area's default spawn wins.
	if not is_nan(inn_x):
		Area.set_entry_spawn(INN_DOOR)
		var consumed := village_packed.instantiate() as Area
		tree.root.add_child(consumed)
		await tree.process_frame
		await tree.process_frame
		if not Area._entry_spawn_path.is_empty():
			failures.append("the doorway spawn override must be consumed when used")
		consumed.queue_free()
		await tree.process_frame

	return failures


## World x of a doorway shape inside the village, or NAN when it is missing.
func _door_x(village: Area, path: String) -> float:
	var shape := village.get_node_or_null(path) as CollisionShape2D
	if shape == null:
		return NAN
	return shape.global_position.x


func _check_exit_spawn(exit: Area2D, expected_path: String, label: String, failures: Array[String]) -> void:
	var path := str(exit.get("entry_spawn_path"))
	if path.is_empty():
		failures.append("%s exit must name the doorway it returns to" % label)
	elif path != expected_path:
		failures.append("%s exit must spawn at its own doorway, not another one" % label)


func _set_feet(player: Character, feet_y: float) -> void:
	player.global_position.y = feet_y - Character.FEET_OFFSET_LOCAL * player.render_scale
