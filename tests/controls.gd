extends Node

## Control-scheme test: sends synthetic key events through the same path a real
## keyboard uses, and asserts the player ends up on the expected cube.
##
##   godot --headless --path . res://tests/controls.tscn
##
## Key remapping is exactly the sort of thing that silently breaks after a
## refactor (a shared enum value, a swapped pair), and it cannot be caught by
## calling `_request_hop()` directly - that skips the whole input layer.

const BoardScript = preload("res://scripts/board.gd")

var _game: Node
var _failures := 0


func _ready() -> void:
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_game)
	await get_tree().process_frame

	_expect(_game._phase == 0, "game boots into the READY phase")
	_press(KEY_SPACE)
	await _frames(3)
	_expect(_game._phase == 1, "SPACE starts the game")

	var origin := Vector3i(2, 2, 2)
	# Every direction is legal from the middle of the pyramid, so each case
	# isolates the key mapping from the board edges.
	await _test_key(KEY_D, origin, BoardScript.DOWN_RIGHT, "D hops down-right")
	await _test_key(KEY_A, origin, BoardScript.DOWN_LEFT, "A hops down-left")
	await _test_key(KEY_E, origin, BoardScript.UP_RIGHT, "E hops up-right")
	await _test_key(KEY_Q, origin, BoardScript.UP_LEFT, "Q hops up-left")
	await _test_key(KEY_KP_3, origin, BoardScript.DOWN_RIGHT, "numpad 3 hops down-right")
	await _test_key(KEY_KP_1, origin, BoardScript.DOWN_LEFT, "numpad 1 hops down-left")
	await _test_key(KEY_KP_9, origin, BoardScript.UP_RIGHT, "numpad 9 hops up-right")
	await _test_key(KEY_KP_7, origin, BoardScript.UP_LEFT, "numpad 7 hops up-left")

	if _failures == 0:
		print("controls: PASS")
		get_tree().quit(0)
	else:
		printerr("controls: FAIL (%d)" % _failures)
		get_tree().quit(1)


func _test_key(keycode: int, origin: Vector3i, direction: Vector3i, label: String) -> void:
	# Teleport rather than walk: the test is about the key, not the path here.
	_game._player_coord = origin
	_game._player.position = _game._tile_top(origin)
	_game._player_busy = false
	_press(keycode)
	# Wall-clock, not frames: headless runs uncapped, so ten "frames" can be
	# ten milliseconds. One hop is 0.22 s; wait for it to finish and then some.
	await get_tree().create_timer(0.45).timeout
	_expect(_game._player_coord == origin + direction,
		"%s (coord %s, phase %d, busy %s)" % [label, _game._player_coord, _game._phase, _game._player_busy])


func _press(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    " + message)
	else:
		_failures += 1
		printerr("  FAIL  " + message)
