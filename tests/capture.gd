extends Node

## Screenshot harness: boots the real game, plays a couple of seconds of it,
## and writes the framebuffer to a PNG. Used to eyeball the layout without
## sitting through a level.
##
##   godot --path . res://tests/capture.tscn --resolution 1280x800
##
## Not part of the game; kept in tests/ because it is still a test (of what the
## camera sees), and because regenerating the README screenshot should not need
## a human with a screenshot tool.

const OUT_DIR := "res://docs"

var _game: Node


func _ready() -> void:
	# Screenshots for the README should always be the same size, whatever the
	# window manager decides to do with the initial window.
	DisplayServer.window_set_size(Vector2i(1280, 800))
	await get_tree().process_frame

	var packed: PackedScene = load("res://scenes/main.tscn")
	_game = packed.instantiate()
	add_child(_game)

	# Title card.
	await get_tree().create_timer(0.6).timeout
	_save("title")

	# Mid-round: cubes flipped, a couple of enemies on the board.
	_game._start_game()
	await get_tree().create_timer(3.2).timeout
	_save("board")

	get_tree().quit(0)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(path)
	print("capture: %s -> %s (%dx%d) err=%d"
		% [name, ProjectSettings.globalize_path(path), image.get_width(), image.get_height(), err])
