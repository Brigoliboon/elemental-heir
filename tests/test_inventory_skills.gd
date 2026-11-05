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

	# The three primary slots mirror the first three loadout entries.
	var primary: Array[SkillEquipSlot] = []
	for i in range(1, 4):
		var primary_slot := _find(panel, "PrimarySkill%d" % i) as SkillEquipSlot
		if primary_slot == null:
			failures.append("the skills page needs PrimarySkill%d" % i)
		else:
			primary.append(primary_slot)
	if primary.size() == 3:
		for i in primary.size():
			var expected := area.player.skill_in_slot(i)
			if primary[i].icon != (expected.icon if expected != null else null):
				failures.append("PrimarySkill%d must show slot %d's skill" % [i + 1, i + 1])

	# Dragging a skill onto a primary slot reorders the loadout and rebinds the HUD.
	var iron_slot: InventorySkillSlot = null
	for slot in slots:
		if slot.skill.id == &"iron_will":
			iron_slot = slot
	if iron_slot == null:
		failures.append("the owned skills grid needs Iron Will")
	elif primary.size() == 3:
		var original: Array[PlayerSkill] = []
		for skill in area.player.config.skills:
			original.append(skill)
		var iron_skill := iron_slot.skill
		var drag_data: Variant = iron_slot._get_drag_data(Vector2.ZERO)
		if drag_data == null or drag_data.get("type") != InventorySkillSlot.DRAG_TYPE:
			failures.append("a skill tile must produce skill drag data")
		elif not primary[0]._can_drop_data(Vector2.ZERO, drag_data):
			failures.append("PrimarySkill1 must accept a dragged skill")
		else:
			primary[0]._drop_data(Vector2.ZERO, drag_data)
			await tree.process_frame
			if area.player.skill_in_slot(0).id != &"iron_will":
				failures.append("dropping on PrimarySkill1 must equip that skill")
			if primary[0].icon != iron_skill.icon:
				failures.append("PrimarySkill1 must show the equipped skill icon")
			var hud_slot := area.get_node_or_null("HUD/UI/Skill1") as SkillButton
			if hud_slot == null or hud_slot.skill == null or hud_slot.skill.id != &"iron_will":
				failures.append("the HUD must rebind after a primary slot changes")
		# Restore the authored order so later suites see the default kit.
		for i in original.size():
			area.player.equip_skill_at(original[i], i)
		panel._save_skill_loadout()
		panel._refresh_skills()
		await tree.process_frame

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
