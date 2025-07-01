# ChunkGeneratorThread.gd
class_name ChunkGeneratorThread
extends Object

# This signal will be emitted on the main thread when generation is complete.
signal chunk_generated(data_packet: Dictionary)

# The main function that the thread will execute.
# It receives all the necessary data from the ChunkManager.
func run_generation(thread_data: Dictionary):
	# 1. Generate the terrain mesh data
	var terrain_surface_arrays = _generate_terrain_data(thread_data)
	
	# 2. Generate the grass transform data using the new terrain data
	var grass_transforms = _generate_grass_data(terrain_surface_arrays, thread_data)
	
	# 3. Generate the tree transform data
	var tree_transforms = _generate_tree_data(terrain_surface_arrays, thread_data)
	
	# 4. Package all the results into a single dictionary
	var output_packet = {
		"coords": thread_data.coords,
		"terrain_arrays": terrain_surface_arrays,
		"grass_transforms": grass_transforms,
		"tree_transforms": tree_transforms
	}
	
	# 5. Emit the signal to send the finished data packet back to the main thread.
	chunk_generated.emit(output_packet)


# --- Private Helper Functions (Heavy Lifting) ---



func _generate_terrain_data(data: Dictionary) -> Array:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Unpack all the needed variables from the data dictionary
	# ... (This unpacking part is unchanged) ...
	var chunk_coords = data.coords; var chunk_size_x = data.chunk_size_x; var chunk_size_z = data.chunk_size_z
	var vertices_x = data.vertices_x; var vertices_z = data.vertices_z; var overall_scale = data.overall_scale
	var noise_continent = data.noise_continent; var continent_slope_scale = data.continent_slope_scale
	var continent_min_height = data.continent_min_height; var continent_max_height = data.continent_max_height
	var noise_mountain = data.noise_mountain; var mountain_scale = data.mountain_scale
	var mountain_start_height = data.mountain_start_height; var mountain_fade_height = data.mountain_fade_height
	var noise_valley = data.noise_valley; var valley_carve_scale = data.valley_carve_scale
	var valley_apply_threshold = data.valley_apply_threshold
	var noise_erosion = data.noise_erosion; var erosion_scale = data.erosion_scale

	# ... (The entire loop for generating vertices and indices is unchanged) ...
	var step_x = chunk_size_x / float(vertices_x - 1); var step_z = chunk_size_z / float(vertices_z - 1)
	for z in range(vertices_z):
		for x in range(vertices_x):
			var vx = x * step_x; var vz = z * step_z
			var wx = vx + chunk_coords.x * chunk_size_x; var wz = vz + chunk_coords.y * chunk_size_z
			var raw_continent_noise = noise_continent.get_noise_2d(wx, wz); var normalized_continent_noise = (raw_continent_noise + 1.0) * 0.5
			var conceptual_base_height = lerp(continent_min_height, continent_max_height, normalized_continent_noise)
			var mountain_modulator = clamp((conceptual_base_height - mountain_start_height) / mountain_fade_height, 0.0, 1.0)
			var m_potential = max(0.0, noise_mountain.get_noise_2d(wx, wz)) * mountain_scale; var m = m_potential * mountain_modulator
			var valley_carve = 0.0
			if conceptual_base_height < valley_apply_threshold:
				var valley_noise = noise_valley.get_noise_2d(wx, wz); var negative_valley = min(valley_noise, 0.0)
				var valley_modulator = clamp((valley_apply_threshold - conceptual_base_height) / valley_apply_threshold, 0.0, 1.0)
				valley_carve = negative_valley * valley_carve_scale * valley_modulator
			var nc = normalized_continent_noise; var erosion_modulator = 1.0 - abs(nc - 0.5) * 2.0
			var bump_e = noise_erosion.get_noise_2d(wx, wz) * erosion_scale * erosion_modulator
			var c_slope_contribution = raw_continent_noise * continent_slope_scale
			var height = c_slope_contribution + m + valley_carve + bump_e
			st.set_uv(Vector2(x / float(vertices_x - 1), z / float(vertices_z - 1)))
			st.add_vertex(Vector3(vx, height, vz))

	for z in range(vertices_z - 1):
		for x in range(vertices_x - 1):
			var i00 = z * vertices_x + x; var i10 = i00 + 1; var i01 = (z + 1) * vertices_x + x; var i11 = i01 + 1
			st.add_index(i00); st.add_index(i10); st.add_index(i01); st.add_index(i10); st.add_index(i11); st.add_index(i01)
	
	st.generate_normals()
	st.generate_tangents()
	
	# --- THIS IS THE FIX ---
	# 1. Commit the SurfaceTool data to a temporary ArrayMesh.
	var temp_mesh: ArrayMesh = st.commit()
	
	# 2. Check if the mesh was created successfully and has at least one surface.
	if temp_mesh and temp_mesh.get_surface_count() > 0:
		# 3. Return the raw array data from the first surface of the temporary mesh.
		return temp_mesh.surface_get_arrays(0)
	else:
		# 4. If something went wrong, return an empty array to prevent crashes.
		printerr("ChunkGeneratorThread: Failed to generate terrain mesh data for chunk.")
		return []




func _generate_grass_data(terrain_arrays: Array, data: Dictionary) -> Array:
	if terrain_arrays.is_empty(): return []
	
	var vertices = terrain_arrays[Mesh.ARRAY_VERTEX]; var normals = terrain_arrays[Mesh.ARRAY_NORMAL]
	var indices = terrain_arrays[Mesh.ARRAY_INDEX]
	
	var grass_min_height = data.grass_min_height; var grass_max_height = data.grass_max_height
	var grass_max_slope = data.grass_max_slope_normal_y; var grass_density = data.grass_density
	var rot_min = data.grass_rotation_min_degrees; var rot_max = data.grass_rotation_max_degrees
	var scale_min = data.grass_scale_min; var scale_max = data.grass_scale_max
	var overall_scale = data.overall_scale

	var temp_transforms: Array[Transform3D] = []
	for i in range(0, indices.size(), 3):
		var p0 = vertices[indices[i]]; var p1 = vertices[indices[i+1]]; var p2 = vertices[indices[i+2]]
		var avg_normal = (normals[indices[i]] + normals[indices[i+1]] + normals[indices[i+2]]).normalized()
		var local_avg_pos = (p0 + p1 + p2) / 3.0
		
		# Note: We are back to checking LOCAL height, because the thread doesn't know the chunk's global position.
		if not (local_avg_pos.y > grass_min_height and local_avg_pos.y < grass_max_height): continue
		if avg_normal.y < grass_max_slope: continue
		
		var area = (p1 - p0).cross(p2 - p0).length() * 0.5; var world_area = area * (overall_scale * overall_scale)
		var num_clumps = floori(world_area * grass_density)
		for j in range(num_clumps):
			var r1 = randf(); var r2 = randf(); if r1 + r2 > 1.0: r1 = 1.0 - r1; r2 = 1.0 - r2
			var point = p0 + r1 * (p1 - p0) + r2 * (p2 - p0)
			var basis = Basis.IDENTITY
			var rot_x = deg_to_rad(randf_range(rot_min.x, rot_max.x)); var rot_y = deg_to_rad(randf_range(rot_min.y, rot_max.y)); var rot_z = deg_to_rad(randf_range(rot_min.z, rot_max.z))
			basis = basis.rotated(Vector3.UP, rot_y).rotated(Vector3.RIGHT, rot_x).rotated(Vector3.FORWARD, rot_z)
			basis = basis.scaled(Vector3.ONE * randf_range(scale_min, scale_max))
			temp_transforms.append(Transform3D(basis, point))

	var chunk_center = Vector3(data.chunk_size_x / 2.0, 0, data.chunk_size_z / 2.0)
	temp_transforms.sort_custom(func(a,b): return a.origin.distance_squared_to(chunk_center) < b.origin.distance_squared_to(chunk_center))
	return temp_transforms


func _generate_tree_data(terrain_arrays: Array, data: Dictionary) -> Array:
	if terrain_arrays.is_empty(): return []

	var vertices = terrain_arrays[Mesh.ARRAY_VERTEX]; var normals = terrain_arrays[Mesh.ARRAY_NORMAL]
	var indices = terrain_arrays[Mesh.ARRAY_INDEX]

	var tree_min_h = data.tree_min_height; var tree_max_h = data.tree_max_height
	var tree_max_slope = data.tree_max_slope_normal_y; var tree_density = data.tree_density
	var tree_scale_min = data.tree_scale_min; var tree_scale_max = data.tree_scale_max

	var tree_transforms: Array[Transform3D] = []
	var rng = RandomNumberGenerator.new()
	for i in range(0, indices.size(), 3):
		var p0 = vertices[indices[i]]; var p1 = vertices[indices[i+1]]; var p2 = vertices[indices[i+2]]
		var avg_normal = (normals[indices[i]] + normals[indices[i+1]] + normals[indices[i+2]]).normalized()
		var local_avg_pos = (p0 + p1 + p2) / 3.0
		
		if not (local_avg_pos.y > tree_min_h and local_avg_pos.y < tree_max_h): continue
		if avg_normal.y < tree_max_slope: continue
		if rng.randf() > tree_density: continue

		var r1 = rng.randf(); var r2 = rng.randf(); if r1 + r2 > 1.0: r1 = 1.0 - r1; r2 = 1.0 - r2
		var point = p0 + r1 * (p1 - p0) + r2 * (p2 - p0)
		var basis = Basis.IDENTITY
		basis = basis.rotated(Vector3.UP, rng.randf_range(0, TAU))
		basis = basis.scaled(Vector3.ONE * rng.randf_range(tree_scale_min, tree_scale_max))
		tree_transforms.append(Transform3D(basis, point))

	return tree_transforms
