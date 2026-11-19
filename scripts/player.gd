class_name Player
extends Node3D

## Q*bert: a voxel blob that faces the direction it last hopped.
##
## Movement itself is driven by game.gd, because only the game knows whether a
## hop ends on a cube, on a disc, or in the void. This node owns presentation:
## which way the model leans, and the squash-and-stretch that sells a landing.
##
## The model is built in x/z-centred, feet-on-y=0 space (see VoxelBuilder), so
## rotating about y spins the character in place and scaling about y squashes it
## into the floor rather than through its own middle.

var coord: Vector3i
var _model: MeshInstance3D
var _squash: Tween


func _ready() -> void:
	_model = MeshInstance3D.new()
	_model.mesh = VoxelModels.player()
	_model.material_override = VoxelBuilder.make_material()
	add_child(_model)


## Turn to face a world-space hop direction. The models are authored facing +z,
## so yaw is simply atan2(x, z); the angle is unwrapped to the nearest
## equivalent first, otherwise a hop that wraps past PI would spin the model all
## the way around instead of snapping 20 degrees.
func face(direction: Vector3) -> void:
	if _model == null or direction.length_squared() < 0.0001:
		return
	var target := atan2(direction.x, direction.z)
	var current := _model.rotation.y
	target = current + wrapf(target - current, -PI, PI)
	var tween := create_tween()
	tween.tween_property(_model, "rotation:y", target, 0.12)


## Compress briefly, then spring back. `amount` is how much of the height is
## lost at the deepest point of the squash.
func squash(amount := 0.22) -> void:
	if _model == null:
		return
	if _squash != null and _squash.is_valid():
		_squash.kill()
	_model.scale = Vector3.ONE
	_squash = create_tween()
	_squash.tween_property(_model, "scale",
		Vector3(1.0 + amount * 0.5, 1.0 - amount, 1.0 + amount * 0.5), 0.07)
	_squash.tween_property(_model, "scale", Vector3.ONE, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Used on respawn: undo any squash left over from a death animation.
func reset_pose() -> void:
	if _model != null:
		_model.scale = Vector3.ONE
		_model.rotation = Vector3.ZERO
	visible = true
