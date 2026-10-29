extends RefCounted
## Validates the shared y -> z-index depth mapping.


func run(tree: SceneTree) -> Array[String]:
	await tree.process_frame
	var failures: Array[String] = []

	var far := DepthSort.z_for_y(300.0)
	var near := DepthSort.z_for_y(900.0)
	if far >= near:
		failures.append("higher on screen (smaller y) must get a lower z-index")
	if DepthSort.z_for_y(-10000.0) != DepthSort.MIN_Z_INDEX:
		failures.append("depth index must clamp to MIN_Z_INDEX")
	if DepthSort.z_for_y(10000.0) != DepthSort.MAX_Z_INDEX:
		failures.append("depth index must clamp to MAX_Z_INDEX")

	var item := Node2D.new()
	tree.root.add_child(item)
	DepthSort.apply(item, 640.0)
	if item.z_index != 640:
		failures.append("DepthSort.apply must assign the z-index")
	item.queue_free()
	await tree.process_frame
	return failures
