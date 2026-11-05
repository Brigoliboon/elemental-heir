extends RefCounted
## Validates the inventory skills page: the bars reuse the stats layout, owned
## skills fill a grid built from the bag slot art, and selecting a slot shows its
## details in the middle panel.

const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const SKILLS_BG := "res://assets/ui/hud/inventory/tab_sections/tab_skills_blank.png"
const BAR_PAIRS := [
	["HealthBar", "SkillHealthBar"],
	["HealthLabel", "SkillHealthLabel"],
	["EnergyBar", "SkillEnergyBar"],
	["EnergyLabel", "SkillEnergyLabel"],
	["XPBar", "SkillXPBar"],
	["XPLabel", "SkillXPLabel"],
]


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the inventory skills test" % AREA_SCENE)
		return failures

	var area := packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame

	var panel := area.get_node_or_null("HUD/UI/InventoryPanel") as InventoryPanel
	if panel == null:
		failures.append("the HUD needs the InventoryPanel")
		area.queue_free()
		await tree.process_frame
		return failures

	panel.show_panel()
	var skills_tab := _find(panel, "SkillsTab") as Button
	if skills_tab == null:
		failures.append("the inventory needs the SkillsTab button")
	else:
		skills_tab.pressed.emit()
		await tree.process_frame
	await tree.process_frame

	if panel.current_tab != &"skills":
		failures.append("clicking SKILLS must switch to the skills tab")

	var background := _find(panel, "Background") as TextureRect
	if background == null or background.texture == null or background.texture.resource_path != SKILLS_BG:
		failures.append("the skills tab must use %s" % SKILLS_BG)

	var skills_page := _find(panel, "SkillsPage") as Control
	var stats_page := _find(panel, "StatsPage") as Control
	if skills_page == null or not skills_page.visible:
		failures.append("the skills page must be visible on the skills tab")
	if stats_page != null and stats_page.visible:
		failures.append("the stats page must be hidden on the skills tab")

	# The bars must sit exactly where the stats page puts them.
	for pair in BAR_PAIRS:
		var reference := _find(panel, pair[0]) as Control
		var skill_bar := _find(panel, pair[1]) as Control
		if reference == null or skill_bar == null:
			failures.append("the skills page needs %s" % pair[1])
			continue
		if not skill_bar.position.is_equal_approx(reference.position) or not skill_bar.size.is_equal_approx(reference.size):
			failures.append("%s must copy the %s placement" % [pair[1], pair[0]])

	var skill_content := _find(panel, "SkillContent") as Control
	if skill_content == null:
		failures.append("the skills page needs its skill grid content")
		area.queue_free()
		await tree.process_frame
		return failures

	var slots: Array[InventorySkillSlot] = []
	for child in skill_content.get_children():
		if child is InventorySkillSlot and (child as InventorySkillSlot).skill != null:
			slots.append(child)
	var owned := area.player.config.skills.size()
	if slots.size() != owned:
		failures.append("the skill grid must show every owned skill (%d)" % owned)
	for slot in slots:
		if slot.icon == null:
			failures.append("%s must show its skill icon" % slot.skill.display_name)

	var detail_name := _find(panel, "SkillDetailName") as Label
	var detail_meta := _find(panel, "SkillDetailMeta") as Label
	var detail_description := _find(panel, "SkillDetailDescription") as Label
	if detail_name == null or detail_meta == null or detail_description == null:
		failures.append("the skills page needs the detail labels")
	else:
		var first := slots[0] if not slots.is_empty() else null
		if first != null:
			first.pressed.emit()
			await tree.process_frame
			if detail_name.text != first.skill.display_name.to_upper():
				failures.append("clicking a skill must show its name")
			if detail_description.text != first.skill.description:
				failures.append("clicking a skill must show its description")
			if not detail_meta.text.contains("ENERGY %d" % first.skill.energy_cost):
				failures.append("the detail meta must show the energy cost")

		var slam: InventorySkillSlot = null
		for slot in slots:
			if slot.skill.id == &"ground_slam":
				slam = slot
		if slam != null:
			slam.pressed.emit()
			await tree.process_frame
			if detail_name.text != "GROUND SLAM":
				failures.append("selecting Ground Slam must update the detail name")
			if not detail_meta.text.contains("AREA"):
				failures.append("the detail meta must describe the skill type")
			if not detail_description.text.contains("knock"):
				failures.append("the detail panel must show the skill description")

	var skill_hp := _find(panel, "SkillHealthLabel") as Label
	var stats_hp := _find(panel, "HealthLabel") as Label
	if skill_hp != null and stats_hp != null and skill_hp.text != stats_hp.text:
		failures.append("the skills health bar must mirror the stats page")

	area.queue_free()
	await tree.process_frame
	return failures


func _find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)
