extends RefCounted
## Guards the inherited playable scenes against stale data overrides. A missing or
## null CharacterData/EnemyData leaves entities invisible and was the cause of the
## 'base_scale' on Nil crash.

const SCENES := [
	"res://scenes/areas/forest/forest_village_square.tscn",
	"res://scenes/areas/forest/forest_entrance.tscn",
	"res://scenes/areas/forest/forest_fight.tscn",
]


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	for path in SCENES:
		var packed := load(path) as PackedScene
		if packed == null:
			failures.append("%s did not load" % path)
			continue

		var scene := packed.instantiate()
		tree.root.add_child(scene)
		await tree.process_frame

		var player := scene.get_node_or_null("Player") as Character
		if player == null:
			failures.append("%s has no Character player" % path)
		elif player.config == null:
			failures.append("%s Player.config is null" % path)
		elif player.rig == null or player.rig.bones.is_empty():
			failures.append("%s player rig did not build" % path)

		var handler := scene.get_node_or_null("SpawnHandler") as SpawnHandler
		if handler == null:
			failures.append("%s has no SpawnHandler" % path)
		elif scene.spawn_data != null and handler.area_id.is_empty():
			failures.append("%s did not start its spawn encounter" % path)

		scene.queue_free()
		await tree.process_frame

	return failures
