class_name PvpArena
extends Node2D
## Dedicated 1v1 PvP arena. Host Start loads this scene on both peers (Net stays
## alive). Two warriors spawn from the handshake loadouts. There are no
## monsters, loot, or XP here.
##
## Background swap: replace `BACKGROUND_PATH` (`assets/backgrounds/pvp/pvp_arena.png`)
## with 1920x1080 art. The Sprite2D node is named `Background` (centered = false,
## bottom-anchored like other areas). `ground_far_px` / `ground_near_px` are
## measured in texture pixels from the top of that image.

const TITLE_SCENE := "res://scenes/title/title_screen.tscn"
const PVP_WARRIOR_SCENE := "res://entities/characters/pvp_warrior.tscn"
const BACKGROUND_PATH := "res://assets/backgrounds/pvp/pvp_arena.png"
const DESIGN_BACKGROUND_SCALE := 1.5
const FEET_OFFSET_LOCAL := Character.FEET_OFFSET_LOCAL
const EXPECTED_BACKGROUND_SIZE := Vector2(1920, 1080)

@export var ground_far_px := 420.0
@export var ground_near_px := 850.0
@export var edge_margin := 110.0
@export var far_character_scale := 1.5
@export var near_character_scale := 2.0
@export var far_zoom := 1.15
@export var near_zoom := 1.0
@export var zoom_follow := 4.0

@onready var background: Sprite2D = $Background
@onready var spawn_host: Marker2D = $SpawnHost
@onready var spawn_challenger: Marker2D = $SpawnChallenger
@onready var pawns_root: Node2D = $Pawns
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var camera: Camera2D = $Camera
@onready var joystick: HudJoystick = $HUD/UI/MoveControls
@onready var attack_button: BaseButton = $HUD/UI/AttackButton
@onready var block_button: BaseButton = $HUD/UI/BlockButton
@onready var skill_buttons: Array[SkillButton] = [
	$HUD/UI/Skill1 as SkillButton,
	$HUD/UI/Skill2 as SkillButton,
	$HUD/UI/Skill3 as SkillButton,
]
@onready var you_label: Label = $HUD/UI/YouHealth
@onready var opponent_label: Label = $HUD/UI/OpponentHealth
@onready var status_label: Label = $HUD/UI/StatusLabel
@onready var leave_button: Button = $HUD/UI/LeaveButton
@onready var result_panel: Control = $HUD/UI/ResultPanel
@onready var result_label: Label = $HUD/UI/ResultPanel/Banner/ResultLabel
@onready var rematch_button: Button = $HUD/UI/ResultPanel/Banner/RematchButton
@onready var result_leave_button: Button = $HUD/UI/ResultPanel/Banner/LeaveButton

var world_width := 1920.0
var ground_far_y := 420.0
var ground_near_y := 850.0
var _feet_y := 0.0
var _local_pawn: Character
var _match_over := false
var _hud_bound := false
var _background_scale := 1.0
## peer_id -> { remaining, maximum, died, knockback } if the hit arrives before setup.
var _pending_combat: Dictionary = {}


func _ready() -> void:
	if spawn_host != null and not spawn_host.has_meta("tex_pos"):
		spawn_host.set_meta("tex_pos", spawn_host.position)
	if spawn_challenger != null and not spawn_challenger.has_meta("tex_pos"):
		spawn_challenger.set_meta("tex_pos", spawn_challenger.position)
	_layout_background()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_on_viewport_resized)
	leave_button.pressed.connect(leave_match)
	result_leave_button.pressed.connect(leave_match)
	rematch_button.pressed.connect(_on_rematch_pressed)
	attack_button.pressed.connect(_on_attack_pressed)
	block_button.button_down.connect(_on_block_button_down)
	block_button.button_up.connect(_on_block_button_up)
	result_panel.visible = false
	spawner.spawn_function = _spawn_pawn
	spawner.add_spawnable_scene(PVP_WARRIOR_SCENE)
	spawner.spawn_path = spawner.get_path_to(pawns_root)
	pawns_root.child_entered_tree.connect(_on_pawn_entered)
	if Net.is_session_active():
		Net.peer_disconnected.connect(_on_peer_left)
		Net.server_disconnected.connect(_on_server_left)
		if not Net.combat_state.is_connected(_on_net_combat_state):
			Net.combat_state.connect(_on_net_combat_state)
		if multiplayer.is_server():
			_spawn_all_when_ready()


func _exit_tree() -> void:
	if Net.peer_disconnected.is_connected(_on_peer_left):
		Net.peer_disconnected.disconnect(_on_peer_left)
	if Net.server_disconnected.is_connected(_on_server_left):
		Net.server_disconnected.disconnect(_on_server_left)
	if Net.combat_state.is_connected(_on_net_combat_state):
		Net.combat_state.disconnect(_on_net_combat_state)


func _spawn_all_when_ready() -> void:
	# Give the client's arena (and its MultiplayerSpawner) a moment to exist
	# after both peers load the scene from match_ready.
	if get_tree() != null:
		await get_tree().create_timer(0.2).timeout
	_spawn_all()


func _spawn_all() -> void:
	if not multiplayer.is_server():
		return
	for peer_id in Net.connected_peer_ids():
		if pawn_for_peer(peer_id) != null:
			continue
		var loadout: Dictionary = {}
		if Net.loadouts.has(peer_id):
			loadout = (Net.loadouts[peer_id] as Dictionary).duplicate(true)
		spawner.spawn({"peer_id": peer_id, "loadout": loadout})


func _spawn_pawn(data: Variant) -> Node:
	var payload: Dictionary = data if data is Dictionary else {}
	var peer_id := int(payload.get("peer_id", 1))
	var packed := load(PVP_WARRIOR_SCENE) as PackedScene
	var pawn := packed.instantiate() as Character
	if pawn == null:
		push_error("Failed to instantiate the PvP warrior")
		return null
	pawn.name = "Pawn_%d" % peer_id
	pawn.set_multiplayer_authority(peer_id)
	var loadout: Dictionary = {}
	if payload.has("loadout") and payload["loadout"] is Dictionary:
		loadout = (payload["loadout"] as Dictionary).duplicate(true)
	elif Net.loadouts.has(peer_id):
		loadout = (Net.loadouts[peer_id] as Dictionary).duplicate(true)
	pawn.set_meta("pvp_peer_id", peer_id)
	pawn.set_meta("pvp_loadout", loadout)
	var feet := _spawn_feet(peer_id)
	var scale := _scale_for_feet(feet.y)
	pawn.position = Vector2(feet.x, feet.y - FEET_OFFSET_LOCAL * scale)
	pawn.z_index = DepthSort.z_for_y(feet.y)
	return pawn


func _on_pawn_entered(node: Node) -> void:
	var pawn := node as Character
	if pawn == null:
		return
	if not pawn.died.is_connected(_on_pawn_died):
		pawn.died.connect(_on_pawn_died.bind(pawn))
	if multiplayer.is_server() and not pawn.damaged.is_connected(_on_pawn_damaged):
		pawn.damaged.connect(_on_pawn_damaged.bind(pawn))
	_setup_pawn.call_deferred(pawn)


func _setup_pawn(pawn: Character) -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	if pawn.has_meta("pvp_setup_done"):
		return
	pawn.set_meta("pvp_setup_done", true)
	pawn.configure_for_pvp()
	var peer_id := int(pawn.get_meta("pvp_peer_id")) if pawn.has_meta("pvp_peer_id") else 0
	var loadout: Dictionary = {}
	if pawn.has_meta("pvp_loadout") and pawn.get_meta("pvp_loadout") is Dictionary:
		loadout = pawn.get_meta("pvp_loadout")
	elif Net.loadouts.has(peer_id):
		loadout = Net.loadouts[peer_id]
	var already_hurt := pawn.max_health > 0 and pawn.current_health < pawn.max_health
	var kept_health := pawn.current_health
	if not loadout.is_empty():
		pawn.apply_loadout(loadout)
	if already_hurt:
		var restored := mini(kept_health, pawn.max_health)
		if pawn.health != null and restored > 0:
			pawn.health.set_current_health(restored)
	if _pending_combat.has(peer_id):
		var pending: Dictionary = _pending_combat[peer_id]
		_pending_combat.erase(peer_id)
		pawn.apply_replicated_hit(
			int(pending.get("remaining", pawn.current_health)),
			int(pending.get("maximum", pawn.max_health)),
			bool(pending.get("died", false)),
			pending.get("knockback", Vector2.ZERO),
		)
	var feet := _spawn_feet(peer_id) if peer_id != 0 else Vector2(pawn.position.x, pawn.get_feet_y())
	_apply_depth_to(pawn, feet)
	pawn.set_facing(peer_id == 1)
	_try_bind_local_hud()


func _try_bind_local_hud() -> void:
	var local_id := Net.local_peer_id()
	var pawn := pawn_for_peer(local_id)
	if pawn == null or _hud_bound:
		return
	_local_pawn = pawn
	_feet_y = pawn.get_feet_y()
	_bind_skill_buttons(pawn)
	_hud_bound = true
	_refresh_health_labels()


func _bind_skill_buttons(pawn: Character) -> void:
	for i in skill_buttons.size():
		var button := skill_buttons[i]
		if button == null:
			continue
		if button.pressed.is_connected(button._on_pressed):
			button.pressed.disconnect(button._on_pressed)
		var skill := pawn.skill_in_slot(i)
		button.bind(pawn, skill, str(i + 1))
		if not button.pressed.is_connected(_on_skill_pressed):
			button.pressed.connect(_on_skill_pressed.bind(i))


func pawn_for_peer(peer_id: int) -> Character:
	if pawns_root == null:
		return null
	return pawns_root.get_node_or_null("Pawn_%d" % peer_id) as Character


func all_pawns() -> Array[Character]:
	var result: Array[Character] = []
	if pawns_root == null:
		return result
	for child in pawns_root.get_children():
		var pawn := child as Character
		if pawn != null:
			result.append(pawn)
	return result


func _process(delta: float) -> void:
	_refresh_health_labels()
	_apply_depth_to_remotes()
	if _match_over or _local_pawn == null or not _local_pawn.is_alive():
		_follow_camera(delta)
		return
	if not is_instance_valid(_local_pawn):
		return
	var direction: Vector2 = joystick.direction if joystick != null else Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0
	direction = direction.limit_length(1.0)
	_move_local_pawn(direction, delta)
	_follow_camera(delta)


func _move_local_pawn(direction: Vector2, delta: float) -> void:
	if not Net.is_session_active() or not _local_pawn.is_multiplayer_authority():
		return
	var before := _local_pawn.position
	var old_feet := Vector2(before.x, _feet_y)
	_local_pawn.move_2d(direction, delta)
	var new_feet := Vector2(_local_pawn.position.x, _feet_y + _local_pawn.position.y - before.y)
	new_feet.y = clampf(new_feet.y, ground_far_y, ground_near_y)
	new_feet.x = clampf(new_feet.x, edge_margin, maxf(edge_margin, world_width - edge_margin))
	_feet_y = new_feet.y
	_apply_depth_to(_local_pawn, new_feet)


func _apply_depth_to(pawn: Character, feet: Vector2) -> void:
	var s := _scale_for_feet(feet.y)
	pawn.set_render_scale(s)
	pawn.position = Vector2(feet.x, feet.y - FEET_OFFSET_LOCAL * s)
	pawn.z_index = DepthSort.z_for_y(feet.y)


func _apply_depth_to_remotes() -> void:
	for pawn in all_pawns():
		if pawn == _local_pawn:
			continue
		var feet_y := pawn.get_feet_y()
		pawn.set_render_scale(_scale_for_feet(feet_y))
		pawn.z_index = DepthSort.z_for_y(feet_y)


func _follow_camera(delta: float) -> void:
	if camera == null:
		return
	var target := Vector2(world_width * 0.5, get_viewport_rect().size.y * 0.5)
	var depth := 0.5
	if _local_pawn != null and is_instance_valid(_local_pawn):
		var feet_y := _local_pawn.get_feet_y()
		var s := _local_pawn.render_scale
		target = Vector2(_local_pawn.position.x, feet_y - FEET_OFFSET_LOCAL * s * 0.5)
		depth = _depth_ratio(feet_y)
	var target_zoom := lerpf(far_zoom, near_zoom, depth)
	var z := lerpf(camera.zoom.x, target_zoom, clampf(zoom_follow * delta, 0.0, 1.0))
	camera.zoom = Vector2(z, z)
	camera.position = target


func _scale_for_feet(feet_y: float) -> float:
	var depth_scale := lerpf(far_character_scale, near_character_scale, _depth_ratio(feet_y))
	return depth_scale * maxf(1.0, _background_scale / DESIGN_BACKGROUND_SCALE)


func _depth_ratio(feet_y: float) -> float:
	if is_equal_approx(ground_near_y, ground_far_y):
		return 0.5
	return clampf((feet_y - ground_far_y) / (ground_near_y - ground_far_y), 0.0, 1.0)


func _spawn_feet(peer_id: int) -> Vector2:
	var marker := spawn_host if peer_id == 1 else spawn_challenger
	if marker != null:
		var y := clampf(marker.position.y, ground_far_y, ground_near_y)
		return Vector2(marker.position.x, y)
	var x := edge_margin * 3.0 if peer_id == 1 else world_width - edge_margin * 3.0
	return Vector2(x, lerpf(ground_far_y, ground_near_y, 0.55))


func _layout_background() -> void:
	var view := get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var texture := background.texture if background != null else null
	if texture == null:
		var loaded := load(BACKGROUND_PATH) as Texture2D
		if loaded != null and background != null:
			background.texture = loaded
			texture = loaded
	if texture == null or background == null:
		world_width = view.x
		ground_far_y = view.y * 0.4
		ground_near_y = view.y * 0.85
		_background_scale = 1.0
		return
	var tex_size := texture.get_size()
	var bg_scale := maxf(1.0, maxf(view.y / tex_size.y, view.x / tex_size.x))
	background.centered = false
	background.scale = Vector2(bg_scale, bg_scale)
	background.position = Vector2(0.0, view.y - tex_size.y * bg_scale)
	_background_scale = bg_scale
	world_width = tex_size.x * bg_scale
	ground_far_y = background.position.y + ground_far_px * bg_scale
	ground_near_y = background.position.y + ground_near_px * bg_scale
	if ground_near_y < ground_far_y:
		var tmp := ground_far_y
		ground_far_y = ground_near_y
		ground_near_y = tmp
	if camera != null:
		camera.limit_left = 0
		camera.limit_right = int(world_width)
		camera.limit_top = int(background.position.y)
		camera.limit_bottom = int(view.y)
	_layout_spawn_markers(tex_size, bg_scale)


func _layout_spawn_markers(tex_size: Vector2, bg_scale: float) -> void:
	# Markers are authored in texture pixels so they stay put when the image scales.
	if spawn_host != null and spawn_host.has_meta("tex_pos"):
		var pos: Vector2 = spawn_host.get_meta("tex_pos")
		spawn_host.position = background.position + pos * bg_scale
	elif spawn_host != null:
		spawn_host.position = Vector2(world_width * 0.22, lerpf(ground_far_y, ground_near_y, 0.55))
	if spawn_challenger != null and spawn_challenger.has_meta("tex_pos"):
		var pos_b: Vector2 = spawn_challenger.get_meta("tex_pos")
		spawn_challenger.position = background.position + pos_b * bg_scale
	elif spawn_challenger != null:
		spawn_challenger.position = Vector2(world_width * 0.78, lerpf(ground_far_y, ground_near_y, 0.55))
	# Silence unused warning when tex_size is only needed for docs / future art.
	if tex_size.x <= 0.0:
		pass


func _on_viewport_resized() -> void:
	_layout_background()
	if _local_pawn != null and is_instance_valid(_local_pawn):
		_feet_y = clampf(_local_pawn.get_feet_y(), ground_far_y, ground_near_y)
		_apply_depth_to(_local_pawn, Vector2(_local_pawn.position.x, _feet_y))


func _refresh_health_labels() -> void:
	if you_label == null:
		return
	var local_id := Net.local_peer_id()
	var you := pawn_for_peer(local_id) if local_id != 0 else _local_pawn
	if you != null:
		you_label.text = "You  %d / %d" % [you.current_health, you.max_health]
	var opponent: Character = null
	for pawn in all_pawns():
		if pawn != you:
			opponent = pawn
			break
	if opponent_label != null:
		if opponent != null:
			opponent_label.text = "Opponent  %d / %d" % [opponent.current_health, opponent.max_health]
		else:
			opponent_label.text = "Opponent  —"


func _on_attack_pressed() -> void:
	_local_controller_send_attack()


func _on_block_button_down() -> void:
	_local_controller_send_block(true)


func _on_block_button_up() -> void:
	_local_controller_send_block(false)


func _on_skill_pressed(slot: int) -> void:
	var controller := _local_controller()
	if controller != null:
		controller.send_skill(slot)


func _unhandled_input(event: InputEvent) -> void:
	if _match_over or _local_pawn == null:
		return
	if event is InputEventKey and not event.echo:
		var slot := int(event.keycode) - KEY_1
		if event.pressed and slot >= 0 and slot < skill_buttons.size():
			_on_skill_pressed(slot)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_J:
			if event.pressed:
				_local_controller_send_attack()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_K or event.keycode == KEY_SHIFT:
			_local_controller_send_block(event.pressed)
			get_viewport().set_input_as_handled()


func _local_controller() -> PvpController:
	if _local_pawn == null or not is_instance_valid(_local_pawn):
		return null
	return _local_pawn.get_node_or_null("PvpController") as PvpController


func _local_controller_send_attack() -> void:
	var controller := _local_controller()
	if controller != null:
		controller.send_attack()


func _local_controller_send_block(on: bool) -> void:
	var controller := _local_controller()
	if controller != null:
		controller.send_block(on)


func _on_pawn_damaged(_amount: int, pawn: Character) -> void:
	_replicate_pawn(pawn, false)


func _replicate_pawn(pawn: Character, died_now: bool) -> void:
	if not multiplayer.is_server() or pawn == null or not is_instance_valid(pawn):
		return
	var peer_id := int(pawn.get_meta("pvp_peer_id")) if pawn.has_meta("pvp_peer_id") else 0
	Net.broadcast_combat_state(peer_id, pawn.current_health, pawn.max_health, died_now, pawn.knockback_velocity)


func _on_net_combat_state(peer_id: int, remaining: int, maximum: int, died_now: bool, knockback: Vector2) -> void:
	var pawn := pawn_for_peer(peer_id)
	if pawn == null:
		_pending_combat[peer_id] = {
			"remaining": remaining,
			"maximum": maximum,
			"died": died_now,
			"knockback": knockback,
		}
		return
	pawn.apply_replicated_hit(remaining, maximum, died_now, knockback)


func _on_pawn_died(pawn: Character) -> void:
	if multiplayer.is_server():
		_replicate_pawn(pawn, true)
	if _match_over:
		return
	if not multiplayer.is_server():
		# Host decides the winner; clients wait for the result RPC.
		return
	var winner: Character = null
	for other in all_pawns():
		if other != pawn and other.is_alive():
			winner = other
			break
	var winner_peer := int(winner.get_meta("pvp_peer_id")) if winner != null and winner.has_meta("pvp_peer_id") else 0
	_rpc_show_result.rpc(winner_peer)


@rpc("authority", "call_local", "reliable")
func _rpc_show_result(winner_peer: int) -> void:
	_match_over = true
	result_panel.visible = true
	rematch_button.visible = multiplayer.is_server()
	var local_id := Net.local_peer_id()
	if winner_peer == 0:
		result_label.text = "Draw"
	elif winner_peer == local_id:
		result_label.text = "Victory"
	else:
		result_label.text = "Defeat"
	if status_label != null:
		status_label.text = result_label.text


func _on_rematch_pressed() -> void:
	if not multiplayer.is_server() or not _match_over:
		return
	_rpc_rematch.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_rematch() -> void:
	_match_over = false
	result_panel.visible = false
	if status_label != null:
		status_label.text = ""
	for pawn in all_pawns():
		var peer_id := int(pawn.get_meta("pvp_peer_id")) if pawn.has_meta("pvp_peer_id") else 1
		pawn.revive()
		var feet := _spawn_feet(peer_id)
		_apply_depth_to(pawn, feet)
		pawn.set_facing(peer_id == 1)
		if multiplayer.is_server():
			_replicate_pawn(pawn, false)
	if _local_pawn != null and is_instance_valid(_local_pawn):
		_feet_y = _local_pawn.get_feet_y()
	_refresh_health_labels()


func _on_peer_left(_peer_id: int) -> void:
	if _match_over:
		return
	_match_over = true
	result_panel.visible = true
	rematch_button.visible = false
	result_label.text = "Opponent left"
	if status_label != null:
		status_label.text = result_label.text


func _on_server_left() -> void:
	_on_peer_left(1)


func leave_match() -> void:
	Net.leave()
	get_tree().change_scene_to_file(TITLE_SCENE)
