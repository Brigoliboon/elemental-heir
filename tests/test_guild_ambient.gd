extends RefCounted
## The guild needs a looping fire crackle under the background music.

const GUILD_SCENE := "res://scenes/areas/forest/forest_guild.tscn"
const FIRE_STREAM := "res://assets/audio/sfx/environment/fire-crackling.mp3"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load(GUILD_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the guild ambience test" % GUILD_SCENE)
		return failures

	var guild := packed.instantiate() as Area
	tree.root.add_child(guild)
	await tree.process_frame
	await tree.process_frame

	var fire := guild.get_node_or_null("FireCrackling") as AudioStreamPlayer
	if fire == null:
		failures.append("the guild needs a FireCrackling AudioStreamPlayer")
	elif fire.stream == null:
		failures.append("the fire ambience must have a stream")
	elif fire.stream.resource_path != FIRE_STREAM:
		failures.append("the fire ambience must use %s" % FIRE_STREAM)
	else:
		if not bool(fire.stream.get("loop")):
			failures.append("the fire ambience must loop")
		if not fire.autoplay:
			failures.append("the fire ambience must autoplay")
		if fire.volume_db > 0.0:
			failures.append("the fire ambience must sit under the music")

	guild.queue_free()
	await tree.process_frame
	return failures
