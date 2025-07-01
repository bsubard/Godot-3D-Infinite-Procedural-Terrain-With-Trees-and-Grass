# Chunk.gd
extends Node3D

# --- Node References ---
@export var mesh_instance: MeshInstance3D
@export var collision_shape: CollisionShape3D
@export var water_mesh_instance: MeshInstance3D
@export var grass_multimesh: MultiMeshInstance3D
@export var tree_multimesh: MultiMeshInstance3D # <-- NEW

# --- Chunk Configuration ---
@export_group("Chunk Size")
@export var chunk_size_x: int = 32
@export var chunk_size_z: int = 32
@export var vertices_x: int = 33
@export var vertices_z: int = 33

# --- Terrain Generation ---
# ... (This entire section is unchanged) ...
@export_group("Base Continent")
@export var noise_continent: FastNoiseLite
@export var continent_slope_scale: float = 8.0
@export var continent_min_height: float = -10.0
@export var continent_max_height: float = 25.0
@export_group("Mountain Control")
@export var noise_mountain: FastNoiseLite
@export var mountain_scale: float = 40.0
@export var mountain_start_height: float = 10.0
@export var mountain_fade_height: float = 10.0
@export_group("Valley Control")
@export var noise_valley: FastNoiseLite
@export var valley_carve_scale: float = 15.0
@export var valley_apply_threshold: float = 5.0
@export_group("Erosion Control")
@export var noise_erosion: FastNoiseLite
@export var erosion_scale: float = 2.5

# --- Water Plane ---
@export_group("Water Plane")
@export var visual_water_level: float = -2.0

# --- Grass Placement Rules ---
# ... (This entire section is unchanged) ...
@export_group("Grass Placement Rules")
@export var grass_material: Material
@export var grass_min_height: float = 2.5
@export var grass_max_height: float = 79.0
@export var grass_max_slope_normal_y: float = 0.8
@export var grass_density: float = 0.1

# --- Grass Randomization ---
# ... (This entire section is unchanged) ...
@export_group("Grass Randomization")
@export var grass_rotation_min_degrees: Vector3 = Vector3(80, 0, -5)
@export var grass_rotation_max_degrees: Vector3 = Vector3(100, 360, 5)
@export var grass_scale_min: float = 0.8
@export var grass_scale_max: float = 1.3

# --- Grass LOD --- <-- NEW
@export_group("Grass LOD")
## Distances at which to switch LOD levels.
@export var lod_distances: PackedFloat32Array = [80.0, 160.0, 240.0]
## Density multipliers for each LOD level. Should have one more element than lod_distances for the final "fallback" density.
@export var lod_density_multipliers: PackedFloat32Array = [1.0, 0.5, 0.2, 0.0]


# --- Tree Placement Rules ---  <-- NEW SECTION
@export_group("Tree Placement Rules")
@export var tree_trunk_material: Material
@export var tree_leaves_material: Material
@export var tree_min_height: float = 5.0
@export var tree_max_height: float = 60.0
@export var tree_max_slope_normal_y: float = 0.9
@export var tree_density: float = 0.005 # Trees are much less dense than grass

# --- Tree Randomization --- <-- NEW SECTION
@export_group("Tree Randomization")
@export var tree_scale_min: float = 0.7
@export var tree_scale_max: float = 1.1
# Note: We only need Y-axis rotation for trees to keep them upright

@export_group("Overall Scaling")
@export var overall_scale: float = 10.0

# --- Internal State ---
var chunk_coords: Vector2i = Vector2i.ZERO
var _grass_blade_mesh: ArrayMesh
var _tree_mesh: ArrayMesh
var _sorted_grass_transforms: Array[Transform3D] = [] # <-- NEW

#=============================================================================
# --- CORE FUNCTIONS ---

func _ready():
	_grass_blade_mesh = _create_grass_blade_mesh()
	_tree_mesh = _create_tree_mesh()

func initialize_chunk(coords: Vector2i):
	chunk_coords = coords
	global_position.x = coords.x * chunk_size_x * overall_scale
	global_position.z = coords.y * chunk_size_z * overall_scale
	name = "Chunk_%d_%d" % [coords.x, coords.y]
	
	generate_terrain()
	setup_water_plane()
	generate_grass()
	generate_trees()
	
	scale = Vector3(overall_scale, overall_scale, overall_scale)


#=============================================================================
# --- MESH GENERATION ---

func _create_grass_blade_mesh() -> ArrayMesh:
	# ... (This function is unchanged) ...
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height = 0.2; var base_width = 0.02; var tip_width = 0.002
	var v0 = Vector3(-base_width, 0, 0); var v1 = Vector3(base_width, 0, 0)
	var v2 = Vector3(tip_width, 0, height); var v3 = Vector3(-tip_width, 0, height)
	st.set_uv(Vector2(0, 1)); st.add_vertex(v0); st.set_uv(Vector2(1, 1)); st.add_vertex(v1)
	st.set_uv(Vector2(1, 0)); st.add_vertex(v2); st.set_uv(Vector2(0, 0)); st.add_vertex(v3)
	st.add_index(0); st.add_index(1); st.add_index(3); st.add_index(1); st.add_index(2); st.add_index(3)
	if is_instance_valid(grass_material): st.set_material(grass_material)
	else:
		printerr("Grass Material not assigned in Chunk Inspector! Creating a bright magenta default.")
		var m = StandardMaterial3D.new(); m.albedo_color = Color.MAGENTA; m.cull_mode = BaseMaterial3D.CULL_DISABLED; st.set_material(m)
	st.generate_normals(); return st.commit()

func _create_tree_mesh() -> ArrayMesh:
	# --- The Robust Solution: Use separate SurfaceTools and commit them to the same ArrayMesh ---

	# --- 1. Create and build the TRUNK surface ---
	var st_trunk = SurfaceTool.new()
	st_trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	if is_instance_valid(tree_trunk_material):
		st_trunk.set_material(tree_trunk_material)
	else:
		printerr("Tree Trunk Material not assigned! Using a brown default.")
		var m = StandardMaterial3D.new(); m.albedo_color = Color("saddlebrown"); st_trunk.set_material(m)
		
	# Define Tree Dimensions
	var trunk_height = 1.5
	var trunk_width = 0.15
	
	# Trunk Vertices
	var trunk_verts = [
		Vector3(-trunk_width, 0, -trunk_width), Vector3(trunk_width, 0, -trunk_width),
		Vector3(trunk_width, 0, trunk_width), Vector3(-trunk_width, 0, trunk_width),
		Vector3(-trunk_width, trunk_height, -trunk_width), Vector3(trunk_width, trunk_height, -trunk_width),
		Vector3(trunk_width, trunk_height, trunk_width), Vector3(-trunk_width, trunk_height, trunk_width)
	]
	
	# Standard UVs for a quad face
	var uv0 = Vector2(0, 1); var uv1 = Vector2(1, 1); var uv2 = Vector2(1, 0); var uv3 = Vector2(0, 0)

	# Build trunk faces with UVs (same as before, but on st_trunk)
	# Front
	st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[4]); st_trunk.set_uv(uv1); st_trunk.add_vertex(trunk_verts[5]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[1])
	st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[4]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[1]); st_trunk.set_uv(uv3); st_trunk.add_vertex(trunk_verts[0])
	# Back
	st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[6]); st_trunk.set_uv(uv1); st_trunk.add_vertex(trunk_verts[7]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[3])
	st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[6]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[3]); st_trunk.set_uv(uv3); st_trunk.add_vertex(trunk_verts[2])
	# Left
	st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[7]); st_trunk.set_uv(uv1); st_trunk.add_vertex(trunk_verts[4]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[0])
	st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[7]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[0]); st_trunk.set_uv(uv3); st_trunk.add_vertex(trunk_verts[3])
	# Right
	st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[5]); st_trunk.set_uv(uv1); st_trunk.add_vertex(trunk_verts[6]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[2])
	st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[5]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[2]); st_trunk.set_uv(uv3); st_trunk.add_vertex(trunk_verts[1])

	st_trunk.generate_normals()
	st_trunk.generate_tangents()


	# --- 2. Create and build the LEAVES surface ---
	var st_leaves = SurfaceTool.new()
	st_leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	if is_instance_valid(tree_leaves_material):
		st_leaves.set_material(tree_leaves_material)
	else:
		printerr("Tree Leaves Material not assigned! Using a green default.")
		var m = StandardMaterial3D.new(); m.albedo_color = Color("forestgreen"); st_leaves.set_material(m)
		
	# Define Leaves Dimensions
	var leaves_height = 1.2
	var leaves_width = 0.7
	var leaves_base_y = trunk_height
	
	# Leaves Vertices
	var leaves_verts = [
		Vector3(-leaves_width, leaves_base_y, -leaves_width), Vector3(leaves_width, leaves_base_y, -leaves_width),
		Vector3(leaves_width, leaves_base_y, leaves_width), Vector3(-leaves_width, leaves_base_y, leaves_width),
		Vector3(-leaves_width, leaves_base_y + leaves_height, -leaves_width), Vector3(leaves_width, leaves_base_y + leaves_height, -leaves_width),
		Vector3(leaves_width, leaves_base_y + leaves_height, leaves_width), Vector3(-leaves_width, leaves_base_y + leaves_height, leaves_width)
	]
	
	# Build leaves faces with UVs (on st_leaves)
	# Front
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[4]); st_leaves.set_uv(uv1); st_leaves.add_vertex(leaves_verts[5]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[1])
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[4]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[1]); st_leaves.set_uv(uv3); st_leaves.add_vertex(leaves_verts[0])
	# Back
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[6]); st_leaves.set_uv(uv1); st_leaves.add_vertex(leaves_verts[7]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[3])
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[6]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[3]); st_leaves.set_uv(uv3); st_leaves.add_vertex(leaves_verts[2])
	# Left
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[7]); st_leaves.set_uv(uv1); st_leaves.add_vertex(leaves_verts[4]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[0])
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[7]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[0]); st_leaves.set_uv(uv3); st_leaves.add_vertex(leaves_verts[3])
	# Right
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[5]); st_leaves.set_uv(uv1); st_leaves.add_vertex(leaves_verts[6]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[2])
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[5]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[2]); st_leaves.set_uv(uv3); st_leaves.add_vertex(leaves_verts[1])
	# Top
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[7]); st_leaves.set_uv(uv1); st_leaves.add_vertex(leaves_verts[6]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[5])
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[7]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[5]); st_leaves.set_uv(uv3); st_leaves.add_vertex(leaves_verts[4])
	# Bottom
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[0]); st_leaves.set_uv(uv1); st_leaves.add_vertex(leaves_verts[1]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[2])
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[0]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[2]); st_leaves.set_uv(uv3); st_leaves.add_vertex(leaves_verts[3])

	st_leaves.generate_normals()
	st_leaves.generate_tangents()


	# --- 3. Combine the surfaces into a single ArrayMesh ---
	var final_mesh = ArrayMesh.new()
	
	# First, commit the trunk tool. This CREATES the mesh with the first surface.
	st_trunk.commit(final_mesh)
	
	# Second, commit the leaves tool TO THE SAME MESH. This APPENDS a second surface.
	st_leaves.commit(final_mesh)
	
	return final_mesh



func generate_terrain():
	# ... (This function is unchanged) ...
	var st = SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); var step_x = chunk_size_x / float(vertices_x - 1); var step_z = chunk_size_z / float(vertices_z - 1); var _noise_continent = noise_continent; var _noise_mountain = noise_mountain; var _noise_valley = noise_valley; var _noise_erosion = noise_erosion;
	for z in range(vertices_z):
		for x in range(vertices_x):
			var vx = x * step_x; var vz = z * step_z; var wx = vx + chunk_coords.x * chunk_size_x; var wz = vz + chunk_coords.y * chunk_size_z; var raw_continent_noise = _noise_continent.get_noise_2d(wx, wz); var normalized_continent_noise = (raw_continent_noise + 1.0) * 0.5; var conceptual_base_height = lerp(continent_min_height, continent_max_height, normalized_continent_noise); var mountain_modulator = clamp((conceptual_base_height - mountain_start_height) / mountain_fade_height, 0.0, 1.0); var m_potential = max(0.0, _noise_mountain.get_noise_2d(wx, wz)) * mountain_scale; var m = m_potential * mountain_modulator; var valley_carve = 0.0;
			if conceptual_base_height < valley_apply_threshold: var valley_noise = _noise_valley.get_noise_2d(wx, wz); var negative_valley = min(valley_noise, 0.0); var valley_modulator = clamp((valley_apply_threshold - conceptual_base_height) / valley_apply_threshold, 0.0, 1.0); valley_carve = negative_valley * valley_carve_scale * valley_modulator;
			var nc = normalized_continent_noise; var erosion_modulator = 1.0 - abs(nc - 0.5) * 2.0; var bump_e = _noise_erosion.get_noise_2d(wx, wz) * erosion_scale * erosion_modulator; var c_slope_contribution = raw_continent_noise * continent_slope_scale; var height = c_slope_contribution + m + valley_carve + bump_e; var vertex = Vector3(vx, height, vz); var uv = Vector2(x / float(vertices_x - 1), z / float(vertices_z - 1)); st.set_uv(uv); st.add_vertex(vertex);
	for z in range(vertices_z - 1):
		for x in range(vertices_x - 1): var i00 = z * vertices_x + x; var i10 = i00 + 1; var i01 = (z + 1) * vertices_x + x; var i11 = i01 + 1; st.add_index(i00); st.add_index(i10); st.add_index(i01); st.add_index(i10); st.add_index(i11); st.add_index(i01);
	st.generate_normals(); st.generate_tangents(); var mesh: ArrayMesh = st.commit(); mesh_instance.mesh = mesh; var coll_shape = ConcavePolygonShape3D.new(); coll_shape.set_faces(mesh.get_faces()); collision_shape.shape = coll_shape;

func setup_water_plane() -> void:
	# ... (This function is unchanged) ...
	var plane_mesh: PlaneMesh; if water_mesh_instance.mesh is PlaneMesh and water_mesh_instance.mesh.size == Vector2(chunk_size_x, chunk_size_z): plane_mesh = water_mesh_instance.mesh
	else: plane_mesh = PlaneMesh.new(); plane_mesh.size = Vector2(chunk_size_x, chunk_size_z); water_mesh_instance.mesh = plane_mesh
	water_mesh_instance.position = Vector3(chunk_size_x / 2.0, visual_water_level, chunk_size_z / 2.0); water_mesh_instance.visible = true

# --- MODIFIED: generate_grass() ---
func generate_grass() -> void:
	_sorted_grass_transforms.clear() # Clear previous data

	if not grass_multimesh or not is_instance_valid(_grass_blade_mesh): return
	var terrain_mesh: ArrayMesh = mesh_instance.mesh
	if not terrain_mesh or terrain_mesh.get_surface_count() == 0: return

	var mesh_arrays = terrain_mesh.surface_get_arrays(0)
	var vertices = mesh_arrays[Mesh.ARRAY_VERTEX]
	var normals = mesh_arrays[Mesh.ARRAY_NORMAL]
	var indices = mesh_arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty(): return

	# We generate all potential transforms into a temporary array first.
	var temp_transforms: Array[Transform3D] = []
	var mesh_global_transform = mesh_instance.global_transform

	for i in range(0, indices.size(), 3):
		var p0 = vertices[indices[i]]; var p1 = vertices[indices[i+1]]; var p2 = vertices[indices[i+2]]
		var avg_normal = (normals[indices[i]] + normals[indices[i+1]] + normals[indices[i+2]]).normalized()
		var local_avg_pos = (p0 + p1 + p2) / 3.0
		var world_avg_pos = mesh_global_transform * local_avg_pos
		
		# Use the correct global height and slope checks
		if not (world_avg_pos.y > grass_min_height and world_avg_pos.y < grass_max_height): continue
		if avg_normal.y < grass_max_slope_normal_y: continue
		
		var area = (p1 - p0).cross(p2 - p0).length() * 0.5
		var world_area = area * (overall_scale * overall_scale)
		var num_clumps_to_spawn = floori(world_area * grass_density)

		for j in range(num_clumps_to_spawn):
			var r1 = randf(); var r2 = randf(); if r1 + r2 > 1.0: r1 = 1.0 - r1; r2 = 1.0 - r2
			var point_on_triangle = p0 + r1 * (p1 - p0) + r2 * (p2 - p0)
			
			var basis = Basis.IDENTITY
			var rot_x = deg_to_rad(randf_range(grass_rotation_min_degrees.x, grass_rotation_max_degrees.x))
			var rot_y = deg_to_rad(randf_range(grass_rotation_min_degrees.y, grass_rotation_max_degrees.y))
			var rot_z = deg_to_rad(randf_range(grass_rotation_min_degrees.z, grass_rotation_max_degrees.z))
			basis = basis.rotated(Vector3.UP, rot_y).rotated(Vector3.RIGHT, rot_x).rotated(Vector3.FORWARD, rot_z)
			basis = basis.scaled(Vector3.ONE * randf_range(grass_scale_min, grass_scale_max))
			
			var transform = Transform3D(basis, point_on_triangle)
			temp_transforms.append(transform)

	if temp_transforms.is_empty():
		grass_multimesh.multimesh = null; return

	# NEW: Sort transforms by distance from the chunk's center.
	# This ensures we remove the "outer" blades of grass within a chunk first.
	var chunk_center = Vector3(chunk_size_x / 2.0, 0, chunk_size_z / 2.0)
	temp_transforms.sort_custom(
		func(a: Transform3D, b: Transform3D) -> bool:
			return a.origin.distance_squared_to(chunk_center) < b.origin.distance_squared_to(chunk_center)
	)
	# Store the fully sorted, master list of transforms.
	_sorted_grass_transforms = temp_transforms

	# Finalize the MultiMesh using ALL the sorted transforms.
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _grass_blade_mesh
	multimesh.instance_count = _sorted_grass_transforms.size()
	
	var buffer = PackedFloat32Array()
	buffer.resize(_sorted_grass_transforms.size() * 12); var idx = 0
	for t in _sorted_grass_transforms:
		buffer[idx+0]=t.basis.x.x; buffer[idx+1]=t.basis.x.y; buffer[idx+2]=t.basis.x.z; buffer[idx+3]=t.origin.x
		buffer[idx+4]=t.basis.y.x; buffer[idx+5]=t.basis.y.y; buffer[idx+6]=t.basis.y.z; buffer[idx+7]=t.origin.y
		buffer[idx+8]=t.basis.z.x; buffer[idx+9]=t.basis.z.y; buffer[idx+10]=t.basis.z.z; buffer[idx+11]=t.origin.z
		idx += 12
	multimesh.set_buffer(buffer)
	# Initially, set the visible count to the max. It will be updated by the ChunkManager.
	multimesh.visible_instance_count = _sorted_grass_transforms.size()
	grass_multimesh.multimesh = multimesh



# --- CORRECTED FUNCTION ---
func update_grass_lod(player_pos: Vector3) -> void:
	if not is_instance_valid(grass_multimesh) or not is_instance_valid(grass_multimesh.multimesh):
		return

	# 1. Get the AABB of the visible terrain mesh in local space.
	var local_aabb: AABB = mesh_instance.get_aabb()
	
	# 2. Transform this local AABB into world space.
	var world_aabb: AABB = global_transform * local_aabb
	
	# 3. Define the min and max corners of the world AABB.
	# The max corner is the position + the size. THIS IS THE FIX.
	var min_corner: Vector3 = world_aabb.position
	var max_corner: Vector3 = world_aabb.position + world_aabb.size
	
	# 4. Find the closest point ON the surface (or inside) of the AABB to the player.
	var closest_point_on_aabb: Vector3 = player_pos.clamp(min_corner, max_corner)
	
	# 5. Now, calculate the distance from the player to that closest point.
	# If the player is inside the box, this distance will correctly be 0.
	var distance_to_chunk = player_pos.distance_to(closest_point_on_aabb)

	# --- The rest of the logic is the same and now works with the correct distance ---
	var density_multiplier = lod_density_multipliers[lod_density_multipliers.size() - 1] # Start with fallback
	for i in range(lod_distances.size()):
		if distance_to_chunk < lod_distances[i]:
			density_multiplier = lod_density_multipliers[i]
			break # Found the right LOD level, exit the loop.

	var total_instances = _sorted_grass_transforms.size()
	var visible_count = int(total_instances * density_multiplier)
	
	grass_multimesh.multimesh.visible_instance_count = visible_count



func generate_trees() -> void:
	if not tree_multimesh or not is_instance_valid(_tree_mesh): return
	var terrain_mesh: ArrayMesh = mesh_instance.mesh
	if not terrain_mesh or terrain_mesh.get_surface_count() == 0: return
	var mesh_arrays = terrain_mesh.surface_get_arrays(0)
	var vertices = mesh_arrays[Mesh.ARRAY_VERTEX]
	var normals = mesh_arrays[Mesh.ARRAY_NORMAL]
	var indices = mesh_arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty(): return
	var tree_transforms: Array[Transform3D] = []
	var rng = RandomNumberGenerator.new()

	# --- FIX: Get the mesh's global transform ONCE outside the loop ---
	var mesh_global_transform = mesh_instance.global_transform

	for i in range(0, indices.size(), 3):
		var p0 = vertices[indices[i]]; var p1 = vertices[indices[i+1]]; var p2 = vertices[indices[i+2]]
		var avg_normal = (normals[indices[i]] + normals[indices[i+1]] + normals[indices[i+2]]).normalized()
		var local_avg_pos = (p0 + p1 + p2) / 3.0 # This is in LOCAL space
		
		# --- FIX: Convert the local position to a global (world) position ---
		var world_avg_pos = mesh_global_transform * local_avg_pos
		
		# --- FIX: Use the world position's Y for the height check ---
		if not (world_avg_pos.y > tree_min_height and world_avg_pos.y < tree_max_height): continue

		if avg_normal.y < tree_max_slope_normal_y: continue
		if rng.randf() > tree_density: continue

		var r1 = rng.randf(); var r2 = rng.randf()
		if r1 + r2 > 1.0: r1 = 1.0 - r1; r2 = 1.0 - r2
		var point_on_triangle = p0 + r1 * (p1 - p0) + r2 * (p2 - p0)
		
		var basis = Basis.IDENTITY
		var rot_y = rng.randf_range(0, TAU)
		basis = basis.rotated(Vector3.UP, rot_y)
		basis = basis.scaled(Vector3.ONE * rng.randf_range(tree_scale_min, tree_scale_max))
		
		var transform = Transform3D(basis, point_on_triangle)
		tree_transforms.append(transform)

	# ... (rest of the function is unchanged) ...
	if tree_transforms.is_empty(): tree_multimesh.multimesh = null; return
	var multimesh = MultiMesh.new(); multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _tree_mesh; multimesh.instance_count = tree_transforms.size()
	var buffer = PackedFloat32Array(); buffer.resize(tree_transforms.size() * 12); var idx = 0
	for t in tree_transforms:
		buffer[idx+0]=t.basis.x.x; buffer[idx+1]=t.basis.x.y; buffer[idx+2]=t.basis.x.z; buffer[idx+3]=t.origin.x
		buffer[idx+4]=t.basis.y.x; buffer[idx+5]=t.basis.y.y; buffer[idx+6]=t.basis.y.z; buffer[idx+7]=t.origin.y
		buffer[idx+8]=t.basis.z.x; buffer[idx+9]=t.basis.z.y; buffer[idx+10]=t.basis.z.z; buffer[idx+11]=t.origin.z
		idx += 12
	multimesh.set_buffer(buffer); tree_multimesh.multimesh = multimesh
