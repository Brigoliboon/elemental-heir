extends Node
## Two-instance host/join smoke test. Not part of the main runner (one tree
## cannot own both ENet peers). Launch with:
##   ~/.local/bin/godot --headless --path . res://tests/mp_sanity.tscn -- --role=host --port=17777
##   ~/.local/bin/godot --headless --path . res://tests/mp_sanity.tscn -- --role=client --port=17777

const TIMEOUT_SECONDS := 8.0

var _role := "host"
var _port := 17777
var _done := false


func _ready() -> void:
	var progress := get_node_or_null("/root/PlayerProgress")
	if progress != null:
		progress.persistence_enabled = false
	_parse_args()
	if _role == "host":
		_run_host()
	else:
		_run_client()
	var timer := get_tree().create_timer(TIMEOUT_SECONDS)
	timer.timeout.connect(_on_timeout)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.substr(7)
		elif arg.begins_with("--port="):
			_port = int(arg.substr(7))


func _run_host() -> void:
	Net.handshake_received.connect(_on_host_handshake)
	var err := Net.host(_port)
	if err != OK:
		_finish(1, "HOST_FAIL %s" % Net.last_error)
		return
	print("HOST_LISTENING %d" % _port)


func _run_client() -> void:
	# Give the host a moment to bind the port when both start together.
	await get_tree().create_timer(0.6).timeout
	Net.handshake_received.connect(_on_client_handshake)
	Net.connection_failed.connect(_on_client_failed)
	var err := Net.join("127.0.0.1", _port)
	if err != OK:
		_finish(1, "CLIENT_FAIL %s" % Net.last_error)
		return
	print("CLIENT_CONNECTING %d" % _port)


func _on_host_handshake(peer_id: int, loadout: Dictionary) -> void:
	if peer_id == Net.local_peer_id():
		return
	if not Net.both_handshook():
		_finish(1, "HOST_FAIL handshake incomplete")
		return
	var level := int(loadout.get("level", 0))
	print("HOST_HANDSHAKE_OK peer=%d level=%d" % [peer_id, level])
	_finish_after_flush(0, "HOST_OK")


func _on_client_handshake(peer_id: int, loadout: Dictionary) -> void:
	if peer_id == Net.local_peer_id():
		return
	if not Net.both_handshook():
		_finish(1, "CLIENT_FAIL handshake incomplete")
		return
	var level := int(loadout.get("level", 0))
	print("CLIENT_HANDSHAKE_OK peer=%d level=%d" % [peer_id, level])
	# Stay up briefly so the host can receive our handshake before we close.
	_finish_after_flush(0, "CLIENT_OK")


func _on_client_failed(reason: String) -> void:
	_finish(1, "CLIENT_FAIL %s" % reason)


func _on_timeout() -> void:
	_finish(1, "%s_TIMEOUT" % _role.to_upper())


func _finish_after_flush(code: int, message: String) -> void:
	if _done:
		return
	await get_tree().create_timer(0.5).timeout
	_finish(code, message)


func _finish(code: int, message: String) -> void:
	if _done:
		return
	_done = true
	print(message)
	Net.leave()
	get_tree().quit(code)
