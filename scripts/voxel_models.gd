class_name VoxelModels
extends RefCounted

## The cast, drawn as voxel grids instead of imported art.
##
## Every model is a Dictionary of Vector3i -> Color handed to VoxelBuilder, so
## there are no .glb/.png files, no import step and no asset licence to ship.
## That is a real trade-off: these models are deliberately chunky, and editing
## them means editing numbers here rather than opening a modelling tool. The
## upside is that a clone of this repo builds the identical game on any machine.
##
## TWO THINGS THAT MAKE VOXEL BLOBS READ AS CHARACTERS
## --------------------------------------------------
## 1. Resolution. A 3x3x3 ball with its corners cut renders as a plus sign from
##    an isometric camera: every face you can see is a 3x3 square with holes in
##    the corners. Five cells across is the minimum that reads as round; seven is
##    comfortable. That is why the player uses a 0.10 cell and the balls 0.14:
##    same pixel-ish grid, different physical size.
## 2. Silhouette parts. A smooth blob is a rock. A snout, two eyes and two feet
##    are what make it a creature, and they cost four cells.
##
## Grid conventions: +y is up, +z is towards the camera (the direction characters
## face), one cell is `CELL` world units. VoxelBuilder centres models in x/z and
## puts their feet on y = 0, so a node's position is "the point this stands on".

const CELL := 0.09
const BALL_CELL := 0.14
const DISC_CELL := 0.11

# Palette. Named so a would-be modder can recolour the whole game from here.
const FROG := Color("6fae3f")        # bullfrog green
const FROG_DARK := Color("4c7d2a")
const BELLY := Color("d9e8a8")       # pale cream belly
const MOUTH := Color("14200d")
const SCLERA := Color("f2f4dc")
const PUPIL := Color("14160f")
const FOOT := Color("3f6a22")

const BALL_RED := Color("e0402f")
const BALL_HI := Color("ff8266")
const SLICK_GREEN := Color("43b06a")
const SLICK_HI := Color("8fe0a4")

const EGG_SHELL := Color("f2edfa")
const EGG_SPOT := Color("8a3fb0")

const SNAKE := Color("8f42b8")
const SNAKE_DARK := Color("5f2480")
const SNAKE_BELLY := Color("d0a3e6")

const GOLD := Color("ffc93c")
const GOLD_DARK := Color("c9932a")
const DISC_CORE := Color("4fe3d4")

# --- dictionary helpers ------------------------------------------------------

static func _put(grid: Dictionary, cell: Vector3i, colour: Color) -> void:
	grid[cell] = colour


## Fills an inclusive box of cells. Inclusive ranges keep the model code as
## short as the shape it describes: (0,0,0)..(2,2,2) really is a 3x3x3 blob.
static func _fill(grid: Dictionary, from: Vector3i, to: Vector3i, colour: Color) -> void:
	for x in range(from.x, to.x + 1):
		for y in range(from.y, to.y + 1):
			for z in range(from.z, to.z + 1):
				grid[Vector3i(x, y, z)] = colour


## A ball of cells around `centre`, rounded by Euclidean distance.
static func _sphere(grid: Dictionary, centre: Vector3i, radius: float, colour: Color) -> void:
	_ellipsoid(grid, Vector3(centre), Vector3(radius, radius, radius), colour)


## A stretched sphere: the frog is wide and low rather than round, and an
## ellipsoid is the cheapest way to say that in a grid.
static func _ellipsoid(grid: Dictionary, centre: Vector3, radii: Vector3, colour: Color) -> void:
	var rx := int(ceil(radii.x))
	var ry := int(ceil(radii.y))
	var rz := int(ceil(radii.z))
	for x in range(-rx, rx + 1):
		for y in range(-ry, ry + 1):
			for z in range(-rz, rz + 1):
				var nx := float(x) / radii.x
				var ny := float(y) / radii.y
				var nz := float(z) / radii.z
				if nx * nx + ny * ny + nz * nz <= 1.0:
					grid[Vector3i(roundi(centre.x) + x, roundi(centre.y) + y,
						roundi(centre.z) + z)] = colour


## Recolours one horizontal layer of a blob, so a ball catches light on top
## instead of being one flat colour.
static func _highlight_layer(grid: Dictionary, layer: int, colour: Color) -> void:
	for cell in grid.keys():
		if (cell as Vector3i).y == layer:
			grid[cell] = colour


# --- models ------------------------------------------------------------------

## The player: a big, fat bullfrog.
##
## Nine cells across at 0.09 makes it 0.81 units wide on a 0.86 cube - as wide as
## it can be without overhanging, which is the whole joke: this frog is too big
## for the block it is standing on. Squat, a pale belly, a wide dark mouth, heavy
## back feet, and two eyes mounded above the head so the silhouette survives the
## fixed top-down camera.
##
## The body is an ellipsoid, then every feature is painted onto the *outermost*
## cell of its column (_front_cell/_top_cell). Painting fixed coordinates is how
## the first version ended up with its mouth buried inside the body: the surface
## of a blob is not a straight line.
static func player() -> ArrayMesh:
	var grid := {}
	_ellipsoid(grid, Vector3(4.0, 3.0, 3.0), Vector3(4.4, 3.0, 3.7), FROG)

	# Eyes first, so the mounds become part of the silhouette the mouth and belly
	# get painted around.
	for eye_x in [2, 6]:
		# Socket mound, then a two-cell sclera bulging forward, then one pupil.
		_fill(grid, Vector3i(eye_x, 5, 3), Vector3i(eye_x + 1, 6, 4), FROG_DARK)
		_fill(grid, Vector3i(eye_x, 6, 5), Vector3i(eye_x + 1, 6, 6), SCLERA)
		_put(grid, Vector3i(eye_x + 1, 6, 6), PUPIL)

	# Pale belly: paint the front of the lower half.
	for x in range(0, 10):
		for y in range(0, 3):
			var cell := _front_cell(grid, x, y)
			if cell.z > -900:
				grid[cell] = BELLY

	# Haunches: mass at the back corners, so it reads as a sitting frog with
	# folded hind legs rather than a floating head.
	for side in [0, 1, 8, 9]:
		for y in range(1, 3):
			var haunch := _back_cell(grid, side, y)
			# The sentinel is +1000 for a column that does not exist; writing it
			# would put a voxel 90 units behind the model (and the mesh bounds
			# would stretch to match).
			if haunch.z < 900:
				grid[haunch] = FROG_DARK

	# Wide mouth: a dark line across the front of the face, just below the eyes
	# and two cells high at the corners so it curves like a frog's jaw.
	for x in range(2, 8):
		var mouth := _front_cell(grid, x, 3)
		if mouth.z > -900:
			grid[mouth] = MOUTH
	for x in [2, 7]:
		var corner := _front_cell(grid, x, 2)
		if corner.z > -900:
			grid[corner] = MOUTH

	# Heavy back feet, painted on the front of the bottom row and kicked out one
	# cell so they read as feet rather than as the underside of the body.
	for x in [0, 1, 8, 9]:
		var foot := _front_cell(grid, x, 0)
		if foot.z > -900:
			grid[foot] = FOOT
			grid[foot + Vector3i(0, 0, 1)] = FOOT
	# Nostrils, above the mouth.
	for x in [3, 7]:
		var nostril := _front_cell(grid, x, 5)
		if nostril.z > -900:
			grid[nostril] = FROG_DARK
	return VoxelBuilder.build(grid, CELL)


## The rearmost cell of the column (x, y), used to darken the frog's back.
static func _back_cell(grid: Dictionary, x: int, y: int) -> Vector3i:
	var best := Vector3i(x, y, 1000)
	for cell in grid.keys():
		var c: Vector3i = cell
		if c.x == x and c.y == y and c.z < best.z:
			best = c
	return best


## The frontmost cell of the column (x, y): what you actually see from the camera.
static func _front_cell(grid: Dictionary, x: int, y: int) -> Vector3i:
	var best := Vector3i(x, y, -1000)
	for cell in grid.keys():
		var c: Vector3i = cell
		if c.x == x and c.y == y and c.z > best.z:
			best = c
	return best


## A red ball: five cells across with a lit top.
static func ball() -> ArrayMesh:
	var grid := {}
	_sphere(grid, Vector3i(2, 2, 2), 2.45, BALL_RED)
	_highlight_layer(grid, 4, BALL_HI)
	_highlight_layer(grid, 3, BALL_HI.lerp(BALL_RED, 0.55))
	return VoxelBuilder.build(grid, BALL_CELL)


## Slick/Sam: the same sphere as a red ball, but green. Reusing the shape is
## honest to the original, where the difference is colour and behaviour.
static func slick() -> ArrayMesh:
	var grid := {}
	_sphere(grid, Vector3i(2, 2, 2), 2.45, SLICK_GREEN)
	_highlight_layer(grid, 4, SLICK_HI)
	_highlight_layer(grid, 3, SLICK_HI.lerp(SLICK_GREEN, 0.55))
	return VoxelBuilder.build(grid, BALL_CELL)


## Coily before it hatches: a pale egg with a purple band, narrower at the top.
static func egg() -> ArrayMesh:
	var grid := {}
	_fill(grid, Vector3i(0, 0, 0), Vector3i(2, 3, 2), EGG_SHELL)
	_put(grid, Vector3i(1, 4, 1), EGG_SHELL)
	# Round the corners off the two widest layers so it is an egg, not a box.
	for cell in grid.keys():
		var c: Vector3i = cell
		if c.y <= 1 and (c.x == 0 or c.x == 2) and (c.z == 0 or c.z == 2):
			grid.erase(cell)
	_put(grid, Vector3i(0, 2, 2), EGG_SPOT)
	_put(grid, Vector3i(2, 2, 2), EGG_SPOT)
	_put(grid, Vector3i(1, 1, 2), EGG_SPOT)
	return VoxelBuilder.build(grid, CELL + 0.03)


## Coily hatched: a purple snake with a head, eyes and a zig-zag body trailing
## backwards, so it reads as "coming towards you" from the fixed camera.
static func snake() -> ArrayMesh:
	var grid := {}
	# Head: a rounded 3x3 block facing +z.
	_fill(grid, Vector3i(0, 2, 2), Vector3i(2, 4, 4), SNAKE)
	grid.erase(Vector3i(0, 4, 2))
	grid.erase(Vector3i(2, 4, 2))
	_put(grid, Vector3i(0, 3, 5), PUPIL)
	_put(grid, Vector3i(2, 3, 5), PUPIL)
	_fill(grid, Vector3i(0, 2, 5), Vector3i(2, 2, 5), SNAKE_BELLY)
	# Body: alternating offsets along -z, so it coils without any rotation code.
	_fill(grid, Vector3i(0, 1, 0), Vector3i(2, 2, 1), SNAKE_DARK)
	_fill(grid, Vector3i(1, 1, 1), Vector3i(2, 3, 1), SNAKE)
	_fill(grid, Vector3i(0, 2, 0), Vector3i(1, 3, 0), SNAKE)
	_fill(grid, Vector3i(2, 0, 0), Vector3i(2, 1, 0), SNAKE_DARK)
	return VoxelBuilder.build(grid, CELL)


## The escape disc: a flat round pad, gold ring around a cyan core. Round means
## round here - a 7x7 grid with a circular mask, not a cross of cells.
static func disc() -> ArrayMesh:
	var grid := {}
	for x in range(-3, 4):
		for z in range(-3, 4):
			var d := sqrt(float(x * x + z * z))
			if d > 3.4:
				continue
			var colour := GOLD
			if d <= 1.1:
				colour = DISC_CORE
			elif d <= 1.8:
				colour = GOLD_DARK
			grid[Vector3i(x, 0, z)] = colour
	# A thin dark underside gives the pad thickness without doubling the cell
	# count; the builder only emits faces that are actually exposed anyway.
	for x in range(-2, 3):
		for z in range(-2, 3):
			if sqrt(float(x * x + z * z)) <= 2.6:
				grid[Vector3i(x, -1, z)] = GOLD_DARK.darkened(0.45)
	return VoxelBuilder.build(grid, DISC_CELL)
