extends RefCounted
## Validates that the title screen controls live under a full-rect Control and
## keep their screen-edge margins when the viewport grows.


const TITLE_SCENE := "res://scenes/title/title_screen.tscn"
const TEST_SIZE := Vector2i(2400, 1200)


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load(TITLE_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the title layout test" % TITLE_SCENE)
		return failures

	tree.root.size = TEST_SIZE
	await tree.process_frame

	var title := packed.instantiate() as Control
	tree.root.add_child(title)
	await tree.process_frame
	await tree.process_frame

	var ui := title.get_node_or_null("CanvasLayer/UI") as Control
	var background := title.get_node_or_null("Background") as Control
	var sound := title.get_node_or_null("CanvasLayer/UI/SoundButton") as Control
	var credits := title.get_node_or_null("CanvasLayer/UI/CreditsButton") as Control
	var offline := title.get_node_or_null("CanvasLayer/UI/OfflineButton") as Control
	var online := title.get_node_or_null("CanvasLayer/UI/OnlineButton") as Control
	var settings := title.get_node_or_null("CanvasLayer/UI/SettingsButton") as Control
	var no_connection := title.get_node_or_null("CanvasLayer/UI/NoConnectionLabel") as Control

	if ui == null:
		failures.append("the title screen needs CanvasLayer/UI as its layout root")
	else:
		_expect_full_rect(failures, ui, "CanvasLayer/UI")
	if background == null:
		failures.append("the title screen needs its Background video")
	else:
		_expect_full_rect(failures, background, "Background")

	for entry in [
		[sound, "SoundButton"],
		[credits, "CreditsButton"],
		[offline, "OfflineButton"],
		[online, "OnlineButton"],
		[settings, "SettingsButton"],
		[no_connection, "NoConnectionLabel"],
	]:
		if entry[0] == null:
			failures.append("the title screen needs CanvasLayer/UI/%s" % entry[1])

	if failures.size() > 0:
		title.queue_free()
		await tree.process_frame
		return failures

	var viewport := tree.root.get_visible_rect().size
	var right_margin := viewport.x - settings.get_global_rect().end.x
	var bottom_margin := viewport.y - settings.get_global_rect().end.y
	var top_right_margin := viewport.x - sound.get_global_rect().end.x
	var label_right_margin := viewport.x - no_connection.get_global_rect().end.x

	if not is_equal_approx(right_margin, 64.0):
		failures.append("the bottom-right buttons must keep a 64 px right margin")
	if not is_equal_approx(bottom_margin, 64.0):
		failures.append("the bottom-right buttons must keep a 64 px bottom margin")
	if not is_equal_approx(top_right_margin, 176.0):
		failures.append("the top-right buttons must keep a 176 px right margin")
	if not is_equal_approx(label_right_margin, 440.0):
		failures.append("the no-connection label must stay left of the online button")

	if sound.get_global_rect().size.x < 120.0 or sound.get_global_rect().size.y < 120.0:
		failures.append("the top-right buttons must be at least 120 px for touch input")
	if settings.get_global_rect().size.x < 320.0 or settings.get_global_rect().size.y < 96.0:
		failures.append("the navigation buttons must be at least 320x96 px for touch input")

	if not _inside(settings.get_global_rect(), viewport):
		failures.append("settings must stay inside the viewport")
	if not _inside(sound.get_global_rect(), viewport):
		failures.append("the sound button must stay inside the viewport")
	if settings.get_global_rect().intersects(online.get_global_rect()):
		failures.append("settings must not overlap the online button")

	# Resize again: controls must stay pinned to the same edges.
	var larger := Vector2i(2560, 1320)
	tree.root.size = larger
	await tree.process_frame
	await tree.process_frame

	viewport = tree.root.get_visible_rect().size
	if not is_equal_approx(viewport.x - settings.get_global_rect().end.x, right_margin):
		failures.append("the right margin must stay fixed when the viewport grows")
	if not is_equal_approx(viewport.y - settings.get_global_rect().end.y, bottom_margin):
		failures.append("the bottom margin must stay fixed when the viewport grows")
	if not is_equal_approx(viewport.x - sound.get_global_rect().end.x, top_right_margin):
		failures.append("top-right controls must follow a wider viewport")
	if not _inside(settings.get_global_rect(), viewport):
		failures.append("settings must stay inside the resized viewport")

	title.queue_free()
	await tree.process_frame
	tree.root.size = Vector2i(1920, 1080)
	await tree.process_frame
	return failures


func _expect_full_rect(failures: Array[String], control: Control, label: String) -> void:
	if not is_equal_approx(control.anchor_left, 0.0) \
			or not is_equal_approx(control.anchor_top, 0.0) \
			or not is_equal_approx(control.anchor_right, 1.0) \
			or not is_equal_approx(control.anchor_bottom, 1.0) \
			or not is_zero_approx(control.offset_left) \
			or not is_zero_approx(control.offset_top) \
			or not is_zero_approx(control.offset_right) \
			or not is_zero_approx(control.offset_bottom):
		failures.append("%s must fill its parent with zero offsets" % label)


func _inside(rect: Rect2, viewport: Vector2) -> bool:
	return rect.position.x >= -1.0 \
		and rect.position.y >= -1.0 \
		and rect.end.x <= viewport.x + 1.0 \
		and rect.end.y <= viewport.y + 1.0
