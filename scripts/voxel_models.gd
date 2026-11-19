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
## Grid conventions used below:
##   * +y is up, +z is towards the camera (the direction the characters face)
##   * one cell is 0.14 world units for characters, 0.2 for the disc
##   * characters are authored starting at (0, 0, 0); VoxelBuilder centres them
##     in x/z and puts their feet on y = 0.

const CELL := 0.14
const DISC_CELL := 0.2

# Palette. Named so a would-be modder can recolour the whole game from here.
const BODY := Color("e8722a")        # Q*bert orange
const HEAD := Color("f5a44a")
const NOSE := Color("c9501c")
const EYE := Color("181820")
const FOOT := Color("a83d12")

const BALL_RED := Color("d63a2f")
const BALL_HI := Color("ff7a63")
const SLICK_GREEN := Color("3fa860")
const SLICK_HI := Color("7fd39a")

const EGG_SHELL := Color("efeaf7")
const EGG_SPOT := Color("8a3fb0")

const SNAKE := Color("8a3fb0")
const SNAKE_DARK := Color("5c2478")
const SNAKE_BELLY := Color("c79bdd")

const GOLD := Color("f2c94c")
const DISC_CORE := Color("3fd0c9")

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


## A ball of cells, rounded by Euclidean distance. Used for the red balls.
static func _sphere(grid: Dictionary, radius: float, colour: Color) -> void:
	var r := int(ceil(radius))
	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			for z in range(-r, r + 1):
				if Vector3(x, y, z).length() <= radius:
					grid[Vector3i(x, y, z)] = colour


# --- models ------------------------------------------------------------------

## The player: a stout orange creature with a snout, two eyes and two feet.
## Four cells tall, which is roughly half a tile - small enough to read as a
## character standing *on* the cube rather than replacing it.
static func player() -> ArrayMesh:
	var grid := {}
	_fill(grid, Vector3i(0, 0, 0), Vector3i(2, 2, 2), BODY)
	_fill(grid, Vector3i(0, 3, 0), Vector3i(2, 3, 2), HEAD)
	_put(grid, Vector3i(1, 2, 3), NOSE)      # snout pokes out the front
	_put(grid, Vector3i(1, 3, 3), NOSE)
	_put(grid, Vector3i(0, 3, 3), EYE)
	_put(grid, Vector3i(2, 3, 3), EYE)
	_put(grid, Vector3i(0, 0, 3), FOOT)
	_put(grid, Vector3i(2, 0, 3), FOOT)
	return VoxelBuilder.build(grid, CELL)


## The red ball: a hopping sphere with a lit top face.
static func ball() -> ArrayMesh:
	var grid := {}
	_sphere(grid, 1.55, BALL_RED)
	for cell in grid.keys():
		if (cell as Vector3i).y >= 1:
			grid[cell] = BALL_HI
	return VoxelBuilder.build(grid, CELL)


## Slick/Sam: the same spherical body as a red ball, but green. Reusing the
## shape is honest to the original, where the difference is colour and behaviour.
static func slick() -> ArrayMesh:
	var grid := {}
	_sphere(grid, 1.55, SLICK_GREEN)
	for cell in grid.keys():
		if (cell as Vector3i).y >= 1:
			grid[cell] = SLICK_HI
	return VoxelBuilder.build(grid, CELL)


## Coily before it hatches: a pale egg with a purple band.
static func egg() -> ArrayMesh:
	var grid := {}
	_fill(grid, Vector3i(0, 0, 0), Vector3i(1, 2, 1), EGG_SHELL)
	_put(grid, Vector3i(0, 3, 0), EGG_SHELL)
	_put(grid, Vector3i(1, 3, 1), EGG_SHELL)
	_put(grid, Vector3i(0, 1, 2), EGG_SPOT)
	_put(grid, Vector3i(1, 1, 2), EGG_SPOT)
	return VoxelBuilder.build(grid, CELL)


## Coily hatched: a purple snake with a head, eyes and a zig-zag body that
## trails backwards so it reads as "coming towards you" from the fixed camera.
static func snake() -> ArrayMesh:
	var grid := {}
	_fill(grid, Vector3i(0, 1, 0), Vector3i(1, 2, 1), SNAKE)
	_put(grid, Vector3i(0, 2, 2), EYE)
	_put(grid, Vector3i(1, 2, 2), EYE)
	_put(grid, Vector3i(0, 0, 1), SNAKE_BELLY)
	_put(grid, Vector3i(1, 0, 1), SNAKE_BELLY)
	# Body: alternating offsets along -z make a coil without any rotation code.
	_put(grid, Vector3i(0, 0, -1), SNAKE_DARK)
	_put(grid, Vector3i(1, 1, -1), SNAKE)
	_put(grid, Vector3i(0, 2, -1), SNAKE_DARK)
	_put(grid, Vector3i(1, 1, -2), SNAKE_DARK)
	_put(grid, Vector3i(0, 0, -2), SNAKE)
	_put(grid, Vector3i(1, 2, -2), SNAKE_DARK)
	return VoxelBuilder.build(grid, CELL)


## The escape disc: a flat gold disc with a cyan core, spun in game code.
static func disc() -> ArrayMesh:
	var grid := {}
	for x in range(-2, 3):
		for z in range(-2, 3):
			var d := x * x + z * z
			if d <= 6:
				grid[Vector3i(x, 0, z)] = DISC_CORE if d <= 1 else GOLD
	return VoxelBuilder.build(grid, DISC_CELL)
