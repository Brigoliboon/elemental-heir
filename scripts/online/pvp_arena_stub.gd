extends Control
## Placeholder shown after the host starts a match. The dedicated PvP arena
## (with Boon's background art) arrives in the next multiplayer PR.

const LOBBY_SCENE := "res://scenes/online/online_lobby.tscn"
const TITLE_SCENE := "res://scenes/title/title_screen.tscn"

@onready var status_label: Label = %StatusLabel
@onready var leave_button: Button = %LeaveButton


func _ready() -> void:
	status_label.text = "Match starting — arena coming in the next PR.\nBoth players are connected. Leave returns to the lobby while the session stays up, or disconnects if the host leaves."
	leave_button.pressed.connect(_on_leave_pressed)
	Net.server_disconnected.connect(_on_server_disconnected)
	Net.peer_disconnected.connect(_on_peer_disconnected)


func _exit_tree() -> void:
	if Net.server_disconnected.is_connected(_on_server_disconnected):
		Net.server_disconnected.disconnect(_on_server_disconnected)
	if Net.peer_disconnected.is_connected(_on_peer_disconnected):
		Net.peer_disconnected.disconnect(_on_peer_disconnected)


func _on_leave_pressed() -> void:
	if Net.is_host():
		Net.leave()
		get_tree().change_scene_to_file(TITLE_SCENE)
		return
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _on_peer_disconnected(_peer_id: int) -> void:
	status_label.text = "The other player left. You can return to the lobby and wait, or leave the session."
