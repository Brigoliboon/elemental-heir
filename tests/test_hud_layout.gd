extends RefCounted
## Validates the HUD layer: it must grow with the design canvas so the profile,
## bars and labels stay readable on phones, keep covering the viewport, and keep
## the area title centred instead of pinned to 1920 px offsets.

const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const SIZES := [Vector2i(2400, 1080), Vector2i(1280, 720)]
const CONTROLS := [
	"HUD/UI/AreaLabel",
	"HUD/UI/BackButton",
	"HUD/UI/MapButton",
	"HUD/UI/AttackButton",
	"HUD/UI/BlockButton",
	"HUD/UI/PlayerHealth",
	"HUD/UI/PlayerHealth/Profile",
	"HUD/UI/PlayerHealth/HealthBar",
	"HUD/UI/PlayerHealth/XPBar",
]


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var previous_size := tree.root.size

	for size in SIZES:
		tree.root.size = size
		await tree.process_frame

		var packed := load(AREA_SCENE) as PackedScene
		var area := packed.instantiate() as Area
		tree.root.add_child(area)
		await tree.process_frame
		await tree.process_frame

		failures.append_array(_check_area(area, tree.root.get_visible_rect().size))

		# Phone pass: force the mobile scale through the desktop knob so corner
		# anchoring is exercised the way a phone sees it.
		var desktop_scale := area.hud_scale_desktop
		area.hud_scale_desktop = area.hud_scale_mobile
		area._layout_hud()
		await tree.process_frame
		failures.append_array(_check_controls(area, tree.root.get_visible_rect().size, "at mobile scale"))
		area.hud_scale_desktop = desktop_scale
		area._layout_hud()
		await tree.process_frame

		area.queue_free()
		await tree.process_frame

	tree.root.size = previous_size
	await tree.process_frame
	return failures


func _check_area(area: Area, view: Vector2) -> Array[String]:
	var failures: Array[String] = []
	var ui := area.get_node_or_null("HUD/UI") as Control
	if ui == null:
		failures.append("the HUD needs a HUD/UI layout root")
		return failures

	var expected := area.hud_scale_for(view, OS.has_feature("mobile"))
	if not is_equal_approx(ui.scale.x, expected) or not is_equal_approx(ui.scale.y, expected):
		failures.append("the HUD must be scaled to %.2f at %s, got %s" % [expected, view, ui.scale])
	if ui.scale.x < 1.0:
		failures.append("the HUD must never be scaled below design size")
	if not (ui.size * ui.scale).is_equal_approx(view):
		failures.append("the scaled HUD must still cover the whole viewport (%s vs %s)" % [
			ui.size * ui.scale,
			view,
		])

	if not is_equal_approx(area.hud_scale_for(Vector2(1920, 1080), false), 1.0):
		failures.append("desktop must keep the HUD at its design scale")
	if not is_equal_approx(area.hud_scale_for(Vector2(2400, 1080), true), 1.4):
		failures.append("phones must grow the HUD so the profile and bars stay readable")

	var label := area.get_node_or_null("HUD/UI/AreaLabel") as Label
	if label == null:
		failures.append("the HUD needs HUD/UI/AreaLabel")
	else:
		var label_rect := label.get_global_rect()
		if absf(label_rect.get_center().x - view.x * 0.5) > 1.0:
			failures.append("the area title must stay horizontally centred at %s (centre %.1f)" % [
				view,
				label_rect.get_center().x,
			])
		if not _inside(label_rect, view):
			failures.append("the area title must stay inside the viewport at %s" % view)

	failures.append_array(_check_controls(area, view, "at desktop scale"))

	var profile := area.get_node_or_null("HUD/UI/PlayerHealth/Profile") as Control
	if profile != null and profile.get_global_rect().size.x < 150.0:
		failures.append("the profile button must stay large enough for touch input")

	return failures


## Every HUD control must stay on screen whatever the layer scale is.
func _check_controls(area: Area, view: Vector2, context: String) -> Array[String]:
	var failures: Array[String] = []
	for path in CONTROLS:
		var control := area.get_node_or_null(path) as Control
		if control == null:
			failures.append("the HUD needs %s" % path)
			continue
		if not control.is_visible_in_tree():
			continue
		if not _inside(control.get_global_rect(), view):
			failures.append("%s must stay inside the viewport %s %s (rect %s)" % [
				path,
				context,
				view,
				control.get_global_rect(),
			])
	return failures


func _inside(rect: Rect2, view: Vector2) -> bool:
	return rect.position.x >= -1.0 \
		and rect.position.y >= -1.0 \
		and rect.end.x <= view.x + 1.0 \
		and rect.end.y <= view.y + 1.0
