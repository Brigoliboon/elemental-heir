extends AudioStreamPlayer

const SETTINGS_PATH := "user://settings.cfg"
const MASTER_BUS := 0
const MUSIC_STREAM: AudioStream = preload("res://assets/audio/music/intro-bg_loop.wav")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Apply the saved mute state before playback so the title never leaks audio
	# on a muted startup.
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		AudioServer.set_bus_mute(MASTER_BUS, bool(config.get_value("audio", "muted", false)))

	stream = MUSIC_STREAM
	bus = "Master"
	finished.connect(_on_finished)
	play()


func _on_finished() -> void:
	play()
