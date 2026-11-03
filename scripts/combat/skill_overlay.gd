class_name SkillOverlay
extends AnimatedSprite2D
## Visual overlay that plays when the owning monster casts a skill whose animation
## matches `trigger_animation`. Auras and trails use this so the body sprite can
## keep its normal clip.

## Skill animation name that starts this overlay. Matches the clip actually
## played, including a MonsterData animation override.
@export var trigger_animation: StringName = &""
## Optional skill id that also starts this overlay. Use when two skills share a
## clip but only one should show the effect.
@export var trigger_skill_id: StringName = &""
## Greater than zero keeps the overlay (usually a looping clip) alive for this many
## seconds. Zero hides it as soon as its clip finishes.
@export var effect_seconds := 0.0


func _ready() -> void:
	visible = false
	animation_finished.connect(_on_animation_finished)
	var node := get_parent()
	while node != null and not node.has_signal("skill_cast"):
		node = node.get_parent()
	if node != null:
		node.skill_cast.connect(_on_skill_cast)


## Flip with the body sprite: child nodes do not inherit `flip_h`, so an aura or
## trail would otherwise keep facing the original direction.
func _process(_delta: float) -> void:
	if not visible:
		return
	var body := get_parent() as AnimatedSprite2D
	if body != null:
		flip_h = body.flip_h
		flip_v = body.flip_v


func _on_skill_cast(skill: MonsterSkill, animation: StringName) -> void:
	if skill == null:
		return
	var matches_animation := trigger_animation != &"" and animation == trigger_animation
	var matches_skill := trigger_skill_id != &"" and skill.id == trigger_skill_id
	if not matches_animation and not matches_skill:
		return
	if sprite_frames == null:
		return
	var clip := trigger_animation
	if clip == &"" or not sprite_frames.has_animation(clip):
		clip = animation
	if not sprite_frames.has_animation(clip):
		return
	visible = true
	play(clip)
	if effect_seconds > 0.0:
		var tree := get_tree()
		if tree != null:
			tree.create_timer(effect_seconds).timeout.connect(_hide)


func _on_animation_finished() -> void:
	if effect_seconds <= 0.0:
		visible = false


func _hide() -> void:
	visible = false
