extends RefCounted
## Validates the HUD stats panel, the player XP bar, and showing mob stats on click.


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load("res://scenes/areas/forest/forest_village_square.tscn") as PackedScene
	if packed == null:
		failures.append("forest_village_square.tscn did not load for the stats UI test")
		return failures

	var area := packed.instantiate()
	tree.root.add_child(area)
	await tree.process_frame

	var panel := area.get_node_or_null("HUD/UI/StatsPanel") as StatsPanel
	var xp_bar := area.get_node_or_null("HUD/UI/PlayerHealth/XPBar") as TextureProgressBar
	var xp_label := area.get_node_or_null("HUD/UI/PlayerHealth/XPLabel") as Label
	if panel == null:
		failures.append("HUD needs a StatsPanel")
	if xp_bar == null or xp_label == null:
		failures.append("HUD needs an XP label and bar")

	if panel != null and panel.visible:
		failures.append("StatsPanel must start hidden")

	if xp_bar != null:
		var to_next := float(area.player.experience_to_next_level())
		if not is_equal_approx(xp_bar.max_value, to_next):
			failures.append("XP bar max must track experience_to_next_level()")
		if not is_equal_approx(xp_bar.value, float(area.player.experience)):
			failures.append("XP bar value must track the player's experience")
	if xp_label != null and not xp_label.text.contains("XP"):
		failures.append("XP label must show XP progress")

	if panel != null:
		area._on_stats_button_pressed()
		await tree.process_frame
		if not panel.visible:
			failures.append("opening stats must show the panel")

		var title := panel.get_node_or_null("Margin/VBox/Title") as Label
		var body := panel.get_node_or_null("Margin/VBox/Body") as Label
		if title == null or body == null:
			failures.append("StatsPanel needs Title and Body labels")
		else:
			if not title.text.contains(area.player.config.character_name):
				failures.append("player stats title must show the character name")
			if not body.text.contains("Attack") or not body.text.contains("Defence"):
				failures.append("player stats body must list combat stats")
			if not body.text.contains("XP"):
				failures.append("player stats body must list XP")

		area._on_stats_button_pressed()
		await tree.process_frame
		if panel.visible:
			failures.append("opening stats again must hide the panel")

	# Partial XP must refresh the bar through experience_changed.
	area.player.add_experience(10)
	await tree.process_frame
	if xp_bar != null and not is_equal_approx(xp_bar.value, float(area.player.experience)):
		failures.append("XP bar must update when the player gains XP")

	# Clicking a mob must show that mob's data in the same panel.
	var mob_packed := load("res://entities/enemies/mob.tscn") as PackedScene
	var mob := mob_packed.instantiate()
	tree.root.add_child(mob)
	await tree.process_frame
	mob.set_physics_process(false)
	mob.global_position = Vector2(400.0, 400.0)
	await tree.physics_frame
	await tree.physics_frame

	var screen_position: Vector2 = area.get_canvas_transform() * mob.global_position
	area._try_show_mob_stats(screen_position)
	await tree.process_frame

	if panel != null:
		if not panel.visible:
			failures.append("clicking a mob must show the stats panel")
		var title := panel.get_node_or_null("Margin/VBox/Title") as Label
		var body := panel.get_node_or_null("Margin/VBox/Body") as Label
		if title != null and not title.text.contains(mob.config.enemy_name):
			failures.append("mob stats title must show the enemy name")
		if body != null:
			if not body.text.contains("XP Reward"):
				failures.append("mob stats body must list the XP reward")
			if not body.text.contains("Attack"):
				failures.append("mob stats body must list combat stats")

	mob.queue_free()
	area.queue_free()
	await tree.process_frame
	return failures
