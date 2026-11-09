class_name LootPickup
extends Area2D
## A dropped item or pile of gold on the ground.
##
## The player collects it by walking over it (Boon's walk-over auto-pickup
## decision). Full inventories leave the pickup on the ground and show a short
## HUD message instead of silently failing. Uncollected pickups despawn after
## [member despawn_seconds] so a cleared area does not fill up with litter.

signal collected(pickup: LootPickup)
## Emitted when collection is refused, e.g. because the bag is full.
signal collect_blocked(message: String)

const TOAST_GROUP := &"hud_toast"
const DEFAULT_DESPAWN_SECONDS := 60.0
## Longest side of a dropped item's icon, in world pixels, regardless of source art size.
const WORLD_ICON_PIXELS := 28.0

@export var despawn_seconds := DEFAULT_DESPAWN_SECONDS
@export var bob_height := 5.0
@export var bob_seconds := 0.9

## Item carried by this pickup. Null for gold pickups.
var item: ItemData
var count := 1
## Gold amount. 0 for item pickups.
var gold := 0

var _collected := false
var _elapsed := 0.0
var _bob_tween: Tween

@onready var _visual: Node2D = $Visual
@onready var _icon: Sprite2D = $Visual/Icon
@onready var _label: Label = $Visual/Label


func _ready() -> void:
	add_to_group("loot_pickup")
	body_entered.connect(_on_body_entered)
	_refresh_visuals()
	_start_bob()


func setup_item(new_item: ItemData, new_count: int = 1) -> void:
	item = new_item
	count = maxi(1, new_count)
	gold = 0
	if is_node_ready():
		_refresh_visuals()


func setup_gold(amount: int) -> void:
	gold = maxi(1, amount)
	item = null
	count = 1
	if is_node_ready():
		_refresh_visuals()


## Attempts to collect this pickup for `character`. Returns true when the
## pickup was consumed. Kept public so tests and debug tools can collect
## without relying on physics overlap timing.
func collect_by(character: Character) -> bool:
	if _collected or character == null:
		return false
	if gold > 0:
		var progress := get_node_or_null("/root/PlayerProgress")
		if progress == null:
			return false
		progress.add_gold(gold)
		_finish()
		return true
	if item == null:
		return false
	var inventory := character.inventory
	if inventory == null:
		return false
	if not inventory.can_add(item, count):
		_notify("Inventory full")
		return false
	inventory.add_item(item, count)
	_finish()
	return true


func is_collected() -> bool:
	return _collected


func _process(delta: float) -> void:
	if _collected or despawn_seconds <= 0.0:
		return
	_elapsed += delta
	if _elapsed >= despawn_seconds:
		_finish()


func _on_body_entered(body: Node2D) -> void:
	if body is Character:
		collect_by(body as Character)


func _refresh_visuals() -> void:
	if _icon == null or _label == null:
		return
	if gold > 0:
		_icon.visible = false
		_label.text = "%dg" % gold
		_label.add_theme_color_override("font_color", Color(1.0, 0.83, 0.3))
		return
	if item == null:
		_label.text = ""
		_icon.visible = false
		return
	_icon.visible = item.icon != null
	_icon.texture = item.icon
	if item.icon != null:
		# Bag icons range from 16 px art to 128 px UI art; normalise the longest
		# side so every drop reads at the same size on the ground.
		var icon_size := item.icon.get_size()
		var longest := maxf(1.0, maxf(icon_size.x, icon_size.y))
		_icon.scale = Vector2.ONE * (WORLD_ICON_PIXELS / longest)
		_label.text = "x%d" % count if count > 1 else ""
	else:
		_label.text = item.display_name if count <= 1 else "%s x%d" % [item.display_name, count]
	_label.add_theme_color_override("font_color", Color(1, 0.94, 0.84))


func _start_bob() -> void:
	if _visual == null or bob_height <= 0.0 or bob_seconds <= 0.0:
		return
	var base_y := _visual.position.y
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(_visual, "position:y", base_y - bob_height, bob_seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(_visual, "position:y", base_y, bob_seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _notify(message: String) -> void:
	collect_blocked.emit(message)
	var toast := get_tree().get_first_node_in_group(TOAST_GROUP)
	if toast != null and toast.has_method("show_message"):
		toast.call("show_message", message)


func _finish() -> void:
	if _collected:
		return
	_collected = true
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	set_deferred("monitoring", false)
	collected.emit(self)
	queue_free()
