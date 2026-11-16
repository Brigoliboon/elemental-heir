extends Node
## Two-instance smoke test: host/join, start the arena, spawn both pawns, and
## send one host-authoritative hit. Not part of the main runner.
##   ~/.local/bin/godot --headless --path . res://tests/mp_combat.tscn -- --role=host --port=17778
##   ~/.local/bin/godot --headless --path . res://tests/mp_combat.tscn -- --role=client --port=17778

const ARENA_SCENE := "res://scenes/pvp/pvp_arena.tscn"
const TIMEOUT_SECONDS := 16.0

var _role := "host"
var _port := 17778
var _done := false
var _arena
var _started := false


func _ready() -> void:
	var progress := get_node_or_null("/root/PlayerProgress")
	if progress != null:
		progress.persistence_enabled = false
		progress.reset(false)
		progress.level = 2 if _role_from_args_preview() == "host" else 3
	_parse_args()
	if progress != null:
		progress.level = 2 if _role == "host" else 3
	if _role == "host":
		_run_host()
	else:
		_run_client()
	var timer := get_tree().create_timer(TIMEOUT_SECONDS)
	timer.timeout.connect(_on_timeout)


func _role_from_args_preview() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			return arg.substr(7)
	return "host"


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.substr(7)
		elif arg.begins_with("--port="):
			_port = int(arg.substr(7))


func _run_host() -> void:
	Net.handshake_received.connect(_on_handshake)
	Net.ready_changed.connect(_on_ready_changed)
	Net.match_ready.connect(_on_match_ready)
	var err := Net.host(_port)
	if err != OK:
		_finish(1, "HOST_FAIL %s" % Net.last_error)


func _run_client() -> void:
	await get_tree().create_timer(0.6).timeout
	Net.handshake_received.connect(_on_handshake)
	Net.ready_changed.connect(_on_ready_changed)
	Net.match_ready.connect(_on_match_ready)
	Net.connection_failed.connect(_on_client_failed)
	var err := Net.join("127.0.0.1", _port)
	if err != OK:
		_finish(1, "CLIENT_FAIL %s" % Net.last_error)
		return
	print("CLIENT_CONNECTING %d" % _port)


func _on_handshake(peer_id: int, loadout: Dictionary) -> void:
	if peer_id == Net.local_peer_id():
		return
	if not Net.both_handshook():
		return
	print("%s_HANDSHAKE_OK peer=%d level=%d" % [_role.to_upper(), peer_id, int(loadout.get("level", 0))])
	Net.set_ready(true)


func _on_ready_changed(_peer_id: int, _is_ready: bool) -> void:
	if _role == "host" and Net.both_ready() and not _started:
		_started = true
		print("HOST_BOTH_READY")
		Net.request_start()


func _on_match_ready() -> void:
	if _arena != null:
		return
	var packed := load(ARENA_SCENE) as PackedScene
	if packed == null:
		_finish(1, "%s_FAIL arena did not load" % _role.to_upper())
		return
	_arena = packed.instantiate() as PvpArena
	get_tree().root.add_child(_arena)
	print("%s_ARENA_LOADED" % _role.to_upper())
	_wait_for_pawns_and_hit()


func _wait_for_pawns_and_hit() -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if _arena != null and _arena.all_pawns().size() >= 2:
			break
	var pawns: Array = _arena.all_pawns() if _arena != null else []
	if pawns.size() < 2:
		_finish(1, "%s_FAIL expected 2 pawns, got %d" % [_role.to_upper(), pawns.size()])
		return
	var host_pawn: Character = _arena.pawn_for_peer(1) as Character
	var other_id := 0
	for pawn in pawns:
		var id := int(pawn.get_meta("pvp_peer_id")) if pawn.has_meta("pvp_peer_id") else 0
		if id != 1:
			other_id = id
	var client_pawn: Character = (_arena.pawn_for_peer(other_id) as Character) if other_id != 0 else null
	if host_pawn == null or client_pawn == null:
		_finish(1, "%s_FAIL missing host or client pawn" % _role.to_upper())
		return
	if host_pawn.get_multiplayer_authority() != 1:
		_finish(1, "%s_FAIL host pawn authority is %d" % [_role.to_upper(), host_pawn.get_multiplayer_authority()])
		return
	var loadout_deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < loadout_deadline:
		if host_pawn.level >= 2 and client_pawn.level >= 3:
			break
		await get_tree().process_frame
	print("%s_SPAWN_OK host_level=%d client_level=%d" % [
		_role.to_upper(),
		host_pawn.level,
		client_pawn.level,
	])
	if host_pawn.level < 2 or client_pawn.level < 3:
		_finish(1, "%s_FAIL loadouts not applied (host=%d client=%d)" % [
			_role.to_upper(), host_pawn.level, client_pawn.level
		])
		return
	var before: int = client_pawn.current_health
	if _role == "host":
		# Let the client finish applying loadouts before the first hit lands.
		await get_tree().create_timer(0.4).timeout
		client_pawn.take_hit(12, Vector2.ZERO, host_pawn)
		if _arena.has_method("_replicate_pawn"):
			_arena._replicate_pawn(client_pawn, false)
		print("HOST_HIT_SENT before=%d after=%d" % [before, client_pawn.current_health])
		if client_pawn.current_health >= before:
			_finish(1, "HOST_FAIL hit did not apply on the host")
			return
		await get_tree().create_timer(2.0).timeout
		_finish(0, "HOST_OK")
	else:
		var wait_until := Time.get_ticks_msec() + 5000
		var last_health := before
		var last_count := 0
		while Time.get_ticks_msec() < wait_until:
			await get_tree().process_frame
			var live: Character = _arena.pawn_for_peer(other_id) as Character if _arena != null else null
			last_count = _arena.all_pawns().size() if _arena != null else 0
			if live == null:
				continue
			last_health = live.current_health
			if last_health < before:
				print("CLIENT_HIT_OK before=%d after=%d" % [before, last_health])
				_finish(0, "CLIENT_OK")
				return
		_finish(1, "CLIENT_FAIL health was not replicated (last=%d pawns=%d before=%d)" % [last_health, last_count, before])


func _on_client_failed(reason: String) -> void:
	_finish(1, "CLIENT_FAIL %s" % reason)


func _on_timeout() -> void:
	_finish(1, "%s_FAIL timeout" % _role.to_upper())


func _finish(code: int, message: String) -> void:
	if _done:
		return
	_done = true
	print(message)
	Net.leave()
	get_tree().quit(code)
