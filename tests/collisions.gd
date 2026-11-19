extends Node

## Contact tests: does anything actually touch anything?
##
##   godot --headless --path . res://tests/collisions.tscn
##
## These exist because a regression here is invisible in the other suites: the
## autopilot clears rounds without ever colliding (it route-plans around the
## board), and the unit tests only cover pure rules. The bug that prompted this
## file made every contact do nothing at all - balls hopped straight through the
## frog - and nothing else noticed.
##
## Each case builds its own enemy and moves it deterministically, so the test
## does not depend on spawn timing or random hops.

const BoardScript = preload("res://scripts/board.gd")

const PHASE_PLAYING := 1
const PHASE_DYING := 2
const PLAYER_TILE := Vector3i(2, 2, 2)

var _game: Node
var _failures := 0


func _ready() -> void:
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_game)
	await get_tree().process_frame
	_game._start_game()
	await get_tree().create_timer(0.3).timeout
	# Stop the scheduled wave and the trickle spawner: this test drives every
	# enemy by hand.
	_game._spawn_queue.clear()
	_game._trickle = 1.0e9

	await _test_ball_is_squashed()
	await _test_ball_kills_the_frog()
	await _test_coily_kills_the_frog()
	await _test_enemy_cannot_hit_a_frog_in_the_air()

	if _failures == 0:
		print("collisions: PASS")
		get_tree().quit(0)
	else:
		printerr("collisions: FAIL (%d)" % _failures)
		get_tree().quit(1)


# --- cases ---------------------------------------------------------------

## Hopping onto a ball squashes it and pays for it.
func _test_ball_is_squashed() -> void:
	_reset()
	var ball := _make_enemy(HopEnemy.KIND_BALL, PLAYER_TILE + BoardScript.DOWN_RIGHT)
	var score_before: int = _game._score
	_game._request_hop(BoardScript.DOWN_RIGHT)
	await get_tree().create_timer(0.5).timeout
	_expect(not ball.alive, "hopping onto a ball squashes it")
	_expect(_game._score > score_before, "squashing pays points (%d -> %d)"
		% [score_before, _game._score])
	_expect(_game._phase == PHASE_PLAYING, "the frog survives landing on a ball")


## A ball landing on the frog kills it.
func _test_ball_kills_the_frog() -> void:
	_reset()
	var lives_before: int = _game._lives
	var ball := _make_enemy(HopEnemy.KIND_BALL, PLAYER_TILE + BoardScript.UP_LEFT)
	_game._move_enemy(ball, PLAYER_TILE)
	await get_tree().create_timer(0.6).timeout
	_expect(_game._phase == PHASE_DYING or _game._lives < lives_before,
		"a ball landing on the frog kills it (phase %d, lives %d)"
		% [_game._phase, _game._lives])
	await _wait_for_respawn()


## Coily landing on the frog kills it too.
func _test_coily_kills_the_frog() -> void:
	_reset()
	var lives_before: int = _game._lives
	var snake := _make_enemy(HopEnemy.KIND_COILY, PLAYER_TILE + BoardScript.DOWN_LEFT)
	snake.hatch()
	_game._move_enemy(snake, PLAYER_TILE)
	await get_tree().create_timer(0.6).timeout
	_expect(_game._phase == PHASE_DYING or _game._lives < lives_before,
		"a hatched Coily landing on the frog kills it (phase %d, lives %d)"
		% [_game._phase, _game._lives])
	await _wait_for_respawn()


## An enemy landing on the cube the frog has already left must not kill it:
## coordinates only update on landing, so this is exactly the "vacated tile"
## case that the collision guards have to get right.
func _test_enemy_cannot_hit_a_frog_in_the_air() -> void:
	_reset()
	var lives_before: int = _game._lives
	var ball := _make_enemy(HopEnemy.KIND_BALL, PLAYER_TILE)
	# Send the frog away, then land the ball on the tile it just left.
	_game._request_hop(BoardScript.UP_RIGHT)
	await get_tree().create_timer(0.05).timeout
	_game._move_enemy(ball, PLAYER_TILE)
	await get_tree().create_timer(0.6).timeout
	_expect(_game._lives == lives_before and _game._phase == PHASE_PLAYING,
		"a ball landing on the vacated cube does not kill the frog (lives %d, phase %d)"
		% [_game._lives, _game._phase])


# --- helpers -------------------------------------------------------------

## Puts the frog back on a known cube with a clean board state.
func _reset() -> void:
	for enemy in _game._enemies.duplicate():
		_game._enemies.erase(enemy)
		(enemy as Node).queue_free()
	_game._phase = PHASE_PLAYING
	_game._player_busy = false
	_game._player_coord = PLAYER_TILE
	_game._player.position = _game._tile_top(PLAYER_TILE)
	_game._player.reset_pose()
	_game._player.scale = Vector3.ONE


## Builds a stationary enemy on `coord`. The hop interval is huge so it never
## moves on its own; each case moves it explicitly.
func _make_enemy(kind: String, coord: Vector3i) -> HopEnemy:
	var enemy := HopEnemy.new()
	enemy.setup(kind, coord, 1.0e9)
	_game._entity_root.add_child(enemy)
	enemy.position = _game._tile_top(coord)
	_game._enemies.append(enemy)
	return enemy


func _wait_for_respawn() -> void:
	# Death animation plus the respawn delay, with slack.
	await get_tree().create_timer(1.8).timeout


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    " + message)
	else:
		_failures += 1
		printerr("  FAIL  " + message)
