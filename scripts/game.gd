extends Node3D

## Bullfrog Blox - the conductor of the whole game.
##
## This node is the only place that knows everything at once: the board, the
## player, the enemies, the score and the phase of play. Everything else is
## deliberately ignorant - tiles know their own colour, enemies know where they
## are, the HUD knows how to draw text, and Board/Hop know the maths. That split
## is what keeps this file readable: it reads like a rulebook ("player lands ->
## what is under them? -> resolve") instead of like a pile of callbacks.
##
## PHASES
##   READY      title screen, board built, no enemies
##   PLAYING    accepting input, enemies hopping
##   DYING      the player is falling or exploding; nothing else moves
##   CLEAR      round won, celebration running, then the next level starts
##   GAME_OVER  out of lives, waiting for R
##
## A phase is checked instead of using a stack of booleans because every handler
## here is triggered by a tween finishing, and a tween that outlives its phase
## must not be able to kill a player who has already respawned.

enum Phase { READY, PLAYING, DYING, CLEAR, GAME_OVER }

const ROWS := 7
## Seconds per hop. 0.22 s is about 4.5 hops a second, close to the arcade pace.
const HOP_TIME := 0.22
const HOP_HEIGHT := 1.05
const ENEMY_HOP_TIME := 0.30
## Height of a tile's walkable surface. Mirrors BoardTile.TOP, which is the
## body's top face plus the cap's lip; the constant is duplicated rather than
## referenced so this file parses without the global class cache.
const TILE_TOP := 0.50
const SAVE_PATH := "user://bullfrog_blox.cfg"

var _phase: int = Phase.READY
var _level: int = 1
var _score: int = 0
var _lives: int = 3
var _high: int = 0

var _apex := Vector3i(0, ROWS - 1, 0)
var _tiles: Dictionary = {}          # Vector3i -> BoardTile
var _palette: Array[Color] = []
var _discs: Dictionary = {}          # Vector3i -> MeshInstance3D
var _enemies: Array[HopEnemy] = []
var _spawn_queue: Array = []         # [{kind: String, at: float}]

var _board_root: Node3D
var _entity_root: Node3D
## Everything on the board hangs off this node, rotated 45 degrees about y.
## Board coordinates run along world x (within a row) and world z (between
## rows); the camera sits on the (1,1) diagonal, so without this rotation the
## rows would run across the screen at 45 degrees and the pyramid would lean.
## Rotating the stage by 45 degrees turns the x axis into pure screen-horizontal
## and the z axis into pure screen-depth - the classic arcade framing - without
## touching a single coordinate in Board.
var _stage: Node3D
var _player: Player
var _player_coord := Vector3i.ZERO
var _player_busy := false
## The tween currently moving the player. Death must be able to stop it, or the
## body keeps sliding towards the cube it never reached while it shrinks.
var _player_tween: Tween
var _buffered_dir := Vector3i.ZERO
var _has_buffered := false

var _camera: Camera3D
var _synth: Synth
var _hud: Hud
## Seconds until the "keep the board busy" spawner is allowed to add a ball.
## Without it a patient player can clear a level with an empty board after the
## first wave has fallen off, which is dull; the arcade never let you rest.
var _trickle := 6.0


# ---------------------------------------------------------------------------
# Boot
# ---------------------------------------------------------------------------

func _ready() -> void:
	randomize()
	_load_high_score()
	_build_world()

	_hud = Hud.new()
	add_child(_hud)
	_synth = Synth.new()
	add_child(_synth)

	_player = Player.new()
	_player.name = "Player"
	_entity_root.add_child(_player)

	_enter_ready()


func _enter_ready() -> void:
	_phase = Phase.READY
	_level = 1
	_score = 0
	_lives = 3
	_build_level()
	_hud.set_stats(_score, _level, _lives, _high)
	_hud.show_banner("BULLFROG BLOX", "SPACE to start")


## Static scene dressing. The board and the characters are built later, per
## level, so this only has to happen once.
##
## The look is three cheap layers stacked: a sky gradient so the void has depth,
## a raking warm key light with real shadows so cubes sit on each other, and a
## pool of additive light underneath so the pyramid floats in something rather
## than on nothing. Glow and ambient occlusion do the rest.
func _build_world() -> void:
	add_child(_make_world_environment())
	_add_vignette()
	_add_lights()

	_stage = Node3D.new()
	_stage.name = "Stage"
	_stage.rotation.y = PI * 0.25
	add_child(_stage)

	_board_root = Node3D.new()
	_board_root.name = "Board"
	_stage.add_child(_board_root)

	_entity_root = Node3D.new()
	_entity_root.name = "Entities"
	_stage.add_child(_entity_root)

	_add_ground_plate()
	_add_dust()

	# Orthographic camera on the classic isometric diagonal: equal x/z puts the
	# camera on a 45-degree azimuth, and y is chosen so it looks down at 30
	# degrees (x/z distance is 12*sqrt(2), so y = that * tan(30)).
	#
	# The target is expressed in *stage* space and then transformed, because the
	# stage is rotated 45 degrees: aiming at a raw world point would offset the
	# board sideways by half a unit, which is exactly the kind of bug that shows
	# up as "the pyramid is not centred" and takes an hour to find.
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 9.0
	var target: Vector3 = _stage.transform * Vector3(0.0, 0.0, 0.5)
	var horizontal := 12.0
	_camera.position = target + Vector3(horizontal, horizontal * sqrt(2.0) * tan(deg_to_rad(30.0)), horizontal)
	add_child(_camera)
	_camera.look_at(target)
	_camera.current = true


## Sky, tone mapping and the two post effects that sell the voxel look:
## glow (finished cubes bloom) and ambient occlusion (the gutters between cubes
## darken instead of reading as flat black lines).
func _make_world_environment() -> WorldEnvironment:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://scripts/sky_gradient.gdshader")

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9fb0ff")
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05

	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 1.1
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	# SSAO stays off. Measured on this scene (tests/tmp/speckle during the art
	# pass): AO raises the luminance standard deviation of a flat cube top from
	# 0.002 to 0.014 at a 30-degree camera angle, which reads as grain, and the
	# shapes it would reveal are already separated by the body/cap value split.
	env.ssao_enabled = false

	# No fog. In an orthographic scene everything is at the same depth, so fog
	# only washes the sky toward a flat grey (measured: a violet gradient turns
	# into #848d9b) and mutes the cube colours for no depth gain.
	env.fog_enabled = false

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	return world_env


## Warm key light raking from the upper left, a cool rim from behind, and a dim
## violet bounce from below. With shadows on, each cube drops a real shadow onto
## its neighbours and the characters cast onto the cubes they stand on - that
## contact shadow is most of what makes the board feel solid.
func _add_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -34, 0)
	key.light_color = Color("ffe3c4")
	key.light_energy = 2.4
	key.shadow_enabled = true
	key.light_angular_distance = 0.35
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key.directional_shadow_max_distance = 45.0
	key.shadow_bias = 0.02
	key.shadow_normal_bias = 0.8
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-14, 152, 0)
	rim.light_color = Color("6fd6ff")
	rim.light_energy = 0.45
	rim.shadow_enabled = false
	add_child(rim)

	var bounce := DirectionalLight3D.new()
	bounce.rotation_degrees = Vector3(-118, 20, 0)
	bounce.light_color = Color("8a63ff")
	bounce.light_energy = 0.18
	bounce.shadow_enabled = false
	add_child(bounce)


## A dark plate under the pyramid. This is the shadow receiver: without it every
## shadow the key light casts lands on nothing, and the board looks like a
## diagram. It sits far enough below the cubes that a player falling off the edge
## drops past it into darkness rather than through it (see _player_falls()).
func _add_ground_plate() -> void:
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = 9.0
	plate_mesh.bottom_radius = 7.6
	plate_mesh.height = 0.5
	plate_mesh.radial_segments = 64
	plate_mesh.rings = 1

	var material := StandardMaterial3D.new()
	material.albedo_color = Color("120e20")
	material.roughness = 1.0
	material.metallic = 0.0

	var plate := MeshInstance3D.new()
	plate.mesh = plate_mesh
	plate.material_override = material
	plate.position = Vector3(0.0, -2.6, 1.0)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(plate)


## Slow motes drifting above the board. Purely atmospheric, but a few moving
## points of light in an otherwise still frame is what stops the scene from
## looking like a screenshot of a screenshot.
func _add_dust() -> void:
	var particle_mesh := BoxMesh.new()
	particle_mesh.size = Vector3(0.05, 0.05, 0.05)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("b9a6ff")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.55
	material.vertex_color_use_as_albedo = false

	var dust := CPUParticles3D.new()
	dust.amount = 70
	dust.lifetime = 9.0
	dust.preprocess = 6.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(9.0, 3.5, 9.0)
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 40.0
	dust.gravity = Vector3(0, 0.05, 0)
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.3
	dust.scale_amount_min = 0.4
	dust.scale_amount_max = 1.4
	dust.mesh = particle_mesh
	dust.material_override = material
	dust.position = Vector3(0.0, 1.2, 1.0)
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(dust)


## Corner darkening, below the HUD. See scripts/vignette.gdshader.
func _add_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/vignette.gdshader")
	rect.material = material
	layer.add_child(rect)
	add_child(layer)


# ---------------------------------------------------------------------------
# Level construction
# ---------------------------------------------------------------------------

func _build_level() -> void:
	_clear_entities()

	for tile in _tiles.values():
		(tile as Node).queue_free()
	_tiles.clear()

	_palette = Board.palette_for(_level)
	for coord in Board.pyramid(ROWS):
		var tile := BoardTile.new()
		tile.setup(coord, _palette)
		tile.position = Board.world_pos(coord, ROWS)
		_board_root.add_child(tile)
		_tiles[coord] = tile

	_build_discs()

	_player_coord = _apex
	_player.position = _tile_top(_apex)
	_player.rotation = Vector3.ZERO
	_player.scale = Vector3.ONE
	_player.reset_pose()
	_player_busy = false
	_has_buffered = false


func _build_discs() -> void:
	for coord in Board.disc_coords():
		var disc := MeshInstance3D.new()
		disc.mesh = VoxelModels.disc()
		disc.material_override = VoxelBuilder.make_material(true)
		# Sits a little above the cube tops so it reads as floating.
		disc.position = Board.world_pos(coord, ROWS) + Vector3(0, 0.30, 0)
		_entity_root.add_child(disc)
		_discs[coord] = disc


func _clear_entities() -> void:
	for enemy in _enemies:
		enemy.queue_free()
	_enemies.clear()
	for disc in _discs.values():
		(disc as Node).queue_free()
	_discs.clear()
	_spawn_queue.clear()


func _start_game() -> void:
	_score = 0
	_lives = 3
	_level = 1
	_start_level()


func _start_level() -> void:
	_build_level()
	_phase = Phase.PLAYING
	_hud.set_stats(_score, _level, _lives, _high)
	_hud.show_banner("LEVEL %d" % _level, _level_hint(), 1.3)
	_synth.play("start")
	_queue_spawns()


func _level_hint() -> String:
	match _level:
		1:
			return "one hop per cube"
		2:
			return "two hops per cube"
		_:
			return "three states - do not overstep"


## How many of each enemy, and how fast they move, per level. Data instead of
## branching in the spawn code so tweaking difficulty is a one-line change.
func _level_plan(level: int) -> Dictionary:
	return {
		"balls": 2,
		"slick": 1 if level >= 2 else 0,
		"coily": 1 if level >= 3 else 0,
		"speed": clampf(1.0 - 0.07 * float(level - 1), 0.42, 1.0),
	}


func _queue_spawns() -> void:
	var plan := _level_plan(_level)
	_spawn_queue.clear()
	var when := 1.4
	for i in range(int(plan["balls"])):
		_spawn_queue.append({"kind": HopEnemy.KIND_BALL, "at": when})
		when += 2.4
	if int(plan["slick"]) > 0:
		_spawn_queue.append({"kind": HopEnemy.KIND_SLICK, "at": when + 0.8})
		when += 1.6
	if int(plan["coily"]) > 0:
		_spawn_queue.append({"kind": HopEnemy.KIND_COILY, "at": when + 0.6})


# ---------------------------------------------------------------------------
# Frame loop: discs spin, spawn queue drains, enemy clocks tick
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	for disc in _discs.values():
		(disc as Node3D).rotation.y += delta * 2.8

	if _phase != Phase.PLAYING:
		return

	_tick_spawns(delta)

	# Trickle spawner: an empty board is boring, so keep one ball in play even
	# after the opening wave has fallen off the bottom.
	_trickle -= delta
	if _trickle <= 0.0:
		_trickle = 6.0
		if _enemies.is_empty() and _spawn_queue.is_empty():
			_spawn_enemy(HopEnemy.KIND_BALL)

	for enemy in _enemies.duplicate():
		var e := enemy as HopEnemy
		if not e.alive or e.busy:
			continue
		e.timer -= delta
		if e.timer <= 0.0:
			e.timer = e.interval
			_enemy_hop(e)


func _tick_spawns(delta: float) -> void:
	if _spawn_queue.is_empty():
		return
	var still_waiting: Array = []
	for entry in _spawn_queue:
		var remaining: float = float(entry["at"]) - delta
		if remaining > 0.0:
			entry["at"] = remaining
			still_waiting.append(entry)
		else:
			_spawn_enemy(String(entry["kind"]))
	_spawn_queue = still_waiting


func _spawn_enemy(kind: String) -> void:
	var start := _pick_spawn_coord(kind)
	var enemy := HopEnemy.new()
	enemy.setup(kind, start, _enemy_interval(kind))
	_entity_root.add_child(enemy)
	enemy.drop_in(_tile_top(start), 0.05)
	# busy until the drop finishes, otherwise it starts hopping out of the sky.
	# The guard matters: a player can squash a ball during its 0.45 s drop, and
	# the timer would then write `busy` on a freed object.
	enemy.busy = true
	get_tree().create_timer(0.5).timeout.connect(func():
		if is_instance_valid(enemy):
			enemy.busy = false)
	_enemies.append(enemy)


## Coily always arrives at the apex; balls and slicks enter from the top rows,
## never on the cube the player is standing on (that would be an unavoidable
## death, and arcade games were cruel but not unfair).
func _pick_spawn_coord(kind: String) -> Vector3i:
	if kind == HopEnemy.KIND_COILY:
		return _apex
	var candidates: Array[Vector3i] = []
	for coord in Board.pyramid(ROWS):
		if coord.y >= ROWS - 2 and coord != _player_coord:
			candidates.append(coord)
	if candidates.is_empty():
		return _apex
	return candidates.pick_random()


func _enemy_interval(kind: String) -> float:
	var base := 1.7
	if kind == HopEnemy.KIND_SLICK:
		base = 1.5
	elif kind == HopEnemy.KIND_COILY:
		base = 1.1
	return base * float(_level_plan(_level)["speed"])


# ---------------------------------------------------------------------------
# Enemy behaviour
# ---------------------------------------------------------------------------

func _enemy_hop(enemy: HopEnemy) -> void:
	# Coily's egg: fall down the pyramid until there is nowhere left to fall,
	# then hatch. This is why the egg is a separate state rather than a timer:
	# the descent is the telegraph that the snake is coming.
	if enemy.kind == HopEnemy.KIND_COILY and not enemy.hatched:
		var downs := _descend_options(enemy.coord)
		if downs.is_empty():
			enemy.hatch()
			enemy.interval = maxf(0.28, enemy.interval * 0.8)
			_synth.play("hatch")
			return
		_move_enemy(enemy, downs.pick_random())
		return

	if enemy.kind == HopEnemy.KIND_COILY:
		var step := Board.chase_step(enemy.coord, _player_coord, _tiles)
		if step != enemy.coord:
			_move_enemy(enemy, step)
		return

	# Balls and slicks only ever hop downhill, which is what makes them
	# predictable enough to dodge.
	var downs := _descend_options(enemy.coord)
	if downs.is_empty():
		_enemy_runs_off(enemy)
		return
	_move_enemy(enemy, downs.pick_random())


func _descend_options(coord: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for dir in [Board.DOWN_RIGHT, Board.DOWN_LEFT]:
		var next: Vector3i = coord + dir
		if _tiles.has(next):
			out.append(next)
	return out


func _move_enemy(enemy: HopEnemy, target: Vector3i) -> void:
	enemy.busy = true
	var from := enemy.position
	var to := _tile_top(target)
	enemy.face_direction(to - from)
	var mover := func(t: float) -> void:
		enemy.position = Hop.arc(t, from, to, 0.65)
	var tween := create_tween()
	tween.tween_method(mover, 0.0, 1.0, ENEMY_HOP_TIME)
	enemy.track_motion(tween)
	tween.finished.connect(func():
		enemy.coord = target
		enemy.busy = false
		_on_enemy_landed(enemy)
	)


func _on_enemy_landed(enemy: HopEnemy) -> void:
	if not enemy.alive or _phase != Phase.PLAYING:
		return

	# Slick undoes progress: this is the enemy that punishes a player who
	# finishes the board quickly and stops paying attention.
	if enemy.kind == HopEnemy.KIND_SLICK:
		var tile: BoardTile = _tiles.get(enemy.coord)
		if tile != null:
			tile.revert()
			_synth.play("revert")

	# A player in the air has already left this cube: their coordinate only
	# updates on landing, so comparing against it mid-hop would kill them for
	# standing somewhere they are not.
	if _player_busy:
		return

	# The egg is harmless; everything else kills on contact.
	if enemy.coord == _player_coord:
		if enemy.kind == HopEnemy.KIND_COILY and not enemy.hatched:
			return
		_kill_player()


func _enemy_runs_off(enemy: HopEnemy, bonus: int = 0) -> void:
	enemy.alive = false
	enemy.busy = true
	if bonus > 0:
		_add_score(bonus)
	var from := enemy.position
	var side := 1.0 if randf() < 0.5 else -1.0
	var faller := func(t: float) -> void:
		enemy.position = from + Vector3(side * 2.0 * t, -10.0 * t * t, 0.0)
		enemy.rotation.z = t * 3.0 * side
	var tween := create_tween()
	tween.tween_method(faller, 0.0, 1.0, 1.0)
	enemy.track_motion(tween)
	tween.finished.connect(func(): _remove_enemy(enemy))


func _remove_enemy(enemy: HopEnemy) -> void:
	_enemies.erase(enemy)
	enemy.queue_free()


func _squash_enemy(enemy: HopEnemy) -> void:
	enemy.alive = false
	_add_score(100)
	_synth.play("squash")
	var tween := create_tween()
	tween.tween_property(enemy, "scale", Vector3(1.5, 0.06, 1.5), 0.10)
	tween.tween_property(enemy, "scale", Vector3.ZERO, 0.10)
	enemy.track_motion(tween)
	tween.finished.connect(func(): _remove_enemy(enemy))


# ---------------------------------------------------------------------------
# Player hops
# ---------------------------------------------------------------------------

func _request_hop(dir: Vector3i) -> void:
	if _phase != Phase.PLAYING:
		return
	if _player_busy:
		# One slot of input buffer. Without it, a hop that lands while the
		# player is mashing feels unresponsive; more than one slot causes
		# unwanted extra hops into enemies.
		_buffered_dir = dir
		_has_buffered = true
		return
	_player_hop(dir)


func _player_hop(dir: Vector3i) -> void:
	_player_busy = true
	var target: Vector3i = _player_coord + dir
	var from := _player.position
	var to := _tile_top(target)
	_player.face(to - from)
	_synth.play("hop")

	var mover := func(t: float) -> void:
		_player.position = Hop.arc(t, from, to, HOP_HEIGHT)
	if _player_tween != null and _player_tween.is_valid():
		_player_tween.kill()
	_player_tween = create_tween()
	_player_tween.tween_method(mover, 0.0, 1.0, HOP_TIME)
	_player_tween.finished.connect(func(): _player_landed(target))


func _player_landed(target: Vector3i) -> void:
	if _phase != Phase.PLAYING:
		return

	if _discs.has(target):
		_ride_disc(target)
		return

	var tile: BoardTile = _tiles.get(target)
	if tile == null:
		_player_falls()
		return

	_player_coord = target
	# Points are for progress, not for hops: bouncing on a finished cube earns
	# nothing, and level 3's wrap-round (2 -> 0) is not rewarded for undoing work.
	if tile.step(_level):
		_add_score(25)
	_player.squash()
	_synth.play("step")

	_check_player_collision()
	if _phase != Phase.PLAYING:
		return
	_check_level_clear()
	if _phase != Phase.PLAYING:
		return
	_finish_player_action()


## Called when a hop resolves and the player may act again. Replays the single
## buffered input if there is one.
func _finish_player_action() -> void:
	_player_busy = false
	if _has_buffered and _phase == Phase.PLAYING:
		var dir := _buffered_dir
		_has_buffered = false
		_player_hop(dir)
	else:
		_has_buffered = false


func _ride_disc(disc_coord: Vector3i) -> void:
	var disc: Node3D = _discs.get(disc_coord)
	if disc != null:
		disc.queue_free()
		_discs.erase(disc_coord)

	_add_score(500)
	_synth.play("disc")

	# Coily panics and leaps off the board. This is the only way to kill him,
	# and it is why the discs are worth spending.
	for enemy in _enemies.duplicate():
		var e := enemy as HopEnemy
		if e.alive and e.kind == HopEnemy.KIND_COILY:
			_enemy_runs_off(e, 500)

	# Take the player off the board immediately: during the ride there is no
	# cube underneath, so enemies must not be able to "catch" them mid-air.
	_player_coord = _apex
	# A direction buffered during the hop onto the disc would fire the instant the
	# ride ends - and from the apex, "up-left"/"up-right" is straight off the board.
	_has_buffered = false
	var from := _player.position
	var to := _tile_top(_apex)
	var rider := func(t: float) -> void:
		_player.position = Hop.arc(t, from, to, 3.0)
	var tween := create_tween()
	tween.tween_method(rider, 0.0, 1.0, 0.55)
	tween.finished.connect(func():
		if _phase != Phase.PLAYING:
			_player_busy = false
			return
		_player.squash()
		var apex_tile: BoardTile = _tiles.get(_apex)
		if apex_tile != null and apex_tile.step(_level):
			_add_score(25)
		_check_player_collision()
		if _phase == Phase.PLAYING:
			_check_level_clear()
			if _phase == Phase.PLAYING:
				_finish_player_action()
	)


func _player_falls() -> void:
	_stop_player_motion()
	_phase = Phase.DYING
	_player_busy = false
	_has_buffered = false
	_synth.play("fall")
	var from := _player.position
	var faller := func(t: float) -> void:
		# Accelerating drop with a tumble and no horizontal drift: the player
		# missed the board, they should look like they fell off the edge. The
		# drop stops short of the ground plate, and the shrink hides the rest.
		_player.position = from + Vector3(0, -2.4 * t * t, 0)
		_player.rotation.z = t * 2.2
		_player.scale = Vector3.ONE * (1.0 - 0.75 * t)
	var tween := create_tween()
	tween.tween_method(faller, 0.0, 1.0, 0.85)
	tween.finished.connect(_after_death)


# ---------------------------------------------------------------------------
# Death, respawn, game over
# ---------------------------------------------------------------------------

## Resolves whoever shares the cube the frog just landed on.
##
## Note there is deliberately no `_player_busy` guard here: this runs from the
## landing callback, which always fires *before* `_player_busy` is cleared, so
## such a guard would make every contact a no-op (that was a real bug, and
## tests/collisions.tscn exists because of it). The "frog is in the air" case is
## handled where it belongs: in _on_enemy_landed(), which is the enemy moving.
func _check_player_collision() -> void:
	if _phase != Phase.PLAYING:
		return
	for enemy in _enemies.duplicate():
		var e := enemy as HopEnemy
		if not e.alive or e.busy or e.coord != _player_coord:
			continue
		if e.kind == HopEnemy.KIND_COILY and not e.hatched:
			continue  # an egg on your cube is harmless
		if e.kind == HopEnemy.KIND_COILY:
			_kill_player()
			return
		# Squashing a ball or slick is worth points - the reward for hopping
		# onto danger deliberately.
		_squash_enemy(e)


func _kill_player() -> void:
	if _phase != Phase.PLAYING:
		return
	_stop_player_motion()
	_phase = Phase.DYING
	_player_busy = false
	_has_buffered = false
	_synth.play("death")
	var tween := create_tween()
	tween.tween_property(_player, "scale", Vector3(1.4, 0.15, 1.4), 0.18)
	tween.tween_property(_player, "scale", Vector3.ZERO, 0.22)
	tween.finished.connect(_after_death)


## Cancels the hop in flight. Called when a death starts, so nothing is still
## moving the body while it is being shrunk into the floor.
func _stop_player_motion() -> void:
	if _player_tween != null and _player_tween.is_valid():
		_player_tween.kill()


func _after_death() -> void:
	_lives -= 1
	_hud.set_stats(_score, _level, _lives, _high)
	if _lives <= 0:
		_game_over()
		return
	_respawn()


func _respawn() -> void:
	_player.reset_pose()
	_player.rotation = Vector3.ZERO
	_player.scale = Vector3.ONE
	_player_coord = _apex
	_player.position = _tile_top(_apex)
	_player_busy = false

	# Anything sitting on the apex would kill the player on the first frame
	# back, which reads as a bug rather than a fair death.
	for enemy in _enemies.duplicate():
		var e := enemy as HopEnemy
		if e.alive and e.coord == _apex:
			_enemy_runs_off(e)

	_phase = Phase.PLAYING


func _game_over() -> void:
	_phase = Phase.GAME_OVER
	_save_high_score()
	_hud.set_stats(_score, _level, 0, _high)
	_hud.show_banner("GAME OVER", "SCORE %06d    ·    R to play again" % _score)


# ---------------------------------------------------------------------------
# Round completion
# ---------------------------------------------------------------------------

func _check_level_clear() -> void:
	for tile in _tiles.values():
		if not (tile as BoardTile).is_complete():
			return

	_phase = Phase.CLEAR
	var bonus := 1000 + 250 * (_level - 1)
	_add_score(bonus)
	_hud.show_banner("ROUND CLEAR", "+%d" % bonus)
	_synth.play("level")

	for enemy in _enemies.duplicate():
		var e := enemy as HopEnemy
		if e.alive:
			_enemy_runs_off(e)

	# Diagonal wave across the pyramid: the delay is proportional to the cube's
	# position, so the flash sweeps the board instead of blinking all at once.
	var delay := 0.0
	for coord in Board.pyramid(ROWS):
		var tile: BoardTile = _tiles[coord]
		get_tree().create_timer(0.35 + delay).timeout.connect(tile.celebrate)
		delay += 0.012

	# A one-shot timer rather than `await`: the round-advance must not run if
	# something else moved the phase on (a restart, a quit), and a timer we can
	# ignore is easier to reason about than a suspended coroutine.
	var advance := get_tree().create_timer(2.4)
	advance.timeout.connect(_advance_level)


func _advance_level() -> void:
	if _phase != Phase.CLEAR:
		return
	# Save here as well as at game over: a player who closes the window on a
	# high score should still keep it.
	_save_high_score()
	_level += 1
	_start_level()


# ---------------------------------------------------------------------------
# Scoring, persistence, helpers
# ---------------------------------------------------------------------------

func _add_score(points: int) -> void:
	_score += points
	if _score > _high:
		_high = _score
	_hud.set_stats(_score, _level, _lives, _high)


func _tile_top(coord: Vector3i) -> Vector3:
	return Board.world_pos(coord, ROWS) + Vector3(0, TILE_TOP, 0)


func _load_high_score() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		_high = int(config.get_value("scores", "high", 0))


func _save_high_score() -> void:
	var config := ConfigFile.new()
	config.set_value("scores", "high", _high)
	config.save(SAVE_PATH)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	match key.keycode:
		KEY_Q, KEY_KP_7:
			_request_hop(Board.UP_LEFT)
		KEY_E, KEY_KP_9:
			_request_hop(Board.UP_RIGHT)
		KEY_A, KEY_KP_1:
			_request_hop(Board.DOWN_LEFT)
		KEY_D, KEY_KP_3:
			_request_hop(Board.DOWN_RIGHT)
		KEY_SPACE:
			if _phase == Phase.READY or _phase == Phase.GAME_OVER:
				_start_game()
		KEY_R:
			if _phase == Phase.GAME_OVER:
				_start_game()
		KEY_ESCAPE:
			_save_high_score()
			get_tree().quit()
