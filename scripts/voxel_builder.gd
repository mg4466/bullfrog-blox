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

## Cube corners, indexed 0..7 as a bit field: bit 0 = x, bit 1 = y, bit 2 = z.
## That is the same packing `_corner()` uses, so index 2 is (0,1,0) - not
## (1,1,0). Getting this table out of sync with the packing produces quads that
## are not even planar, which renders as shredded, inside-out models.
##
## Quad lists below run counter-clockwise seen from outside the cube, which is
## Godot's front-face winding for a right-handed, y-up, -z-forward world.
const FACE_DEFS := [
	{"direction": Vector3i(1, 0, 0), "quad": [1, 3, 7, 5], "shade": 0.88},   # +x
	{"direction": Vector3i(-1, 0, 0), "quad": [0, 4, 6, 2], "shade": 0.70},  # -x
	{"direction": Vector3i(0, 1, 0), "quad": [2, 6, 7, 3], "shade": 1.00},   # +y (top)
	{"direction": Vector3i(0, -1, 0), "quad": [0, 1, 5, 4], "shade": 0.42},  # -y
	{"direction": Vector3i(0, 0, 1), "quad": [4, 5, 7, 6], "shade": 0.82},   # +z
	{"direction": Vector3i(0, 0, -1), "quad": [0, 2, 3, 1], "shade": 0.60},  # -z
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
			#
			# The order is reversed here on purpose: Godot treats clockwise
			# triangles as front faces when seen from outside, which is the
			# opposite of the right-hand-rule table above. Reversing at emission
			# keeps the table in the orientation a human can check, and keeps
			# the flip in exactly one place.
			for corner_index in [quad[0], quad[2], quad[1], quad[0], quad[3], quad[2]]:
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


## The material every voxel model shares.
##
## Characters are unshaded on purpose. A physically-lit orange lit by a warm key
## and a blue fill comes out beige: the red channel clips first and the tonemapper
## desaturates the highlight, so a saturated character becomes a pastel blob.
## The face shading is already baked into the vertex colours (top 1.0, sides
## 0.88/0.82, undersides 0.6/0.42), so dropping the real lights keeps the palette
## exactly as authored while still reading as a solid volume. They keep casting
## shadows into the world, which is what actually grounds them.
static func make_material(unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.0
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat.roughness = 0.85
	return mat


## Convenience: a ready-to-add MeshInstance3D for a voxel dictionary.
static func make_instance(voxels: Dictionary, voxel_size: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = build(voxels, voxel_size)
	instance.material_override = make_material()
	return instance
