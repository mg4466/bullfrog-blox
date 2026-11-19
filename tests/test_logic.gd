extends SceneTree

## Headless rule tests: `godot --headless --path . --script res://tests/test_logic.gd`
##
## Deliberately limited to the pure layer (Board, Hop, VoxelBuilder, VoxelModels).
## Anything that needs a window is verified by running the game instead, which
## is why every rule in this project was pushed out of the scene code in the
## first place: the maths is testable, the presentation is eyeballable.

const BoardScript = preload("res://scripts/board.gd")
const HopScript = preload("res://scripts/hop.gd")
const BuilderScript = preload("res://scripts/voxel_builder.gd")
const ModelsScript = preload("res://scripts/voxel_models.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	print("Voxel Q*bert - logic tests")
	_test_pyramid()
	_test_moves()
	_test_projection()
	_test_state_rules()
	_test_palettes()
	_test_hop_maths()
	_test_chase()
	_test_discs()
	_test_voxel_builder()
	_test_voxel_models()

	print("")
	if _failures == 0:
		print("OK: %d checks passed" % _checks)
		quit(0)
	else:
		printerr("FAILED: %d of %d checks" % [_failures, _checks])
		quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("  FAIL  " + message)


# --- board shape -------------------------------------------------------------

func _test_pyramid() -> void:
	print("- pyramid")
	var coords: Array = BoardScript.pyramid(7)
	_check(coords.size() == 28, "7-row pyramid has 28 cubes, got %d" % coords.size())
	_check(BoardScript.tile_count(7) == 28, "tile_count(7) == 28")

	var seen := {}
	for coord in coords:
		var c: Vector3i = coord
		_check(c.x >= 0 and c.y >= 0 and c.z >= 0, "cube %s has a negative axis" % c)
		_check(c.x + c.y + c.z == 6, "cube %s is off the plane" % c)
		_check(not seen.has(c), "cube %s appears twice" % c)
		seen[c] = true

	# Row y has (7 - y) cubes: y is the height above the base, so y=6 is the
	# apex and y=0 is the seven-cube base row. 7 + 6 + ... + 1 = 28.
	for y in range(7):
		var row := 0
		for coord in coords:
			if (coord as Vector3i).y == y:
				row += 1
		_check(row == 7 - y, "row y=%d has %d cubes, expected %d" % [y, row, 7 - y])


func _test_moves() -> void:
	print("- movement")
	var sums := {}
	for dir in BoardScript.DIRECTIONS:
		sums[dir] = 0
	_check(BoardScript.DIRECTIONS.size() == 4, "four hop directions")

	for coord in BoardScript.pyramid(7):
		var c: Vector3i = coord
		for dir in BoardScript.DIRECTIONS:
			var next: Vector3i = c + dir
			sums[dir] += 1
			_check(next.x + next.y + next.z == 6, "move %s leaves the plane" % dir)
			# Leaving the board is legal as a *move* (that is how you die), but
			# the result must then be recognisable as off-board.
			if next.x < 0 or next.y < 0 or next.z < 0:
				_check(not BoardScript.is_on_board(next, 7),
					"off-board cube %s reported as on board" % next)

	_check(not BoardScript.is_on_board(Vector3i(7, -1, 0), 7), "disc coord is off board")
	_check(BoardScript.is_on_board(Vector3i(0, 6, 0), 7), "apex is on board")
	_check(not BoardScript.is_on_board(Vector3i(1, 6, 0), 7), "wrong-sum cube is off board")


func _test_projection() -> void:
	print("- projection")
	var apex := BoardScript.world_pos(Vector3i(0, 6, 0), 7)
	var base_left := BoardScript.world_pos(Vector3i(0, 0, 6), 7)
	var base_right := BoardScript.world_pos(Vector3i(6, 0, 0), 7)
	_check(is_equal_approx(apex.x, 0.0), "apex is horizontally centred")
	_check(base_left.z > apex.z, "base row is nearer the camera than the apex")
	_check(is_equal_approx(base_left.x, -base_right.x), "base row is symmetric")
	_check(is_equal_approx(base_right.x - base_left.x, 6.0 * BoardScript.TILE_SPACING_X),
		"base row spans 6 tile steps")

	# Every cube must land on its own point, otherwise two tiles overlap.
	var points := {}
	var collisions := 0
	for coord in BoardScript.pyramid(7):
		var p := BoardScript.world_pos(coord, 7)
		var key := "%.3f,%.3f" % [p.x, p.z]
		if points.has(key):
			collisions += 1
		points[key] = true
	_check(collisions == 0, "%d cubes projected on top of each other" % collisions)

	# Neighbouring rows are one depth step apart, and hops are consistent.
	var a := BoardScript.world_pos(Vector3i(3, 3, 0), 7)
	var b := BoardScript.world_pos(Vector3i(3, 3, 0) + BoardScript.DOWN_RIGHT, 7)
	_check(is_equal_approx(b.z - a.z, BoardScript.TILE_SPACING_Z), "row step matches spacing")
	_check(b.x > a.x, "down-right moves right on screen")


func _test_state_rules() -> void:
	print("- state rules")
	# Level 1: one hop, then it stays done.
	_check(BoardScript.next_state(0, 1, 2) == 1, "level 1: 0 -> 1")
	_check(BoardScript.next_state(1, 1, 2) == 1, "level 1: completed stays completed")
	# Level 2: two hops, then it stays done.
	_check(BoardScript.next_state(0, 2, 3) == 1, "level 2: 0 -> 1")
	_check(BoardScript.next_state(1, 2, 3) == 2, "level 2: 1 -> 2")
	_check(BoardScript.next_state(2, 2, 3) == 2, "level 2: completed stays completed")
	# Level 3+: cycles, so overstepping is punished.
	_check(BoardScript.next_state(0, 3, 3) == 1, "level 3: 0 -> 1")
	_check(BoardScript.next_state(1, 3, 3) == 2, "level 3: 1 -> 2")
	_check(BoardScript.next_state(2, 3, 3) == 0, "level 3: 2 -> 0")
	_check(BoardScript.next_state(0, 9, 3) == 1, "level 9 uses the level-3 rule")

	_check(BoardScript.reverted_state(2) == 1, "revert: 2 -> 1")
	_check(BoardScript.reverted_state(0) == 0, "revert never goes below 0")

	_check(BoardScript.is_complete(1, 2), "state 1 of 2 is complete")
	_check(not BoardScript.is_complete(0, 2), "state 0 of 2 is not complete")
	_check(BoardScript.is_complete(2, 3), "state 2 of 3 is complete")


func _test_palettes() -> void:
	print("- palettes")
	_check(BoardScript.palette_for(1).size() == 2, "level 1 has two colours")
	_check(BoardScript.palette_for(2).size() == 3, "level 2 has three colours")
	_check(BoardScript.palette_for(3).size() == 3, "level 3 has three colours")
	_check(BoardScript.palette_for(99).size() == 3, "high levels clamp to the last palette")
	var first: Color = BoardScript.palette_for(1)[0]
	var last: Color = BoardScript.palette_for(1)[1]
	_check(first != last, "level 1 start and target colours differ")


# --- movement maths ----------------------------------------------------------

func _test_hop_maths() -> void:
	print("- hop arc")
	var from := Vector3(0, 0, 0)
	var to := Vector3(2, 0, 2)
	var start := HopScript.arc(0.0, from, to, 1.0)
	var middle := HopScript.arc(0.5, from, to, 1.0)
	var finish := HopScript.arc(1.0, from, to, 1.0)
	_check(start.is_equal_approx(from), "hop starts at the origin cube")
	_check(finish.is_equal_approx(to), "hop lands exactly on the target cube")
	_check(is_equal_approx(middle.y, 1.0), "hop peaks at the requested height")
	_check(is_equal_approx(middle.x, 1.0) and is_equal_approx(middle.z, 1.0),
		"hop travels linearly in x/z")

	# The arc must never dip below the start, or a hop would clip through tiles.
	var dipped := false
	for i in range(0, 101):
		var p := HopScript.arc(float(i) / 100.0, from, to, 1.2)
		if p.y < -0.0001:
			dipped = true
	_check(not dipped, "hop never goes below the takeoff height")

	_check(is_equal_approx(HopScript.smoothstep(0.0), 0.0), "smoothstep starts at 0")
	_check(is_equal_approx(HopScript.smoothstep(1.0), 1.0), "smoothstep ends at 1")
	_check(is_equal_approx(HopScript.smoothstep(0.5), 0.5), "smoothstep is symmetric")


func _test_chase() -> void:
	print("- coily chase")
	var board := {}
	for coord in BoardScript.pyramid(7):
		board[coord] = true

	# Aim for a target down-left of a mid-board cube: the greedy step must
	# reduce the Manhattan distance, never increase it.
	var snake := Vector3i(1, 4, 1)
	var target := Vector3i(4, 0, 2)
	var before := absi(snake.x - target.x) + absi(snake.y - target.y) + absi(snake.z - target.z)
	var step := BoardScript.chase_step(snake, target, board)
	var after := absi(step.x - target.x) + absi(step.y - target.y) + absi(step.z - target.z)
	_check(board.has(step), "chase step stays on the board")
	_check(after < before, "chase step gets closer (%d -> %d)" % [before, after])
	_check(step != snake, "chase step moves")

	# Sitting on the target: any neighbour is further away, but it must still
	# return a legal cube rather than null.
	var on_target := BoardScript.chase_step(target, target, board)
	_check(board.has(on_target), "chase from the target still returns a cube")

	# A base corner is the extreme point of the triangle: only one of its four
	# hops stays on the board (up-left for the x=6 corner).
	var corner := Vector3i(6, 0, 0)
	var neighbours := BoardScript.neighbours_on(corner, board)
	_check(neighbours.size() == 1, "base corner has 1 neighbour, got %d" % neighbours.size())

	# A mid-board cube has exactly four.
	var middle := Vector3i(2, 2, 2)
	_check(BoardScript.neighbours_on(middle, board).size() == 4, "mid cube has 4 neighbours")


func _test_discs() -> void:
	print("- discs")
	var discs: Array = BoardScript.disc_coords()
	_check(discs.size() == 2, "two discs")
	for coord in discs:
		var c: Vector3i = coord
		_check(not BoardScript.is_on_board(c, 7), "disc %s must not be a playable cube" % c)
		# A disc is useless if no cube is one hop away from it.
		var reachable := false
		for tile in BoardScript.pyramid(7):
			for dir in BoardScript.DIRECTIONS:
				if (tile as Vector3i) + dir == c:
					reachable = true
		_check(reachable, "disc %s is not one hop from any cube" % c)


# --- meshes ------------------------------------------------------------------

func _test_voxel_builder() -> void:
	print("- voxel builder")
	var single := {Vector3i(0, 0, 0): Color.WHITE}
	var mesh: ArrayMesh = BuilderScript.build(single, 1.0)
	_check(mesh.get_surface_count() == 1, "one voxel makes one surface")
	var vertices := mesh.surface_get_array_len(0)
	_check(vertices == 36, "one voxel is 6 quads = 36 vertices, got %d" % vertices)

	# Two touching voxels hide one face each: 10 faces instead of 12.
	var pair := {Vector3i(0, 0, 0): Color.WHITE, Vector3i(1, 0, 0): Color.RED}
	var pair_mesh: ArrayMesh = BuilderScript.build(pair, 1.0)
	_check(pair_mesh.surface_get_array_len(0) == 60,
		"two touching voxels emit 10 faces = 60 vertices, got %d"
		% pair_mesh.surface_get_array_len(0))

	# The mesh must sit on y=0 and be centred in x/z, which is what makes
	# characters stand on a tile when their node is placed there.
	var bounds := pair_mesh.get_aabb()
	_check(is_equal_approx(bounds.position.y, 0.0), "voxel model floor is y=0")
	_check(is_equal_approx(bounds.position.x, -bounds.end.x), "voxel model is centred in x")
	_check(is_equal_approx(bounds.position.z, -bounds.end.z), "voxel model is centred in z")

	_check(BuilderScript.build({}, 1.0).get_surface_count() == 0, "empty model is empty")


func _test_voxel_models() -> void:
	print("- voxel models")
	var models := {
		"player": ModelsScript.player(),
		"slick": ModelsScript.slick(),
		"ball": ModelsScript.ball(),
		"egg": ModelsScript.egg(),
		"snake": ModelsScript.snake(),
		"disc": ModelsScript.disc(),
	}
	for name in models:
		var mesh: ArrayMesh = models[name]
		_check(mesh.get_surface_count() == 1, "%s model has geometry" % name)
		if mesh.get_surface_count() == 1:
			_check(mesh.surface_get_array_len(0) % 3 == 0, "%s vertex count is triangles" % name)
			var box := mesh.get_aabb()
			_check(box.size.y > 0.05, "%s model has height" % name)
	# Characters must fit on a tile: a model wider than 0.85 would overlap
	# its neighbours and make the board unreadable.
	for name in ["player", "ball", "egg", "snake", "slick"]:
		var mesh: ArrayMesh = models[name]
		_check(mesh.get_aabb().size.x < 0.85, "%s is narrower than a tile" % name)
