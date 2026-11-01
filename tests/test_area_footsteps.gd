extends RefCounted
## Scenes select a surface on the root Area; the area must hand that set to the
## player so walking actually produces footsteps.

const GRASS := "res://resources/audio/footsteps_grass.tres"
const SCENES := [
	"res://scenes/areas/forest/forest_village_square.tscn",
	"res://scenes/areas/forest/forest_fight.tscn",
]


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	for scene_path in SCENES:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			failures.append("%s did not load for the footstep wiring test" % scene_path)
			continue

		var area := packed.instantiate() as Area
		tree.root.add_child(area)
		await tree.process_frame
		await tree.process_frame

		var footsteps := area.get("footsteps") as FootstepSet
		if footsteps == null:
			failures.append("%s must expose its footstep set" % scene_path)
		elif footsteps.resource_path != GRASS:
			failures.append("%s must use %s" % [scene_path, GRASS])
		elif area.player == null or area.player.sfx == null:
			failures.append("%s must have a player voice" % scene_path)
		elif area.player.sfx.footsteps != footsteps:
			failures.append("%s must hand its footstep set to the player" % scene_path)

		area.queue_free()
		await tree.process_frame

	return failures
