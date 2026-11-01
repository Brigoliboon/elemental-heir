extends RefCounted
## Rotated HUD buttons have rectangular controls that overlap. Their click masks
## must follow the visible art so transparent corners do not steal taps.

const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const BUTTONS := [
	"HUD/UI/AttackButton",
	"HUD/UI/BlockButton",
	"HUD/UI/PassiveButton",
]


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the HUD click mask test" % AREA_SCENE)
		return failures

	var area := packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame
	await tree.process_frame

	var buttons: Array[TextureButton] = []
	for path in BUTTONS:
		var button := area.get_node_or_null(path) as TextureButton
		if button == null:
			failures.append("the HUD needs %s as a TextureButton" % path)
			continue
		buttons.append(button)
		failures.append_array(_check_mask(button, path))

	if buttons.size() == BUTTONS.size():
		failures.append_array(_check_no_overlapping_hits(buttons))

	area.queue_free()
	await tree.process_frame
	return failures


func _check_mask(button: TextureButton, path: String) -> Array[String]:
	var failures: Array[String] = []
	if button.texture_normal == null:
		failures.append("%s must have button art" % path)
		return failures

	var image := button.texture_normal.get_image()
	if image == null or image.is_empty():
		failures.append("%s must expose its art image for the click mask" % path)
		return failures

	var mask := button.texture_click_mask
	if mask == null:
		failures.append("%s must have a texture click mask" % path)
		return failures
	if mask.get_size() != image.get_size():
		failures.append("%s click mask must match the art size" % path)
		return failures

	if mask.get_bit(0, 0):
		failures.append("%s must not accept clicks in a transparent corner" % path)
	var center := Vector2i(image.get_width() / 2, image.get_height() / 2)
	if not mask.get_bit(center.x, center.y):
		failures.append("%s must accept clicks on its visible center" % path)
	return failures


func _check_no_overlapping_hits(buttons: Array[TextureButton]) -> Array[String]:
	var failures: Array[String] = []
	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			var a := buttons[i]
			var b := buttons[j]
			var overlap := a.get_global_rect().intersection(b.get_global_rect())
			if not overlap.has_area():
				continue
			for y in range(int(overlap.position.y), int(overlap.end.y), 4):
				for x in range(int(overlap.position.x), int(overlap.end.x), 4):
					var point := Vector2(x, y)
					if _mask_hit(a, point) and _mask_hit(b, point):
						failures.append("%s and %s click masks overlap at %s" % [
							a.name,
							b.name,
							point,
						])
						return failures
	return failures


func _mask_hit(button: TextureButton, screen_point: Vector2) -> bool:
	var mask := button.texture_click_mask
	if mask == null:
		return false
	var local := button.get_global_transform().affine_inverse() * screen_point
	if not Rect2(Vector2.ZERO, button.size).has_point(local):
		return false
	var mask_size := mask.get_size()
	var pixel := Vector2i(
		clampi(int(local.x / button.size.x * mask_size.x), 0, mask_size.x - 1),
		clampi(int(local.y / button.size.y * mask_size.y), 0, mask_size.y - 1)
	)
	return mask.get_bit(pixel.x, pixel.y)
