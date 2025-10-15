extends Node3D

@export_range(2, 512, 1)
var size: int = 128

@export_range(1.0, 100.0)
var island_scale: float = 20.0

@export_range(0.1, 10.0)
var noise_scale: float = 3.0

@export_range(0.0, 20.0)
var max_height: float = 10.0

@export var seed: int = 0

# Exported materials
@export var water_material: Material
@export var sand_material: Material
@export var grass_material: Material
@export var rock_material: Material

var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D
var noise: FastNoiseLite

func _ready():
	randomize()

	# Setup noise
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.NoiseType.TYPE_SIMPLEX
	noise.frequency = 1.0 / noise_scale
	noise.fractal_type = FastNoiseLite.FractalType.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.seed = (seed if seed != 0 else randi())

	# Setup mesh instance
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)

	collision_shape = CollisionShape3D.new()
	add_child(collision_shape)

	_generate_island()


func _generate_island():
	# Create SurfaceTools for each material layer
	var st_water = SurfaceTool.new()
	var st_sand = SurfaceTool.new()
	var st_grass = SurfaceTool.new()
	var st_rock = SurfaceTool.new()

	for st in [st_water, st_sand, st_grass, st_rock]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)

	# Track vertex counts manually
	var vertex_counts = [0, 0, 0, 0]  # water, sand, grass, rock

	var heightmap: Array[float] = []
	var positions: Array[Vector3] = []
	var uvs: Array[Vector2] = []

	# Generate heightmap and positions
	for y in range(size):
		for x in range(size):
			var fx = float(x) / (size - 1)
			var fy = float(y) / (size - 1)

			var world_x = (fx - 0.5) * island_scale
			var world_y = (fy - 0.5) * island_scale

			var raw_noise = clamp(noise.get_noise_2d(world_x, world_y), -1.0, 1.0)
			var falloff = island_falloff(x, y)

			var height = (raw_noise * 0.5 + 0.5) * falloff * max_height
			heightmap.append(height)
			positions.append(Vector3(world_x, height, world_y))
			uvs.append(Vector2(fx, fy))



	# Generate triangles and assign to material layer
	for y in range(size - 1):
		for x in range(size - 1):
			var i = y * size + x
			var i_right = i + 1
			var i_down = i + size
			var i_down_right = i_down + 1

			# Triangle A
			vertex_counts[_add_triangle_by_height(
				[positions[i], positions[i_right], positions[i_down]],
				[heightmap[i], heightmap[i_right], heightmap[i_down]],
				[uvs[i], uvs[i_right], uvs[i_down]],   # Pass UVs here
				[st_water, st_sand, st_grass, st_rock],
				vertex_counts
			)] += 3

			# Triangle B
			vertex_counts[_add_triangle_by_height(
				[positions[i_right], positions[i_down_right], positions[i_down]],
				[heightmap[i_right], heightmap[i_down_right], heightmap[i_down]],
				[uvs[i_right], uvs[i_down_right], uvs[i_down]],   # Pass UVs here
				[st_water, st_sand, st_grass, st_rock],
				vertex_counts
			)] += 3


	# Commit mesh with multiple surfaces
	var mesh = ArrayMesh.new()

	for i in range(4):
		if vertex_counts[i] > 0:
			# Index and commit SurfaceTool
			var st = [st_water, st_sand, st_grass, st_rock][i]
			var temp_mesh = st.commit()
			# Get arrays from the temp mesh
			var arrays = temp_mesh.surface_get_arrays(0)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			




	# Assign materials to mesh
	var materials = [water_material, sand_material, grass_material, rock_material]
	for i in range(mesh.get_surface_count()):
		mesh.surface_set_material(i, materials[i])

	mesh_instance.mesh = mesh

	# Set collision shape using full mesh
	var shape = ConcavePolygonShape3D.new()
	shape.data = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	collision_shape.shape = shape



func _add_triangle_by_height(verts: Array, heights: Array, uvs: Array, st_list: Array, vertex_counts: Array) -> int:
	# Get average height of triangle
	var avg_height = (heights[0] + heights[1] + heights[2]) / 3.0
	var st_index: int

	if avg_height < max_height * 0.05:
		st_index = 0  # Water
	elif avg_height < max_height * 0.15:
		st_index = 1  # Sand
	elif avg_height < max_height * 0.6:
		st_index = 2  # Grass
	else:
		st_index = 3  # Rock

	var st = st_list[st_index]

	for i in range(3):
		st.set_uv(uvs[i])     # Set UV before adding vertex
		st.add_vertex(verts[i])

	return st_index


func _add_vertex(st: SurfaceTool, vertex: Vector3, uv: Vector2, color: Color):
	st.set_color(color)
	st.add_uv(uv)
	st.add_vertex(vertex)


func island_falloff(x: int, y: int) -> float:
	var cx = size / 2.0
	var cy = size / 2.0
	var dx = (x - cx) / cx
	var dy = (y - cy) / cy
	var dist = sqrt(dx * dx + dy * dy)
	return clamp(1.0 - dist * dist * 2.0, 0.0, 1.0)
