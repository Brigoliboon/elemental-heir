extends RefCounted
## Unit tests for the Net autoload helpers: LAN IP filtering, loadout shape,
## and session defaults. Live host/join is covered by tests/mp_sanity.gd.


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_check_lan_filter())
	failures.append_array(_check_autoload_and_loadout(tree))
	failures.append_array(_check_lobby_scene())
	return failures


func _check_lan_filter() -> Array[String]:
	var failures: Array[String] = []
	var script := load("res://scripts/net/net.gd")
	if script == null:
		failures.append("scripts/net/net.gd did not load")
		return failures

	var cases := [
		["192.168.1.20", true],
		["10.0.0.5", true],
		["172.16.0.2", true],
		["172.31.255.1", true],
		["172.15.0.1", false],
		["172.32.0.1", false],
		["127.0.0.1", false],
		["8.8.8.8", false],
		["::1", false],
		["fe80::1", false],
		["not-an-ip", false],
		["", false],
	]
	for entry in cases:
		var address := str(entry[0])
		var expected := bool(entry[1])
		if script.is_lan_ipv4(address) != expected:
			failures.append("is_lan_ipv4(%s) should be %s" % [address, expected])
	return failures


func _check_autoload_and_loadout(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var net := tree.root.get_node_or_null("Net")
	if net == null:
		failures.append("Net autoload is missing")
		return failures

	if net.PROTOCOL_VERSION != 1:
		failures.append("protocol version should start at 1")
	if net.DEFAULT_PORT != 7777:
		failures.append("default port should be 7777")
	if net.MAX_PLAYERS != 2:
		failures.append("max players should be 2")
	if net.is_session_active():
		failures.append("tests must start with no live session")

	var progress := tree.root.get_node_or_null("PlayerProgress")
	if progress != null:
		progress.persistence_enabled = false
		progress.reset(false)
		progress.record(7, 40)
		progress.equipped[0] = "res://resources/items/weapons/swords/default_sword.tres"
		progress.equipped_skills[0] = "res://resources/skills/player/heavy_strike.tres"

	var loadout: Dictionary = net.local_loadout()
	if str(loadout.get("display_name", "")) != "Warrior":
		failures.append("local loadout should use the Warrior display name")
	if int(loadout.get("level", 0)) != 7:
		failures.append("local loadout should read the saved level")
	var equipped: Array = loadout.get("equipped", [])
	if equipped.is_empty() or str(equipped[0]).find("default_sword") < 0:
		failures.append("local loadout should include equipped item paths")
	var skills: Array = loadout.get("equipped_skills", [])
	if skills.is_empty() or str(skills[0]).find("heavy_strike") < 0:
		failures.append("local loadout should include equipped skill paths")

	if progress != null:
		progress.reset(false)
	return failures


func _check_lobby_scene() -> Array[String]:
	var failures: Array[String] = []
	var packed := load("res://scenes/online/online_lobby.tscn") as PackedScene
	if packed == null:
		failures.append("online_lobby.tscn did not load")
		return failures
	var lobby := packed.instantiate() as Control
	if lobby == null:
		failures.append("online_lobby.tscn must instantiate a Control")
		return failures
	for path in [
		"Layout/StatusLabel",
		"Layout/AddressLabel",
		"Layout/HostRow/HostButton",
		"Layout/HostRow/HostPortField",
		"Layout/JoinRow/JoinButton",
		"Layout/JoinRow/JoinIpField",
		"Layout/JoinRow/JoinPortField",
		"Layout/PlayersPanel",
		"Layout/PlayersPanel/LocalPlayerLabel",
		"Layout/PlayersPanel/RemotePlayerLabel",
		"Layout/PlayersPanel/ReadyRow/ReadyButton",
		"Layout/PlayersPanel/ReadyRow/StartButton",
		"Layout/BackButton",
	]:
		if lobby.get_node_or_null(path) == null:
			failures.append("online lobby is missing %s" % path)
	var host := lobby.get_node_or_null("Layout/HostRow/HostButton") as Control
	var join := lobby.get_node_or_null("Layout/JoinRow/JoinButton") as Control
	var ready := lobby.get_node_or_null("Layout/PlayersPanel/ReadyRow/ReadyButton") as Control
	for button in [host, join, ready]:
		if button != null and button.custom_minimum_size.y < 64.0:
			failures.append("%s must stay at least 64 px tall for touch" % button.name)
	lobby.free()
	return failures
