# Chunk.gd (Simplified Version)
extends Node3D

# --- Node References (Unchanged) ---
@export var mesh_instance: MeshInstance3D
@export var collision_shape: CollisionShape3D
@export var water_mesh_instance: MeshInstance3D
@export var grass_multimesh: MultiMeshInstance3D
@export var tree_multimesh: MultiMeshInstance3D

# --- Configuration (Unchanged) ---
# These are still useful for the ChunkManager to read and for default values.
@export_group("Chunk Size")
@export var chunk_size_x: int = 32
@export var chunk_size_z: int = 32
@export var vertices_x: int = 33
@export var vertices_z: int = 33

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

@export_group("Water Plane")
@export var visual_water_level: float = -2.0

@export_group("Grass Placement Rules")
@export var grass_material: Material
@export var grass_min_height: float = 2.5
@export var grass_max_height: float = 79.0
@export var grass_max_slope_normal_y: float = 0.8
@export var grass_density: float = 0.1

@export_group("Grass Randomization")
@export var grass_rotation_min_degrees: Vector3 = Vector3(80, 0, -5)
@export var grass_rotation_max_degrees: Vector3 = Vector3(100, 360, 5)
@export var grass_scale_min: float = 0.8
@export var grass_scale_max: float = 1.3

@export_group("Grass LOD")
@export var lod_distances: PackedFloat32Array = [80.0, 160.0, 240.0]
@export var lod_density_multipliers: PackedFloat32Array = [1.0, 0.5, 0.2, 0.0]

@export_group("Tree Placement Rules")
@export var tree_trunk_material: Material
@export var tree_leaves_material: Material
@export var tree_min_height: float = 5.0
@export var tree_max_height: float = 60.0
@export var tree_max_slope_normal_y: float = 0.9
@export var tree_density: float = 0.005

@export_group("Tree Randomization")
@export var tree_scale_min: float = 0.7
@export var tree_scale_max: float = 1.1

@export_group("Overall Scaling")
@export var overall_scale: float = 10.0

# --- Internal State ---
var chunk_coords: Vector2i = Vector2i.ZERO
var _grass_blade_mesh: ArrayMesh
var _tree_mesh: ArrayMesh
var _sorted_grass_transforms: Array[Transform3D] = []

func _ready():
	_grass_blade_mesh = _create_grass_blade_mesh()
	_tree_mesh = _create_tree_mesh()

func apply_generated_data(data: Dictionary):
	# --- 1. Apply Terrain Mesh ---
	var terrain_arrays = data.terrain_arrays
	var terrain_mesh = ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, terrain_arrays)
	mesh_instance.mesh = terrain_mesh
	var coll_shape = ConcavePolygonShape3D.new()
	coll_shape.set_faces(terrain_mesh.get_faces())
	collision_shape.shape = coll_shape

	# --- 2. Apply Grass ---
	_sorted_grass_transforms = data.grass_transforms
	if not _sorted_grass_transforms.is_empty():
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _grass_blade_mesh
		multimesh.instance_count = _sorted_grass_transforms.size()
		var buffer = PackedFloat32Array(); buffer.resize(_sorted_grass_transforms.size() * 12); var idx = 0
		for t in _sorted_grass_transforms:
			buffer[idx+0]=t.basis.x.x; buffer[idx+1]=t.basis.x.y; buffer[idx+2]=t.basis.x.z; buffer[idx+3]=t.origin.x
			buffer[idx+4]=t.basis.y.x; buffer[idx+5]=t.basis.y.y; buffer[idx+6]=t.basis.y.z; buffer[idx+7]=t.origin.y
			buffer[idx+8]=t.basis.z.x; buffer[idx+9]=t.basis.z.y; buffer[idx+10]=t.basis.z.z; buffer[idx+11]=t.origin.z
			idx += 12
		multimesh.set_buffer(buffer)
		grass_multimesh.multimesh = multimesh
	else:
		grass_multimesh.multimesh = null
	
	# --- 3. Apply Trees ---
	var tree_transforms = data.tree_transforms
	if not tree_transforms.is_empty():
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _tree_mesh
		multimesh.instance_count = tree_transforms.size()
		var buffer = PackedFloat32Array(); buffer.resize(tree_transforms.size() * 12); var idx = 0
		for t in tree_transforms:
			buffer[idx+0]=t.basis.x.x; buffer[idx+1]=t.basis.x.y; buffer[idx+2]=t.basis.x.z; buffer[idx+3]=t.origin.x
			buffer[idx+4]=t.basis.y.x; buffer[idx+5]=t.basis.y.y; buffer[idx+6]=t.basis.y.z; buffer[idx+7]=t.origin.y
			buffer[idx+8]=t.basis.z.x; buffer[idx+9]=t.basis.z.y; buffer[idx+10]=t.basis.z.z; buffer[idx+11]=t.origin.z
			idx += 12
		multimesh.set_buffer(buffer)
		tree_multimesh.multimesh = multimesh
	else:
		tree_multimesh.multimesh = null
	
	# --- 4. Final Setup ---
	setup_water_plane()
	scale = Vector3(overall_scale, overall_scale, overall_scale)

# --- UNCHANGED FUNCTIONS BELOW ---

func update_grass_lod(player_pos: Vector3) -> void:
	if not is_instance_valid(grass_multimesh) or not is_instance_valid(grass_multimesh.multimesh): return
	var local_aabb: AABB = mesh_instance.get_aabb()
	var world_aabb: AABB = global_transform * local_aabb
	var min_corner: Vector3 = world_aabb.position
	var max_corner: Vector3 = world_aabb.position + world_aabb.size
	var closest_point_on_aabb: Vector3 = player_pos.clamp(min_corner, max_corner)
	var distance_to_chunk = player_pos.distance_to(closest_point_on_aabb)
	var density_multiplier = lod_density_multipliers[lod_density_multipliers.size() - 1]
	for i in range(lod_distances.size()):
		if distance_to_chunk < lod_distances[i]:
			density_multiplier = lod_density_multipliers[i]; break
	var total_instances = _sorted_grass_transforms.size()
	var visible_count = int(total_instances * density_multiplier)
	grass_multimesh.multimesh.visible_instance_count = visible_count

func setup_water_plane() -> void:
	var plane_mesh: PlaneMesh
	if water_mesh_instance.mesh is PlaneMesh and water_mesh_instance.mesh.size == Vector2(chunk_size_x, chunk_size_z): plane_mesh = water_mesh_instance.mesh
	else: plane_mesh = PlaneMesh.new(); plane_mesh.size = Vector2(chunk_size_x, chunk_size_z); water_mesh_instance.mesh = plane_mesh
	water_mesh_instance.position = Vector3(chunk_size_x / 2.0, visual_water_level, chunk_size_z / 2.0)
	water_mesh_instance.visible = true

func _create_grass_blade_mesh() -> ArrayMesh:
	var st = SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); var height = 0.2; var base_width = 0.02; var tip_width = 0.002
	var v0 = Vector3(-base_width, 0, 0); var v1 = Vector3(base_width, 0, 0); var v2 = Vector3(tip_width, 0, height); var v3 = Vector3(-tip_width, 0, height)
	st.set_uv(Vector2(0, 1)); st.add_vertex(v0); st.set_uv(Vector2(1, 1)); st.add_vertex(v1); st.set_uv(Vector2(1, 0)); st.add_vertex(v2); st.set_uv(Vector2(0, 0)); st.add_vertex(v3)
	st.add_index(0); st.add_index(1); st.add_index(3); st.add_index(1); st.add_index(2); st.add_index(3)
	if is_instance_valid(grass_material): st.set_material(grass_material)
	else: var m = StandardMaterial3D.new(); m.albedo_color = Color.MAGENTA; m.cull_mode = BaseMaterial3D.CULL_DISABLED; st.set_material(m)
	st.generate_normals(); return st.commit()

func _create_tree_mesh() -> ArrayMesh:
	var st_trunk = SurfaceTool.new(); st_trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	if is_instance_valid(tree_trunk_material): st_trunk.set_material(tree_trunk_material)
	else: var m = StandardMaterial3D.new(); m.albedo_color = Color("saddlebrown"); st_trunk.set_material(m)
	var trunk_height = 1.5; var trunk_width = 0.15; var trunk_verts = [Vector3(-trunk_width, 0, -trunk_width), Vector3(trunk_width, 0, -trunk_width), Vector3(trunk_width, 0, trunk_width), Vector3(-trunk_width, 0, trunk_width), Vector3(-trunk_width, trunk_height, -trunk_width), Vector3(trunk_width, trunk_height, -trunk_width), Vector3(trunk_width, trunk_height, trunk_width), Vector3(-trunk_width, trunk_height, trunk_width)]; var uv0 = Vector2(0, 1); var uv1 = Vector2(1, 1); var uv2 = Vector2(1, 0); var uv3 = Vector2(0, 0)
	st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[4]); st_trunk.set_uv(uv1); st_trunk.add_vertex(trunk_verts[5]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[1]); st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[4]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[1]); st_trunk.set_uv(uv3); st_trunk.add_vertex(trunk_verts[0]); st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[6]); st_trunk.set_uv(uv1); st_trunk.add_vertex(trunk_verts[7]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[3]); st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[6]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[3]); st_trunk.set_uv(uv3); st_trunk.add_vertex(trunk_verts[2]); st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[7]); st_trunk.set_uv(uv1); st_trunk.add_vertex(trunk_verts[4]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[0]); st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[7]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[0]); st_trunk.set_uv(uv3); st_trunk.add_vertex(trunk_verts[3]); st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[5]); st_trunk.set_uv(uv1); st_trunk.add_vertex(trunk_verts[6]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[2]); st_trunk.set_uv(uv0); st_trunk.add_vertex(trunk_verts[5]); st_trunk.set_uv(uv2); st_trunk.add_vertex(trunk_verts[2]); st_trunk.set_uv(uv3); st_trunk.add_vertex(trunk_verts[1]); st_trunk.generate_normals(); st_trunk.generate_tangents()
	var st_leaves = SurfaceTool.new(); st_leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	if is_instance_valid(tree_leaves_material): st_leaves.set_material(tree_leaves_material)
	else: var m = StandardMaterial3D.new(); m.albedo_color = Color("forestgreen"); st_leaves.set_material(m)
	var leaves_height = 1.2; var leaves_width = 0.7; var leaves_base_y = trunk_height; var leaves_verts = [Vector3(-leaves_width, leaves_base_y, -leaves_width), Vector3(leaves_width, leaves_base_y, -leaves_width), Vector3(leaves_width, leaves_base_y, leaves_width), Vector3(-leaves_width, leaves_base_y, leaves_width), Vector3(-leaves_width, leaves_base_y + leaves_height, -leaves_width), Vector3(leaves_width, leaves_base_y + leaves_height, -leaves_width), Vector3(leaves_width, leaves_base_y + leaves_height, leaves_width), Vector3(-leaves_width, leaves_base_y + leaves_height, leaves_width)]
	st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[4]); st_leaves.set_uv(uv1); st_leaves.add_vertex(leaves_verts[5]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[1]); st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[4]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[1]); st_leaves.set_uv(uv3); st_leaves.add_vertex(leaves_verts[0]); st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[6]); st_leaves.set_uv(uv1); st_leaves.add_vertex(leaves_verts[7]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[3]); st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[6]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[3]); st_leaves.set_uv(uv3); st_leaves.add_vertex(leaves_verts[2]); st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[7]); st_leaves.set_uv(uv1); st_leaves.add_vertex(leaves_verts[4]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[0]); st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[7]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[0]); st_leaves.set_uv(uv3); st_leaves.add_vertex(leaves_verts[3]); st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[5]); st_leaves.set_uv(uv1); st_leaves.add_vertex(leaves_verts[6]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[2]); st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[5]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[2]); st_leaves.set_uv(uv3); st_leaves.add_vertex(leaves_verts[1]); st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[7]); st_leaves.set_uv(uv1); st_leaves.add_vertex(leaves_verts[6]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[5]); st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[7]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[5]); st_leaves.set_uv(uv3); st_leaves.add_vertex(leaves_verts[4]); st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[0]); st_leaves.set_uv(uv1); st_leaves.add_vertex(leaves_verts[1]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[2]); st_leaves.set_uv(uv0); st_leaves.add_vertex(leaves_verts[0]); st_leaves.set_uv(uv2); st_leaves.add_vertex(leaves_verts[2]); st_leaves.set_uv(uv3); st_leaves.add_vertex(leaves_verts[3]); st_leaves.generate_normals(); st_leaves.generate_tangents()
	var final_mesh = ArrayMesh.new(); st_trunk.commit(final_mesh); st_leaves.commit(final_mesh); return final_mesh
