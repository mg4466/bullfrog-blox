class_name Board
extends RefCounted

## Pure, renderer-free rules for the Q*bert pyramid.
##
## Everything in this file is a static function or a plain data question: which
## cubes exist, where a cube sits in the world, what a hop does to a cube, which
## way a snake should turn. Nothing here touches a MeshInstance3D, a Tween or the
## scene tree, which is what lets `tests/test_logic.gd` exercise the whole rule
## set headlessly (no window, no GPU).
##
## THE COORDINATE SYSTEM, and why it is three-dimensional
## ------------------------------------------------------
## Every cube is addressed by a Vector3i (x, y, z) with
##     x >= 0, y >= 0, z >= 0 and x + y + z == side - 1
## For the classic 7-row board that sum is 6, so there are 28 cubes: the plane
## x+y+z=6 contains exactly the triangle of a Q*bert pyramid.
##
## Because the sum is constant, the four legal moves never leave the plane:
##     down-right (1, -1, 0)      down-left (0, -1, 1)
##     up-right   (0,  1, -1)     up-left  (-1, 1, 0)
## Each move changes two coordinates and leaves the third alone, so "is this
## cube on the board?" is a single integer test rather than a 2D lookup table.
##
## This is why the board is a Dictionary of Vector3i -> tile instead of a 2D
## array of triangles: the rules stay valid if the board ever grows to a
## ziggurat, a pyramid with bridges, or several stacked layers, because a
## coordinate simply answers "am I in the set?".

## The four hop directions, in the order they are listed in the HUD and tests.
const DOWN_RIGHT := Vector3i(1, -1, 0)
const DOWN_LEFT := Vector3i(0, -1, 1)
const UP_LEFT := Vector3i(-1, 1, 0)
const UP_RIGHT := Vector3i(0, 1, -1)
const DIRECTIONS: Array[Vector3i] = [DOWN_RIGHT, DOWN_LEFT, UP_LEFT, UP_RIGHT]

## Horizontal distance between two cubes on the same row, in world units.
## Cube meshes are 0.85 wide, so 1.0 leaves a visible gutter between them -
## the black outline that makes an isometric board readable.
const TILE_SPACING_X := 1.0
## Depth step between two rows. The camera looks down at 30 degrees, which
## foreshortens depth by sin(30) = 0.5, so the depth step must be twice the
## horizontal step for a cube to project as a square. Getting this ratio wrong
## is what makes a "3D" board look like a pile of overlapping diamonds.
const TILE_SPACING_Z := TILE_SPACING_X / 0.5

## Palette per level, as plain hex strings so this table can be `const`
## (Color() is not allowed in a constant expression). Level 3 and beyond reuse
## the last row; more entries would mean more colours before a new rule kicks in.
const LEVEL_COLORS := [
	["4b3f9e", "f2c94c"],              # level 1: purple -> gold, one hop each
	["1d3f73", "2f9e6f", "f2c94c"],    # level 2: blue -> green -> gold, two hops
	["701a3c", "c9542e", "f2c94c"],    # level 3+: three states that wrap around
]

## How many tiles the board has for a given number of rows.
static func tile_count(rows: int) -> int:
	return rows * (rows + 1) / 2


## Builds the pyramid: every coordinate with non-negative parts summing to
## rows - 1. Returned in a deterministic order (apex first) so tests and the
## level-clear animation can rely on it.
static func pyramid(rows: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var total := rows - 1
	for y in range(rows):
		for x in range(rows - y):
			var z := total - x - y
			out.append(Vector3i(x, y, z))
	return out


## Is this coordinate part of a board of `rows` rows?
static func is_on_board(coord: Vector3i, rows: int) -> bool:
	if coord.x < 0 or coord.y < 0 or coord.z < 0:
		return false
	return coord.x + coord.y + coord.z == rows - 1


## World-space position of a cube's centre. The board lies flat on y = 0 and
## the camera looks down at it isometrically, so the row index (derived from y)
## becomes depth and the in-row index (x) becomes the horizontal offset.
##
## Note this is a *projection*: two different coordinates can never land on the
## same point, because (row, index) is a bijection with the plane.
static func world_pos(coord: Vector3i, rows: int) -> Vector3:
	var row: int = rows - 1 - coord.y      # 0 = apex row, rows-1 = base row
	var index: int = coord.x               # 0 .. row, left to right
	var x := (float(index) - float(row) * 0.5) * TILE_SPACING_X
	var z := (float(row) - float(rows - 1) * 0.5) * TILE_SPACING_Z
	return Vector3(x, 0.0, z)


## State transition for stepping on a cube. Level rules are the original game's:
##   1: one hop completes a cube, and it stays completed.
##   2: two hops (start -> middle -> target), still monotonic.
##   3+: three states that cycle, so over-stepping a finished cube starts it
##       over. This is what stops level 3 from being "walk the board twice".
static func next_state(state: int, level: int, state_count: int) -> int:
	if level >= 3:
		return (state + 1) % state_count
	return mini(state + 1, state_count - 1)


## What a Slick/Sam landing on a cube does: one step backwards, never below 0.
static func reverted_state(state: int) -> int:
	return maxi(state - 1, 0)


## A completed cube is the last state in the palette.
static func is_complete(state: int, state_count: int) -> bool:
	return state == state_count - 1


## Colours for a level, as Color objects. `level` is 1-based.
static func palette_for(level: int) -> Array[Color]:
	var index := clampi(level - 1, 0, LEVEL_COLORS.size() - 1)
	var hexes: Array = LEVEL_COLORS[index]
	var out: Array[Color] = []
	for hex in hexes:
		out.append(Color(hex))
	return out


## Where the two escape discs sit. They are *not* board cubes: their y is -1,
## so they are one hop below the base row, flanking its left and right corners.
## is_on_board() therefore says no, which is exactly what the game wants: the
## player may only reach them by hopping off the edge towards them.
static func disc_coords() -> Array[Vector3i]:
	return [Vector3i(7, -1, 0), Vector3i(0, -1, 7)]


## The neighbours of `coord` that actually exist on `board` (a Dictionary keyed
## by Vector3i). Used by Coily to decide where to hop and by tests.
static func neighbours_on(coord: Vector3i, board: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for dir in DIRECTIONS:
		var next: Vector3i = coord + dir
		if board.has(next):
			out.append(next)
	return out


## Coily's brain: pick the legal neighbour that minimises Manhattan distance to
## the player. It is deliberately greedy and therefore beatable - a perfect
## chaser would make the disc the only escape and the game unplayable.
## Returns `from` when there is nowhere to go, which only happens on the base
## corners, and the caller treats it as "sit still".
static func chase_step(from: Vector3i, target: Vector3i, board: Dictionary) -> Vector3i:
	var best := from
	var best_distance := 1 << 30
	for next in neighbours_on(from, board):
		var distance := absi(next.x - target.x) + absi(next.y - target.y) + absi(next.z - target.z)
		if distance < best_distance:
			best_distance = distance
			best = next
	return best
