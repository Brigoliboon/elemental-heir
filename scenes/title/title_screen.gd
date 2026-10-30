extends Control

const SETTINGS_PATH := "user://settings.cfg"
const MASTER_BUS := 0
const CHECK_URL := "https://www.google.com/generate_204"
const CHECK_INTERVAL := 5.0

const TEX_SOUND_ON_NORMAL: Texture2D = preload("res://assets/ui/title/btn_sound_on_normal.png")
const TEX_SOUND_ON_PRESSED: Texture2D = preload("res://assets/ui/title/btn_sound_on_pressed.png")
const TEX_SOUND_ON_DISABLED: Texture2D = preload("res://assets/ui/title/btn_sound_on_disabled.png")
const TEX_SOUND_OFF_NORMAL: Texture2D = preload("res://assets/ui/title/btn_sound_off_normal.png")
const TEX_SOUND_OFF_PRESSED: Texture2D = preload("res://assets/ui/title/btn_sound_off_pressed.png")
const TEX_SOUND_OFF_DISABLED: Texture2D = preload("res://assets/ui/title/btn_sound_off_disabled.png")

const RIG_TEST_SCENE := "res://scenes/tests/warrior_rig_test.tscn"
const ONLINE_SCENE := "res://scenes/online/online_placeholder.tscn"
const SETTINGS_SCENE := "res://scenes/settings/settings_placeholder.tscn"
const CREDITS_SCENE := "res://scenes/credits/credits_screen.tscn"
const FOREST_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"

@onready var sound_button: TextureButton = %SoundButton
@onready var credits_button: TextureButton = %CreditsButton
@onready var offline_button: TextureButton = %OfflineButton
@onready var online_button: TextureButton = %OnlineButton
@onready var settings_button: TextureButton = %SettingsButton
@onready var no_connection_label: Label = %NoConnectionLabel
@onready var connectivity_check: HTTPRequest = %ConnectivityCheck

var _muted := false
var _online := false
var _check_in_flight := false


func _ready() -> void:
	_load_audio_settings()
	MusicPlayer.play_track(MusicPlayer.INTRO_STREAM)

	sound_button.pressed.connect(_on_sound_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	offline_button.pressed.connect(_on_offline_pressed)
	online_button.pressed.connect(_on_online_pressed)
	settings_button.pressed.connect(_on_settings_pressed)

	online_button.disabled = true
	no_connection_label.visible = false

	connectivity_check.timeout = 4.0
	connectivity_check.request_completed.connect(_on_check_completed)

	var check_timer := Timer.new()
	check_timer.name = "ConnectivityTimer"
	check_timer.wait_time = CHECK_INTERVAL
	check_timer.one_shot = false
	check_timer.autostart = true
	check_timer.timeout.connect(_check_connection)
	add_child(check_timer)

	_check_connection()


func _load_audio_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		_muted = bool(config.get_value("audio", "muted", false))
	_apply_mute()


func _apply_mute() -> void:
	AudioServer.set_bus_mute(MASTER_BUS, _muted)
	sound_button.texture_normal = TEX_SOUND_OFF_NORMAL if _muted else TEX_SOUND_ON_NORMAL
	sound_button.texture_pressed = TEX_SOUND_OFF_PRESSED if _muted else TEX_SOUND_ON_PRESSED
	sound_button.texture_disabled = TEX_SOUND_OFF_DISABLED if _muted else TEX_SOUND_ON_DISABLED


func _on_sound_pressed() -> void:
	_muted = not _muted
	_apply_mute()

	var config := ConfigFile.new()
	config.set_value("audio", "muted", _muted)
	config.save(SETTINGS_PATH)


func _check_connection() -> void:
	if _check_in_flight:
		return
	_check_in_flight = true
	var err := connectivity_check.request(
		CHECK_URL,
		PackedStringArray(["User-Agent: ElementalHeir/1.0", "Cache-Control: no-cache"]),
		HTTPClient.METHOD_GET
	)
	if err != OK:
		_check_in_flight = false
		_set_online(false, true)


func _on_check_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_check_in_flight = false
	var reachable := result == HTTPRequest.RESULT_SUCCESS and (response_code == 204 or response_code == 200)
	_set_online(reachable, true)


func _set_online(online: bool, known: bool) -> void:
	_online = online
	online_button.disabled = not online
	no_connection_label.visible = known and not online


func _on_offline_pressed() -> void:
	get_tree().change_scene_to_file(FOREST_SCENE)


func _on_online_pressed() -> void:
	if _online:
		get_tree().change_scene_to_file(ONLINE_SCENE)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file(SETTINGS_SCENE)


func _on_credits_pressed() -> void:
	get_tree().change_scene_to_file(CREDITS_SCENE)
