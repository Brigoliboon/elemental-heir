extends AudioStreamPlayer

const SETTINGS_PATH := "user://settings.cfg"
const MASTER_BUS := 0
const INTRO_STREAM: AudioStream = preload("res://assets/audio/music/intro-bg_loop.wav")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		AudioServer.set_bus_mute(MASTER_BUS, bool(config.get_value("audio", "muted", false)))

	bus = "Master"
	finished.connect(_on_finished)
	play_track(INTRO_STREAM)


func play_track(stream_to_play: AudioStream) -> void:
	if stream_to_play == null:
		return
	if stream != stream_to_play:
		stream = stream_to_play
	if not playing:
		play()


func _on_finished() -> void:
	play()
