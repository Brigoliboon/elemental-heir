extends RefCounted
## Guards the data-to-sound chain: every enemy that declares an [SfxSet] must have
## real streams behind it, and the entities must actually ask for them at the right
## moments. Silence is the failure mode that is hardest to notice, so this suite
## fails loudly instead of letting an empty slot ship.

const ENEMY_DIR := "res://resources/entities"
const MOB_SCENE := "res://entities/enemies/mob.tscn"
const WARRIOR_SCENE := "res://entities/characters/warrior.tscn"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	_check_enemy_sets(failures)
	_check_idle_bounds(failures)
	_check_variant_pick(failures)
	await _check_mob_triggers(tree, failures)
	await _check_player_triggers(tree, failures)
	return failures


## Any EnemyData carrying an sfx set is expected to speak when it swings and when
## it is hit. Death and idle stay optional: a set may ship before those recordings
## exist, and a missing one is silent rather than an error.
func _check_enemy_sets(failures: Array[String]) -> void:
	for file in _tres_files(ENEMY_DIR):
		var data := load(file)
		if not (data is EnemyData):
			continue
		if data.sfx == null:
			continue
		for kind in ["attack", "hurt", "death", "idle", "block"]:
			if (kind == "attack" or kind == "hurt") and not data.sfx.has_streams(kind):
				failures.append("%s: sfx set %s has no %s stream" % [
					file, data.sfx.resource_path, kind,
				])
			for stream in data.sfx.get(kind):
				if stream != null and stream.get_length() <= 0.0:
					failures.append("%s: sfx %s stream has no audio" % [file, kind])


func _check_idle_bounds(failures: Array[String]) -> void:
	var set := SfxSet.new()
	set.idle_delay_min = 9.0
	set.idle_delay_max = 2.0
	var bounds := set.idle_delay_bounds()
	if bounds.x > bounds.y:
		failures.append("idle delay bounds must not invert when min > max")
	if bounds.x != 2.0 or bounds.y != 9.0:
		failures.append("idle delay bounds should normalize to (2, 9), got %s" % bounds)


## A slot with several variants must cycle through them instead of replaying the
## same one every time, and must never immediately repeat a stream.
func _check_variant_pick(failures: Array[String]) -> void:
	var set := SfxSet.new()
	var first := AudioStreamWAV.new()
	var second := AudioStreamWAV.new()
	set.attack = [first, second]

	var seen: Dictionary = {}
	var previous: AudioStream = null
	var repeated := false
	for i in 40:
		var picked := set.pick(&"attack", previous)
		if picked == previous:
			repeated = true
		seen[picked] = true
		previous = picked
	if repeated:
		failures.append("sfx pick repeated the previous variant")
	if seen.size() != 2:
		failures.append("sfx pick never chose every variant")
	if set.pick(&"hurt") != null:
		failures.append("sfx pick must return null for an empty slot")

	var single := SfxSet.new()
	single.death = [first]
	if single.pick(&"death", first) != first:
		failures.append("sfx pick must return the only variant even when told to avoid it")


func _check_mob_triggers(tree: SceneTree, failures: Array[String]) -> void:
	var scene := load(MOB_SCENE) as PackedScene
	if scene == null:
		failures.append("mob scene did not load")
		return
	var mob := scene.instantiate()
	tree.root.add_child(mob)
	await tree.physics_frame
	mob.set_physics_process(false)

	if mob.sfx == null:
		failures.append("mob did not create an SfxComponent")
		_cleanup(mob)
		return
	if mob.config != null and mob.config.sfx != null and mob.sfx.sfx_set == null:
		failures.append("mob did not bind its EnemyData.sfx set")

	var events: Array[StringName] = []
	mob.sfx.played.connect(func(kind: StringName) -> void: events.append(kind))

	var dummy := Node2D.new()
	tree.root.add_child(dummy)

	mob.player_in_range = dummy
	mob.attack_timer = 0.0
	mob.attack_player()
	await tree.physics_frame
	if not events.has(&"attack"):
		failures.append("mob attack did not fire its attack sound")

	events.clear()
	mob.take_damage(1)
	await tree.physics_frame
	if not events.has(&"hurt"):
		failures.append("mob damage did not fire its hurt sound")

	events.clear()
	mob.take_damage(9999)
	await tree.physics_frame
	if mob.sfx.sfx_set != null and mob.sfx.sfx_set.has_streams(&"death") and not events.has(&"death"):
		failures.append("mob death did not fire its death sound")

	_cleanup(dummy)
	_cleanup(mob)
	await tree.physics_frame


func _check_player_triggers(tree: SceneTree, failures: Array[String]) -> void:
	var scene := load(WARRIOR_SCENE) as PackedScene
	if scene == null:
		failures.append("warrior scene did not load")
		return
	var player := scene.instantiate()
	tree.root.add_child(player)
	await tree.physics_frame

	if player.sfx == null or player.sfx.sfx_set == null:
		failures.append("warrior did not bind a CharacterData.sfx set")
		_cleanup(player)
		return

	var events: Array[StringName] = []
	player.sfx.played.connect(func(kind: StringName) -> void: events.append(kind))

	player.attack()
	await tree.physics_frame
	if not events.has(&"attack"):
		failures.append("warrior swing did not fire its attack sound")

	events.clear()
	player.block(true)
	await tree.physics_frame
	player.take_damage(20)
	await tree.physics_frame
	if not events.has(&"block"):
		failures.append("a blocked hit did not fire the block sound")

	events.clear()
	player.block(false)
	await tree.physics_frame
	player.take_damage(20)
	await tree.physics_frame
	if events.has(&"block"):
		failures.append("an unblocked hit must not play the block sound")

	_cleanup(player)
	await tree.physics_frame


func _tres_files(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	for file in dir.get_files():
		if file.ends_with(".tres"):
			files.append(dir_path.path_join(file))
	return files


func _cleanup(node: Node) -> void:
	if is_instance_valid(node):
		node.free()
