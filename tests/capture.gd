extends Node

## Screenshot harness: boots the real game in a fixed-size SubViewport and
## writes the PNGs used by the README.
##
##   godot --path . res://tests/capture.tscn
##
## The SubViewport is the important part. Rendering into the window means the
## image size is whatever the compositor decided, and `unproject_position`
## disagrees with it, so screenshots come out at odd sizes and every pixel
## measurement is off by the scale factor. A 1280x800 SubViewport is identical on
## every machine, which makes the images reproducible.
##
## Not part of the game; kept in tests/ because it is still a test (of what the
## camera sees), and because regenerating the README shot should not need a human
## with a screenshot tool.

const WIDTH := 1280
const HEIGHT := 800
const OUT_DIR := "res://docs"

var _game: Node
var _viewport: SubViewport


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(WIDTH, HEIGHT)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var packed: PackedScene = load("res://scenes/main.tscn")
	_game = packed.instantiate()
	_viewport.add_child(_game)

	# Title card: board built, banner up, no enemies yet.
	await get_tree().create_timer(0.8).timeout
	await _save("title")

	# Mid-round: some cubes flipped, enemies on the board.
	_game._start_game()
	await get_tree().create_timer(3.4).timeout
	await _save("board")

	get_tree().quit(0)


## `await` is load-bearing: this function waits for the frame to actually be
## drawn, so calling it without awaiting would save the *previous* frame (or
## race the quit). That is how a screenshot ends up showing the level banner
## instead of the title.
func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(path)
	print("capture: %s -> %s (%dx%d) err=%d"
		% [name, ProjectSettings.globalize_path(path), image.get_width(), image.get_height(), err])
