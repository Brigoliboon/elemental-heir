extends AudioStreamPlayer
## Plays the UI click on button press. Every BaseButton is wired automatically, so
## scenes don't need to hook buttons up individually.

const CLICK_STREAM: AudioStream = preload("res://assets/audio/btn-click.wav")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	stream = CLICK_STREAM
	bus = "Master"
	get_tree().node_added.connect(_on_node_added)
	await get_tree().process_frame
	_wire_existing(get_tree().root)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node as BaseButton)


func _wire_existing(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node as BaseButton)
	for child in node.get_children():
		_wire_existing(child)


func _connect_button(button: BaseButton) -> void:
	if not button.button_down.is_connected(_play_click):
		button.button_down.connect(_play_click)


func _play_click() -> void:
	play()
