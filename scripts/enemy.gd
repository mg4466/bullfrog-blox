class_name HopEnemy
extends Node3D

## The three things that want Q*bert dead, reduced to the differences that
## matter:
##
##   ball   hops downhill at random, harmless to the board, kills on contact
##   slick  hops downhill, reverts the cube it lands on, kills on contact
##   coily  descends as an egg, hatches at the base row, then *chases*
##
## Each enemy is a plain node with a coordinate and a countdown. game.gd owns
## the countdown and calls `hop`, because the decision of where to hop needs the
## board and the player, and this node deliberately knows neither.

const KIND_BALL := "ball"
const KIND_SLICK := "slick"
const KIND_COILY := "coily"

var kind: String = KIND_BALL
var coord: Vector3i
var hatched := false
var alive := true
## True while a hop tween is in flight; game.gd skips the countdown meanwhile.
var busy := false
var timer := 1.0
var interval := 1.2

var _model: MeshInstance3D
var _bob: float = 0.0
var _spawn_tween: Tween
var _motion_tween: Tween


func setup(enemy_kind: String, start_coord: Vector3i, hop_interval: float) -> void:
	kind = enemy_kind
	coord = start_coord
	interval = hop_interval
	timer = hop_interval
	hatched = false
	alive = true

	_model = MeshInstance3D.new()
	_model.mesh = _mesh_for_kind()
	_model.material_override = VoxelBuilder.make_material()
	add_child(_model)


func _mesh_for_kind() -> ArrayMesh:
	match kind:
		KIND_SLICK:
			return VoxelModels.slick()
		KIND_COILY:
			return VoxelModels.egg()
		_:
			return VoxelModels.ball()


## Coily's egg cracked. The same node becomes the snake, which keeps the board
## coordinate and the countdown continuous - no swap-in replacement needed.
func hatch() -> void:
	hatched = true
	_model.mesh = VoxelModels.snake()
	_model.scale = Vector3(1.4, 0.6, 1.4)
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Start high above the board and drop in, so enemies *arrive* instead of
## materialising on top of the player.
func drop_in(to_position: Vector3, delay: float) -> void:
	var start := to_position + Vector3(0, 6.0, 0)
	position = start
	visible = false
	var mover := func(t: float) -> void:
		position = Hop.arc(t, start, to_position, 0.0)
	_spawn_tween = create_tween()
	_spawn_tween.tween_interval(delay)
	_spawn_tween.tween_callback(func(): visible = true)
	_spawn_tween.tween_method(mover, 0.0, 1.0, 0.4)


## Every tween that moves this enemy is registered here, and killed when the
## node leaves the tree. Without this, a level transition that frees enemies
## leaves their hop tweens running against a dead object, which produces a
## stream of "lambda capture was freed" errors and, worse, can write a stale
## position onto a recycled node id.
func track_motion(tween: Tween) -> void:
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = tween


func _exit_tree() -> void:
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	if _spawn_tween != null and _spawn_tween.is_valid():
		_spawn_tween.kill()


## Turn to face a hop direction, snapped rather than tweened: a ball is a ball,
## but the snake's head should point where it is going, and it only ever moves
## between hops.
func face_direction(direction: Vector3) -> void:
	if _model == null or direction.length_squared() < 0.0001:
		return
	_model.rotation.y = atan2(direction.x, direction.z)


## Idle float. Purely decorative, and deliberately tiny (2 cm) - enough that a
## stationary enemy still reads as alive at 60 fps, not enough to look like it
## is hopping.
func _process(delta: float) -> void:
	if _model == null:
		return
	_bob += delta * 3.0
	_model.position.y = sin(_bob) * 0.02
