class_name BoardTile
extends Node3D

## One cube of the pyramid.
##
## A tile owns three things: its coordinate, its colour state, and the mesh that
## shows both. The level's palette decides how many states there are, so a tile
## has no idea whether "complete" means one hop (level 1) or two (level 3) -
## that rule lives in Board.next_state() and this node just asks it.
##
## The cube is two boxes: a dark body and a slightly smaller, brighter cap that
## sits proud of the top face. That lip is what makes the board read as objects
## rather than as a flat grid - the cap catches the key light along its edge, and
## the shadow it drops on its own body is a real shadow, not painted on. It also
## gives the player an obvious "this is the surface you stand on" height.

signal stepped(coord: Vector3i)

## Edge length of the cube body. Slightly under Board.TILE_SPACING_X so
## neighbours never touch, which is what draws the dark gutters between cubes.
const SIZE := 0.86
## The cap is inset, which is what creates the beveled lip at the top.
const CAP_SIZE := 0.72
const CAP_HEIGHT := 0.14
## Height of the walkable surface above the tile's origin: the body's top face
## plus the part of the cap that sticks out above it.
const TOP := SIZE * 0.5 + 0.07

var coord: Vector3i
var state: int = 0
var palette: Array[Color] = []

var _body: MeshInstance3D
var _cap: MeshInstance3D
var _body_material: StandardMaterial3D
var _cap_material: StandardMaterial3D
var _tween: Tween


## Must be called before the node is added to the tree. Building the mesh here
## rather than in _ready() keeps construction synchronous, so tests and the
## level builder never see a half-built tile.
func setup(tile_coord: Vector3i, tile_palette: Array[Color]) -> void:
	coord = tile_coord
	palette = tile_palette
	state = 0

	_body_material = StandardMaterial3D.new()
	_body_material.roughness = 0.55
	_body_material.metallic = 0.0

	var body_box := BoxMesh.new()
	body_box.size = Vector3(SIZE, SIZE, SIZE)
	_body = MeshInstance3D.new()
	_body.mesh = body_box
	_body.material_override = _body_material
	add_child(_body)

	_cap_material = StandardMaterial3D.new()
	_cap_material.roughness = 0.38
	_cap_material.metallic = 0.0
	# Emission is what makes a finished cube pop when the world uses glow at an
	# HDR threshold above 1.0. Incomplete cubes get a whisper of it so their
	# colour survives in shadow.
	_cap_material.emission_enabled = true

	var cap_box := BoxMesh.new()
	cap_box.size = Vector3(CAP_SIZE, CAP_HEIGHT, CAP_SIZE)
	_cap = MeshInstance3D.new()
	_cap.mesh = cap_box
	_cap.material_override = _cap_material
	_cap.position.y = SIZE * 0.5
	add_child(_cap)

	_refresh_colour()


## The player stepped here. Applies the level's transition rule, then animates.
## Returns true when the hop moved the cube towards completion, so callers can
## score only real progress: bouncing on finished cubes earns nothing, and level
## 3's wrap-round (2 -> 0) is not rewarded for undoing work.
func step(level: int) -> bool:
	var before := state
	state = Board.next_state(state, level, palette.size())
	_refresh_colour()
	_bounce()
	stepped.emit(coord)
	return state > before


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
	_body.scale = Vector3.ONE
	_cap.scale = Vector3.ONE
	_tween.tween_property(_body, "scale", Vector3(1.05, 0.84, 1.05), 0.06)
	_tween.parallel().tween_property(_cap, "scale", Vector3(1.05, 0.84, 1.05), 0.06)
	_tween.tween_property(_body, "scale", Vector3.ONE, 0.13) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_cap, "scale", Vector3.ONE, 0.13) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func colour() -> Color:
	return palette[clampi(state, 0, palette.size() - 1)]


func _refresh_colour() -> void:
	if _cap_material == null or palette.is_empty():
		return
	var c := colour()
	# Body: the same hue knocked down hard, so the board stays colourful without
	# turning every side face into a wall of brightness.
	_body_material.albedo_color = c.darkened(0.28)
	_cap_material.albedo_color = c
	var glow := 1.0 if is_complete() else 0.05
	_cap_material.emission = c * glow
