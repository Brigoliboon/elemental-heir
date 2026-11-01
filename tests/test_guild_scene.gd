extends RefCounted
## Guards the guild scene against stale import-cache texture references that
## work in the editor but disappear from exported/mobile builds.


const GUILD_SCENE := "res://scenes/areas/forest/forest_guild.tscn"
const GUILD_BACKGROUND_PATH := "res://assets/backgrounds/forest/forest_guild/forest_guild_interior.png"
const SIZES := [Vector2i(1920, 1080), Vector2i(2400, 1080), Vector2i(1280, 720)]


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var previous_size := tree.root.size

	var packed := load(GUILD_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load" % GUILD_SCENE)
		return failures

	for size in SIZES:
		tree.root.size = size
		await tree.process_frame

		var guild := packed.instantiate() as Area
		tree.root.add_child(guild)
		await tree.process_frame
		await tree.process_frame

		failures.append_array(_check_guild(guild, size))

		guild.queue_free()
		await tree.process_frame

	tree.root.size = previous_size
	await tree.process_frame
	return failures


func _check_guild(guild: Area, view: Vector2i) -> Array[String]:
	var failures: Array[String] = []

	if guild.background_texture == null:
		failures.append("the guild must have a background texture")
	else:
		var path := guild.background_texture.resource_path
		if path.contains(".godot/imported"):
			failures.append("the guild background must not reference the import cache")
		elif path != GUILD_BACKGROUND_PATH:
			failures.append("the guild background must use %s" % GUILD_BACKGROUND_PATH)
		var texture_size := guild.background_texture.get_size()
		if texture_size.x <= 0.0 or texture_size.y <= 0.0:
			failures.append("the guild background texture must have a valid size")

	if guild.background.texture != guild.background_texture:
		failures.append("the guild Background sprite must use the guild background texture")
	if guild.area_label.text != "Forest - Guild":
		failures.append("the guild area label must show its area name")

	if guild.player == null:
		failures.append("the guild must have a player")
	else:
		if guild.player.config == null:
			failures.append("the guild player must keep its character data")
		elif guild.player.rig == null or guild.player.rig.bones.is_empty():
			failures.append("the guild player rig must build")
		if not guild.player.position.is_finite():
			failures.append("the guild player position must be finite")
		if not guild.player.is_visible_in_tree():
			failures.append("the guild player must be visible")
		var feet := Vector2(guild.player.position.x, guild.player.get_feet_y())
		if guild.is_blocked(feet):
			failures.append("the guild spawn must not be inside a collision block at %s" % view)

	return failures
