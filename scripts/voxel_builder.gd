class_name VoxelBuilder
extends RefCounted

## Turns a small sparse voxel grid into a single ArrayMesh with vertex colours.
##
## THE IDEA
## --------
## A "voxel model" here is just a Dictionary mapping Vector3i -> Color. This
## builder walks it and emits one quad per *exposed* face. A face is exposed
## when the neighbouring cell is empty, so a 4x4x4 blob emits 96 quads instead
## of 384 - and, more importantly, internal faces would never be seen anyway.
##
## COLOUR IS THE LIGHTING FLOOR
## ----------------------------
## Each face is multiplied by a fixed shade factor (top brightest, bottom
## darkest). Real lights are doing most of the work, but the per-face factor is
## what keeps a model readable when it is back-lit or standing in a shadow: the
## silhouette still separates into top / side / underside, like a sprite.
##
## WHY NOT Zylann's godot_voxel, or GridMap?
## -----------------------------------------
## Both solve a bigger problem than this game has. godot_voxel streams chunked
## terrain and needs a native module; GridMap is built for static scenery and
## gives you no per-instance colour. Here a model is a dozen cells and the
## result is one static ArrayMesh built once at startup, so plain SurfaceTool is
## both the smallest and the fastest option.

## Cube corners, indexed 0..7 in (x, y, z) bits: x = bit 0, y = bit 1, z = bit 2.
## Quad lists below are counter-clockwise seen from outside, which is Godot's
## front-face winding.
const FACE_DEFS := [
	{"direction": Vector3i(1, 0, 0), "quad": [1, 2, 6, 5], "shade": 0.88},   # +x
	{"direction": Vector3i(-1, 0, 0), "quad": [0, 4, 7, 3], "shade": 0.70},  # -x
	{"direction": Vector3i(0, 1, 0), "quad": [3, 7, 6, 2], "shade": 1.00},   # +y (top)
	{"direction": Vector3i(0, -1, 0), "quad": [0, 1, 5, 4], "shade": 0.42},  # -y
	{"direction": Vector3i(0, 0, 1), "quad": [4, 5, 6, 7], "shade": 0.82},   # +z
	{"direction": Vector3i(0, 0, -1), "quad": [0, 3, 2, 1], "shade": 0.60},  # -z
]

## Builds a mesh from `voxels` (Vector3i -> Color).
##
## `voxel_size` is the edge length of one cell. The result is centred on the
## origin in x/z and has its lowest cell sitting on y = 0, which is the
## convention every character in this game wants: a node's position is then
## "the point on the floor this thing stands on".
static func build(voxels: Dictionary, voxel_size: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if voxels.is_empty():
		return mesh

	var lo := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var hi := Vector3i(-(1 << 30), -(1 << 30), -(1 << 30))
	for key in voxels.keys():
		var cell: Vector3i = key
		lo = Vector3i(mini(lo.x, cell.x), mini(lo.y, cell.y), mini(lo.z, cell.z))
		hi = Vector3i(maxi(hi.x, cell.x), maxi(hi.y, cell.y), maxi(hi.z, cell.z))

	# A cell occupies [cell, cell+1] in grid space, so its centre is cell + 0.5.
	# Shifting by whole cells centres the model without resampling anything.
	var centre := Vector3(
		(float(lo.x + hi.x + 1) * 0.5) * voxel_size,
		0.0,
		(float(lo.z + hi.z + 1) * 0.5) * voxel_size
	)
	var floor_y := float(lo.y) * voxel_size

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for key in voxels.keys():
		var cell: Vector3i = key
		var colour: Color = voxels[key]
		for def in FACE_DEFS:
			var direction: Vector3i = def["direction"]
			if voxels.has(cell + direction):
				continue  # hidden by a neighbour, skip it
			var quad: Array = def["quad"]
			var shade: float = def["shade"]
			var normal := Vector3(direction)
			var lit := Color(
				clampf(colour.r * shade, 0.0, 1.0),
				clampf(colour.g * shade, 0.0, 1.0),
				clampf(colour.b * shade, 0.0, 1.0),
				colour.a
			)
			# A quad is two triangles. SurfaceTool has no implicit fan for
			# PRIMITIVE_TRIANGLES, so the shared diagonal vertex is repeated.
			for corner_index in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
				var corner := _corner(int(corner_index), cell, voxel_size, centre, floor_y)
				st.set_color(lit)
				st.set_normal(normal)
				st.add_vertex(corner)
	mesh = st.commit()
	return mesh


## Vertex position in model space: cell corner -> scaled, centred, floored.
static func _corner(corner_index: int, cell: Vector3i, voxel_size: float,
		centre: Vector3, floor_y: float) -> Vector3:
	var corner := Vector3(
		float(cell.x + (corner_index & 1)),
		float(cell.y + ((corner_index >> 1) & 1)),
		float(cell.z + ((corner_index >> 2) & 1))
	)
	return corner * voxel_size - Vector3(centre.x, floor_y, centre.z)


## The material every voxel model shares. Vertex colour carries the albedo;
## roughness is high because these are toys, not chrome.
static func make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.metallic = 0.0
	return mat


## Convenience: a ready-to-add MeshInstance3D for a voxel dictionary.
static func make_instance(voxels: Dictionary, voxel_size: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = build(voxels, voxel_size)
	instance.material_override = make_material()
	return instance
