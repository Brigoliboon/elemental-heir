class_name PvpController
extends Node
## Per-pawn multiplayer glue. The owning peer drives movement and sends
## attack/block/skill intents; the host resolves hits and replicates health.
## Remote copies interpolate the exported sync fields.

const INTERP_SPEED := 14.0
const SYNC_INTERVAL := 0.05

@export var sync_x := 0.0
@export var sync_y := 0.0
@export var sync_facing := true
@export var sync_anim := &"idle"
@export var sync_scale := 1.0

var character: Character
var _got_sync := false
var _last_anim := &""

@onready var _peer_id: int = 1


func _ready() -> void:
	character = get_parent() as Character
	if character == null:
		push_error("PvpController must be a child of a Character")
		return
	_peer_id = character.get_multiplayer_authority()
	# Combat RPCs are host-authoritative. Movement authority stays on the
	# Character (and its MultiplayerSynchronizer), which is the owning peer.
	set_multiplayer_authority(1)
	character.configure_for_pvp()
	if character.has_meta("pvp_loadout"):
		character.apply_loadout(character.get_meta("pvp_loadout"))
	_setup_synchronizer()
	if character.is_multiplayer_authority():
		_copy_sync_from_character()
		_got_sync = true


func _setup_synchronizer() -> void:
	if character == null or not is_instance_valid(character):
		return
	var sync := character.get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync == null:
		sync = MultiplayerSynchronizer.new()
		sync.name = "MultiplayerSynchronizer"
		character.add_child(sync)
	sync.replication_interval = SYNC_INTERVAL
	sync.delta_interval = SYNC_INTERVAL
	sync.root_path = NodePath("../PvpController")
	sync.set_multiplayer_authority(_peer_id)
	var config := SceneReplicationConfig.new()
	for prop in ["sync_x", "sync_y", "sync_facing", "sync_anim", "sync_scale"]:
		var path := NodePath(".:%s" % prop)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config


func _has_session() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


func _process(delta: float) -> void:
	if character == null or not is_instance_valid(character):
		return
	if not _has_session():
		return
	if character.is_multiplayer_authority():
		_copy_sync_from_character()
		return
	if not _got_sync:
		if not is_equal_approx(sync_x, 0.0) or not is_equal_approx(sync_y, 0.0):
			_got_sync = true
			character.position = Vector2(sync_x, sync_y)
		else:
			return
	var target := Vector2(sync_x, sync_y)
	var weight := clampf(delta * INTERP_SPEED, 0.0, 1.0)
	character.position = character.position.lerp(target, weight)
	character.set_facing(sync_facing)
	character.set_render_scale(sync_scale)
	if sync_anim != _last_anim and sync_anim != StringName():
		_last_anim = sync_anim
		if character.anim_player != null and character.anim_player.has_animation(sync_anim):
			if character.anim_player.current_animation != sync_anim:
				character.anim_player.play(sync_anim)


func _copy_sync_from_character() -> void:
	sync_x = character.position.x
	sync_y = character.position.y
	sync_facing = character.facing_right
	sync_scale = character.render_scale
	if character.anim_player != null:
		var current := StringName(character.anim_player.current_animation)
		if current != StringName():
			sync_anim = current


func send_attack() -> void:
	if character == null or not character.is_alive():
		return
	if multiplayer.is_server():
		_perform_attack()
	else:
		_rpc_request_attack.rpc_id(1)


func send_block(on: bool) -> void:
	if character == null or not character.is_alive():
		return
	if multiplayer.is_server():
		_perform_block(on)
	else:
		_rpc_request_block.rpc_id(1, on)


func send_skill(slot: int) -> void:
	if character == null or not character.is_alive():
		return
	if multiplayer.is_server():
		_perform_skill(slot)
	else:
		_rpc_request_skill.rpc_id(1, slot)


@rpc("any_peer", "reliable")
func _rpc_request_attack() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _peer_id:
		return
	_perform_attack()


@rpc("any_peer", "reliable")
func _rpc_request_block(on: bool) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _peer_id:
		return
	_perform_block(on)


@rpc("any_peer", "reliable")
func _rpc_request_skill(slot: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _peer_id:
		return
	_perform_skill(slot)


func _perform_attack() -> void:
	_rpc_do_attack.rpc()


func _perform_block(on: bool) -> void:
	_rpc_do_block.rpc(on)


func _perform_skill(slot: int) -> void:
	_rpc_do_skill.rpc(slot)


@rpc("authority", "call_local", "reliable")
func _rpc_do_attack() -> void:
	if character != null:
		character.attack()


@rpc("authority", "call_local", "reliable")
func _rpc_do_block(on: bool) -> void:
	if character != null:
		character.block(on)


@rpc("authority", "call_local", "reliable")
func _rpc_do_skill(slot: int) -> void:
	if character != null:
		character.use_skill(slot)
