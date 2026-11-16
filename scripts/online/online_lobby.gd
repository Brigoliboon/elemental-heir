extends Control
## LAN / direct-IP lobby for 1v1 PvP. Host advertises an address; a second
## player joins by IP. When both have handshook, each can Ready and the host
## can start the stub arena (the real arena art lands in the next PR).

const TITLE_SCENE := "res://scenes/title/title_screen.tscn"
const ARENA_SCENE := "res://scenes/pvp/pvp_arena.tscn"
const DEFAULT_PORT := 7777

@onready var status_label: Label = %StatusLabel
@onready var address_label: Label = %AddressLabel
@onready var host_port_field: LineEdit = %HostPortField
@onready var host_button: Button = %HostButton
@onready var join_ip_field: LineEdit = %JoinIpField
@onready var join_port_field: LineEdit = %JoinPortField
@onready var join_button: Button = %JoinButton
@onready var players_panel: Control = %PlayersPanel
@onready var local_player_label: Label = %LocalPlayerLabel
@onready var remote_player_label: Label = %RemotePlayerLabel
@onready var ready_button: Button = %ReadyButton
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	host_port_field.text = str(DEFAULT_PORT)
	join_port_field.text = str(DEFAULT_PORT)
	join_ip_field.placeholder_text = "192.168.x.x"
	_refresh_address_label()
	_set_status("Host a match or join one on your network.")
	players_panel.visible = false
	start_button.visible = false
	ready_button.visible = false

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)

	Net.peer_connected.connect(_on_net_peer_connected)
	Net.peer_disconnected.connect(_on_net_peer_disconnected)
	Net.connection_failed.connect(_on_net_connection_failed)
	Net.server_disconnected.connect(_on_net_server_disconnected)
	Net.handshake_received.connect(_on_handshake_received)
	Net.ready_changed.connect(_on_ready_changed)
	Net.match_ready.connect(_on_match_ready)

	# Returning from the stub arena should still show the live session.
	if Net.is_session_active():
		_refresh_session_ui()


func _exit_tree() -> void:
	if Net.peer_connected.is_connected(_on_net_peer_connected):
		Net.peer_connected.disconnect(_on_net_peer_connected)
	if Net.peer_disconnected.is_connected(_on_net_peer_disconnected):
		Net.peer_disconnected.disconnect(_on_net_peer_disconnected)
	if Net.connection_failed.is_connected(_on_net_connection_failed):
		Net.connection_failed.disconnect(_on_net_connection_failed)
	if Net.server_disconnected.is_connected(_on_net_server_disconnected):
		Net.server_disconnected.disconnect(_on_net_server_disconnected)
	if Net.handshake_received.is_connected(_on_handshake_received):
		Net.handshake_received.disconnect(_on_handshake_received)
	if Net.ready_changed.is_connected(_on_ready_changed):
		Net.ready_changed.disconnect(_on_ready_changed)
	if Net.match_ready.is_connected(_on_match_ready):
		Net.match_ready.disconnect(_on_match_ready)


func _refresh_address_label() -> void:
	var addresses := Net.lan_ipv4_addresses()
	if addresses.is_empty():
		address_label.text = "No LAN IPv4 address found. You can still host; the other device will need this computer's IP."
		return
	if addresses.size() == 1:
		address_label.text = "Your LAN IP: %s" % addresses[0]
		return
	address_label.text = "Your LAN IPs: %s" % ", ".join(addresses)


func _set_status(text: String) -> void:
	status_label.text = text


func _parse_port(field: LineEdit) -> int:
	var raw := field.text.strip_edges()
	if raw.is_empty():
		return DEFAULT_PORT
	if not raw.is_valid_int():
		return -1
	return int(raw)


func _on_host_pressed() -> void:
	var listen_port := _parse_port(host_port_field)
	if listen_port < 1:
		_set_status("Enter a valid port (1–65535).")
		return
	var err := Net.host(listen_port)
	if err != OK:
		_set_status(Net.last_error)
		return
	_set_hosting_controls(true)
	var ip := Net.preferred_lan_ip()
	if ip.is_empty():
		_set_status("Hosting on port %d. Waiting for a challenger… (no LAN IP detected)" % listen_port)
	else:
		_set_status("Hosting at %s:%d. Waiting for a challenger…" % [ip, listen_port])
	_refresh_session_ui()


func _on_join_pressed() -> void:
	var listen_port := _parse_port(join_port_field)
	if listen_port < 1:
		_set_status("Enter a valid port (1–65535).")
		return
	var err := Net.join(join_ip_field.text, listen_port)
	if err != OK:
		_set_status(Net.last_error)
		return
	_set_hosting_controls(true)
	_set_status("Connecting to %s:%d…" % [join_ip_field.text.strip_edges(), listen_port])


func _on_ready_pressed() -> void:
	var me := Net.local_peer_id()
	Net.set_ready(not Net.is_peer_ready(me))
	_refresh_session_ui()


func _on_start_pressed() -> void:
	Net.request_start()
	if Net.last_error != "" and not Net.both_ready():
		_set_status(Net.last_error)


func _on_back_pressed() -> void:
	Net.leave()
	get_tree().change_scene_to_file(TITLE_SCENE)


func _on_net_peer_connected(_peer_id: int) -> void:
	_set_status("Challenger connected. Exchanging loadouts…")
	_refresh_session_ui()


func _on_net_peer_disconnected(_peer_id: int) -> void:
	_set_status("The other player left. Waiting for a new challenger…")
	_refresh_session_ui()


func _on_net_connection_failed(reason: String) -> void:
	_set_hosting_controls(false)
	_set_status(reason)
	_refresh_session_ui()


func _on_net_server_disconnected() -> void:
	_set_hosting_controls(false)
	_set_status("The host disconnected.")
	_refresh_session_ui()


func _on_handshake_received(_peer_id: int, _loadout: Dictionary) -> void:
	if Net.both_handshook():
		_set_status("Both players are in. Ready up when you want to start.")
	_refresh_session_ui()


func _on_ready_changed(_peer_id: int, _is_ready: bool) -> void:
	_refresh_session_ui()


func _on_match_ready() -> void:
	get_tree().change_scene_to_file(ARENA_SCENE)


func _set_hosting_controls(in_session: bool) -> void:
	host_button.disabled = in_session
	join_button.disabled = in_session
	host_port_field.editable = not in_session
	join_ip_field.editable = not in_session
	join_port_field.editable = not in_session


func _refresh_session_ui() -> void:
	var active := Net.is_session_active()
	_set_hosting_controls(active)
	if not active:
		players_panel.visible = false
		ready_button.visible = false
		start_button.visible = false
		return

	players_panel.visible = true
	local_player_label.text = _describe_peer(Net.local_peer_id(), true)
	var remote_id := _remote_peer_id()
	if remote_id == 0:
		remote_player_label.text = "Challenger: waiting…"
	else:
		remote_player_label.text = _describe_peer(remote_id, false)

	var handshook := Net.both_handshook()
	ready_button.visible = handshook
	ready_button.disabled = not handshook
	if handshook:
		ready_button.text = "Unready" if Net.is_peer_ready(Net.local_peer_id()) else "Ready"
	start_button.visible = Net.is_host()
	start_button.disabled = not Net.both_ready()


func _remote_peer_id() -> int:
	var me := Net.local_peer_id()
	for id in Net.connected_peer_ids():
		if id != me:
			return id
	return 0


func _describe_peer(peer_id: int, is_local: bool) -> String:
	var loadout: Dictionary = Net.loadouts.get(peer_id, {})
	var name := str(loadout.get("display_name", Net.DEFAULT_DISPLAY_NAME))
	var level := int(loadout.get("level", 1))
	var ready := "Ready" if Net.is_peer_ready(peer_id) else "Not ready"
	var who := "You" if is_local else "Opponent"
	var role := "Host" if peer_id == 1 else "Challenger"
	return "%s (%s): %s  Lv.%d  — %s" % [who, role, name, level, ready]
