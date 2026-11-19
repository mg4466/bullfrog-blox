class_name Hud
extends CanvasLayer

## Arcade-style overlay: a score bar, a centred banner, a controls hint.
##
## Built in code like the rest of the game, so there is no .tscn to keep in sync
## and no theme resource to ship. Everything sits inside a full-rect Control with
## anchors, which means it scales with the window instead of drifting to a corner.

var _score_label: Label
var _level_label: Label
var _lives_label: Label
var _banner_title: Label
var _banner_sub: Label
var _banner_box: VBoxContainer
var _banner_tween: Tween


func _ready() -> void:
	layer = 1

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- top bar: score | level | lives ---------------------------------------
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 28
	top.offset_right = -28
	top.offset_top = 18
	top.offset_bottom = 50
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	_score_label = _make_label(18)
	_level_label = _make_label(18)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lives_label = _make_label(18)
	_lives_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_score_label)
	top.add_child(_expander())
	top.add_child(_level_label)
	top.add_child(_expander())
	top.add_child(_lives_label)

	# --- centre banner --------------------------------------------------------
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)

	_banner_box = VBoxContainer.new()
	_banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_banner_box)

	_banner_title = _make_label(56)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.label_settings.font_color = Color("f2c94c")
	_banner_box.add_child(_banner_title)

	_banner_sub = _make_label(18)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.label_settings.font_color = Color("cfd8ea")
	_banner_box.add_child(_banner_sub)

	# --- bottom hint ----------------------------------------------------------
	var hint := _make_label(14)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -38
	hint.offset_bottom = -14
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.label_settings.font_color = Color(0.72, 0.76, 0.86, 0.75)
	hint.text = "Q/E/A/D  or  numpad 7/9/1/3  to hop   ·   SPACE start   ·   R restart   ·   ESC quit"
	root.add_child(hint)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.font_color = Color("f4f1ea")
	settings.outline_size = maxi(4, font_size / 7)
	settings.outline_color = Color(0, 0, 0, 0.85)
	# Outline rather than a background panel: the board behind the text is
	# bright in places and dark in others, and an outline survives both.
	label.label_settings = settings
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _expander() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func set_stats(score: int, level: int, lives: int, high: int) -> void:
	_score_label.text = "SCORE %06d    HIGH %06d" % [score, maxi(high, score)]
	_level_label.text = "LEVEL %d" % level
	_lives_label.text = "LIVES %d" % maxi(lives, 0)


## Fades a big message in, optionally holding it, then fades it out.
## `duration` of 0 leaves the banner up until something replaces it (score
## screens, game over) - a message that removes itself is only right for
## transient announcements like "LEVEL 2".
func show_banner(title: String, subtitle: String = "", duration: float = 0.0) -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_title.text = title
	_banner_sub.text = subtitle
	_banner_box.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner_box, "modulate:a", 1.0, 0.18)
	if duration > 0.0:
		_banner_tween.tween_interval(duration)
		_banner_tween.tween_property(_banner_box, "modulate:a", 0.0, 0.30)
