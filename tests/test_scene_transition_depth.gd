extends RefCounted
## Guards the depth gate on scene transitions: a doorway painted into the back
## wall must only fire at the far edge of the walkable band, while exits walked
## down into use the near edge.

const VILLAGE_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const INN_SCENE := "res://scenes/areas/forest/forest_inn.tscn"


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

	inn.queue_free()
	await tree.process_frame
	return failures


func _set_feet(player: Character, feet_y: float) -> void:
	player.global_position.y = feet_y - Character.FEET_OFFSET_LOCAL * player.render_scale
