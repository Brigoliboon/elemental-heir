class_name SkillButton
extends BaseButton
## Circular HUD button for one [PlayerSkill].
##
## Draws its own frame, icon, cooldown sweep and key hint, so no per-skill scene or
## texture is needed. The hit area is the circle itself, keeping the transparent
## corners from stealing taps aimed at the buttons behind it.

## Optional key label drawn in the lower-right corner ("1", "2", ...).
@export var key_hint := ""
## Frame colour when the skill is ready.
@export var frame_color := Color(0.85, 0.72, 0.5, 1.0)
## Frame colour while on cooldown.
@export var cooldown_color := Color(0.45, 0.38, 0.3, 1.0)

var skill: PlayerSkill
var character: Character

var _icon: Texture2D
var _was_ready := true


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(92, 92)
	pressed.connect(_on_pressed)


func bind(who: Character, what: PlayerSkill, hint := "") -> void:
	character = who
	skill = what
	if hint != "":
		key_hint = hint
	_icon = _circular_icon(skill.icon) if skill != null else null
	tooltip_text = _tooltip()
	queue_redraw()


func _process(_delta: float) -> void:
	if skill == null or character == null:
		return
	var ready := _is_ready()
	if ready != _was_ready:
		_was_ready = ready
	queue_redraw()


## BaseButton only uses a rectangle by default; a circular hit area matches the art.
func _has_point(point: Vector2) -> bool:
	var center := size * 0.5
	return point.distance_to(center) <= minf(size.x, size.y) * 0.5


func _on_pressed() -> void:
	if character == null or skill == null:
		return
	character.cast_skill(skill)


func _is_ready() -> bool:
	if character == null or skill == null:
		return false
	return character.can_cast_skill(skill)


func _tooltip() -> String:
	if skill == null:
		return ""
	var parts: Array[String] = [skill.display_name]
	if skill.description != "":
		parts.append(skill.description)
	parts.append("Cooldown %.0fs" % skill.cooldown)
	if skill.energy_cost > 0:
		parts.append("%d energy" % skill.energy_cost)
	return "\n".join(parts)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 4.0
	if radius <= 0.0:
		return

	var ready := _is_ready()
	var darkened := not ready and character != null and skill != null

	draw_circle(center, radius, Color(0.055, 0.045, 0.035, 0.92))

	if _icon != null:
		var icon_size := radius * 1.28
		var icon_rect := Rect2(center - Vector2(icon_size, icon_size) * 0.5, Vector2(icon_size, icon_size))
		var tint := Color(1.0, 1.0, 1.0, 1.0 if ready else 0.42)
		draw_texture_rect(_icon, icon_rect, false, tint)

	_draw_cooldown(center, radius)
	_draw_frame(center, radius, ready)
	_draw_hint(center, radius)

	if darkened and skill != null and character != null and character.energy < float(skill.energy_cost):
		draw_circle(center, radius, Color(0.15, 0.0, 0.0, 0.18))


func _draw_frame(center: Vector2, radius: float, ready: bool) -> void:
	var border := frame_color if ready else cooldown_color
	draw_arc(center, radius - 1.0, 0.0, TAU, 56, border, 3.0, true)
	var glow := border
	glow.a = 0.25
	draw_arc(center, radius - 4.0, 0.0, TAU, 56, glow, 1.5, true)


func _draw_cooldown(center: Vector2, radius: float) -> void:
	if character == null or skill == null:
		return
	var total := character.cooldown_total(skill)
	if total <= 0.0:
		return
	var left := character.cooldown_left(skill)
	if left <= 0.0:
		return
	var fraction := clampf(left / total, 0.0, 1.0)
	var points := PackedVector2Array([center])
	var steps := 48
	for i in steps + 1:
		var angle := -PI * 0.5 + TAU * fraction * float(i) / float(steps)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, Color(0.0, 0.0, 0.0, 0.66))

	var font := get_theme_default_font()
	if font != null:
		var text := str(ceili(left))
		var font_size := int(radius * 0.55)
		var width := radius * 2.0
		draw_string(
			font,
			center + Vector2(-radius, font_size * 0.35),
			text,
			HORIZONTAL_ALIGNMENT_CENTER,
			width,
			font_size,
			Color(1.0, 0.92, 0.78, 0.95)
		)


func _draw_hint(center: Vector2, radius: float) -> void:
	if key_hint == "":
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := int(maxf(12.0, radius * 0.30))
	var pos := center + Vector2(radius * 0.55, radius * 0.62)
	draw_circle(pos, font_size * 0.72, Color(0.0, 0.0, 0.0, 0.55))
	draw_string(
		font,
		pos + Vector2(-font_size, font_size * 0.36),
		key_hint,
		HORIZONTAL_ALIGNMENT_CENTER,
		font_size * 2.0,
		font_size,
		Color(1.0, 0.94, 0.84, 0.95)
	)


## Cuts the source icon into a circle so a square image cannot poke out of the
## frame. Icons that are already circular on a transparent background are used
## as-is, which avoids copying a large texture on every HUD build.
func _circular_icon(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var w := image.get_width()
	var h := image.get_height()
	var corners := [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]
	var transparent_corners := true
	for corner in corners:
		if image.get_pixel(corner.x, corner.y).a > 0.05:
			transparent_corners = false
			break
	if transparent_corners:
		return texture
	var center := Vector2(w, h) * 0.5
	var radius := minf(center.x, center.y)
	for y in h:
		for x in w:
			if Vector2(x + 0.5, y + 0.5).distance_to(center) > radius:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)
