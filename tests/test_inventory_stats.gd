extends RefCounted
## Validates the inventory stats tab: full-frame art, tab buttons, live progress
## values, transparent equipment slots and the six combat stat rows.

const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const STATS_BG := "res://assets/ui/hud/inventory/tab_sections/tab_stats_blank.png"
const SKILLS_BG := "res://assets/ui/hud/inventory/tab_sections/tab_skills_blank.png"
const ITEMS_BG := "res://assets/ui/hud/inventory/tab_sections/tab_items_blank.png"
const EQUIP_SLOTS := [
	"EquipHelmet",
	"EquipChest",
	"EquipPrimary",
	"EquipPants",
	"EquipNecklace",
	"EquipCape",
	"EquipSecondary",
	"EquipRing",
	"EquipBoots",
]
const STAT_ROWS := [
	"StatAttack",
	"StatDefence",
	"StatMoveSpeed",
	"StatCritRate",
	"StatCritDamage",
	"StatCooldown",
]


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the inventory stats test" % AREA_SCENE)
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

	area.player.apply_progress(3, 0)
	panel.show_panel()
	await tree.process_frame

	if not panel.visible:
		failures.append("show_panel must make the inventory visible")

	var background := _find(panel, "Background") as TextureRect
	if background == null:
		failures.append("the inventory needs its frame background")
	elif background.texture == null or background.texture.resource_path != STATS_BG:
		failures.append("the stats tab must use %s" % STATS_BG)

	for tab_name in ["StatsTab", "SkillsTab", "ItemsTab"]:
		var tab := _find(panel, tab_name) as Button
		if tab == null:
			failures.append("the inventory needs an invisible %s button" % tab_name)
		elif tab.text != "":
			failures.append("%s must stay invisible (no text)" % tab_name)

	var level_label := _find(panel, "LevelLabel") as Label
	if level_label == null:
		failures.append("the stats tab needs LevelLabel")
	elif not level_label.text.contains("3"):
		failures.append("LevelLabel must show the player's level, got '%s'" % level_label.text)

	var health_bar := _find(panel, "HealthBar") as TextureProgressBar
	var xp_bar := _find(panel, "XPBar") as TextureProgressBar
	var energy_bar := _find(panel, "EnergyBar") as TextureProgressBar
	if health_bar == null or health_bar.max_value != area.player.max_health:
		failures.append("HealthBar must use the player's maximum health")
	elif health_bar.value != area.player.current_health:
		failures.append("HealthBar must show the player's current health")
	if xp_bar == null:
		failures.append("the stats tab needs XPBar")
	else:
		var to_next := maxf(1.0, float(area.player.experience_to_next_level()))
		if not is_equal_approx(xp_bar.max_value, to_next):
			failures.append("XPBar must show the XP required for the next level")
	if energy_bar == null:
		failures.append("the stats tab needs EnergyBar")
	elif not is_equal_approx(energy_bar.max_value, area.player.max_energy):
		failures.append("EnergyBar must use the player's maximum energy")
	elif not is_equal_approx(energy_bar.value, area.player.energy):
		failures.append("EnergyBar must show the player's current energy")

	area.player.set_health(area.player.max_health - 5)
	await tree.process_frame
	if health_bar != null and health_bar.value != area.player.current_health:
		failures.append("HealthBar must refresh when the player takes damage")

	for slot_name in EQUIP_SLOTS:
		var slot := _find(panel, slot_name) as Button
		if slot == null:
			failures.append("the equipment section needs %s" % slot_name)
			continue
		var style := slot.get_theme_stylebox("normal")
		if not (style is StyleBoxEmpty):
			failures.append("%s must be transparent" % slot_name)

	for stat_name in STAT_ROWS:
		if _find(panel, stat_name) as Label == null:
			failures.append("the stat list needs %s" % stat_name)

	var expected_attack := str(roundi(area.player.stats.get_stat(Stats.ATTACK)))
	var attack_label := _find(panel, "StatAttack") as Label
	if attack_label != null and attack_label.text != expected_attack:
		failures.append("StatAttack must show the live attack value")

	var skills_tab := _find(panel, "SkillsTab") as Button
	if skills_tab != null:
		skills_tab.pressed.emit()
		await tree.process_frame
		if panel.current_tab != &"skills":
			failures.append("clicking SKILLS must switch to the skills tab")
		if background != null and (background.texture == null or background.texture.resource_path != SKILLS_BG):
			failures.append("the skills tab must use %s" % SKILLS_BG)

	var items_tab := _find(panel, "ItemsTab") as Button
	if items_tab != null:
		items_tab.pressed.emit()
		await tree.process_frame
		if panel.current_tab != &"items":
			failures.append("clicking ITEMS must switch to the items tab")
		if background != null and (background.texture == null or background.texture.resource_path != ITEMS_BG):
			failures.append("the items tab must use %s" % ITEMS_BG)

	var stats_tab := _find(panel, "StatsTab") as Button
	if stats_tab != null:
		stats_tab.pressed.emit()
		await tree.process_frame
		if panel.current_tab != &"stats":
			failures.append("clicking STATS must return to the stats tab")

	var close_button := _find(panel, "CloseButton") as Button
	if close_button == null:
		failures.append("the inventory needs a CloseButton")
	else:
		close_button.pressed.emit()
		await tree.process_frame
		if panel.visible:
			failures.append("CloseButton must hide the inventory")

	area.queue_free()
	await tree.process_frame
	return failures


func _find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)
