extends RefCounted
## Guards the guild scene against stale import-cache texture references that
## work in the editor but disappear from exported/mobile builds.


const GUILD_SCENE := "res://scenes/areas/forest/forest_guild.tscn"
const GUILD_BACKGROUND_PATH := "res://assets/backgrounds/forest/forest_guild/forest_guild_interior.png"
const LARA_SHEET_PATH := "res://assets/characters/npcs/Lara/animation/lara_idle/lara_idle_sheet.png"
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

	failures.append_array(_check_lara(guild))
	return failures


func _check_lara(guild: Area) -> Array[String]:
	var failures: Array[String] = []
	var lara := guild.get_node_or_null("BackgroundProps/Lara") as AnimatedSprite2D
	if lara == null:
		failures.append("the guild needs an AnimatedSprite2D named Lara")
		return failures

	if lara.sprite_frames == null:
		failures.append("Lara needs sprite frames")
		return failures
	if not lara.sprite_frames.has_animation("idle"):
		failures.append("Lara needs an idle animation")
		return failures
	if lara.sprite_frames.get_frame_count("idle") != 8:
		failures.append("Lara's idle animation must have 8 frames")
	if not lara.sprite_frames.get_animation_loop("idle"):
		failures.append("Lara's idle animation must loop")
	if not is_equal_approx(lara.sprite_frames.get_frame_duration("idle", 0), 0.5):
		failures.append("Lara's idle frames must keep their authored durations")
	if lara.animation != &"idle":
		failures.append("Lara must start on the idle animation")
	if not lara.is_playing():
		failures.append("Lara's idle animation must autoplay")

	for index in lara.sprite_frames.get_frame_count("idle"):
		var frame := lara.sprite_frames.get_frame_texture("idle", index) as AtlasTexture
		if frame == null:
			failures.append("Lara's idle frame %d must be an AtlasTexture" % index)
		elif frame.atlas == null or frame.atlas.resource_path != LARA_SHEET_PATH:
			failures.append("Lara's idle frame %d must use the native sheet" % index)

	return failures
