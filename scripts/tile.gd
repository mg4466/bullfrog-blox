class_name BoardTile
extends Node3D

## One cube of the pyramid.
##
## A tile owns three things: its coordinate, its colour state, and the mesh that
## shows both. The level's palette decides how many states there are, so a tile
## has no idea whether "complete" means one hop (level 1) or two (level 3) -
## that rule lives in Board.next_state() and this node just asks it.
##
## Tiles are cubes rather than voxel-built meshes on purpose. 28 of them, each
## with its own material so a single tile can flip colour without touching its
## neighbours, and a BoxMesh with a 0.85 size gives the grid gutter that makes
## the isometric board legible. Voxel meshes are used for the characters, where
## chunky silhouettes actually matter.

signal stepped(coord: Vector3i)

## Edge length of the cube. Slightly under Board.TILE_SPACING_X so neighbours
## never touch, which is what draws the black lines between cubes.
const SIZE := 0.85
## Height of the walkable surface above the tile's origin.
const TOP := SIZE * 0.5

var coord: Vector3i
var state: int = 0
var palette: Array[Color] = []

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _tween: Tween


## Must be called before the node is added to the tree. Building the mesh here
## rather than in _ready() keeps construction synchronous, so tests and the
## level builder never see a half-built tile.
func setup(tile_coord: Vector3i, tile_palette: Array[Color]) -> void:
	coord = tile_coord
	palette = tile_palette
	state = 0

	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(SIZE, SIZE, SIZE)
	_mesh.mesh = box

	_material = StandardMaterial3D.new()
	_material.roughness = 0.72
	# A little emission keeps the purple start colour readable in shadow and
	# gives completed cubes a glow that can be spotted at a glance.
	_material.emission_enabled = true
	_mesh.material_override = _material
	add_child(_mesh)
	_refresh_colour()


## The player stepped here. Applies the level's transition rule, then animates.
func step(level: int) -> void:
	state = Board.next_state(state, level, palette.size())
	_refresh_colour()
	_bounce()
	stepped.emit(coord)


## Slick/Sam landed here: one step backwards, never below the start state.
func revert() -> void:
	state = Board.reverted_state(state)
	_refresh_colour()


func is_complete() -> bool:
	return Board.is_complete(state, palette.size())


## The pure visual half of step(): bounce without changing state. Used by the
## round-clear wave, where re-running the level rule would push a three-state
## board backwards and leave it looking incomplete.
func celebrate() -> void:
	_bounce()


func _bounce() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_mesh.scale = Vector3.ONE
	_tween.tween_property(_mesh, "scale", Vector3(1.05, 0.84, 1.05), 0.06)
	_tween.tween_property(_mesh, "scale", Vector3.ONE, 0.13) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func colour() -> Color:
	return palette[clampi(state, 0, palette.size() - 1)]


func _refresh_colour() -> void:
	if _material == null or palette.is_empty():
		return
	var c := colour()
	_material.albedo_color = c
	# Completed cubes glow harder than untouched ones; nothing else differs, so
	# the player can read progress from a single glance at the board.
	var glow := 0.35 if is_complete() else 0.08
	_material.emission = c * glow
