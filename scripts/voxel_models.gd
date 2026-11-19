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

const CELL := 0.10
const BALL_CELL := 0.14
const DISC_CELL := 0.11

# Palette. Named so a would-be modder can recolour the whole game from here.
const BODY := Color("e8701f")        # Q*bert orange
const HEAD := Color("ff9a3c")
const NOSE := Color("d8571f")
const EYE := Color("1a1626")
const FOOT := Color("a83d12")

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
	var r := int(ceil(radius))
	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			for z in range(-r, r + 1):
				if Vector3(x, y, z).length() <= radius:
					grid[centre + Vector3i(x, y, z)] = colour


## Recolours one horizontal layer of a blob, so a ball catches light on top
## instead of being one flat colour.
static func _highlight_layer(grid: Dictionary, layer: int, colour: Color) -> void:
	for cell in grid.keys():
		if (cell as Vector3i).y == layer:
			grid[cell] = colour


# --- models ------------------------------------------------------------------

## The player: an orange creature with a big snout, two eyes and two feet.
## Seven cells across at 0.10 makes it 0.70 units wide - chunky on a 0.86 cube,
## and round enough that the silhouette reads as a head rather than a box.
static func player() -> ArrayMesh:
	var grid := {}
	_sphere(grid, Vector3i(3, 3, 3), 3.35, BODY)

	# Flatten the underside so it sits on a cube instead of balancing on a point.
	for cell in grid.keys():
		if (cell as Vector3i).y < 1:
			grid.erase(cell)

	# The upper third is lighter, which reads as a separate mass - a head.
	for cell in grid.keys():
		if (cell as Vector3i).y >= 5:
			grid[cell] = HEAD

	# Snout: two cells wide, two tall, sticking out of the front.
	_fill(grid, Vector3i(2, 2, 6), Vector3i(3, 3, 6), NOSE)
	# Eyes sit above the snout, on the front face.
	_put(grid, Vector3i(1, 4, 6), EYE)
	_put(grid, Vector3i(4, 4, 6), EYE)
	# Feet, dark and slightly forward.
	_put(grid, Vector3i(1, 1, 5), FOOT)
	_put(grid, Vector3i(4, 1, 5), FOOT)
	return VoxelBuilder.build(grid, CELL)


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
	_put(grid, Vector3i(0, 3, 5), EYE)
	_put(grid, Vector3i(2, 3, 5), EYE)
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
