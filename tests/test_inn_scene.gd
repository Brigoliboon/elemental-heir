extends RefCounted
## Guards the inn scene and both halves of its village doorway.

const INN_SCENE := "res://scenes/areas/forest/forest_inn.tscn"
const INN_BACKGROUND := "res://assets/backgrounds/forest/forest_inn/forest_inn.png"
const VILLAGE_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var inn_packed := load(INN_SCENE) as PackedScene
	if inn_packed == null:
		failures.append("%s did not load" % INN_SCENE)
		return failures

	var inn := inn_packed.instantiate() as Area
	tree.root.add_child(inn)
	await tree.process_frame
	await tree.process_frame
	failures.append_array(_check_inn(inn))
	inn.queue_free()
	await tree.process_frame

	var village_packed := load(VILLAGE_SCENE) as PackedScene
	if village_packed == null:
		failures.append("%s did not load for the inn doorway test" % VILLAGE_SCENE)
		return failures

	var village := village_packed.instantiate() as Area
	tree.root.add_child(village)
	await tree.process_frame

	var entrance := village.get_node_or_null("InnEntrance") as Area2D
	if entrance == null:
		failures.append("the village needs an InnEntrance")
	elif entrance.get("target_scene") != INN_SCENE:
		failures.append("the village InnEntrance must point at %s" % INN_SCENE)

	village.queue_free()
	await tree.process_frame
	return failures


func _check_inn(inn: Area) -> Array[String]:
	var failures: Array[String] = []

	if inn.area_name != "Forest - Inn":
		failures.append("the inn must use its own area name")
	if inn.background_texture == null:
		failures.append("the inn needs a background texture")
	elif inn.background_texture.resource_path != INN_BACKGROUND:
		failures.append("the inn must use %s" % INN_BACKGROUND)
	if inn.background.texture != inn.background_texture:
		failures.append("the inn Background sprite must use the inn texture")
	if inn.ground_near_y <= inn.ground_far_y:
		failures.append("the inn needs a walkable floor band")
	if not inn.player.position.is_finite():
		failures.append("the inn player position must be finite")
	if inn.is_blocked(Vector2(inn.player.position.x, inn.player.get_feet_y())):
		failures.append("the inn spawn must not be inside an obstacle")

	var transition := inn.get_node_or_null("BackgroundProps/SceneTransition") as Area2D
	if transition == null:
		failures.append("the inn needs a SceneTransition back to the village")
	elif transition.get("target_scene") != VILLAGE_SCENE:
		failures.append("the inn exit must point at %s" % VILLAGE_SCENE)

	return failures
