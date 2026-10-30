extends RefCounted
## Validates the top-left HUD bar art and live health/XP values.


const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const FRAME_PATH := "res://assets/ui/hud/bars/bar-container.png"
const HEALTH_PATH := "res://assets/ui/hud/bars/health-bar.png"
const EXP_PATH := "res://assets/ui/hud/bars/exp-bar.png"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the HUD bar test" % AREA_SCENE)
		return failures

	var area := packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame

	var health_frame := area.get_node_or_null("HUD/UI/PlayerHealth/HealthFrame") as TextureRect
	var health_bar := area.get_node_or_null("HUD/UI/PlayerHealth/HealthBar") as TextureProgressBar
	var health_label := area.get_node_or_null("HUD/UI/PlayerHealth/HealthLabel") as Label
	var xp_frame := area.get_node_or_null("HUD/UI/PlayerHealth/XPFrame") as TextureRect
	var xp_bar := area.get_node_or_null("HUD/UI/PlayerHealth/XPBar") as TextureProgressBar
	var xp_label := area.get_node_or_null("HUD/UI/PlayerHealth/XPLabel") as Label

	if health_frame == null or health_bar == null or health_label == null:
		failures.append("the HUD needs the health frame, bar and label")
	if xp_frame == null or xp_bar == null or xp_label == null:
		failures.append("the HUD needs the XP frame, bar and label")

	_expect_texture(failures, health_frame, FRAME_PATH, "health frame")
	_expect_texture(failures, xp_frame, FRAME_PATH, "XP frame")
	_expect_texture(failures, health_bar, HEALTH_PATH, "health bar fill")
	_expect_texture(failures, xp_bar, EXP_PATH, "XP bar fill")

	if health_bar != null:
		if not is_equal_approx(health_bar.max_value, float(area.player.max_health)):
			failures.append("the health bar max must track player.max_health")
		if not is_equal_approx(health_bar.value, float(area.player.current_health)):
			failures.append("the health bar value must track player.current_health")
	if health_label != null and not health_label.text.contains(str(area.player.current_health)):
		failures.append("the health label must show current health")

	if xp_bar != null:
		if not is_equal_approx(xp_bar.max_value, float(area.player.experience_to_next_level())):
			failures.append("the XP bar max must track experience_to_next_level()")
		if not is_equal_approx(xp_bar.value, float(area.player.experience)):
			failures.append("the XP bar value must track player.experience")
	if xp_label != null and not xp_label.text.contains("XP"):
		failures.append("the XP label must show XP progress")

	area.player.add_experience(10)
	await tree.process_frame
	if xp_bar != null and not is_equal_approx(xp_bar.value, float(area.player.experience)):
		failures.append("the XP bar must update when XP changes")

	area.queue_free()
	await tree.process_frame
	return failures


func _expect_texture(
	failures: Array[String],
	control: Control,
	path: String,
	label: String,
) -> void:
	if control == null:
		return
	var texture: Texture2D
	if control is TextureProgressBar:
		texture = (control as TextureProgressBar).texture_progress
	elif control is TextureRect:
		texture = (control as TextureRect).texture
	if texture == null:
		failures.append("%s must have its art assigned" % label)
	elif texture.resource_path != path:
		failures.append("%s must use %s" % [label, path])
