extends Node

## Headless soak test: boot the real game, play it with an autopilot, then
## deliberately die until the run ends and check that restarting is clean.
##
##   godot --headless --path . res://tests/playthrough.tscn --fixed-fps 60 --quit-after 6000
##
## This is the test that catches what unit tests cannot see: a tween that fires
## after its node was freed, a level-clear timer that never advances, a respawn
## that leaves the player busy forever, a restart that keeps the old score.
##
## It talks to the game's internals on purpose. A public testing API would be
## production code that exists only for this file, and the fields it touches
## (``_phase``, ``_tiles``, ``_request_hop``, ``_start_game``) are the game's
## actual state machine.

const BoardScript = preload("res://scripts/board.gd")

## Phase enum values, mirrored so this file does not depend on game.gd's enum
## being readable before the scene is instantiated.
const PHASE_PLAYING := 1
const PHASE_GAME_OVER := 4

## Where a fall is guaranteed. A base-row cube is the edge of the board, so a
## hop "downhill" from it has no cube to land on - and this pair is chosen so it
## is not one of the two escape discs either, which would carry the player away
## instead of dropping them.
const CLIFF_COORD := Vector3i(3, 0, 3)
const CLIFF_STEP := Vector3i(1, -1, 0)

var _game: Node
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _hop_clock := 0.0
var _deaths := 0
var _last_lives := 3
var _levels_cleared := 0
var _last_level := 1
var _stage := 0
var _stage_clock := 0.0
var _drill_falls := 0
var _restart_ok := false
## Set once the report starts; it is a coroutine (it frees the game and waits a
## frame), so _process must not keep poking a half-freed scene.
var _finished := false

const PLAY_SECONDS := 30.0


func _ready() -> void:
	_rng.seed = 20261119
	var packed: PackedScene = load("res://scenes/main.tscn")
	_game = packed.instantiate()
	add_child(_game)
	_game._start_game()
	_last_lives = _game._lives
	print("autopilot: started")


func _process(delta: float) -> void:
	if _finished:
		return
	_clock += delta
	_stage_clock += delta

	if _game._lives < _last_lives:
		_deaths += 1
		_last_lives = _game._lives
	if _game._level > _last_level:
		_levels_cleared += 1
		_last_level = _game._level
		print("autopilot: cleared a round at %.1fs, now level %d (score %d)"
			% [_clock, _game._level, _game._score])

	match _stage:
		0:
			_play(delta)
			if _clock >= PLAY_SECONDS:
				_begin_death_drill()
		1:
			_death_drill()


# --- stage 0: play for points -------------------------------------------------

func _play(delta: float) -> void:
	if _game._phase != PHASE_PLAYING or _game._player_busy:
		return
	_hop_clock -= delta
	if _hop_clock > 0.0:
		return
	_hop_clock = 0.07
	var dir: Variant = _choose_direction()
	if dir != null:
		_game._request_hop(dir)


## Breadth-first search for the nearest cube that still needs work, then take
## the first step of that path. BFS rather than greedy distance because the
## board is a triangle: "walk downhill towards the target" gets stuck in its
## corners, which is exactly the bug this test found.
func _choose_direction() -> Variant:
	var start: Vector3i = _game._player_coord
	var tiles: Dictionary = _game._tiles

	var frontier: Array[Vector3i] = [start]
	var came_from: Dictionary = {start: start}
	var goal: Variant = null

	while not frontier.is_empty() and goal == null:
		var current: Vector3i = frontier.pop_front()
		for dir in BoardScript.DIRECTIONS:
			var next: Vector3i = current + dir
			if not tiles.has(next) or came_from.has(next):
				continue
			came_from[next] = current
			if not (tiles[next] as BoardTile).is_complete():
				goal = next
				break
			frontier.append(next)

	if goal == null:
		return _random_legal_step(start)

	# Walk the parent chain back to the player: the last cube before start is
	# the step to take now.
	var step: Vector3i = goal
	while came_from[step] != start:
		step = came_from[step]
	return step - start


func _random_legal_step(start: Vector3i) -> Variant:
	var options: Array = []
	for dir in BoardScript.DIRECTIONS:
		if _game._tiles.has(start + dir) or _game._discs.has(start + dir):
			options.append(dir)
	if options.is_empty():
		return null
	return options[_rng.randi() % options.size()]


# --- stage 1: die on purpose, then verify the restart -------------------------

func _begin_death_drill() -> void:
	_stage = 1
	_stage_clock = 0.0
	print("autopilot: death drill at %.1fs (lives %d, score %d)"
		% [_clock, _game._lives, _game._score])


func _death_drill() -> void:
	# One action every 1.8 s: enough for fall -> death -> respawn to complete.
	if _stage_clock < 1.8:
		return
	_stage_clock = 0.0

	if _game._phase == PHASE_GAME_OVER:
		_verify_restart()
		return

	if _game._phase != PHASE_PLAYING or _game._player_busy:
		return

	# Stand on the cliff edge and step into the void.
	_game._player_coord = CLIFF_COORD
	_game._player.position = _game._tile_top(CLIFF_COORD)
	_drill_falls += 1
	print("autopilot: deliberate fall %d (lives before %d)" % [_drill_falls, _game._lives])
	_game._request_hop(CLIFF_STEP)


func _verify_restart() -> void:
	print("autopilot: game over reached after %d deliberate falls (score %d)"
		% [_drill_falls, _game._score])
	var tiles_before: int = _game._tiles.size()
	_game._start_game()
	_restart_ok = (_game._lives == 3 and _game._score == 0 and _game._level == 1
		and _game._tiles.size() == tiles_before and _game._phase == PHASE_PLAYING)
	if _restart_ok:
		print("autopilot: restart is clean (lives 3, score 0, level 1, %d cubes)" % tiles_before)
	else:
		printerr("autopilot: restart did not reset the game")
	_report()


# --- report ------------------------------------------------------------------

func _report() -> void:
	_finished = true
	print("autopilot: %.1fs simulated, %d hops requested" % [_clock, _drill_falls])
	print("autopilot: reached level %d, score %d, %d deaths, %d rounds cleared"
		% [_game._level, _game._score, _deaths, _levels_cleared])

	var complete := 0
	for tile in _game._tiles.values():
		if (tile as BoardTile).is_complete():
			complete += 1

	var ok: bool = (_game._tiles.size() == 28
		and _levels_cleared >= 1
		and _deaths >= 1
		and _restart_ok)
	if ok:
		print("autopilot: PASS (%d cubes, %d complete at rest)" % [_game._tiles.size(), complete])
	else:
		printerr("autopilot: FAIL (levels cleared %d, deaths %d, restart ok %s)"
			% [_levels_cleared, _deaths, _restart_ok])

	# Free the game and let a frame pass before quitting. Quitting with live
	# tweens and scene-tree timers makes Godot print ObjectDB leak warnings at
	# exit, which look alarming in CI even though nothing is actually wrong.
	_game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if ok else 1)
