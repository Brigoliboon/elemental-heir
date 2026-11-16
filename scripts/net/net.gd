extends Node
## High-level ENet session for 1v1 PvP. Host or join over LAN / direct IP,
## exchange a loadout handshake, then signal when both peers are ready to start.
## Matchplay itself lands in later PRs; this autoload only owns the connection.

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 2
const DEFAULT_DISPLAY_NAME := "Warrior"

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_failed(reason: String)
signal server_disconnected
signal handshake_received(peer_id: int, loadout: Dictionary)
signal ready_changed(peer_id: int, is_ready: bool)
signal match_ready

enum Role { NONE, HOST, CLIENT }

var role := Role.NONE
var port := DEFAULT_PORT
var last_error := ""
## peer_id -> loadout dictionary from the handshake.
var loadouts: Dictionary = {}
## peer_id -> ready flag.
var ready_flags: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_session_active() -> bool:
	# The SceneTree always has an OfflineMultiplayerPeer; that is not a session.
	if role == Role.NONE:
		return false
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func is_host() -> bool:
	return role == Role.HOST and is_session_active()


func is_client() -> bool:
	return role == Role.CLIENT and is_session_active()


func local_peer_id() -> int:
	if not is_session_active():
		return 0
	return multiplayer.get_unique_id()


func connected_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	if not is_session_active():
		return ids
	ids.append(local_peer_id())
	for id in multiplayer.get_peers():
		ids.append(int(id))
	ids.sort()
	return ids


func player_count() -> int:
	return connected_peer_ids().size()


func both_connected() -> bool:
	return player_count() >= MAX_PLAYERS


func both_handshook() -> bool:
	if not both_connected():
		return false
	for id in connected_peer_ids():
		if not loadouts.has(id):
			return false
	return true


func is_peer_ready(peer_id: int) -> bool:
	return bool(ready_flags.get(peer_id, false))


func both_ready() -> bool:
	if not both_handshook():
		return false
	for id in connected_peer_ids():
		if not is_peer_ready(id):
			return false
	return true


func host(listen_port: int = DEFAULT_PORT) -> Error:
	if is_session_active():
		return _fail("Already in a session")
	if listen_port < 1 or listen_port > 65535:
		return _fail("Port must be between 1 and 65535")

	var peer := ENetMultiplayerPeer.new()
	# max_clients is the number of remote peers, so 1 plus the host is 2 players.
	var err := peer.create_server(listen_port, MAX_PLAYERS - 1)
	if err != OK:
		return _fail("Could not host on port %d (error %d)" % [listen_port, err], err)

	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	port = listen_port
	last_error = ""
	_reset_match_state()
	_record_local_loadout()
	return OK


func join(ip: String, listen_port: int = DEFAULT_PORT) -> Error:
	if is_session_active():
		return _fail("Already in a session")
	var address := ip.strip_edges()
	if address.is_empty():
		return _fail("Enter the host's IP address")
	if listen_port < 1 or listen_port > 65535:
		return _fail("Port must be between 1 and 65535")

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, listen_port)
	if err != OK:
		return _fail("Could not connect to %s:%d (error %d)" % [address, listen_port, err], err)

	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	port = listen_port
	last_error = ""
	_reset_match_state()
	return OK


func leave() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null
	role = Role.NONE
	_reset_match_state()


func set_ready(is_ready: bool) -> void:
	if not both_handshook():
		return
	_rpc_set_ready.rpc(is_ready)


func request_start() -> void:
	if not is_host():
		return
	if not both_ready():
		last_error = "Both players must be ready before starting"
		return
	last_error = ""
	_rpc_start_match.rpc()


func local_loadout() -> Dictionary:
	var progress := get_node_or_null("/root/PlayerProgress")
	var level := 1
	var equipped: Array = []
	var skills: Array = []
	if progress != null:
		level = int(progress.level)
		equipped = progress.equipped.duplicate()
		skills = progress.equipped_skills.duplicate()
	return {
		"display_name": DEFAULT_DISPLAY_NAME,
		"level": level,
		"equipped": equipped,
		"equipped_skills": skills,
	}


## RFC1918 IPv4 addresses on this device, excluding loopback and IPv6.
func lan_ipv4_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if is_lan_ipv4(str(address)) and not result.has(str(address)):
			result.append(str(address))
	return _prefer_common_lan(result)


func preferred_lan_ip() -> String:
	var addresses := lan_ipv4_addresses()
	if addresses.is_empty():
		return ""
	return addresses[0]


static func is_lan_ipv4(address: String) -> bool:
	if address.is_empty() or address.contains(":"):
		return false
	var parts := address.split(".")
	if parts.size() != 4:
		return false
	var octets: Array[int] = []
	for part in parts:
		if not part.is_valid_int():
			return false
		var value := int(part)
		if value < 0 or value > 255:
			return false
		octets.append(value)
	var a := octets[0]
	var b := octets[1]
	if a == 10:
		return true
	if a == 192 and b == 168:
		return true
	if a == 172 and b >= 16 and b <= 31:
		return true
	return false


func _prefer_common_lan(addresses: PackedStringArray) -> PackedStringArray:
	var ranked: Array[String] = []
	for address in addresses:
		if address.begins_with("192.168."):
			ranked.append(address)
	for address in addresses:
		if address.begins_with("10.") and not ranked.has(address):
			ranked.append(address)
	for address in addresses:
		if not ranked.has(address):
			ranked.append(address)
	var packed := PackedStringArray()
	for address in ranked:
		packed.append(address)
	return packed


func _fail(reason: String, err: Error = FAILED) -> Error:
	last_error = reason
	connection_failed.emit(reason)
	return err


func _reset_match_state() -> void:
	loadouts.clear()
	ready_flags.clear()


func _record_local_loadout() -> void:
	var id := local_peer_id()
	if id == 0:
		return
	loadouts[id] = local_loadout()
	ready_flags[id] = false


func _send_handshake_to(peer_id: int) -> void:
	if not is_session_active() or peer_id == 0 or peer_id == local_peer_id():
		return
	_rpc_handshake.rpc_id(peer_id, PROTOCOL_VERSION, local_loadout())


func _on_peer_connected(peer_id: int) -> void:
	# The server is notified of a new client. A third peer cannot join because
	# the ENet server was created with a single remote slot.
	peer_connected.emit(peer_id)
	# Defer so ENet finishes adding the peer before the first reliable RPC.
	_send_handshake_to.call_deferred(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	loadouts.erase(peer_id)
	ready_flags.erase(peer_id)
	peer_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	_record_local_loadout()
	_send_handshake_to.call_deferred(1)


func _on_connection_failed() -> void:
	leave()
	_fail("Could not reach the host")


func _on_server_disconnected() -> void:
	leave()
	server_disconnected.emit()


@rpc("any_peer", "reliable")
func _rpc_handshake(version: int, loadout: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	if version != PROTOCOL_VERSION:
		var reason := "Protocol mismatch (theirs %d, ours %d)" % [version, PROTOCOL_VERSION]
		if is_host():
			_rpc_kick.rpc_id(sender, reason)
			multiplayer.multiplayer_peer.disconnect_peer(sender)
		else:
			_fail(reason)
			leave()
		return
	if typeof(loadout) != TYPE_DICTIONARY:
		return
	var first := not loadouts.has(sender)
	loadouts[sender] = loadout
	if first:
		ready_flags[sender] = false
		handshake_received.emit(sender, loadout)


@rpc("any_peer", "reliable", "call_local")
func _rpc_set_ready(is_ready: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = local_peer_id()
	ready_flags[sender] = is_ready
	ready_changed.emit(sender, is_ready)


@rpc("authority", "reliable", "call_local")
func _rpc_start_match() -> void:
	match_ready.emit()


@rpc("authority", "reliable")
func _rpc_kick(reason: String) -> void:
	_fail(reason)
	leave()
