extends Node

## Measures the rendered layout: where cubes land in screen pixels, how big a
## cube is, and whether the pyramid is centred. Numbers instead of eyeballing,
## because "the board looks squashed" is hard to argue about otherwise.
##
##   godot --path . res://tests/measure.tscn --resolution 1280x800

var _game: Node


func _ready() -> void:
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_measure()
	get_tree().quit(0)


func _measure() -> void:
	var cam: Camera3D = _game._camera
	var vp := get_viewport().get_visible_rect().size
	print("viewport: %s" % vp)

	var apex: Vector3 = (_game._tiles[Vector3i(0, 6, 0)] as BoardTile).global_position
	var base_l: Vector3 = (_game._tiles[Vector3i(0, 0, 6)] as BoardTile).global_position
	var base_r: Vector3 = (_game._tiles[Vector3i(6, 0, 0)] as BoardTile).global_position
	var base_r2: Vector3 = (_game._tiles[Vector3i(5, 0, 1)] as BoardTile).global_position
	var row1_l: Vector3 = (_game._tiles[Vector3i(0, 5, 1)] as BoardTile).global_position

	var p_apex := cam.unproject_position(apex)
	var p_bl := cam.unproject_position(base_l)
	var p_br := cam.unproject_position(base_r)
	var p_br2 := cam.unproject_position(base_r2)
	var p_row1 := cam.unproject_position(row1_l)

	var tile_step := p_br2 - p_br
	var row_step := p_row1.y - p_apex.y

	print("apex screen: %s" % p_apex)
	print("base left : %s   base right: %s" % [p_bl, p_br])
	print("screen centre x: %.1f   board centre x: %.1f" % [vp.x * 0.5, (p_bl.x + p_br.x) * 0.5])
	print("base row width: %.1f px" % (p_br.x - p_bl.x))
	print("same-row step: %.1f px  (dx=%.1f dy=%.1f)" % [tile_step.length(), tile_step.x, tile_step.y])
	print("row step (vertical): %.1f px" % row_step)

	# A cube's screen size: project its world corners.
	var half := 0.425
	var top_centre: Vector3 = apex + Vector3(0, half, 0)
	var up_px := cam.unproject_position(top_centre)
	var top_px := cam.unproject_position(top_centre + Vector3(0, 0, half))
	var side_px := cam.unproject_position(top_centre + Vector3(0, 0, -half))
	print("cube top face depth on screen: %.1f px  (height %.1f px)"
		% [absf(side_px.y - top_px.y), absf(side_px.y - top_px.y)])
	print("player on screen: apex cube at y %.1f, base row at y %.1f" % [p_apex.y, p_bl.y])
	print("board vertical span: %.1f px of %.1f" % [absf(p_bl.y - p_apex.y), vp.y])

	# Whole-content bounds: every cube, every disc, and the player.
	var min_x := 1e9
	var max_x := -1e9
	var min_y := 1e9
	var max_y := -1e9
	for node in _game._board_root.get_children() + _game._entity_root.get_children():
		var centre: Vector3 = (node as Node3D).global_position
		var p := cam.unproject_position(centre)
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	print("content bbox: x %.0f..%.0f  y %.0f..%.0f  (viewport %s)"
		% [min_x, max_x, min_y, max_y, vp])
