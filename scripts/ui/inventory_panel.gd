class_name InventoryPanel
extends Control

const DESIGN_SIZE := Vector2(1920, 1080)
const STATS_BG := preload("res://assets/ui/hud/inventory/tab_sections/tab_stats_blank.png")
const SKILLS_BG := preload("res://assets/ui/hud/inventory/tab_sections/tab_skills_blank.png")
const ITEMS_BG := preload("res://assets/ui/hud/inventory/tab_sections/tab_items_blank.png")
const BAG_SLOT_SCENE := preload("res://scenes/ui/inventory_bag_slot.tscn")
const SKILL_SLOT_SCENE := preload("res://scenes/ui/inventory_skill_slot.tscn")

const BAG_COLUMNS := 4
const BAG_SLOT_SIZE := 128.0
const BAG_GAP := 8.0
const BAG_PADDING := 8.0
const BAG_STRIDE := 136.0

const SKILL_COLUMNS := 3
const SKILL_SLOT_SIZE := 128.0
const SKILL_GAP := 16.0
const SKILL_PADDING := 8.0
const SKILL_STRIDE := 144.0
const SKILL_MIN_ROWS := 4

const EQUIP_GROUPS := ["helmet", "chest_armour", "pants", "boots", "necklace", "ring", "sword", "shield"]
const EQUIP_STORAGE := [0, 1, 6, 2, 4, -1, 7, 5, 3]
const EQUIP_LABELS := ["Helmet", "Chestplate", "Primary", "Pants", "Necklace", "Cape", "Secondary", "Ring", "Boots"]
const EQUIP_ACCEPTS := [&"head", &"chest", &"primary", &"pants", &"necklace", &"", &"secondary", &"ring", &"boots"]

var current_tab: StringName = &"stats"

var _inventory: Inventory
var _stats: Stats
var _player: Character
var _equipped: Array = [null, null, null, null, null, null, null, null]
var _bag_slots: Array[InventoryBagSlot] = []
var _bag_pool_rows := 0
var _skill_slots: Array[InventorySkillSlot] = []
var _selected_skill: PlayerSkill

@onready var _frame: Control = $Frame
@onready var _background: TextureRect = $Frame/Background
@onready var _stats_page_bg: TextureRect = $Frame/StatsPage/Background
@onready var _skills_page_bg: TextureRect = $Frame/SkillsPage/Background
@onready var _items_page_bg: TextureRect = $Frame/ItemsPage/Background
@onready var _stats_page: Control = $Frame/StatsPage
@onready var _skills_page: Control = $Frame/SkillsPage
@onready var _items_page: Control = $Frame/ItemsPage
@onready var _bag_viewport: ScrollContainer = $Frame/ItemsPage/BagViewport
@onready var _bag_content: Control = $Frame/ItemsPage/BagViewport/BagContent
@onready var _sort_button: Button = $Frame/ItemsPage/SortButton
@onready var _skill_viewport: ScrollContainer = $Frame/SkillsPage/SkillViewport
@onready var _skill_content: Control = $Frame/SkillsPage/SkillViewport/SkillContent
@onready var _skill_detail_name: Label = $Frame/SkillsPage/SkillDetailName
@onready var _skill_detail_meta: Label = $Frame/SkillsPage/SkillDetailMeta
@onready var _skill_detail_description: Label = $Frame/SkillsPage/SkillDetailDescription
@onready var _placeholder: Label = $Frame/Placeholder
@onready var _level_label: Label = $Frame/StatsPage/LevelLabel
@onready var _health_bar: TextureProgressBar = $Frame/StatsPage/HealthBar
@onready var _health_label: Label = $Frame/StatsPage/HealthLabel
@onready var _xp_bar: TextureProgressBar = $Frame/StatsPage/XPBar
@onready var _xp_label: Label = $Frame/StatsPage/XPLabel
@onready var _energy_bar: TextureProgressBar = $Frame/StatsPage/EnergyBar
@onready var _energy_label: Label = $Frame/StatsPage/EnergyLabel
@onready var _skill_health_bar: TextureProgressBar = $Frame/SkillsPage/SkillHealthBar
@onready var _skill_health_label: Label = $Frame/SkillsPage/SkillHealthLabel
@onready var _skill_energy_bar: TextureProgressBar = $Frame/SkillsPage/SkillEnergyBar
@onready var _skill_energy_label: Label = $Frame/SkillsPage/SkillEnergyLabel
@onready var _skill_xp_bar: TextureProgressBar = $Frame/SkillsPage/SkillXPBar
@onready var _skill_xp_label: Label = $Frame/SkillsPage/SkillXPLabel
@onready var _equip_buttons: Array[Button] = [
	$Frame/StatsPage/EquipHelmet,
	$Frame/StatsPage/EquipChest,
	$Frame/StatsPage/EquipPrimary,
	$Frame/StatsPage/EquipPants,
	$Frame/StatsPage/EquipNecklace,
	$Frame/StatsPage/EquipCape,
	$Frame/StatsPage/EquipSecondary,
	$Frame/StatsPage/EquipRing,
	$Frame/StatsPage/EquipBoots,
]
@onready var _item_equip_buttons: Array[Button] = [
	$Frame/ItemsPage/ItemEquipHelmet,
	$Frame/ItemsPage/ItemEquipChest,
	$Frame/ItemsPage/ItemEquipPrimary,
	$Frame/ItemsPage/ItemEquipPants,
	$Frame/ItemsPage/ItemEquipNecklace,
	$Frame/ItemsPage/ItemEquipCape,
	$Frame/ItemsPage/ItemEquipSecondary,
	$Frame/ItemsPage/ItemEquipRing,
	$Frame/ItemsPage/ItemEquipBoots,
]
@onready var _item_health_bar: TextureProgressBar = $Frame/ItemsPage/ItemHealthBar
@onready var _item_health_label: Label = $Frame/ItemsPage/ItemHealthLabel
@onready var _item_energy_bar: TextureProgressBar = $Frame/ItemsPage/ItemEnergyBar
@onready var _item_energy_label: Label = $Frame/ItemsPage/ItemEnergyLabel
@onready var _item_xp_bar: TextureProgressBar = $Frame/ItemsPage/ItemXPBar
@onready var _item_xp_label: Label = $Frame/ItemsPage/ItemXPLabel
@onready var _stat_labels: Dictionary = {
	&"attack": $Frame/StatsPage/StatAttack,
	&"defence": $Frame/StatsPage/StatDefence,
	&"move_speed": $Frame/StatsPage/StatMoveSpeed,
	&"crit_rate": $Frame/StatsPage/StatCritRate,
	&"crit_damage": $Frame/StatsPage/StatCritDamage,
	&"cooldown_reduction": $Frame/StatsPage/StatCooldown,
}
@onready var _stats_tab: Button = $Frame/StatsTab
@onready var _skills_tab: Button = $Frame/SkillsTab
@onready var _items_tab: Button = $Frame/ItemsTab
@onready var _close_button: Button = $Frame/CloseButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_stats_tab.pressed.connect(_set_tab.bind(&"stats"))
	_skills_tab.pressed.connect(_set_tab.bind(&"skills"))
	_items_tab.pressed.connect(_set_tab.bind(&"items"))
	_sort_button.pressed.connect(_on_sort_pressed)
	_close_button.pressed.connect(hide_panel)
	_bag_viewport.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bag_viewport.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_bag_viewport.get_v_scroll_bar().value_changed.connect(_on_bag_scrolled)
	_bag_viewport.resized.connect(_layout_bag)
	_skill_viewport.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_skill_viewport.resized.connect(_layout_skill_grid)
	for i in _equip_buttons.size():
		var btn = _equip_buttons[i]
		btn.slot_index = i
		btn.accepts = EQUIP_ACCEPTS[i]
		btn.item_dropped.connect(_on_equip_item_dropped)
	for i in _item_equip_buttons.size():
		var btn = _item_equip_buttons[i]
		btn.slot_index = i
		btn.accepts = EQUIP_ACCEPTS[i]
		btn.item_dropped.connect(_on_equip_item_dropped)
	resized.connect(_layout_frame)
	_layout_frame.call_deferred()
	_layout_bag.call_deferred()
	_layout_skill_grid.call_deferred()
	hide_panel()


func bind(inventory: Inventory, stats: Stats = null, player: Character = null) -> void:
	_inventory = inventory
	_bind_stats(stats)
	_bind_player(player)
	_restore_equipped()
	_layout_bag()
	_layout_skill_grid()
	refresh()


func show_panel() -> void:
	_set_tab(&"stats")
	refresh()
	visible = true


func hide_panel() -> void:
	visible = false


func toggle() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()


func refresh() -> void:
	if not is_node_ready():
		return
	_refresh_equipment()
	_refresh_progress()
	_refresh_stats()
	_refresh_bag()
	_refresh_skills()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		hide_panel()
		get_viewport().set_input_as_handled()


func _set_tab(tab: StringName) -> void:
	current_tab = tab
	match tab:
		&"skills":
			_background.texture = SKILLS_BG
			_stats_page_bg.visible = false
			_skills_page_bg.visible = true
			_items_page_bg.visible = false
			_stats_page.visible = false
			_skills_page.visible = true
			_items_page.visible = false
			_placeholder.visible = false
			_layout_skill_grid()
		&"items":
			_background.texture = ITEMS_BG
			_stats_page_bg.visible = false
			_skills_page_bg.visible = false
			_items_page_bg.visible = true
			_stats_page.visible = false
			_skills_page.visible = false
			_items_page.visible = true
			_placeholder.visible = false
			_layout_bag()
		_:
			current_tab = &"stats"
			_background.texture = STATS_BG
			_stats_page_bg.visible = true
			_skills_page_bg.visible = false
			_items_page_bg.visible = false
			_stats_page.visible = true
			_skills_page.visible = false
			_items_page.visible = false
			_placeholder.visible = false
	if current_tab == &"stats":
		_refresh_stats()


func _layout_frame() -> void:
	if _frame == null:
		return
	var view := size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var fit := minf(view.x / DESIGN_SIZE.x, view.y / DESIGN_SIZE.y)
	_frame.scale = Vector2(fit, fit)
	_frame.position = (view - DESIGN_SIZE * fit) * 0.5


func _layout_bag() -> void:
	if not is_node_ready() or _bag_content == null:
		return
	var capacity := _bag_capacity()
	var rows := maxi(1, ceili(float(capacity) / float(BAG_COLUMNS)))
	var width := BAG_PADDING * 2.0 + BAG_COLUMNS * BAG_SLOT_SIZE + (BAG_COLUMNS - 1) * BAG_GAP
	var height := BAG_PADDING * 2.0 + rows * BAG_SLOT_SIZE + maxi(0, rows - 1) * BAG_GAP
	_bag_content.custom_minimum_size = Vector2(width, height)
	_ensure_bag_pool()
	_refresh_bag()


func _ensure_bag_pool() -> void:
	var visible_rows := maxi(1, ceili((_bag_viewport.size.y - BAG_PADDING) / BAG_STRIDE))
	var needed_rows := visible_rows + 1
	if needed_rows == _bag_pool_rows and _bag_slots.size() == needed_rows * BAG_COLUMNS:
		return
	_bag_pool_rows = needed_rows
	for slot in _bag_slots:
		slot.free()
	_bag_slots.clear()
	for i in range(BAG_COLUMNS * needed_rows):
		var slot := BAG_SLOT_SCENE.instantiate() as InventoryBagSlot
		_bag_content.add_child(slot)
		_bag_slots.append(slot)


func _refresh_bag() -> void:
	if _bag_content == null or _bag_slots.is_empty():
		return
	var capacity := _bag_capacity()
	var total_rows := maxi(1, ceili(float(capacity) / float(BAG_COLUMNS)))
	var first_row := maxi(0, floori(_bag_viewport.scroll_vertical / BAG_STRIDE))
	var slots := _inventory.get_slots() if _inventory != null else []
	for i in _bag_slots.size():
		var slot := _bag_slots[i]
		var local_row := floori(float(i) / float(BAG_COLUMNS))
		var column := i % BAG_COLUMNS
		var row := first_row + local_row
		var index := row * BAG_COLUMNS + column
		if row >= total_rows or index >= capacity:
			slot.clear_slot()
			slot.visible = false
			continue
		slot.visible = true
		slot.position = Vector2(BAG_PADDING + column * BAG_STRIDE, BAG_PADDING + row * BAG_STRIDE)
		var item: ItemData = null
		var count := 0
		if index < slots.size():
			item = slots[index]["item"]
			count = int(slots[index]["count"])
		slot.bind_slot(index, item, count)


func _bag_capacity() -> int:
	if _inventory == null:
		return 30
	return maxi(1, _inventory.get_slots().size())


func _on_bag_scrolled(_value: float) -> void:
	_refresh_bag()


func _on_sort_pressed() -> void:
	if _inventory == null:
		return
	_inventory.sort_by_type()
	_bag_viewport.scroll_vertical = 0
	_layout_bag()


func _layout_skill_grid() -> void:
	if not is_node_ready() or _skill_content == null:
		return
	var skills := _owned_skills()
	var rows := maxi(SKILL_MIN_ROWS, ceili(float(skills.size()) / float(SKILL_COLUMNS)))
	var width := SKILL_PADDING * 2.0 + SKILL_COLUMNS * SKILL_SLOT_SIZE + (SKILL_COLUMNS - 1) * SKILL_GAP
	var height := SKILL_PADDING * 2.0 + rows * SKILL_SLOT_SIZE + maxi(0, rows - 1) * SKILL_GAP
	_skill_content.custom_minimum_size = Vector2(width, height)
	_ensure_skill_pool(rows * SKILL_COLUMNS)
	_refresh_skills()


func _ensure_skill_pool(size: int) -> void:
	if _skill_slots.size() == size:
		return
	for slot in _skill_slots:
		slot.free()
	_skill_slots.clear()
	for i in size:
		var slot := SKILL_SLOT_SCENE.instantiate() as InventorySkillSlot
		_skill_content.add_child(slot)
		slot.skill_selected.connect(_on_skill_selected)
		_skill_slots.append(slot)


func _refresh_skills() -> void:
	if _skill_content == null:
		return
	var skills := _owned_skills()
	if _selected_skill != null and not skills.has(_selected_skill):
		_selected_skill = null
	for i in _skill_slots.size():
		var slot := _skill_slots[i]
		var local_row := floori(float(i) / float(SKILL_COLUMNS))
		var column := i % SKILL_COLUMNS
		slot.position = Vector2(
			SKILL_PADDING + column * SKILL_STRIDE,
			SKILL_PADDING + local_row * SKILL_STRIDE,
		)
		if i < skills.size():
			slot.bind_skill(i, skills[i])
			slot.set_selected(_selected_skill == skills[i])
		else:
			slot.bind_skill(-1, null)
	_show_skill_details(_selected_skill)


func _owned_skills() -> Array[PlayerSkill]:
	var skills: Array[PlayerSkill] = []
	if _player == null or _player.config == null:
		return skills
	for skill in _player.config.skills:
		if skill != null:
			skills.append(skill)
	return skills


func _on_skill_selected(skill: PlayerSkill) -> void:
	_selected_skill = skill
	_refresh_skills()


func _show_skill_details(skill: PlayerSkill) -> void:
	if _skill_detail_name == null:
		return
	if skill == null:
		_skill_detail_name.text = "SELECT A SKILL"
		_skill_detail_meta.text = ""
		_skill_detail_description.text = "Choose a skill from Owned Skills to see its details."
		return
	var reduction := 0.0
	if _stats != null:
		reduction = _stats.get_stat(Stats.COOLDOWN_REDUCTION)
	var cooldown := skill.effective_cooldown(reduction)
	var kind := "STRIKE"
	if skill is GroundSlamSkill:
		kind = "AREA"
	elif skill is SelfBuffSkill:
		kind = "BUFF"
	_skill_detail_name.text = skill.display_name.to_upper()
	_skill_detail_meta.text = "%s   |   COOLDOWN %.1fs   |   ENERGY %d" % [kind, cooldown, skill.energy_cost]
	_skill_detail_description.text = skill.description
	if _player != null and _player.level < skill.unlock_level:
		_skill_detail_description.text += "\n\nRequires level %d." % skill.unlock_level


func _bind_stats(stats: Stats) -> void:
	if _stats != null and _stats.stats_changed.is_connected(_on_stats_changed):
		_stats.stats_changed.disconnect(_on_stats_changed)
	_stats = stats
	if _stats != null:
		_stats.stats_changed.connect(_on_stats_changed)


func _bind_player(player: Character) -> void:
	if _player != null:
		if _player.health_changed.is_connected(_on_health_changed):
			_player.health_changed.disconnect(_on_health_changed)
		if _player.experience_changed.is_connected(_on_progress_changed):
			_player.experience_changed.disconnect(_on_progress_changed)
		if _player.level_changed.is_connected(_on_level_changed):
			_player.level_changed.disconnect(_on_level_changed)
		if _player.energy_changed.is_connected(_on_energy_changed):
			_player.energy_changed.disconnect(_on_energy_changed)
	_player = player
	if _player != null:
		_player.health_changed.connect(_on_health_changed)
		_player.experience_changed.connect(_on_progress_changed)
		_player.level_changed.connect(_on_level_changed)
		_player.energy_changed.connect(_on_energy_changed)


func _on_health_changed(_current: int, _maximum: int) -> void:
	_refresh_progress()


func _on_progress_changed(_experience: int, _to_next: int) -> void:
	_refresh_progress()


func _on_level_changed(_level: int, _experience: int, _to_next: int) -> void:
	_refresh_progress()
	_refresh_stats()


func _on_energy_changed(_current: float, _maximum: float) -> void:
	_refresh_progress()


func _on_stats_changed() -> void:
	_refresh_stats()


func _refresh_progress() -> void:
	if _player == null:
		return
	_level_label.text = "LV %d" % _player.level
	_apply_progress_bars(_health_bar, _health_label, [
		[_item_health_bar, _item_health_label],
		[_skill_health_bar, _skill_health_label],
	])
	_apply_progress_bars(_energy_bar, _energy_label, [
		[_item_energy_bar, _item_energy_label],
		[_skill_energy_bar, _skill_energy_label],
	])
	_apply_progress_bars(_xp_bar, _xp_label, [
		[_item_xp_bar, _item_xp_label],
		[_skill_xp_bar, _skill_xp_label],
	])


func _apply_progress_bars(stats_bar: TextureProgressBar, stats_label: Label, mirrors: Array) -> void:
	if stats_bar == null or stats_label == null:
		return
	var is_health := stats_bar == _health_bar
	var is_energy := stats_bar == _energy_bar
	var is_xp := stats_bar == _xp_bar
	if is_health:
		stats_bar.max_value = maxf(1.0, float(_player.max_health))
		stats_bar.value = float(_player.current_health)
		stats_label.text = "HP %d / %d" % [_player.current_health, _player.max_health]
	elif is_energy:
		stats_bar.max_value = maxf(1.0, _player.max_energy)
		stats_bar.value = _player.energy
		stats_label.text = "EN %d / %d" % [roundi(_player.energy), roundi(_player.max_energy)]
	elif is_xp:
		var to_next := _player.experience_to_next_level()
		stats_bar.max_value = maxf(1.0, float(to_next))
		stats_bar.value = float(_player.experience) if to_next > 0 else 0.0
		stats_label.text = "XP %d / %d" % [_player.experience, to_next] if to_next > 0 else "XP MAX"
	# mirror to the items and skills pages
	for mirror in mirrors:
		var bar = mirror[0] as TextureProgressBar
		var label = mirror[1] as Label
		if bar == null or label == null:
			continue
		bar.max_value = stats_bar.max_value
		bar.value = stats_bar.value
		label.text = stats_label.text


func _refresh_stats() -> void:
	if _stats == null:
		return
	_set_stat_value(_stat_labels[&"attack"] as Label, _stats.get_stat(Stats.ATTACK), false)
	_set_stat_value(_stat_labels[&"defence"] as Label, _stats.get_stat(Stats.DEFENCE), false)
	_set_stat_value(_stat_labels[&"move_speed"] as Label, _stats.get_stat(Stats.MOVE_SPEED), false)
	_set_stat_value(_stat_labels[&"crit_rate"] as Label, _stats.get_stat(Stats.CRIT_RATE), true)
	_set_stat_value(_stat_labels[&"crit_damage"] as Label, _stats.get_stat(Stats.CRIT_DAMAGE), true)
	_set_stat_value(_stat_labels[&"cooldown_reduction"] as Label, _stats.get_stat(Stats.COOLDOWN_REDUCTION), true)


func _set_stat_value(label: Label, value: float, percent: bool) -> void:
	label.text = "%d%%" % roundi(value * 100.0) if percent else str(roundi(value))


func _refresh_equipment() -> void:
	for i in _equip_buttons.size():
		_update_equip_button(_equip_buttons[i], i)
		_update_equip_button(_item_equip_buttons[i], i)


func _update_equip_button(button: Button, i: int) -> void:
	var index := int(EQUIP_STORAGE[i])
	if index < 0:
		button.icon = null
		button.tooltip_text = EQUIP_LABELS[i]
		return
	var item = _equipped[index]
	button.icon = item.icon if item != null else null
	button.tooltip_text = item.display_name if item != null else EQUIP_LABELS[i]


func _on_equip_item_dropped(visual_index: int, bag_index: int, item: ItemData) -> void:
	if _inventory == null or not (item is EquipmentData):
		return
	var slot_idx := int(EQUIP_STORAGE[visual_index])
	if slot_idx < 0:
		return
	var equipment := item as EquipmentData
	if equipment.equip_slot != EQUIP_ACCEPTS[visual_index]:
		return
	var slots := _inventory.get_slots()
	if bag_index < 0 or bag_index >= slots.size():
		return
	if slots[bag_index]["item"] != equipment:
		return
	var previous = _equipped[slot_idx]
	if previous == equipment:
		return
	_inventory.remove_item(bag_index, 1)
	if previous != null:
		if _stats != null:
			_stats.remove_modifier(previous.id)
		_inventory.add_item(previous, 1)
	_equipped[slot_idx] = equipment
	if _stats != null:
		for mod in equipment.stat_modifiers:
			if mod != null:
				_stats.add_modifier(equipment.id, mod.stat, mod.flat, mod.pct)
	_save_equipped(slot_idx, equipment)
	_refresh_equipment()
	_layout_bag()
	_refresh_stats()


func _save_equipped(slot_idx: int, item: EquipmentData) -> void:
	var progress := get_node_or_null("/root/PlayerProgress")
	if progress == null:
		return
	if slot_idx < progress.equipped.size():
		progress.equipped[slot_idx] = item.resource_path
		progress.save_progress()


func _restore_equipped() -> void:
	if _inventory == null:
		return
	var progress := get_node_or_null("/root/PlayerProgress")
	if progress == null:
		return
	for i in range(EQUIP_GROUPS.size()):
		var path := ""
		if i < progress.equipped.size():
			path = str(progress.equipped[i])
		if path.is_empty():
			continue
		var item = load(path)
		if item == null:
			continue
		var slots := _inventory.get_slots()
		for idx in range(slots.size()):
			if slots[idx]["item"] == item:
				_inventory.remove_item(idx, int(slots[idx]["count"]))
				break
		_equipped[i] = item
		if _stats != null and item is EquipmentData:
			for mod in item.stat_modifiers:
				if mod != null:
					_stats.add_modifier(item.id, mod.stat, mod.flat, mod.pct)
